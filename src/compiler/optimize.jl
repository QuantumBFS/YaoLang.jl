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
    ir.quantum_blocks = quantum_blocks(ir)
    return ir
end

function permute_stmts(ir::IR, perms)
    map = Dict()
    count = 0
    for pm in perms, v in pm
        count += 1
        map[v] = IRTools.var(count)
    end

    to = IR([], [], ir.lines, nothing)
    for b in blocks(ir)
        bb = BasicBlock(b)
        push!(
            to.blocks,
            BasicBlock([], substitute(map, bb.args), bb.argtypes, substitute(map, bb.branches)),
        )
    end

    for (b, pm) in zip(blocks(to), perms)
        for v in pm
            st = ir[v]
            push!(b, Statement(st; expr = substitute(map, st.expr)))
        end
    end
    return to
end

function substitute(d::Dict, ex)
    if ex isa Expr
        return Expr(ex.head, map(x -> substitute(d, x), ex.args)...)
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
