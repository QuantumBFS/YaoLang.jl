using Test
using YaoLang
using YaoLang.Compiler

@device function demo_circ_simp()
    1 => shift($(7π / 4))
    1 => H
    1 => Rx($(π / 4))
    4 => H
    @ctrl 1 4 => Z
    @ctrl 4 1 => X
    1 => H
    4 => H
    1 => T
    4 => shift($(3π / 2))
    4 => X
    1 => H
    4 => S
    4 => X
    2 => S
    @ctrl 2 3 => X
    2 => H
    @ctrl 2 3 => X
    2 => T
    3 => S
    2 => H
    3 => H
    3 => S
    @ctrl 2 3 => X
end

@testset "gate_count" begin
    @test gate_count(demo_circ_simp) == Dict(
        "YaoLang.T" => 2,
        "YaoLang.H" => 8,
        "YaoLang.Rx" => 1,
        "YaoLang.X" => 2,
        "YaoLang.S" => 4,
        "YaoLang.shift" => 2,
        "@ctrl YaoLang.Z" => 1,
        "@ctrl YaoLang.X" => 4,
    )
end
