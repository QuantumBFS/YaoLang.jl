using YaoLang
using YaoLang.Compiler: optimize!
using YaoPlots
using IRTools: IR
using ZXCalculus: ZXDiagram

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
circ = ZXDiagram(code)
code = optimize(code)
circ2 = ZXDiagram(code)

plot(circ)
plot(circ2)
