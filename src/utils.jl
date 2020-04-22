using MLStyle
using Base.Meta: ParseError

struct MethodSignature
    name::Any
    args::Vector
    signature::Vector
end

signature(ex) = throw(ParseError("This is not a function definition."))

function signature(ex::Expr)
    head = find_function_head(ex)
end

function find_function_head(ex::Expr)
    # call = body
    if ex.head in [:(=), :function, :(->)]
        head = ex.args[1]
    else
        throw(ParseError("This is not a valid function definition."))
    end
    return head
end

function propagate_where(ex::Expr, w::Expr) end

ex = :(f(x) = x)
ex = :(f(x, y) = x, y)
ex = :(x -> x + 1)
ex = :(x::Int -> x + 1)
ex = :((x::Int, y::T) where {T<:Integer->x + y}) # invalid

ex = :(function foo(x) end)
ex = :(function foo(x::M, y::T) where {M,T<:M} end)
ex = :(f(x, y::T) where {T<:Integer} = x + y)

find_function_head(ex)

ex.args[1].args


struct Goo{Args<:Tuple}
    args::Args
end

goo = Goo((1, 2))

exec(goo::Goo, x::Int) = println("abstract")

function exec(goo::Goo{Tuple{Integer,Number}}, x::Int)
    println(goo.args)
end
Goo{Tuple{<:Integer,<:M} where {M<:Number}}
typeof(goo) <: Goo{Tuple{Integer,Number}}

exec(goo, 2)

@generated function foo(x::Int)
    quote
        @eval function moo(x::Float64)
            return x
        end
    end
end

const __CIRCUIT_TABLE__ = Dict{Circuit,CircuitMethod}

abstract type AbstractRegister end
struct ArrayReg end

struct Circuit{Args<:Tuple}
    args::Tuple
end

struct CircuitMethod
    signature::Any
end

struct Location
    location::Any
end

struct CtrlLocation
    location::Any
    ctrl_location::Any
    configuration::Any # ctrl configuration
end

function evaluate!(
    register::AbstractRegister,
    locations::CtrlLocation,
    circuit::Circuit,
    n::Int,
    theta,
) end
