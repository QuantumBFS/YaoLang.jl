struct GenericCircuit{name} end

function Base.show(io::IO, x::GenericCircuit{name}) where name
    print(io, name, " (generic circuit with ", length(methods(x).ms), " methods)")
end

struct Circuit{name, F <: Function, Free <: Tuple}
    fn::Function
    free::Free
end

Circuit{name}(fn::Function, free::Tuple) where name = Circuit{name, typeof(fn), typeof(free)}(fn, free)
Circuit{name}(fn::Function) where name = Circuit{name}(fn, ())

function Base.show(io::IO, x::Circuit{name}) where name
    print(io, name, " (quantum circuit)")
end

# syntax sugar
(p::Pair{<:Locations, <:Circuit})(register::AbstractRegister) = p.second(register, p.first)
(p::Pair{Int, <:Circuit})(register::AbstractRegister) = p.second(register, p.first)
(p::Pair{UnitRange{Int}, <:Circuit})(register::AbstractRegister) = p.second(register, p.first)
(p::Pair{NTuple{N, Int}, <:Circuit} where N)(register::AbstractRegister) = p.second(register, p.first)

(circ::Circuit)(r::AbstractRegister) = circ(r, 1:nactive(r))
(circ::Circuit)(locs) = Pair(locs, circ)

# we only convert to Locations right before we call the stubs
(circ::Circuit)(register, locs) = circ.fn(circ, register, Locations(locs))
(circ::Circuit)(register, locs, ctrl_locs) = circ.fn(circ, register, Locations(locs), Locations(ctrl_locs))
