using YaoLang
using YaoLang.Compiler

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

r = Compiler.EchoReg();
locs = Locations((1, 2, 3))
ctrl = CtrlLocations((4, ))
# execute(qft(3), r, locs)
c = qft(3)
ri = RoutineInfo(typeof(c))
# mi, ci = obtain_code_info(typeof(c))

ci = @code_lowered YaoLang.Compiler.execute(c, r, locs)

ci = @code_lowered YaoLang.Compiler.execute(c, r, locs)

YaoLang.Compiler.execute(c, r, locs, ctrl)

