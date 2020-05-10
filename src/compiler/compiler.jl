abstract type CompileCtx end
abstract type AbstractJuliaASTCtx <: CompileCtx end

struct JuliaASTCodegenCtx <: AbstractJuliaASTCtx
    stub_name
    circuit::Symbol
    register::Symbol
    locations::Symbol
    ctrl_locations::Symbol
    codegen_pass::Vector{Any}
end

function codegen_classical end
function codegen_eval end
function codegen_quantum_circuit end
function codegen_ctrl_circuit end
function codegen_create_symbol end
function codegen_code_qast_stub end
function codegen_code_qast_runtime_stub end

const DEFAULT_CODEGEN_PASS = [
    codegen_classical,
    codegen_eval,
    codegen_quantum_circuit,
    codegen_ctrl_circuit,
    codegen_code_qast_stub,
    codegen_code_qast_runtime_stub,
    codegen_create_symbol,
]

function JuliaASTCodegenCtx(ir, pass=DEFAULT_CODEGEN_PASS)
    stub_name = gensym(ir.def[:name])
    JuliaASTCodegenCtx(
        stub_name,
        gensym(:circ), gensym(:register),
        gensym(:locations), gensym(:ctrl_locations),
        pass)
end

# code transform entries
# NOTE: transform doesn't guarantee the return code remains in the same IR
transform(ctx::CompileCtx, ex) = ex
transform(ctx::CompileCtx, ex::Expr) =
    Expr(ex.head, map(x->transform(ctx, x), ex.args)...)

ctrl_transform(ctx::CompileCtx, ex) = ex
ctrl_transform(ctx::CompileCtx, ex::Expr) =
    Expr(ex.head, map(x->ctrl_transform(ctx, x), ex.args)...)


# JuliaASTCodegen pass
function codegen_classical(ctx::JuliaASTCodegenCtx, ir::QASTCode)
    quoted_name = QuoteNode(ir.name)
    classical_def = deepcopy(ir.def)
    classical_def[:name] = :(::$(generic_circuit(ir.name)))

    classical_def[:body] = :($Circuit{$quoted_name}($(ctx.stub_name), $(Expr(:tuple, ir.free_variables...))))

    return combinedef(classical_def)
end

function codegen_eval(ctx::JuliaASTCodegenCtx, ir::QASTCode)
    quoted_name = QuoteNode(ir.name)
    def = deepcopy(ir.def)
    def[:name] = GlobalRef(YaoIR, :evaluate)
    def[:args] = Any[:(::$(generic_circuit(ir.name))), variables(def)...]
    def[:body] = :($Circuit{$quoted_name}($(ctx.stub_name), $(Expr(:tuple, ir.free_variables...))))
    return combinedef(def)
end

function codegen_quantum_circuit(ctx::JuliaASTCodegenCtx, ir::QASTCode)
    stub_def = Dict{Symbol, Any}()
    stub_def[:name] = ctx.stub_name
    stub_def[:args] = Any[:($(ctx.circuit)::$Circuit), :($(ctx.register)::$AbstractRegister), :($(ctx.locations)::Locations)]
    stub_def[:body] = quote
        $(splatting_variables(ir.free_variables, :($(ctx.circuit).free)))
        $(transform(ctx, ir.code))
        return $(ctx.register)
    end
    return combinedef(stub_def)
end

function codegen_ctrl_circuit(ctx::JuliaASTCodegenCtx, ir::QASTCode)
    hasmeasure(ir) && return :()
    stub_def = Dict{Symbol, Any}()
    stub_def[:name] = ctx.stub_name
    stub_def[:args] = Any[:($(ctx.circuit)::$Circuit), :($(ctx.register)::$AbstractRegister),
        :($(ctx.locations)::Locations), :($(ctx.ctrl_locations)::CtrlLocations)]
    stub_def[:body] = quote
        $(splatting_variables(ir.free_variables, :($(ctx.circuit).free)))
        $(ctrl_transform(ctx, ir.code))
        return $(ctx.register)
    end
    return combinedef(stub_def)
end

