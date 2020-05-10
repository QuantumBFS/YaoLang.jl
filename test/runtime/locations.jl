using Test
using YaoIR

@testset "constructor type check" begin
    @test_throws LocationError Locations(1.0)
    @test_throws LocationError Locations(1, 2, 3.0)
    @test_throws LocationError Locations(1, 2, 3.0)
end

@testset "tuple conversion" begin
    @test Tuple(Locations(1)) == (1,)
    @test Tuple(Locations((2, 4, 5))) == (2, 4, 5)
    @test Tuple(Locations(1:4)) == (1, 2, 3, 4)
end

@testset "merge locations" begin
    @test merge_locations(Locations(1), Locations(2)) == Locations(1, 2)
    @test merge_locations(Locations(1:3), Locations(5:9)) == Locations((1:3..., 5:9...))
    @test merge_locations(Locations(1), Locations(2), Locations(4:8)) == Locations((1, 2, 4:8...))
end

@testset "location mapping" begin
    locs = Locations(2)
    @test_throws LocationError locs[Locations(2)]
    @test_throws LocationError locs[Locations(1, 2)]
    @test_throws LocationError locs[Locations(1:3)]

    @test locs[Locations(1)] == locs
    @test locs[Locations(1:1)] == locs
    @test locs[Locations((1,))] == locs

    locs = Locations((1, 3, 5))
    @test_throws LocationError locs[Locations(4)]
    @test_throws LocationError locs[Locations(1, 4)]
    @test_throws LocationError locs[Locations(3:4)]

    @test locs[Locations(2)] == Locations(3)
    @test locs[Locations(1, 2)] == Locations(1, 3)
    @test locs[Locations(1:3)] == Locations(1, 3, 5)

    locs = Locations(3:5)
    @test_throws LocationError locs[Locations(4)]
    @test_throws LocationError locs[Locations(1, 4)]
    @test_throws LocationError locs[Locations(4:6)]

    @test locs[Locations(2)] == Locations(4)
    @test locs[Locations(1, 3)] == Locations(3, 5)
    @test locs[Locations(1:2)] == Locations(3:4)
end
