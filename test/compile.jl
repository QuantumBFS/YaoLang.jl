using YaoIR, YaoArrayRegister
using Test

@testset "test transform" begin
    @test transform(:(1 => H)) == GateLocation(1, :H)
    @test transform(:(control(k, 1=>H))) == Control(:k, GateLocation(1, :H))
    @test transform(:(measure(1, 2))) == Measure((1, 2))
    @test transform(:(measure(1:2))) == Measure(:(1:2))
end

@testset "compile to jl" begin
    @test compile_to_jl(:r, GateLocation(1, :H)) == :(YaoIR.exec!(r, H, $(Position(1))))
    @test compile_to_jl(:r, Control(:k, GateLocation(1, :H))) == :(YaoIR.exec!(r, H, $(Position(1)), Locations(k)))
    @test compile_to_jl(:r, Measure(:(1:2))) == :(YaoIR.measure!(r, $(Locations(1:2))))

    @test compile_to_jl(:r, GateLocation(1, :H), :locs) == :(YaoIR.exec!(r, H, locs[$(Position(1))]))
    @test compile_to_jl(:r, Control(:k, GateLocation(1, :H)), :locs) == :(YaoIR.exec!(r, H, locs[$(Position(1))], locs[Locations(k)]))
    @test compile_to_jl(:r, Measure(:(1:2)), :locs) == :(YaoIR.measure!(r, locs[$(Locations(1:2))]))

    # TODO: test @column after this is handled
end
