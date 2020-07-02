export YaoIR

"""
    YaoIR

The Yao Intermediate Representation. See compilation section for more details.

    YaoIR([m::Module=YaoLang.Compiler], ast::Expr)

Creates a `YaoIR` from Julia AST.
"""
mutable struct YaoIR
    mod::Module
    name::Any
    args::Vector{Any}
    whereparams::Vector{Any}
    body::IR
    quantum_blocks::Any # Vector{Tuple{Int, UnitRange{Int}}}
    pure_quantum::Bool
    qasm_compatible::Bool
end

function YaoIR(m::Module, ast::Expr)
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

    ir = YaoIR(
        m,
        defs[:name],
        get(defs, :args, Any[]),
        get(defs, :whereparams, Any[]),
        mark_quantum(body),
        nothing,
        false,
        false,
    )
    sink_quantum!(ir)
    update_slots!(ir)
    ir.quantum_blocks = quantum_blocks(ir)
    return ir
end

YaoIR(ast::Expr) = YaoIR(@__MODULE__, ast)

function Base.copy(ir::YaoIR)
    YaoIR(
        ir.mod,
        ir.name isa Expr ? copy(ir.name) : ir.name ,
        copy(ir.args),
        copy(ir.whereparams),
        copy(ir.body),
        ir.quantum_blocks === nothing ? nothing : copy(ir.quantum_blocks),
        ir.pure_quantum,
        ir.qasm_compatible,
    )
end

"""
    mark_quantum(ir::IR)

swap the statement tag with `:quantum`.
"""
function mark_quantum(ir::IR)
    for (v, st) in ir
        if (st.expr isa Expr) && (st.expr.head === :call) && (st.expr.args[1] isa GlobalRef)
            ref = st.expr.args[1]
            if ref.mod === Compiler && ref.name in RESERVED
                ir[v] = Statement(st; expr = Expr(:quantum, ref.name, st.expr.args[2:end]...))
            end
        end

        # mark quantum meta
        if (st.expr isa Expr) && (st.expr.head === :meta) && (st.expr.args[1] in RESERVED)
            ir[v] = Statement(st; expr = Expr(:quantum, st.expr.args...))
        end
    end
    return ir
end


function update_slots!(ir::YaoIR)
    fn_args = arguements(ir)
    for (v, st) in ir.body
        if st.expr isa Expr
            args = Any[]
            for each in st.expr.args
                if each in fn_args
                    push!(args, IRTools.Slot(each))
                else
                    push!(args, each)
                end
            end
            ir.body[v] = Statement(st; expr = Expr(st.expr.head, args...))
        elseif (st.expr isa Symbol) && (st.expr in fn_args)
            ir.body[v] = Statement(st; expr = IRTools.Slot(st.expr))
        end
    end
    return ir
end

function sink_quantum!(ir::YaoIR)
    ir_perms = []
    for (k, b) in enumerate(blocks(ir.body))
        perms = Variable[]
        qstmts_tape = Variable[]
        cstmts_tape = Variable[]

        for (v, st) in b
            if is_quantum(st)
                if st.expr.args[1] === :measure
                    append!(perms, cstmts_tape)
                    append!(perms, qstmts_tape)
                    push!(perms, v)

                    empty!(cstmts_tape)
                    empty!(qstmts_tape)
                else
                    push!(qstmts_tape, v)
                end
            else
                push!(cstmts_tape, v)
            end
        end

        append!(perms, cstmts_tape)
        append!(perms, qstmts_tape)
        push!(ir_perms, perms)
    end

    ir.body = permute_stmts(ir.body, ir_perms)
    return ir
end

function permute_stmts(ir::IR, perms)
    map = Dict()
    count = 0
    for pm in perms, v in pm
        count += 1
        map[v] = IRTools.var(count)
    end

    to = IR([],[], ir.lines, nothing)
    for b in blocks(ir)
        bb = BasicBlock(b)
        push!(to.blocks, BasicBlock([], substitute(map, bb.args), bb.argtypes, substitute(map, bb.branches)))
    end

    for (b, pm) in zip(blocks(to), perms)
        for v in pm
            st = ir[v]
            push!(b, Statement(st; expr=substitute(map, st.expr)))
        end
    end
    return to
end

function substitute(d::Dict, ex)
    if ex isa Expr
        return Expr(ex.head, map(x->substitute(d, x), ex.args)...)
    elseif ex isa Variable
        return d[ex]
    else
        return ex
    end
end

function substitute(d::Dict, ex::Vector)
    return [substitute(d, x) for x in ex]
end

function substitute(d::Dict, ex::IRTools.Branch)
    return IRTools.Branch(substitute(d, ex.condition), ex.block, substitute(d, ex.args))
end

function quantum_blocks(ir::YaoIR)
    quantum_blocks = UnitRange{Int}[]

    for b in blocks(ir.body)
        start, stop = 0, 0
        for (v, st) in b
            if is_quantum(st)
                if st.expr.args[1] === :measure
                    push!(quantum_blocks, start:stop+1)
                    start = stop = 0
                else                
                    if start > 0
                        stop += 1
                    else
                        start = stop = v.id
                    end
                end
            else
                if start > 0
                    push!(quantum_blocks, start:stop)
                    start = stop = 0
                end
            end
        end

        if start > 0
            push!(quantum_blocks, start:stop)
        end
    end

    return quantum_blocks
end
