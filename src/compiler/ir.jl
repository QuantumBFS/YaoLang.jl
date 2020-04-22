export LocationExpr, GateLocation, Control, Measure, SameColumn

"""
    LocationExpr

Location expression.
"""
struct LocationExpr
    ex::Any
end

LocationExpr(ex::LocationExpr) = ex
create_locations(ex::LocationExpr) = ex
function Base.show(io::IO, x::LocationExpr)
    if x.ex isa Locations
        m = x.ex
    else
        m = x.ex.args[2]
    end
    printstyled(io, m, color = :light_blue)
end

struct GateLocation
    location::LocationExpr
    gate::Any

    GateLocation(locations, gate) = new(LocationExpr(create_locations(locations)), gate)
end

struct Control
    ctrl_location::LocationExpr
    content::GateLocation

    function Control(ctrl_locations, content)
        new(LocationExpr(create_locations(ctrl_locations)), content)
    end
end

struct Measure
    location::LocationExpr

    Measure(locations) = new(LocationExpr(create_locations(locations)))
    Measure(locs...) = Measure(locs)
end

struct SameColumn
    args::Vector{Any}
end

function Base.show(io::IO, ex::GateLocation)
    print(io, ex.location)
    printstyled(io, " => ", color = :light_magenta)
    print(io, ex.gate)
    printstyled(io, "  #=gate=#", color = :light_black)
end

function Base.show(io::IO, ctrl::Control)
    printstyled(io, "control", color = :light_red)
    print(io, "(", ctrl.ctrl_location, ", ", ctrl.content, ")")
end

function Base.show(io::IO, ex::Measure)
    printstyled(io, "measure", color = :light_cyan)

    if ex.location.ex.locations isa Tuple
        print(io, ex.location)
    else
        print(io, "(", ex.location, ")")
    end
end

function Base.show_unquoted(io::IO, ex::SameColumn, indent::Int, prec::Int)
    printstyled(io, "@column ", color = :magenta)
    for each in ex.args
        Base.show_unquoted(io, each, indent, prec)
    end
end

function Base.show(io::IO, ex::SameColumn)
    Base.show_unquoted(io, ex, 0, -1)
end

Base.:(==)(lhs::LocationExpr, rhs::LocationExpr) = lhs.ex == rhs.ex

function Base.:(==)(lhs::GateLocation, rhs::GateLocation)
    lhs.location == rhs.location && lhs.gate == rhs.gate
end

function Base.:(==)(lhs::Control, rhs::Control)
    lhs.ctrl_location == rhs.ctrl_location && lhs.content == rhs.content
end

function Base.:(==)(lhs::Measure, rhs::Measure)
    lhs.location == rhs.location
end
