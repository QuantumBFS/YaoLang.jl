# MLStyle patches

@active GlobalRef(x) begin
    if x isa GlobalRef
        (x.mod, x.name)
    else
        nothing
    end
end

@active Argument(x) begin
    if x isa Argument
        Some(x.n)
    else
        nothing
    end
end

@active SSAValue(x) begin
    if x isa SSAValue
        Some(x.id)
    else
        nothing
    end
end

@active SlotNumber(x) begin
    if x isa SlotNumber
        Some(x.id)
    else
        nothing
    end
end

"""
    rm_annotations(x)

Remove type annotation of given expression.
"""
function rm_annotations(x)
    x isa Expr || return x
    if x.head == :(::)
        if length(x.args) == 1 # anonymous
            return
        else
            return x.args[1]
        end
    elseif x.head in [:(=), :kw] # default values
        return rm_annotations(x.args[1])
    else
        return x
    end
end

function annotations(x)
    x isa Expr || return x
    if x.head == :(::)
        x.args[end]
    elseif x.head in [:(=), :kw]
        return annotations(x.args[1])
    else
        return x
    end
end

function splatting_variables(variables, free)
    Expr(:(=), Expr(:tuple, variables...), free)
end
