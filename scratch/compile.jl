using Core.Compiler
using Core.Compiler: InferenceParams, OptimizationParams, get_world_counter, get_inference_cache, AbstractInterpreter, VarTable, InferenceState
using Core: CodeInfo


using YaoLang
using YaoLang.Compiler: @device, @ctrl, obtain_code_info, perform_typeinf, convert_to_quantum_head!, group_quantum_stmts
using YaoLang.Compiler: RoutineInfo, YaoIR
using YaoLang.Compiler: replace_with_execute, replace_with_ctrl_execute
using YaoArrayRegister
using IRTools
using YaoLang.Compiler: H, shift

@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
    return 1
end

r = rand_state(5)
locs = Locations((1, 2, 3))
ctrl = CtrlLocations((4, ))
# execute(qft(3), r, locs)
c = qft(3)
ri = RoutineInfo(typeof(c))
# mi, ci = obtain_code_info(typeof(c))

ci = @code_lowered YaoLang.Compiler.execute(c, r, locs)

function (spec::YaoLang.Compiler.RoutineSpec)(r::ArrayReg, loc::Locations)
    YaoLang.Compiler.execute(spec, r, locs)
end

ci = @code_lowered YaoLang.Compiler.execute(c, r, locs)

YaoLang.Compiler.execute(c, r, locs, ctrl)

