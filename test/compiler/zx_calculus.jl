using YaoLang
using YaoLang.Compiler
using YaoLang.Compiler: device_m, enable_timings, timings

include("../../../ZXCalculus/script/zx_plot.jl")

# enable_timings()

@device function testcir()
    1 => shift($(3/2*π))
    1 => H
    1 => shift($(1/2*π))
    2 => shift($(1/2*π))
    4 => H
    @ctrl 2 3 => X
    @ctrl 1 4 => Z
    2 => H
    @ctrl 2 3 => X
    @ctrl 4 1 => X
    1 => H
    2 => shift($(1/4*π))
    3 => shift($(1/2*π))
    4 => H
    1 => shift($(1/4*π))
    2 => H
    3 => H
    4 => shift($(3/2*π))
    3 => shift($(1/2*π))
    4 => Rx($(π))
    @ctrl 2 3 => X
    1 => H
    4 => shift($(1/2*π))
    4 => Rx($(π))
end

code = @code_yao testcir()
code.pure_quantum = true
circ = YaoLang.Compiler.to_ZX_diagram(code)
ex_circ = YaoLang.Compiler.clifford_simplify!(circ)
ZXplot(circ)
ZXplot(ex_circ)
