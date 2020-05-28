using YaoLang
using YaoArrayRegister
using FFTW
using Test

@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
end

@device strict=:pure function hadamard()
    1 => H
end

@testset "example/hadamard" begin
    ir = @code_qast hadamard()
    @test ir.strict_mode == :pure
    r = rand_state(1)
    @test (copy(r) |> hadamard()) ≈ (copy(r) |> H())
end


@testset "example/qft" begin
    r = rand_state(4)
    state_vec = statevec(r)
    a = invorder!(copy(r)) |> qft(4)
    kv = ifft(state_vec) * sqrt(length(state_vec))
    @test statevec(a) ≈ kv

    circ = qft(4)
    @test circ(1:4) == ((1:4) => circ)
    @test ((1:4) => circ)(copy(r)) == circ(1:4)(copy(r))
    @test ((1, 2, 3, 4) => circ)(copy(r)) == circ(1:4)(copy(r))
end
