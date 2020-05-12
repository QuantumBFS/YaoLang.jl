"""
    split_device_def(ex)

Split device kernel definition, similar to `ExprTools.splitdef`, but checks syntax.
"""
function split_device_def(ex::Expr)
    def = splitdef(ex, throw = false)
    # syntax check
    def !== nothing || throw(Meta.ParseError("Invalid Syntax: expect a function definition."))
    haskey(def, :name) ||
        throw(Meta.ParseError("Invalid Syntax: generic circuit cannot be anonymous"))
    def[:name] isa Symbol ||
        throw(Meta.ParseError("Invalid Syntax: generic circuit cannot be defined on existing Julia objects"))
    return def
end

function variables(def::Dict)
    if haskey(def, :args)
        return def[:args]
    else
        return Any[]
    end
end

function arguements(def::Dict)
    map(rm_annotations, variables(def))
end

# TODO: actually implement this using JuliaVariables
function capture_free_variables(def::Dict)
    return arguements(def)
end


"""
    rm_annotations(x)

Remove type annotation of given expression.
"""
rm_annotations(x) = x

function rm_annotations(x::Expr)
    if x.head == :(::)
        return x.args[1]
    elseif x.head in [:(=), :kw] # default values
        return rm_annotations(x.args[1])
    else
        return x
    end
end

function splatting_variables(variables, free)
    Expr(:(=), Expr(:tuple, variables...), free)
end

function argtypes(def::Dict)
    ex = Expr(:curly, :Tuple)
    if haskey(def, :args)
        for each in def[:args]
            if each isa Symbol
                push!(ex.args, :Any)
            elseif (each isa Expr) && (each.head === :(::))
                push!(ex.args, each.args[end])
            end
        end
    end

    return ex
end

generic_circuit(name::Symbol) = :($(GenericCircuit){$(QuoteNode(name))})

to_locations(x) = :(Locations($x))
to_locations(x::Int) = Locations(x)

is_literal(x) = true
is_literal(x::Expr) = false
is_literal(x::Symbol) = false


value(x) = x
value(x::QuoteNode) = x.value
