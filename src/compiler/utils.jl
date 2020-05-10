export rm_annotations, argtypes

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
