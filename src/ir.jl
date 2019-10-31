# keywords
struct GateLocation{T}
    location::T
    gate
end

struct Control
    ctrl_location
    content::GateLocation
end

struct Measure{T}
    location::T
end

struct SameColumn
    args::Vector{Any}
end

function Base.show(io::IO, ex::GateLocation)
    print(io, ex.location)
    printstyled(io, " => ", color=:light_blue)
    print(io, ex.gate)
    printstyled(io, "  #=gate=#", color=:light_black)
end

function Base.show(io::IO, ctrl::Control)
    printstyled(io, "control", color=:light_red)
    print(io, "(", ctrl.ctrl_location, ", ", ctrl.content, ")")
end

function Base.show(io::IO, ex::Measure)
    printstyled(io, "measure", color=:light_cyan)
    print(io, "(", ex.location, ")")
end

function Base.show(io::IO, ex::Measure{<:Tuple})
    printstyled(io, "measure", color=:light_cyan)
    print(io, ex.location)
end

function Base.show_unquoted(io::IO, ex::SameColumn, indent::Int, prec::Int)
    printstyled(io, "@column ", color=:magenta)
    for each in ex.args
        Base.show_unquoted(io, each, indent, prec)
    end
end

function Base.show(io::IO, ex::SameColumn)
    Base.show_unquoted(io, ex, 0, -1)
end
