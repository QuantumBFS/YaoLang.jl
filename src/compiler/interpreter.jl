struct MeasureResult end
# this is a Bool in runtime
# but we need to know this comes from
# a measurement so we can distringuish
# a classical control flow on quantum
# operation
struct QuantumBool end
Base.:(==)(x::MeasureResult, y::Int) = QuantumBool()
Base.:(==)(x::Int, y::MeasureResult) = QuantumBool()

struct YaoInterpreter <: AbstractInterpreter
    native_interpreter::Core.Compiler.NativeInterpreter
end

YaoInterpreter() = YaoInterpreter(Core.Compiler.NativeInterpreter())

InferenceParams(interp::YaoInterpreter) = InferenceParams(interp.native_interpreter)
OptimizationParams(interp::YaoInterpreter) = OptimizationParams(interp.native_interpreter)
Core.Compiler.get_world_counter(interp::YaoInterpreter) = get_world_counter(interp.native_interpreter)
Core.Compiler.get_inference_cache(interp::YaoInterpreter) = get_inference_cache(interp.native_interpreter)
Core.Compiler.code_cache(interp::YaoInterpreter) = Core.Compiler.code_cache(interp.native_interpreter)
Core.Compiler.may_optimize(interp::YaoInterpreter) = Core.Compiler.may_optimize(interp.native_interpreter)
Core.Compiler.may_discard_trees(interp::YaoInterpreter) = Core.Compiler.may_discard_trees(interp.native_interpreter)
Core.Compiler.may_compress(interp::YaoInterpreter) = Core.Compiler.may_compress(interp.native_interpreter)
Core.Compiler.unlock_mi_inference(interp::YaoInterpreter, mi::Core.MethodInstance) = Core.Compiler.unlock_mi_inference(interp.native_interpreter, mi)
Core.Compiler.lock_mi_inference(interp::YaoInterpreter, mi::Core.MethodInstance) = Core.Compiler.lock_mi_inference(interp.native_interpreter, mi)
Core.Compiler.add_remark!(interp::YaoInterpreter, st::Core.Compiler.InferenceState, msg::String) = println(msg)

function Core.Compiler.abstract_eval_statement(interp::YaoInterpreter, @nospecialize(e), vtypes::VarTable, sv::InferenceState)
    is_quantum_statement(e) || return Core.Compiler.abstract_eval_statement(interp.native_interpreter, e, vtypes, sv)
    type = quantum_stmt_type(e)
    if type === :measure
        return MeasureResult
    elseif type === :gate || type === :ctrl
        ea = e.args
        n = length(ea)
        argtypes = Vector{Any}(undef, n)
        @inbounds for i = 1:n
            ai = Core.Compiler.abstract_eval_value(interp, ea[i], vtypes, sv)
            if ai === Core.Compiler.Bottom
                return Core.Compiler.Bottom
            end
            argtypes[i] = ai
        end
        gt = Core.Compiler.widenconst(argtypes[2])
        gt <: IntrinsicSpec && return Core.Const(nothing)
        atypes = Core.Compiler.argtypes_to_type(argtypes)

        if type === :gate
            sf = Compiler.Semantic.gate
        else
            sf = Compiler.Semantic.ctrl
        end

        callinfo = Core.Compiler.abstract_call_gf_by_type(interp, sf, argtypes, atypes, sv)
        sv.stmt_info[sv.currpc] = callinfo.info
        t = callinfo.rt
    else
        return Core.Const(nothing)
    end

    # copied from abstract_eval_statement
    @assert !isa(t, TypeVar)
    if isa(t, DataType) && isdefined(t, :instance)
        # replace singleton types with their equivalent Const object
        t = Core.Const(t.instance)
    end
    return t
end

function is_semantic_fn_call(e)
    return e isa Expr && e.head === :call &&
        e.args[1] isa GlobalRef &&
            e.args[1].mod === YaoLang.Compiler.Semantic
end

function convert_to_quantum_head!(ci::CodeInfo)
    for (v, e) in enumerate(ci.code)
        ci.code[v] = convert_to_quantum_head(e)
    end
    return ci
end
