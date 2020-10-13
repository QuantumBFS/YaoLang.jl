using YaoLang
using YaoLang.Compiler
using IRTools
using Core.Compiler
import Core.Compiler: InferenceParams, OptimizationParams, get_world_counter, get_inference_cache, AbstractInterpreter, VarTable, InferenceState

struct YaoInterpreter <: AbstractInterpreter
    quantum_stmts::Vector{Any}
    native_interpreter::Core.Compiler.NativeInterpreter
end

struct Quantum end

InferenceParams(interp::YaoInterpreter) = InferenceParams(interp.native_interpreter)
OptimizationParams(interp::YaoInterpreter) = OptimizationParams(interp.native_interpreter)
get_world_counter(interp::YaoInterpreter) = get_world_counter(interp.native_interpreter)
get_inference_cache(interp::YaoInterpreter) = get_inference_cache(interp.native_interpreter)

function Core.Compiler.abstract_eval_statement(interp::YaoInterpreter, @nospecialize(e), vtypes::VarTable, sv::InferenceState)
    if !isa(e, Expr)
        return Core.Compiler.abstract_eval_special_value(interp, e, vtypes, sv)
    end
    e = e::Expr

    if e.head === :call && e.args[1] isa GlobalRef && e.args[1].mod === YaoLang.Compiler.Semantic
        push!(interp.quantum_stmts, e)
        return Quantum
    else
        return Core.Compiler.abstract_eval_statement(interp.native_interpreter, e, vtypes, sv)
    end
end

@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
end

c = qft(3)

ci = @code_lowered c.stub(3)

c = qft(3)



x = Int
method = first(methods(c.stub, (x, )))
method_args = Tuple{typeof(c.stub), x}
mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
ci = Core.Compiler.retrieve_code_info(mi)
result = Core.Compiler.InferenceResult(mi)
world = Core.Compiler.get_world_counter()
interp = YaoInterpreter([], Core.Compiler.NativeInterpreter()) # Core.Compiler.NativeInterpreter()

frame = Core.Compiler.InferenceState(result, ci, #=cached=# true, interp)
Core.Compiler.typeinf_local(interp, frame)
ci = result.result.src

function qft_foo(n::Int)
end

shift(2π/3)
interp.quantum_stmts[1]

result.result


ex = :(function (::RoutineSpec)(r::AbstractRegister, locs::Locations)
end)

Meta.lower(Main, ex)


ex = :(function goo(::Integer)
end)

Meta.lower(Main, ex).args[1].code[4].args[2]

ex

function goo(::AbstractFloat)
end

method = first(methods(goo, (Int, )))

