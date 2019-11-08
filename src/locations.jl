export Locations, ContiguousLocations, Position, LocationError
export create_locations, create_contiguous_locations
using MLStyle

"""
    Locations{T}

A general immutable struct to tag locations. This prevents dispatch problems
in [`exec!`](@ref).
"""
struct Locations{T}
    locations::T
end

"""
    ContiguousLocations

Type for contiguous locations, it can be initialized with
`ContiguousLocations(start, stop)` or `ContiguousLocations(unit_range)`.
"""
const ContiguousLocations = Locations{UnitRange{Int}}

ContiguousLocations(start::Int, stop::Int) = ContiguousLocations(start:stop)

"""
    Position

A single location marked by `Int`, it can be initialized with
`Position(x)` or `Locations(int)`.
"""
const Position = Locations{Int}

Base.show(io::IO, x::Locations) = printstyled(io, x.locations, color=:light_blue)

# we try to convert it to Locations in runtime by default
# so this will give a nice error
create_locations(x) = :(Locations($x))
# if the location is specified by literals
# we process it to Locations in compile time
create_locations(x::Locations) = x
create_locations(x::Int) = Position(x)
create_locations(x::NTuple{N, Int}) where N = Locations(x)
create_contiguous_locations(start::Int, stop::Int) = Locations(start:stop)

create_locations(x::Symbol) = :(Locations($x))
create_contiguous_locations(start, stop) = :(Locations($start:$stop))

function create_locations(ex::Expr)
    @match ex begin
        :($start:$stop) => create_contiguous_locations(start, stop)
        _ => :(Locations($ex))
    end
end

## comparision
Base.:(==)(lhs::Locations{T}, rhs::Locations{T}) where T = lhs.locations == rhs.locations
Base.:(==)(lhs::Locations, rhs::Locations) = false

Base.length(x::Position) = 1
Base.length(x::Locations) = length(x.locations)

# we use the builtin slice as default
function Base.getindex(x::Locations, inds::Locations)
    return Locations(x.locations[inds.locations])
end

struct LocationError <: Exception
    msg::String
end

LocationError() = LocationError("")

# index parent location space is 1
# we need this check explicitly since for Int this won't error
Base.@propagate_inbounds function Base.getindex(x::Position, inds::Locations{Int})
    @boundscheck inds.locations == 1 || throw(LocationError())
    return x
end

to_tuple(x::Locations) = Tuple(x.locations)
to_tuple(x::Locations{<:Tuple}) = x.locations
