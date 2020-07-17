using YaoLang
using YaoLang.Compiler: optimize, sink_quantum!
using YaoPlots
using IRTools: IR
using ZXCalculus
using YaoArrayRegister

@device function test_extract()
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

@device function test_phase()
    5 => H
    5 => shift(0.0)
    @ctrl 4 5 => X
    5 => shift($(7/4*π))
    @ctrl 1 5 => X
    5 => shift($(1/4*π))
    @ctrl 4 5 => X
    5 => shift($(7/4*π))
    @ctrl 1 5 => X
    4 => shift($(1/4*π))
    5 => shift($(1/4*π))
    @ctrl 1 4 => X
    4 => shift($(7/4*π))
    1 => shift($(1/4*π))
    @ctrl 1 4 => X
    @ctrl 4 5 => X
    5 => shift($(7/4*π))
    @ctrl 3 5 => X
    5 => shift($(1/4*π))
    @ctrl 4 5 => X
    5 => shift($(7/4*π))
    @ctrl 3 5 => X
    4 => shift($(1/4*π))
    5 => shift($(1/4*π))
    @ctrl 3 4 => X
    4 => shift($(7/4*π))
    5 => H
    3 => shift($(1/4*π))
    @ctrl 3 4 => X
    5 => shift(0.0)
    @ctrl 4 5 => X
    5 => H
    5 => shift(0.0)
    @ctrl 3 5 => X
    5 => shift($(7/4*π))
    @ctrl 2 5 => X
    5 => shift($(1/4*π))
    @ctrl 3 5 => X
    5 => shift($(7/4*π))
    @ctrl 2 5 => X
    3 => shift($(1/4*π))
    5 => shift($(1/4*π))
    @ctrl 2 3 => X
    3 => shift($(7/4*π))
    5 => H
    2 => shift($(1/4*π))
    @ctrl 2 3 => X
    5 => shift(0.0)
    @ctrl 3 5 => X
    5 => H
    5 => shift(0.0)
    @ctrl 2 5 => X
    5 => shift($(7/4*π))
    @ctrl 1 5 => X
    5 => shift($(1/4*π))
    @ctrl 2 5 => X
    5 => shift($(7/4*π))
    @ctrl 1 5 => X
    2 => shift($(1/4*π))
    5 => shift($(1/4*π))
    @ctrl 1 2 => X
    2 => shift($(7/4*π))
    5 => H
    1 => shift($(1/4*π))
    @ctrl 1 2 => X
    5 => shift(0.0)
    @ctrl 2 5 => X
    @ctrl 1 5 => X
end

circ0 = test_phase()
mat0 = zeros(ComplexF64, 32, 32)
for i = 1:32
    st = zeros(ComplexF64, 32)
    st[i] = 1
    r0 = ArrayReg(st)
    r0 |> circ0
    mat0[:,i] = r0.state
end
println(findall(real.(mat0) .> 1/2))

circ1 = test_phase()
mat1 = zeros(ComplexF64, 32, 32)
for i = 1:32
    st = zeros(ComplexF64, 32)
    st[i] = 1
    r1 = ArrayReg(st)
    r1 |> circ1
    mat1[:,i] = r1.state
end
println(findall(real.(mat1) .> 1/2))

sum(real.(mat0 - mat1) .> 1e-15)
findall(real.(mat0) .> 1/2) == findall(real.(mat1) .> 1/2)

println(r0.state - r1.state)

code = @code_yao test_phase()
circ = ZXDiagram(code)
code2 = optimize(code)
circ2 = ZXDiagram(code2)
plot(circ)
plot(circ2)
code2 = sink_quantum!(optimize(code))

println(code)
println(code2)
