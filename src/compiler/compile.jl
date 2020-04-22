export transform,
    ignore_line_numbers,
    compile_to_jl,
    pack_arguements,
    function_name,
    replace_function_name,
    create_circuit,
    is_function,
    device_m,
    @device

using MLStyle

function transform(ex)
    name = Symbol("@column")
    @match ex begin
        :($location => $gate) => GateLocation(location, transform(gate))
        :(control($ctrl, $locs => $gate)) => Control(ctrl, GateLocation(locs, gate))
        :(measure($locs)) => Measure(locs)
        :(measure($(locs...))) => Measure(locs...)
        Expr(:macrocall, name, line, body...) => SameColumn(map(transform, body))
        ::Expr => Expr(ex.head, map(transform, ex.args)...)
        _ => ex
    end
end

ignore_line_numbers(ex) = ex

function ignore_line_numbers(ex::Expr)
    if ex.head === :macrocall
        args = map(ignore_line_numbers, filter(x -> !(x isa LineNumberNode), ex.args[3:end]))
        return Expr(ex.head, ex.args[1], ex.args[2], args...)
    else
        args = map(ignore_line_numbers, filter(x -> !(x isa LineNumberNode), ex.args))
        Expr(ex.head, args...)
    end
end

compile_to_jl(register::Symbol, x) = x

function compile_to_jl(register::Symbol, ex::Expr)
    Expr(ex.head, map(x -> compile_to_jl(register, x), ex.args)...)
end

function compile_to_jl(register::Symbol, ex::GateLocation)
    Expr(:call, :(YaoIR.evaluate!), register, ex.gate, ex.location.ex)
end

function compile_to_jl(register::Symbol, ex::Control)
    Expr(
        :call,
        :(YaoIR.evaluate!),
        register,
        ex.content.gate,
        ex.content.location.ex,
        ex.ctrl_location.ex,
    )
end

function compile_to_jl(register::Symbol, ex::Measure)
    Expr(:call, :(YaoIR.measure!), register, ex.location.ex)
end

# ignore same column when compiling to simulation code
function compile_to_jl(register::Symbol, ex::SameColumn)
    out = Expr(:block)
    for each in ex.args
        push!(out.args, compile_to_jl(register, each))
    end
    return out
end

# handle relative location
flatten_position(ir, locs) = ir
function flatten_position(ir::Expr, locs)
    Expr(ir.head, map(x -> flatten_position(x, locs), ir.args)...)
end

function flatten_position(ir::GateLocation, locs)
    location = LocationExpr(:($locs[$(ir.location.ex)]))
    return GateLocation(location, ir.gate)
end

function flatten_position(ir::Control, locs)
    ctrl_location = LocationExpr(:($locs[$(ir.ctrl_location.ex)]))
    return Control(ctrl_location, flatten_position(ir.content, locs))
end

function flatten_position(ir::Measure, locs)
    location = :($locs[$(ir.location.ex)])
    return Measure(location)
end

function is_quantum_controlable(ex::Expr)
    flag = true
    for each in ex.args
        flag = flag && is_quantum_controlable(each)
    end
    return flag
end

is_quantum_controlable(x) = true
is_quantum_controlable(x::Measure) = false

ctrl_transform(ctrl_locs, x) = x

function ctrl_transform(ctrl_locs, ex::Expr)
    Expr(ex.head, map(x -> ctrl_transform(ctrl_locs, x), ex.args)...)
end

function ctrl_transform(ctrl_locs, x::GateLocation)
    Control(LocationExpr(ctrl_locs), x)
end

function ctrl_transform(ctrl_locs, x::Control)
    ctrl_locs = :(YaoIR.merge_location($ctrl_locs, $(x.ctrl_location.ex)))
    Control(LocationExpr(ctrl_locs), x.content)
end


"""
    is_function(expr)

Return `true` if given `expr` is a valid function definition.
"""
function is_function(ex::Expr)
    ex.head === :function ||
        ex.head === :(=) && (ex.args[1].head === :call || ex.args[1].head === :where)
end

"""
    pack_arguements(ex)

Pack the function arguement symbols as a tuple.
"""
function pack_arguements(ex::Expr)
    is_function(ex) || throw(Meta.ParseError("expect function definition got $ex"))
    _pack_arguements(ex.args[1])
end

function _pack_arguements(ex::Expr)
    ex.head === :where && return _pack_arguements(ex.args[1])

    t_ex = Expr(:tuple)
    for each in ex.args[2:end]
        if each isa Symbol
            push!(t_ex.args, each)
        elseif each.head === :(::)
            push!(t_ex.args, each.args[1])
        else
            throw(Meta.ParseError("invalid function arguement, got $each"))
        end
    end
    return t_ex
