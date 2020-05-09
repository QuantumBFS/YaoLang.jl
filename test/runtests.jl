using YaoIR
using Test
using FFTW
using YaoArrayRegister

@testset "runtime" begin
    include("runtime/locations.jl")
end

@testset "compiler" begin
    include("compiler/ir.jl")
end

@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1=>shift(2π/2^k)
    end

    if n > 1
        2:n => qft(n-1)
    end
end

@testset "check example" begin
    r = rand_state(4)
    state_vec = statevec(r)
    a = invorder!(copy(r)) |> qft(4)
    kv = ifft(state_vec) * sqrt(length(state_vec))
    @test statevec(a) ≈ kv
end
