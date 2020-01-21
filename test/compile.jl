using Revise
using YaoIR, YaoArrayRegister
using Test

@testset "test transform" begin
    @test transform(:(1 => H)) == GateLocation(1, :H)
    @test transform(:(control(k, 1=>H))) == Control(:k, GateLocation(1, :H))
    @test transform(:(measure(1, 2))) == Measure((1, 2))
    @test transform(:(measure(1:2))) == Measure(:(1:2))
end

@testset "compile to jl" begin
    @test compile_to_jl(:r, GateLocation(1, :H)) == :(YaoIR.evaluate!(r, H, $(Position(1))))
    @test compile_to_jl(:r, Control(:k, GateLocation(1, :H))) == :(YaoIR.evaluate!(r, H, $(Position(1)), Locations(k)))
    @test compile_to_jl(:r, Measure(:(1:2))) == :(YaoIR.measure!(r, $(Locations(1:2))))

    @test compile_to_jl(:r, GateLocation(1, :H), :locs) == :(YaoIR.evaluate!(r, H, locs[$(Position(1))]))
    @test compile_to_jl(:r, Control(:k, GateLocation(1, :H)), :locs) == :(YaoIR.evaluate!(r, H, locs[$(Position(1))], locs[Locations(k)]))
    @test compile_to_jl(:r, Measure(:(1:2)), :locs) == :(YaoIR.measure!(r, locs[$(Locations(1:2))]))

    # TODO: test @column after this is handled
end

@which YaoIR.flatten_position(GateLocation(1, :H), :locs)


@device function qft(n::Int)
    1 => H
    for k in 2:n
        control(k, 1=>Shift(2π/2^k))
    end

    if n > 1
        2:n => qft(n-1)
    end
end

@device function qft(l::Int, n::Int)
    1 => H
end


YaoIR.evaluate!(rand_state(3), qft(3))