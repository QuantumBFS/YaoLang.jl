using YaoLang
using YaoLang.Compiler
using Test

ex = :(function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
end)

@testset "validation" begin
    ir = YaoIR(@__MODULE__, ex)
    @test is_quantum(ir) == false
    @test is_pure_quantum(ir) == false
    @test is_qasm_compatible(ir) == false
end

@testset "disallow constants" begin
    ex = :(function circ()
        1=>H
        2=>Z
        1 => shift(π/2)
        3 => X
        @ctrl 1 2=>X
    end)
    ir = YaoIR(@__MODULE__, ex)
    @test is_pure_quantum(ir) == false
end
