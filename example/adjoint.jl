using YaoIR
using NiLang

@i @device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1=>shift(2π/2^k)
    end

    #if (n > 1, ~)
        #2:n => qft(n-1)
    #end
end

Base.adjoint(h::Circuit{:H}) = h
function Base.adjoint(s::Circuit{:shift})
    typeof(s)(s.fn, s.free .|> conj)
end

function Base.adjoint(s::Circuit{name}) where name
    Inv(s)
end

using YaoArrayRegister, Test
using FFTW
@testset "check example" begin
    r = rand_state(4)
    state_vec = statevec(r)
    a = invorder!(copy(r)) |> qft(4)
    kv = ifft(state_vec) * sqrt(length(state_vec))
    @test statevec(a) ≈ kv
    r2 = copy(r) |> qft(4) |> (~qft)(4)
    @test r2 ≈ r
end
