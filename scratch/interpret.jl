using YaoLang
import Core.Compiler: InferenceParams, OptimizationParams, get_world_counter, get_inference_cache, AbstractInterpreter, VarTable, InferenceState

const YC = YaoLang.Compiler
const CC = Core.Compiler

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
ri = @code_yao qft(3)

mi, ci = YC.obtain_codeinfo(c)
result = CC.InferenceResult(mi)
world = CC.get_world_counter()
interp = YC.YaoInterpreter()
frame = CC.InferenceState(result, ci, #=cached=# true, interp)
fargs = Any[GlobalRef(Base, :sin), Core.SSAValue(2)]
argtypes = Any[typeof(sin), Int]
CC.abstract_call_known(interp, sin, fargs, argtypes, frame)
CC.argtypes_to_type(argtypes)
Core.Compiler.InferenceState
Core.Compiler.InferenceResult
Core.Compiler.matching_cache_argtypes