function codegen_create_symbol(ctx::JuliaASTCodegenCtx, ir::QASTCode)
    :(Core.@__doc__ const $(ir.name) = $(generic_circuit(ir.name))())
end

function codegen_code_qast_runtime_stub(ctx::JuliaASTCodegenCtx, ir::QASTCode)
    def = Dict{Symbol, Any}()
    def[:name] = GlobalRef(YaoIR, :code_qast)
    def[:args] = Any[:(::$(generic_circuit(ir.name))), variables(ir.def)...]
    def[:body] = ir
    if haskey(ir.def, :whereparams)
        def[:whereparams] = ir.def[:whereparams]
    end
    return combinedef(def)
end

function codegen_code_qast_stub(ctx::JuliaASTCodegenCtx, ir::QASTCode)
    def = Dict{Symbol, Any}()
    def[:name] = GlobalRef(YaoIR, :code_qast)
    def[:args] = Any[:(::$(generic_circuit(ir.name))), :(::Type{$(argtypes(ir.def))})]
    def[:body] = ir

    if haskey(ir.def, :whereparams)
        def[:whereparams] = ir.def[:whereparams]
    end
    return combinedef(def)
end

function codegen(ctx::JuliaASTCodegenCtx, ir)
    ex = Expr(:block)
    for pass in ctx.codegen_pass
        push!(ex.args, pass(ctx, ir))
    end
    return ex
end

function device_m(ex::Expr, strict_mode=nothing)
    ir = QASTCode(ex; strict_mode=value(strict_mode) #= default parsing pass =#)

    # TODO: code optimization/transformation pass
    # TODO: switch compile target

    codegen_ctx = JuliaASTCodegenCtx(ir #= default pass =#)
    return codegen(codegen_ctx, ir)
end

flatten_locations(parent, x) = Expr(:ref, parent, x)

# merge location in runtime
merge_location_ex(l1, l2) = :(merge_locations($l1, $l2))
# merge literal location in compile time
merge_location_ex(l1::AbstractLocations, l2::AbstractLocations) = merge_locations(l1, l2)

evaluate_ex(gate::Symbol) = Expr(:call, evaluate, gate)
evaluate_ex(gate::Expr) = Expr(:call, evaluate, gate.args...)

# transform
function transform(ctx::JuliaASTCodegenCtx, ex::GateLocation)
    return Expr(:call, evaluate_ex(ex.gate), ctx.register, flatten_locations(ctx.locations, ex.location))
end

function transform(ctx::JuliaASTCodegenCtx, ex::Control)
    ret = transform(ctx, ex.gate)
    push!(ret.args, flatten_locations(ctx.locations, ex.ctrl_location))
    return ret
end

function transform(ctx::JuliaASTCodegenCtx, ex::Measure)
    ret = Expr(:call, :measure!)
    cfg = _transform_measure_cfg(ex.config)
    cfg === nothing || push!(ret.args, cfg)
    ex.operator === nothing || push!(ret.args, ex.operator)
    push!(ret.args, ctx.register)
    push!(ret.args, flatten_locations(ctx.locations, ex.location))
    return ret
end

_transform_measure_cfg(cfg) = nothing

function _transform_measure_cfg(cfg::Expr)
    if cfg.args[1] === :reset_to
        return :(ResetTo($(cfg.args[2])))
    elseif (cfg.args[1] === :remove) && (cfg.args[2] == true)
        return RemoveMeasured()
    else
        return nothing
    end
end

function ctrl_transform(ctx::JuliaASTCodegenCtx, ex::GateLocation)
    ret = transform(ctx, ex)
    push!(ret.args, ctx.ctrl_locations)
    return ret
end

function ctrl_transform(ctx::JuliaASTCodegenCtx, ex::Control)
    ret = transform(ctx, ex.gate)
    push!(ret.args, # NOTE: the control location has two part:
    # 1. control locations from the context
    # 2. control locations in the given location space (need flatten it)
        merge_location_ex(
                ctx.ctrl_locations,
                flatten_locations(ctx.locations, ex.ctrl_location)
            )
    )
    return ret
end

ctrl_transform(ctx::CompileCtx, ex::Control) = error("cannot generate controled measurement")
