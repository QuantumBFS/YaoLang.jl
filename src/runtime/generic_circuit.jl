export GenericCircuit, Circuit

function evaluate end

export PrimitiveCircuit
# Primitive Routines
struct PrimitiveCircuit{name} end

# avoid splatting
evaluate(c::PrimitiveCircuit) = c()
evaluate(c::PrimitiveCircuit, x) = c(x)
evaluate(c::PrimitiveCircuit, x, y) = c(x, y)
evaluate(c::PrimitiveCircuit, x, y, xs...) = c(x, y, xs...)

function Base.show(io::IO, x::PrimitiveCircuit{name}) where {name}
    print(io, name, " (primitive circuit)")
end

"""
    GenericCircuit{name}

Generic quantum circuit is the quantum counterpart of generic function.
"""
struct GenericCircuit{name} end

function Base.show(io::IO, x::GenericCircuit{name}) where {name}
    print(io, name, " (generic circuit with ", length(methods(x).ms), " methods)")
end

struct Circuit{name,F<:Function,Free<:Tuple}
    fn::Function
    free::Free
end

Circuit{name}(fn::Function, free::Tuple) where {name} =
    Circuit{name,typeof(fn),typeof(free)}(fn, free)
Circuit{name}(fn::Function) where {name} = Circuit{name}(fn, ())

function Base.show(io::IO, x::Circuit{name}) where {name}
    print(io, name, " (quantum circuit)")
end

# syntax sugar
(circ::Circuit)(r::AbstractRegister) = circ(r, 1:nactive(r))
(circ::Circuit)(locs) = r->(circ(r, locs); r)
(circ::Circuit)(locs, ctrl_locs) = r->(circ(r, locs, ctrl_locs); r)

function Base.:(|>)(r::AbstractRegister, circ::Circuit)
    circ(r)
    return r
end

# we only convert to Locations right before we call the stubs
(circ::Circuit)(register::AbstractRegister, locs) = circ.fn(circ, register, Locations(locs))
(circ::Circuit)(register::AbstractRegister, locs, ctrl_locs) =
    circ.fn(circ, register, Locations(locs), CtrlLocations(ctrl_locs))

# allow primitive circuits to be called directly
(c::PrimitiveCircuit)(r::AbstractRegister, locs) = c()(r, locs)
(c::PrimitiveCircuit)(r::AbstractRegister) = c()(r)
(c::PrimitiveCircuit)(locs::Locations) = r->c(r, locs)
(c::PrimitiveCircuit)(locs::Locations, ctrl_locs::CtrlLocations) = r->c(r, locs, ctrl_locs)
