export Locations, CtrlLocations, AbstractLocations, LocationError, merge_locations

const LocationStorageTypes = Union{Int, NTuple{N, Int} where N, UnitRange{Int}, Vector{Int}}

abstract type AbstractLocations end

"""
    merge_locations(locations...)

Construct a new `Locations` by merging two or more existing locations.
"""
merge_locations(x::AbstractLocations, y::AbstractLocations, locations::AbstractLocations...) = merge_locations(merge_locations(x, y), locations...)

"""
    Locations <: AbstractLocations

Type to annotate locations in quantum circuit.

    Locations(x)

Create a `Locations` object from a raw location statement. Valid storage types are:

- `Int`: single position
- `NTuple{N, Int}`: a list of locations
- `UnitRange{Int}`: contiguous locations

Other types will be converted to the storage type via `Tuple`.
"""
struct Locations{T <: LocationStorageTypes} <: AbstractLocations
    storage::T

    Locations(x::T) where {T <: LocationStorageTypes} = new{T}(x)
end

# skip it if x is a location
Locations(x::Locations) = x
Locations(xs...) = Locations(xs)
Locations(x::NTuple{N,T}) where {N,T} = throw(LocationError("expect Int, got $T"))

Base.@propagate_inbounds Base.getindex(l::Locations, idx...) = getindex(l.storage, idx...)
Base.length(l::Locations) = length(l.storage)
Base.iterate(l::Locations) = iterate(l.storage)
Base.iterate(l::Locations, st) = iterate(l.storage, st)
Base.eltype(::Type{T}) where {T<:Locations} = Int
Base.eltype(x::Locations) = Int
Base.show(io::IO, x::Locations) = print(io, "Locations(", x.storage, ")")
Base.Tuple(x::Locations) = (x.storage..., )

struct LocationError <: Exception
    msg::String
end

function merge_locations(l1::Locations, l2::Locations)
    Locations((l1.storage..., l2.storage...))
end

# location mapping
# TODO: preserve sign when indexing
# TODO: provide a @inlocation macro via Expr(:meta, :inlocation, true) so when we compile to Julia functions
#       we can use unsafe_mapping directly
@inline unsafe_mapping(parent::Locations{Int}, sub::Locations{Int}) = parent
@inline unsafe_mapping(parent::Locations{Int}, sub::Locations{NTuple{N,Int}}) where {N} = parent
@inline unsafe_mapping(parent::Locations{Int}, sub::Locations{UnitRange{Int}}) = parent
@inline unsafe_mapping(parent::Locations{NTuple{N,Int}}, sub::Locations{Int}) where {N} =
    Locations(@inbounds parent[sub.storage])
@inline unsafe_mapping(parent::Locations{NTuple{N,Int}}, sub::Locations{NTuple{M,Int}}) where {N,M} =
    Locations(map(x -> @inbounds(parent[x]), sub.storage))
@inline unsafe_mapping(parent::Locations{NTuple{N,Int}}, sub::Locations{UnitRange{Int}}) where {N} =
    Locations(@inbounds parent[sub.storage])
@inline unsafe_mapping(parent::Locations{UnitRange{Int}}, sub::Locations{Int}) =
    Locations(@inbounds parent[sub.storage])
@inline unsafe_mapping(parent::Locations{UnitRange{Int}}, sub::Locations{NTuple{N,Int}}) where {N} =
    Locations(map(x -> @inbounds(parent[x]), sub.storage))
@inline unsafe_mapping(parent::Locations{UnitRange{Int}}, sub::Locations{UnitRange{Int}}) =
    Locations(@inbounds parent[sub.storage])

map_error(parent, sub) = throw(LocationError("got $sub in parent space $parent"))

@inline function map_check(parent::Locations{Int}, sub::Locations{Int})
    sub.storage == 1 || map_error(parent, sub)
end

@inline function map_check(parent::Locations{Int}, sub::Locations{Tuple{Int}})
    sub.storage[1] == 1 || map_error(parent, sub)
end

@inline function map_check(parent::Locations{Int}, sub::Locations{NTuple{N,Int}}) where {N}
    map_error(parent, sub)
end

@inline function map_check(parent::Locations{Int}, sub::Locations{UnitRange{Int}})
    (length(sub) == 1) && (sub.storage.start == 1) || map_error(parent, sub)
end

@inline function map_check(parent::Locations{NTuple{N,Int}}, sub::Locations{Int}) where {N}
    1 <= sub.storage <= N || map_error(parent, sub)
end

@inline function map_check(
    parent::Locations{NTuple{N,Int}},
    sub::Locations{NTuple{M,Int}},
) where {N,M}
    all(x -> (1 <= x <= N), sub.storage) || map_error(parent, sub)
end

@inline function map_check(parent::Locations{NTuple{N,Int}}, sub::Locations{UnitRange{Int}}) where {N}
    (1 <= sub.storage.start) && (sub.storage.stop <= N) || map_error(parent, sub)
end

@inline function map_check(parent::Locations{UnitRange{Int}}, sub::Locations{Int})
    1 <= sub.storage <= length(parent) || map_error(parent, sub)
end

@inline function map_check(parent::Locations{UnitRange{Int}}, sub::Locations{NTuple{N,Int}}) where {N}
    all(x -> (1 <= x <= length(parent)), sub.storage) || map_error(parent, sub)
end

@inline function map_check(parent::Locations{UnitRange{Int}}, sub::Locations{UnitRange{Int}})
    (1 <= sub.storage.start) && (sub.storage.stop <= length(parent)) || map_error(parent, sub)
end

# comparing
function Base.:(==)(l1::Locations, l2::Locations)
    length(l1) == length(l2) || return false
    return all(l1.storage .== l2.storage)
end

# CtrlLocations
struct CtrlLocations{T <: LocationStorageTypes} <: AbstractLocations
    storage::Locations{T}
    configs::BitVector
end

# skip itself
CtrlLocations(x::CtrlLocations) = x
CtrlLocations(x::Locations) = CtrlLocations(x, trues(length(x)))
CtrlLocations(x::LocationStorageTypes, cfg::Tuple) = CtrlLocations(Locations(x), BitVector(map(Bool, cfg)))
CtrlLocations(xs...) = CtrlLocations(Locations(xs...))

Base.length(l::CtrlLocations) = length(l.storage)

function Base.show(io::IO, x::CtrlLocations)
    print(io, "CtrlLocations(")
    if all(x.configs)
        print(io, x.storage.storage)
    else
        join(io, map((l, c)-> c ? string(l) : "!"*string(l), x.storage.storage, x.configs), ", ")
    end
    print(io, ")")
end

function merge_locations(l1::CtrlLocations, l2::CtrlLocations)
    CtrlLocations(merge_locations(l1.storage, l2.storage), vcat(l1.configs, l2.configs))
end

# NOTE: CtrlLocations can not be mapped by Locations
@inline unsafe_mapping(parent::Locations, sub::CtrlLocations) = CtrlLocations(unsafe_mapping(parent, sub.storage), sub.configs)
@inline map_check(parent::Locations, sub::CtrlLocations) = map_check(parent, sub.storage)

Base.:(==)(l1::CtrlLocations, l2::CtrlLocations) = (l1.storage == l2.storage) && (l1.configs == l2.configs)

# parent location has to be Locations since CtrlLocations can't be parent
@inline function Base.getindex(parent::Locations, sub::AbstractLocations)
    map_check(parent, sub)
    return unsafe_mapping(parent, sub)
end
