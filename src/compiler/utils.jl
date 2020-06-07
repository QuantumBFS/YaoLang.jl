function signature(ir::YaoIR)
    defs = Dict(:name=>ir.name, :args=>ir.args)
    if !isempty(ir.whereparams)
        defs[:whereparams] = ir.whereparams
    end
    return defs
end

function hasmeasure(ir::YaoIR)
    for (v, st) in ir.body
        if is_quantum(st) && (st.expr.args[1] === :measure)
            return true
        end
    end
    return false
end

function build_codeinfo(m::Module, defs::Dict, ir::IR)
    defs[:body] = :(return)
    ci = Meta.lower(m, combinedef(defs))
    mt = ci.args[].code[end-1]
    mt_ci = mt.args[end]

    # update method CodeInfo
    ir = copy(ir)
    Inner.argument!(ir, at = 1)
    Inner.update!(mt_ci, ir)
    Core.Compiler.validate_code(mt_ci)
    return ci
end

function build_codeinfo(ir::YaoIR)
    build_codeinfo(ir.mod, signature(ir), ir.body)
end

function variables(def::Dict)
    if haskey(def, :args)
        return def[:args]
    else
        return Any[]
    end
end

function arguements(ir::YaoIR)
    map(rm_annotations, ir.args)
end

# TODO: actually implement this using JuliaVariables
function capture_free_variables(def::Dict)
    return arguements(def)
end

is_quantum(x) = false
is_quantum(st::Statement) = is_quantum(st.expr)
is_quantum(ex::Expr) = ex.head === :quantum

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

generic_circuit(name::Symbol) = Expr(:curly, GlobalRef(YaoLang, :GenericCircuit), QuoteNode(name))
circuit(name::Symbol) = Expr(:curly, GlobalRef(YaoLang, :Circuit), QuoteNode(name))
to_locations(x) = :(Locations($x))
to_locations(x::Int) = Locations(x)

is_literal(x) = true
is_literal(x::Expr) = false
is_literal(x::Symbol) = false


value(x) = x
value(x::QuoteNode) = x.value
