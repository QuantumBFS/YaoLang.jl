export YaoIR

struct YaoIR
    mod::Module
    name::Any
    args::Vector{Any}
    whereparams::Vector{Any}
    body::IR
    mode::Symbol
end

function YaoIR(m::Module, ast::Expr, mode::Symbol=:hybrid)
    defs = splitdef(ast; throw = false)
    defs === nothing && throw(ParseError("expect function definition"))

    # potentially we could have code transform pass
    # on frontend AST as well here, but not necessary
    # for now, and all syntax related things should
    # go into to_function transformation
    ex = to_function(m, defs[:body])
    lowered_ast = Meta.lower(m, ex)

    if lowered_ast === nothing
        body = IR()
    else
        body = IR(lowered_ast.args[], 0)
    end

    return YaoIR(m, defs[:name], get(defs, :args, Any[]), get(defs, :whereparams, Any[]), mark_quantum(body), mode)
end

YaoIR(ast::Expr) = YaoIR(@__MODULE__, ast)

"""
    mark_quantum(ir::IR)

swap the statement tag with `:quantum`.
"""
function mark_quantum(ir::IR)
    for (v, st) in ir
        if (st.expr isa Expr) && (st.expr.head === :call) && (st.expr.args[1] isa GlobalRef)
            ref = st.expr.args[1]
            if ref.mod === Compiler && ref.name in RESERVED
                ir[v] = Statement(st; expr=Expr(:quantum, ref.name, st.expr.args[2:end]...))
            end
        end

        # mark quantum meta
        if (st.expr isa Expr) && (st.expr.head === :meta) && (st.expr.args[1] in RESERVED)
            ir[v] = Statement(st; expr=Expr(:quantum, st.expr.args...))
        end
    end
    return ir
end
