function signature(ir::YaoIR)
    defs = Dict(:name=>ir.name, :args=>ir.args)
    if !isempty(ir.whereparams)
        defs[:whereparams] = ir.whereparams
    end
    return defs
end

function build_codeinfo(m::Module, defs::Dict, ir::IR)
    defs[:body] = :(return)
    @timeit_debug to "make empty CI" ci = Meta.lower(m, combinedef(defs))
    mt = ci.args[].code[end-1]
    mt_ci = mt.args[end]

    # update method CodeInfo
    @timeit_debug to "copy IR"     ir = copy(ir)
    @timeit_debug to "insert self" Inner.argument!(ir, at = 1)
    @timeit_debug to "update CI"   Inner.update!(mt_ci, ir)
    @timeit_debug to "validate CI" Core.Compiler.validate_code(mt_ci)
    return ci
end

function build_codeinfo(ir::YaoIR)
    build_codeinfo(ir.mod, signature(ir), ir.body)
end

function arguements(ir::YaoIR)
    map(rm_annotations, map(rm_default_value, ir.args))
end

"""
    rm_annotations(x)

Remove type annotation of given expression.
"""
function rm_annotations(x)
    x isa Expr || return x
    if x.head == :(::)
        return x.args[1]
    elseif x.head in [:(=), :kw] # default values
        return rm_annotations(x.args[1])
    else
        return x
    end
end

function rm_default_value(x)
    x isa Expr || return x
    if x.head === :kw
        return x.args[1]
    else
        return x
    end
end

function splatting_variables(variables, free)
    Expr(:(=), Expr(:tuple, variables...), free)
end

# function argtypes(def::Dict)
#     ex = Expr(:curly, :Tuple)
#     if haskey(def, :args)
#         for each in def[:args]
#             if each isa Symbol
#                 push!(ex.args, :Any)
#             elseif (each isa Expr) && (each.head === :(::))
#                 push!(ex.args, each.args[end])
#             end
#         end
#     end

#     return ex
# end

generic_circuit(name::Symbol) = Expr(:curly, GlobalRef(YaoLang, :GenericCircuit), QuoteNode(name))
circuit(name::Symbol) = Expr(:curly, GlobalRef(YaoLang, :Circuit), QuoteNode(name))
to_locations(x) = :(Locations($x))
to_locations(x::Int) = Locations(x)
