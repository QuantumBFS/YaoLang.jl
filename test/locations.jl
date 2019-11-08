using YaoIR
using Test

@test Locations(2) == Position(2)
@test Locations(2:5) == ContiguousLocations(2, 5)

@test create_locations(:k) == :(Locations(k))
@test create_locations(:(2 + 3)) == :(Locations(2 + 3))
@test create_locations(2) == Position(2)
@test create_locations(:(2:5)) == ContiguousLocations(2, 5)
