struct MeasureResult end

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

function is_quantum_statement(e)
    return e isa Expr && e.head === :quantum
end

quantum_stmt_type(e) = e.args[1]

function Core.Compiler.abstract_eval_statement(interp::YaoInterpreter, @nospecialize(e), vtypes::VarTable, sv::InferenceState)
    if is_quantum_statement(e)
        type = quantum_stmt_type(e)
        if type === :measure
            return MeasureResult
        else
            return Nothing
        end
    end
    return Core.Compiler.abstract_eval_statement(interp.native_interpreter, e, vtypes, sv)
end
