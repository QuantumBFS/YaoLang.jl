using YaoLang
using YaoLang.Compiler
using YaoArrayRegister
using IRTools
using Core.Compiler
using Core.Compiler: InferenceParams, OptimizationParams, get_world_counter, get_inference_cache, AbstractInterpreter, VarTable, InferenceState
using Core: CodeInfo
using YaoLang.Compiler: typed_ir

@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
end

r = rand_state(5)
locs = Locations((1, ))
# execute(qft(3), r, locs)
using YaoLang.Compiler: replace_with_execute
c = qft(3)

method = first(methods(c.stub)) # this is garuanteed by construction
method_args = Tuple{typeof(c.stub), Int}
mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
ci = Core.Compiler.retrieve_code_info(mi)
YaoLang.Compiler.convert_to_quantum_head!(ci)

# type infer
result = Core.Compiler.InferenceResult(mi)
world = Core.Compiler.get_world_counter()
interp = YaoLang.Compiler.YaoInterpreter()
frame = Core.Compiler.InferenceState(result, ci, #=cached=# true, interp)
Core.Compiler.typeinf_local(interp, frame)
ci = result.result.src
ci.code

using YaoLang.Compiler: blockstarts, group_quantum_stmts, permute_stmts

bs = blockstarts(ci)
    # group quantum statements
    perms = group_quantum_stmts(ci, bs)
    ci = permute_stmts(ci, perms)

typed_ir(ci, 1)


ri = RoutineInfo(typeof(c))
IRTools.Inner.update!(copy(ri.ci), replace_with_execute(ri))
ci = ri.ci
