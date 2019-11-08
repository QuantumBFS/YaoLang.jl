using YaoIR, YaoArrayRegister
using LinearAlgebra
using Test

shift_m(theta::T) where T = M = Diagonal(Complex{T}[1.0, exp(im * theta)])

function qft3!(r)
    H = ComplexF64[1 1;1 -1] / sqrt(2)
    instruct!(r, H, (1, ))

    for k in 2:3
        U = shift_m(2π/2^k)
        instruct!(r, U, (1, ), (k, ), (1, ))
    end

    instruct!(r, H, (2, ))

    U = shift_m(2π/2^2)
    instruct!(r, U, (2, ), (3, ), (2, ))

    instruct!(r, H, (3, ))
    return nothing
end

@device function qft(n::Int)
    1 => H
    for k in 2:n
        control(k, 1=>Shift(2π/2^k))
    end

    if n > 1
        2:n => qft(n-1)
    end
end

@testset "test qft compilation" begin
    r = rand_state(3)
    r1 = copy(r); r2 = copy(r);
    exec!(r1, qft(3))
    qft3!(r2)

    @test isapprox(r1, r2)
end
