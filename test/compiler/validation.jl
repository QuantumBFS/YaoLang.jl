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
    ir = YaoIR(@__MODULE__, ex, :hybrid)
    @test is_quantum(ir) == false
    @test is_pure_quantum(ir) == false
    @test is_qasm_compatible(ir) == false
end