end

function replace_function_name(ex::Expr, new)
    is_function(ex) || throw(Meta.ParseError("expect function definition got $ex"))
    _replace_function_name(ex.args[1], new)
end

function _replace_function_name(ex::Expr, new)
    if ex.head === :call
        Expr(ex.head, new, ex.args[2:end]...)
    elseif ex.head === :where
        Expr(:where, _replace_function_name(ex.args[1], new), ex.args[2:end]...)
    elseif ex.head === :tuple
        Expr(:call, new, ex.args...)
    else
        throw(Meta.ParseError("invalid syntax, got $ex"))
    end
end

"""
    function_name(ex::Expr)

Return the function name in function definition. If it is an anonymous function
returns `nothing`.
"""
function function_name(ex::Expr)
    is_function(ex) || throw(Meta.ParseError("expect function definition got $ex"))
    return _function_name(ex.args[1])
end

function _function_name(ex::Expr)
    ex.head === :where && return _function_name(ex.args[1])
    if ex.head === :call
        return ex.args[1]
    elseif ex.head === :tuple
        return nothing
    end
end

function with_similar_signature(new_name, fn_head::Expr)
    # if it has where
    # iterate the function body part, keep the rest where statement
    fn_head.head === :where &&
        return Expr(:where, with_similar_signature(fn_head.args[1]), fn_head.args[2:end]...)

    # if not
    if fn_head.head === :call
        fn_head.args[1] isa Symbol ||
            throw(Meta.ParseError("expect a function name, got $(fn_head.args[1])"))
        return Expr(
            :call,
            new_name,
            :(::YaoIR.Circuit{$(QuoteNode(fn_head.args[1]))}),
            fn_head.args[2:end]...,
        )
    else
        throw(Meta.ParseError("invalid device function"))
    end
end


struct Circuit{name,Args<:Tuple}
    args::Args
    Circuit{name}(args::Tuple) where {name} = new{name,typeof(args)}(args)
end

function Base.show(io::IO, ::Type{Circuit{name}}) where {name}
    print(io, "Circuit{$(QuoteNode(name))}")
end

circuit_method(circ::Circuit) = circuit_method(circ, circ.args...)
ctrl_circuit_method(circ::Circuit) = ctrl_circuit_method(circ, circ.args...)

function evaluate!(r::AbstractRegister, circ::Circuit, locs::Locations)
    circuit_method(circ)(r, locs)
    return r
end

function generate_methods(ex::Expr)
    # kernel function should be a Julia function
    is_function(ex) || throw(Meta.ParseError("expect function definition, got $ex"))
    ir = transform(ex.args[2])

    # create circuit method heads
    circ_method_def = with_similar_signature(:(YaoIR.circuit_method), ex.args[1])
    ctrl_circ_method_def = with_similar_signature(:(YaoIR.ctrl_circuit_method), ex.args[1])

    quote
        $(Expr(:function, circ_method_def, generate_circuit_method(ir)))
        $(Expr(:function, ctrl_circ_method_def, generate_ctrl_circuit_method(ir)))
    end
end

function generate_circuit_method(ir::Expr)
    register = gensym(:register)
    locs = gensym(:locs)

    ir = flatten_position(ir, locs)
    body = compile_to_jl(register, ir)
    quote
        return function routine!($register, $locs)
            $body
            return $register
        end
    end
end

function generate_ctrl_circuit_method(ir::Expr)
    register = gensym(:register)
    locs = gensym(:locs)
    ctrl_locs = gensym(:ctrl_locs)

    is_quantum_controlable(ir) || return :(error("cannot control this circuit"))

    ir = flatten_position(ir, locs)
    ir = ctrl_transform(ctrl_locs, ir)
    body = compile_to_jl(register, ir)
    quote
        return function routine!($register, $locs, $ctrl_locs)
            $body
            return $register
        end
    end
end

"""
    create_circuit(ex)

Create a closure as `struct` according to the function definition.
"""
function create_circuit(ex::Expr)
    name = function_name(ex)
    if name === nothing # anonymous function
        name = gensym()
    end
    args = pack_arguements(ex)
    circ_name = :($Circuit{$(QuoteNode(name))})
    mt_head = replace_function_name(ex, circ_name)

    mt = Expr(:function, mt_head, :($circ_name($args)))
    quote
        Core.@__doc__ const $(esc(name)) = $circ_name
        $mt
        $(esc(generate_methods(ex)))
    end
end

function device_m(ex::Expr)
    return create_circuit(ex)
end

macro device(ex::Expr)
    return device_m(ex)
end
