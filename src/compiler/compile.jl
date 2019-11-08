export transform, ignore_line_numbers, compile_to_jl, pack_arguements,
    function_name, replace_function_name, create_closure, is_function,
    device_m, @device

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
        args = map(ignore_line_numbers, filter(x ->!(x isa LineNumberNode), ex.args[3:end]))
        return Expr(ex.head, ex.args[1], ex.args[2], args...)
    else
        args = map(ignore_line_numbers, filter(x ->!(x isa LineNumberNode), ex.args))
        Expr(ex.head, args...)
    end
end

compile_to_jl(register::Symbol, x) = x

function compile_to_jl(register::Symbol, ex::Expr)
    Expr(ex.head, map(x->compile_to_jl(register, x), ex.args)...)
end

function compile_to_jl(register::Symbol, ex::GateLocation)
    Expr(:call, :(YaoIR.exec!), register, ex.gate, ex.location.ex)
end

function compile_to_jl(register::Symbol, ex::Control)
    Expr(:call, :(YaoIR.exec!), register, ex.content.gate, ex.content.location.ex, ex.ctrl_location.ex)
end

function compile_to_jl(register::Symbol, ex::Measure)
    Expr(:call, :(YaoIR.measure!), register, ex.location.ex)
end

# handle relative location
compile_to_jl(register::Symbol, x, locs) = x

function compile_to_jl(register::Symbol, ex::Expr, locs)
    Expr(ex.head, map(x->compile_to_jl(register, x, locs), ex.args)...)
end

function compile_to_jl(register::Symbol, ex::GateLocation, locs)
    location = :($locs[$(ex.location.ex)])
    Expr(:call, :(YaoIR.exec!), register, ex.gate, location)
end

function compile_to_jl(register::Symbol, ex::Control, locs)
    location = :($locs[$(ex.content.location.ex)])
    ctrl_location = :($locs[$(ex.ctrl_location.ex)])
    Expr(:call, :(YaoIR.exec!), register, ex.content.gate, location, ctrl_location)
end

function compile_to_jl(register::Symbol, ex::Measure, locs)
    location = :($locs[$(ex.location.ex)])
    Expr(:call, :(YaoIR.measure!), register, location)
end

# ignore same column when compiling to simulation code
function compile_to_jl(register::Symbol, ex::SameColumn, locs)
    ex = Expr(:block)
    for each in ex.args
        push!(ex.args, compile_to_jl(register, each, locs))
    end
    return ex
end

function compile_to_jl(register::Symbol, ex::SameColumn)
    out = Expr(:block)
    for each in ex.args
        push!(out.args, compile_to_jl(register, each))
    end
    return out
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

struct Circuit{name, Args <: Tuple}
    args::Args
    Circuit{name}(args::Tuple) where name = new{name, typeof(args)}(args)
end

function Base.show(io::IO, ::Type{Circuit{name}}) where name
    print(io, "Circuit{$(QuoteNode(name))}")
end

"""
    create_closure(ex)

Create a closure as `struct` according to the function definition.
"""
function create_closure(ex::Expr)
    name = function_name(ex)
    if name === nothing
        name = gensym()
    end
    args = pack_arguements(ex)
    circ_name = :($Circuit{$(QuoteNode(name))})
    mt_head = replace_function_name(ex, circ_name)

    mt = Expr(:function, mt_head, :($circ_name($args)))
    quote
        Core.@__doc__ const $(esc(name)) = $circ_name
        $mt
        $(esc(generate_instruct(ex)))
    end
end

function generate_instruct(ex::Expr)
    is_function(ex) || throw(Meta.ParseError("expect function definition, got $ex"))

    register = gensym(:register)
    locs = gensym(:locs)
    gate = gensym(:gate)
    name = function_name(ex)
    args = pack_arguements(ex)
    body = compile_to_jl(register, transform(ex.args[2]), locs)
    
    d = Dict()
    for (k, x) in enumerate(args.args)
        d[x] = :($gate.args[$k])
    end

    body = scan_replace(body, d)
    quote
        function YaoIR.exec!($(register), $gate::$(Circuit{name}), $locs)
            $body
        end

        function YaoIR.exec!($register, $gate::$(Circuit{name}), $locs::Locations{Int})
            exec!($register, $gate, $locs:nqubits($register))
        end        
    end
end

function scan_replace(x, d::Dict)
    if x in keys(d)
        return d[x]
    else
        return x
    end
end

function scan_replace(body::Expr, d::Dict)
    if body in keys(d)
        return d[body]
    else
        Expr(body.head, map(x->scan_replace(x, d), body.args)...)
    end
end

function device_m(ex::Expr)
    return create_closure(ex)
end

macro device(ex::Expr)
    return device_m(ex)
end
