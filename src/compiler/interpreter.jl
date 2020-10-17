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
function is_quantum_statement(@nospecialize(e))
    e isa Expr || return false
    e.head === :quantum && return true
    # could be measurement
    e.head === :(=) && return is_quantum_statement(e.args[2])
    return false
end

function quantum_stmt_type(e::Expr)
    if e.head === :quantum
        return e.args[1]
    elseif e.head === :(=)
        return quantum_stmt_type(e.args[2])
    else
        error("not a quantum statement")
    end
end

function Core.Compiler.abstract_eval_statement(interp::YaoInterpreter, @nospecialize(e), vtypes::VarTable, sv::InferenceState)
    is_quantum_statement(e) || return Core.Compiler.abstract_eval_statement(interp.native_interpreter, e, vtypes, sv)
    
    type = quantum_stmt_type(e)
    if type === :measure
        return MeasureResult
    else
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
        # call into a quantum routine
        callinfo = abstract_call_quantum(interp, type, argtypes[1], sv)
        # callinfo = abstract_call(interp, ea, argtypes, sv)
        sv.stmt_info[sv.currpc] = callinfo.info
        t = callinfo.rt
    end

    # copied from abstract_eval_statement
    @assert !isa(t, TypeVar)
    if isa(t, DataType) && isdefined(t, :instance)
        # replace singleton types with their equivalent Const object
        t = Core.Const(t.instance)
    end
    return t
end

function abstract_call_quantum(interp::YaoInterpreter, type::Symbol, @nospecialize(f), sv::InferenceState)
    return Core.Compiler.CallMeta(Nothing, false)
    # if type === :gate || type === :ctrl

    # else
    # end
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

function convert_to_quantum_head(@nospecialize(e))
    if e isa Expr
        if is_semantic_fn_call(e)
            type = e.args[1].name
            return Expr(:quantum, e.args[1].name, e.args[2:end]...)
        else
            return Expr(e.head, convert_to_quantum_head.(e.args)...)
        end
    else
        return e
    end
end
