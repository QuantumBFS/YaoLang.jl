export YaoIR

function convert_intrinsic_function(ir::IR)
    for (v, st) in ir
        if (st.expr isa Expr) && (st.expr.head === :call) && (st.expr.args[1] isa GlobalRef)
            ref = st.expr.args[1]
            if ref.mod === Semantic && ref.name in Semantic.SEMANTIC_STUBS
                @show ref.name
                ir[v] = Statement(st; expr = Expr(:quantum, ref.name, st.expr.args[2:end]...))
            end
        end
    end
    return ir
end

function group_quantum_stmts(ir::IR)

end

struct YaoIR
    code::IR
    # range of stmts contains pure quantum stmts
    blocks::Vector{UnitRange{Int}}

    function YaoIR(ir::IR, blocks::Vector{UnitRange{Int}})
        code = convert_intrinsic_function(ir)
        validate(code)
        return new(code, blocks)
    end
end

YaoIR(types...) = YaoIR(IR(types...))
YaoIR(fn::GenericRoutine, xs...) = Base.typesof(xs)
function validate(code)
end

# export YaoIR

# struct Intrinsic
#     name::Symbol
#     sigs
# end

# """
#     YaoIR

# The Yao Intermediate Representation. See compilation section for more details.

#     YaoIR([m::Module=YaoLang.Compiler], ast::Expr)

# Creates a `YaoIR` from Julia AST.
# """
# mutable struct YaoIR
#     mod::Module
#     name::Any
#     args::Vector{Any}
#     whereparams::Vector{Any}
#     body::IR
#     quantum_blocks::Any # Vector{Tuple{Int, UnitRange{Int}}}
#     pure_quantum::Bool
#     qasm_compatible::Bool
# end

# function YaoIR(m::Module, ast::Expr)
#     defs = splitdef(ast; throw = false)
#     defs === nothing && throw(ParseError("expect function definition"))

#     # potentially we could have code transform pass
#     # on frontend AST as well here, but not necessary
#     # for now, and all syntax related things should
#     # go into to_function transformation
#     ex = to_function(m, defs[:body])
#     lowered_ast = Meta.lower(m, ex)

#     if lowered_ast === nothing
#         body = IR()
#     else
#         body = IR(lowered_ast.args[], 0)
#     end

#     ir = YaoIR(
#         m,
#         defs[:name],
#         get(defs, :args, Any[]),
#         get(defs, :whereparams, Any[]),
#         mark_quantum(body),
#         nothing,
#         false,
#         false,
#     )
#     update_slots!(ir)
#     return ir
# end

# YaoIR(ast::Expr) = YaoIR(@__MODULE__, ast)

# function Base.copy(ir::YaoIR)
#     YaoIR(
#         ir.mod,
#         ir.name isa Expr ? copy(ir.name) : ir.name,
#         copy(ir.args),
#         copy(ir.whereparams),
#         copy(ir.body),
#         ir.quantum_blocks === nothing ? nothing : copy(ir.quantum_blocks),
#         ir.pure_quantum,
#         ir.qasm_compatible,
#     )
# end

# """
#     mark_quantum(ir::IR)

# swap the statement tag with `:quantum`.
# """
# function mark_quantum(ir::IR)
#     for (v, st) in ir
#         if (st.expr isa Expr) && (st.expr.head === :call) && (st.expr.args[1] isa GlobalRef)
#             ref = st.expr.args[1]
#             if ref.mod === Compiler && ref.name in RESERVED
#                 ir[v] = Statement(st; expr = Expr(:quantum, ref.name, st.expr.args[2:end]...))
#             end
#         end

#         # mark quantum meta
#         if (st.expr isa Expr) && (st.expr.head === :meta) && (st.expr.args[1] in RESERVED)
#             ir[v] = Statement(st; expr = Expr(:quantum, st.expr.args...))
#         end
#     end
#     return ir
# end


# function update_slots!(ir::YaoIR)
#     fn_args = arguements(ir)
#     for (v, st) in ir.body
#         if st.expr isa Expr
#             args = Any[]
#             for each in st.expr.args
#                 if each in fn_args
#                     push!(args, IRTools.Slot(each))
#                 else
#                     push!(args, each)
#                 end
#             end
#             ir.body[v] = Statement(st; expr = Expr(st.expr.head, args...))
#         elseif (st.expr isa Symbol) && (st.expr in fn_args)
#             ir.body[v] = Statement(st; expr = IRTools.Slot(st.expr))
#         end
#     end
#     return ir
# end
