using YaoLang
using YaoLang.Compiler: optimize
using ZXCalculus
using YaoArrayRegister
using Test

@device function test_cir()
    @ctrl $(2, 3) 1 => X
    1 => X
    2 => X
    @ctrl $(2, 1) 3 => X
    @ctrl $(2, 1) 3 => X
    @ctrl $(2, 1) 3 => X
    @ctrl $(1, 2) 3 => X
    @ctrl $(1, 3) 2 => X
end
cir = test_cir()
mat = zeros(ComplexF64, 8, 8)
for i = 1:8
    st = zeros(ComplexF64, 8)
    st[i] = 1
    r0 = ArrayReg(st)
    r0 |> cir
    mat[:,i] = r0.state
end

@device optimizer = [:zx_teleport] function test_cir_teleport()
    @ctrl $(2, 3) 1 => X
    1 => X
    2 => X
    @ctrl $(2, 1) 3 => X
    @ctrl $(2, 1) 3 => X
    @ctrl $(2, 1) 3 => X
    @ctrl $(1, 2) 3 => X
    @ctrl $(1, 3) 2 => X
end
cir_teleport = test_cir_teleport()
mat_teleport = zeros(ComplexF64, 8, 8)
for i = 1:8
    st = zeros(ComplexF64, 8)
    st[i] = 1
    r0 = ArrayReg(st)
    r0 |> cir_teleport
    mat_teleport[:,i] = r0.state
end
abs.(mat_teleport) .> 1e-10
mat_teleport = (mat[1,4]/mat_teleport[1,4]) .* mat_teleport
sum(abs.(mat - mat_teleport) .> 1e-10)
