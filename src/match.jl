struct Variable
    id::Symbol
end

abstract type AbstractPattern end

struct ExactPattern <: AbstractPattern
    ex::Expr
end

struct Matches
    p::Dict{Variable,Any}
end

function match(pattern::ExactPattern, ex::Expr, m)
    pattern.head === ex.head || return

    for (x, y) in zip(pattern.args, ex.args)
        m = match(x, y, m)
        m === nothing && return
    end
end
