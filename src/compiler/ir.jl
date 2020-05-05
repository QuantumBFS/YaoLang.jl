export LocationExpr, GateLocation, Control, Measure, Column
export parse_ast, parse_locations, parse_ctrl, parse_measure

struct IRCode
end

struct LocationExpr
    ex
    LocationExpr(ex) = new(to_locations(ex))
end

to_locations(x) = :(Locations($x))
to_locations(x::Int) = Locations(x)

is_literal(x) = true
is_literal(x::Expr) = false
is_literal(x::Symbol) = false

function to_locations(x::Expr)
    # literal range
    if (x.head === :call) && (x.args[1] === :(:))
        args = x.args[2:end]
        all(is_literal, args) && return Locations(Colon()(args...))
    elseif x.head === :tuple # literal tuple
        all(is_literal, x.args) && return Locations(Tuple(x.args))
    end
    return :(Locations($x))
end

struct GateLocation
    location::LocationExpr
    gate

    GateLocation(loc, gate) = new(LocationExpr(loc), gate)
end

struct Control
    ctrl_location::LocationExpr
    gate::GateLocation

    Control(ctrl_locs, gate) = new(LocationExpr(ctrl_locs), gate)
end

struct Measure
    location::LocationExpr
    operator
    config

    Measure(locs, operator, config) = new(LocationExpr(locs), operator, config)
end

Measure(locs) = Measure(locs, nothing, nothing)
Measure(locs, operator) = Measure(locs, operator, nothing)

struct Column
    ex
end

function Base.show(io::IO, ex::LocationExpr)
    if ex.ex isa Locations
        m = ex.ex
    else
        m = ex.ex.args[2]
    end
    printstyled(io, m, color=:light_blue)
end

function Base.show(io::IO, ex::GateLocation)
    print(io, ex.location)
    printstyled(io, " => ", color=:light_magenta)
    print(io, ex.gate)
end

function Base.show(io::IO, ex::Control)
    printstyled(io, "@ctrl ", color=:light_cyan)
    print(io, ex.ctrl_location, " ", ex.gate)
end

function Base.show(io::IO, ex::Measure)
    printstyled(io, "@measure ", color=:light_cyan)
    ex.config === nothing || printstyled(io, ex.config, " ", color=:yellow)
    print(io, ex.location)
    ex.operator === nothing || print(io, " ", ex.operator)
end

Base.:(==)(x::LocationExpr, y::LocationExpr) = x.ex == y.ex
Base.:(==)(x::GateLocation, y::GateLocation) = (x.gate == y.gate) && (x.location == y.location)
Base.:(==)(x::Control, y::Control) = (x.ctrl_location == y.ctrl_location) && (x.gate == y.gate)
Base.:(==)(x::Measure, y::Measure) = (x.location == y.location) && (x.operator == y.operator)
Base.:(==)(x::Column, y::Column) = x.ex == y.ex

parse_ast(x) = x
function parse_ast(ex::Expr; pass=[parse_locations, parse_ctrl, parse_measure])
    for p in pass
        ex = p(ex)
    end
    return ex
end

"""
    parse_locations(x)

Transform location argument from Julia AST to Yao IR. The definition of
gate locations is the first layer `=>` in a block.

# Example

```julia
quote
    1 => H # gate location
    [1=>H, 3=>X] # construct a list of pairs
    y = 1 => H # create a pair and assign it to variable y
end
```
"""
parse_locations(x) = x

function parse_locations(ex::Expr)
    if (ex.head === :call) && (ex.args[1] == :(=>))
        return GateLocation(ex.args[2], ex.args[3])
    elseif ex.head in [:block, :if, :for, :macrocall #= make @inbounds etc. work =#]
        return Expr(ex.head, map(parse_locations, ex.args)...)
    else
        return ex
    end
end

"""
    parse_ctrl(x)

Transform controlled location argument from Julia AST to Yao IR. The definition of controlled gate
location is `@ctrl <ctrl locations> <gate location>`. The control configuration is specified using
signs.

# Example

```julia
quote
    @ctrl (-1, 2, 3) 4=>X
    @ctrl 1:3 4=>X
end
```
"""
parse_ctrl(x) = x

function parse_ctrl(ex::Expr)
    if (ex.head === :macrocall) && (ex.args[1] == Symbol("@ctrl"))
        length(ex.args) == 4 || throw(Meta.ParseError("@ctrl expect 2 argument, got $(length(ex.args)-2)"))
        return Control(ex.args[3], parse_locations(ex.args[4]))
    else
        return Expr(ex.head, map(parse_ctrl, ex.args)...)
    end
end

"""
    parse_measure(x)

Transform measurement statement from Julia AST to Yao IR. The definition of measurement is
`@measure <location> <operator expression>`. The operator expression should return an `AbstractMatrix`
or `AbstractBlock`. It will return a value which is the measurement result.

# Example

```julia
quote
    c1 = @measure 1:3
    c2 = @measure 1:2 kron(X, X)
    c3 = @measure 1:2 kron(X, X) reset_to=1
end
```
"""
parse_measure(x) = x

function parse_measure(ex::Expr)
    if (ex.head === :macrocall) && (ex.args[1] == Symbol("@measure"))
        length(ex.args) <= 5 || throw(Meta.ParseError("@measure expect 1, 2 or 3 arguments, got $(length(ex.args)-2)"))
        if length(ex.args) == 3
            return Measure(ex.args[3])
        elseif length(ex.args) == 4 
            return is_measure_cfg(ex.args[3]) ? Measure(ex.args[4], nothing, ex.args[3]) :
                is_measure_cfg(ex.args[4]) ? Measure(ex.args[3], nothing, ex.args[4]) :
                Measure(ex.args[3], ex.args[4])
        else
            return is_measure_cfg(ex.args[3]) ? Measure(ex.args[4], ex.args[5], ex.args[3]) :
                is_measure_cfg(ex.args[4]) ? Measure(ex.args[3], ex.args[5], ex.args[4]) :
                is_measure_cfg(ex.args[5]) ? Measure(ex.args[3], ex.args[4], ex.args[5]) :
                throw(Meta.ParseError("Invalid Syntax: expect measurement configuration, got $ex"))
        end
    else
        return Expr(ex.head, map(parse_measure, ex.args)...)
    end
end

is_measure_cfg(x) = false
function is_measure_cfg(ex::Expr)
    ex.head == :(=) &&
    ex.args[1] in [:reset_to, :remove]
end
