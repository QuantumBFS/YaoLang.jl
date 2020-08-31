export gate_count

function signature(ir::YaoIR)
    defs = Dict(:name => ir.name, :args => ir.args)
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
    @timeit_debug to "copy IR" ir = copy(ir)
    @timeit_debug to "insert self" Inner.argument!(ir, at = 1)
    @timeit_debug to "update CI" Inner.update!(mt_ci, ir)
    @timeit_debug to "validate CI" Core.Compiler.validate_code(mt_ci)
    return ci
end

function build_codeinfo(ir::YaoIR)
    build_codeinfo(ir.mod, signature(ir), ir.body)
end

function arguements(ir::YaoIR)
    args = map(rm_annotations, ir.args)
    if (ir.name isa Expr) && (ir.name.head === :(::))
        insert!(args, 1, ir.name.args[1])
    end
    return args
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

function annotations(x)
    x isa Expr || return x
    if x.head == :(::)
        return x.args[2]
    elseif x.head in [:(=), :kw]
        return annotations(x.args[1])
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
# custom struct
generic_circuit(name) = annotations(name)
circuit(name) =
    Expr(:curly, GlobalRef(YaoLang, :Circuit), QuoteNode(gensym(Symbol(annotations(name)))))

to_locations(x) = :(Locations($x))
to_locations(x::Int) = Locations(x)

function count_nqubits(ir::YaoIR)
    if ir.pure_quantum
        stmts = ir.body.blocks[].stmts
        locs = Int[]
        for stmt in stmts
            head = stmt.expr.head
            args = stmt.expr.args
            if args[1] == :gate
                push!(locs, args[3]...)
            elseif args[1] == :ctrl
                push!(locs, args[3]..., args[4]...)
            end
        end
        return maximum(locs)
    else
        error("expect a pure quantum circuit")
    end
end

_get_primitive_name(ex::GlobalRef) = ex
_get_primitive_name(ex::Symbol) = ex

function _get_primitive_name(ex::Expr)
    if (ex.head === :call) && (ex.args[1] isa GlobalRef || ex.args[1] isa Symbol)
        return ex
    end
    throw(ParseError("invalid primitive instruction $ex"))
end

"""
    gate_count(circuit)::Dict

Count the number of each primitive instructions in given pure quantum
circuit.
"""
function gate_count(x::YaoLang.GenericCircuit)
    if hasmethod(x, ())
        tape = TraceTape()
        n = count_nqubits(code_yao(x))
        count = Dict()
        x()(tape, Locations(1:n))

        for each in tape.commands[1]
            if each.args[1] === :gate
                name = string(_get_primitive_name(each.args[2]))
                count[name] = get(count, name, 0) + 1
            elseif each.args[1] === :ctrl
                ctrl_name = string("@ctrl ", _get_primitive_name(each.args[2]))
                count[ctrl_name] = get(count, ctrl_name, 0) + 1
            end
        end
        return count
    else
        error("not a pure quantum circuit")
    end
end
