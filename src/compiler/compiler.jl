export compile, JuliaAST, CtrlJuliaAST, device_m, @device, @ctrl, @measure

abstract type CompileCtx end

struct JuliaAST <: CompileCtx
    register::Symbol
    locations::Symbol
end

struct CtrlJuliaAST <: CompileCtx
    register::Symbol
    locations::Symbol
    ctrl_locs::Symbol
end

JuliaAST() = JuliaAST(gensym(:register), gensym(:locs))
CtrlJuliaAST() = CtrlJuliaAST(gensym(:register), gensym(:locations), gensym(:ctrl_locs))

macro device(ex)
    return esc(device_m(ex))
end

"""
    @ctrl k <gate location>

Keyword for controlled gates in quantum circuit. It must be used inside `@device`. See also [`@device`](@ref).
"""
macro ctrl end

"""
    @measure <location> [operator] [configuration]

Keyword for measurement in quantum circuit. It must be used inside `@device`. See also [`@device`](@ref).

# Arguments

- `<location>`: a valid `Locations` argument to specifiy where to measure the register
- `[operator]`: Optional, specifiy which operator to measure
- `[configuration]`: Optional, it can be either:
    - `remove=true` will remove the measured qubits
    - `reset_to=<bitstring>` will reset the measured qubits to given bitstring
"""
macro measure end

"""
    rm_annotations(x)

Remove type annotation of given expression.
"""
rm_annotations(x) = x

function rm_annotations(x::Expr)
    if x.head == :(::)
        return x.args[1]
    else
        return x
    end
end

function device_m(ex::Expr)
    def = splitdef(ex)
    haskey(def, :name) || throw(Meta.ParseError("Invalid Syntax: generic circuit should have a name"))

    name = def[:name]
    quote_name = QuoteNode(name)
    stub_name = gensym(name)
    generic_circuit = :($(GenericCircuit){$quote_name})
    classical_def = deepcopy(def)
    classical_def[:name] = :(::$generic_circuit)

    free_args = Expr(:tuple, map(rm_annotations, classical_def[:args])...)
    classical_def[:body] = :($Circuit{$quote_name}($stub_name, $free_args))

    # generate kernel stub
    stub_circ = gensym(:circ)
    stub_register = gensym(:register)
    stub_location = gensym(:locs)
    stub_ctrl_location = gensym(:ctrl_locs)

    # splatting original classical arguments
    splat_args = Expr(:(=), free_args, :($stub_circ.free))
    ex = parse_ast(def[:body])

    stub_def = Dict{Symbol, Any}()
    stub_def[:name] = stub_name    
    stub_def[:args] = Any[:($stub_circ::$Circuit), :($stub_register::$AbstractRegister), :($stub_location::Locations)]
    stub_def[:body] = quote
        $splat_args
        $(compile(JuliaAST(stub_register, stub_location), ex))
        return $stub_register
    end

    ctrl_stub_def = Dict{Symbol, Any}()
    ctrl_stub_def[:name] = stub_name
    ctrl_stub_def[:args] = Any[:($stub_circ::$Circuit), :($stub_register::$AbstractRegister), :($stub_location::Locations), :($stub_ctrl_location::Locations)]
    ctrl_stub_def[:body] = quote
        $splat_args
        $(compile(CtrlJuliaAST(stub_register, stub_location, stub_ctrl_location), ex))
        return $stub_register
    end
    
    return quote
        $(combinedef(classical_def))
        # stub def
        $(combinedef(stub_def))
        # ctrl stub def
        $(combinedef(ctrl_stub_def))

        const $name = $generic_circuit()
    end
end

compile(ctx::CompileCtx, ex) = ex
compile(ctx::CompileCtx, ex::Expr) =
    Expr(ex.head, map(x->compile(ctx, x), ex.args)...)


function evaluate_ex(stub, ex::GateLocation)
    if ex.gate isa Symbol
        gate = Expr(:call, stub, ex.gate)
    elseif (ex.gate isa Expr) && (ex.gate.head === :call)
        head = :(GenericCircuit{$(QuoteNode(ex.gate.args[1]))}())
        gate = Expr(:call, stub, head, ex.gate.args[2:end]...)
    else
        throw(Meta.ParseError("Invalid syntax, expect a primitive gate or a function call"))
    end
    return gate
end

function compile(ctx::JuliaAST, ex::GateLocation)
    return Expr(:call, ex.gate, ctx.register, flatten_locations(ctx.locations, ex.location))
end

function compile(ctx::JuliaAST, ex::Control)
    return Expr(:call, ex.gate.gate, ctx.register,
        flatten_locations(ctx.locations, ex.gate.location),
        flatten_locations(ctx.locations, ex.ctrl_location))
end

flatten_locations(parent_locs, x::LocationExpr) = flatten_locations(parent_locs, x.ex)
flatten_locations(parent_locs, x) = Expr(:ref, parent_locs, x)

# merge location in runtime
merge_location_ex(l1, l2) = :(merge_location($l1, $l2))
# merge literal location in compile time
merge_location_ex(l1::Locations, l2::Locations) = merge_location(l1, l2)
merge_location_ex(l1::LocationExpr, l2) = merge_location_ex(l1.ex, l2)
merge_location_ex(l1, l2::LocationExpr) = merge_location_ex(l1, l2.ex)
merge_location_ex(l1::LocationExpr, l2::LocationExpr) = merge_location_ex(l1.ex, l2.ex)

function compile(ctx::CtrlJuliaAST, ex::GateLocation)
    return Expr(:call, ex.gate, ctx.register,
        flatten_locations(ctx.locations, ex.location), ctx.ctrl_locs)
end

function compile(ctx::CtrlJuliaAST, ex::Control)
    return Expr(:call, ex.gate.gate, ctx.register,
        flatten_locations(ctx.locations, ex.gate.location),
        # NOTE: the control location has two part:
        # 1. control locations from the context
        # 2. control locations in the given location space (need flatten it)
            merge_location_ex(
                    ctx.ctrl_locs,
                    flatten_locations(ctx.locations, ex.ctrl_location)
                )
        )
end

function compile(ctx::JuliaAST, ex::Measure)
    ret = Expr(:call, :measure!)
    cfg = _compile_measure_cfg(ex.config)
    cfg === nothing || push!(ret.args, cfg)
    ex.operator === nothing || push!(ret.args, ex.operator)
    push!(ret.args, ctx.register)
    push!(ret.args, flatten_locations(ctx.locations, ex.location))
    return ret
end

_compile_measure_cfg(cfg) = nothing

function _compile_measure_cfg(cfg::Expr)
    if cfg.args[1] === :reset_to
        return :(ResetTo($(cfg.args[2])))
    elseif (cfg.args[1] === :remove) && (cfg.args[2] == true)
        return RemoveMeasured()
    else
        return nothing
    end
end

function compile(ctx::CtrlJuliaAST, ex::Measure)
    throw(Meta.ParseError("Invalid Syntax: cannot control measurement via qubits"))
end