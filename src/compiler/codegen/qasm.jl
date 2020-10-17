using RBNF

# NOTE:
# we can only transform routines satisfy the following:
# 1. locations are constants, in Julia we can calculate locations dynamically
#    but this is not allowed in QASM
# 2. do not contain classical functions calls except for 
# fn = ("sin" | "cos" | "tan" | "exp" | "ln" | "sqrt")
# binop = ('+' | '-' | '*' | '/')
# since QASM's if is actually a GotoIfNot node
# we don't reloop the SSA here, but assume the CodeInfo should
# not contain any GotoNode, which is incompatible with QASM
mutable struct QASMCtx
    ri::RoutineInfo
    src::CodeInfo
    record::QASM.RegisterRecord
    pc::Int
    nstmts::Int
    qubits::Set{Vector{Int}}
    cbits::Dict{String, Int}
end

function QASMCtx(ri::RoutineInfo)
    pc = first(first(ri.code.blocks))
    nstmts = length(ri.code.ci.code)
    QASMCtx(ri, ri.code.ci, QASM.RegisterRecord(), pc, nstmts, Set(Int[]), Dict{String, Int}())
end

function codegen_main(ctx::QASMCtx)
    ver = RBNF.Token{:real}(0, 0, 0, "2.0", 0)
    prog = Any[]
    pc = ctx.pc

    while pc <= ctx.nstmts
        stmt = ctx.src.code[pc]
        stmt_type = ctx.src.ssavaluetypes[pc]

        if stmt isa Expr
            push!(prog, codegen_expr(ctx, stmt))
        elseif stmt isa Core.GotoIfNot
            # cond = stmt.cond
            # dest = stmt.dest

            # if cond isa SSAValue
            #     ctx.src.ssavaluetypes[cond.id] == QuantumBool ||
            #         error("condition does not contain measurement result")
            #     ex = ctx.src.code[cond.id]
            #     ex isa Expr && ex.head === :call && ex.args[1] === :(==) ||
            #         error("only `==` is compatible when compiling to QASM, got $ex")
                
            #     left = ex.args[2]
            #     if left isa Core.SlotNumber
            #         left = ctx.src.slotnames[ex.args[2].id]
            #     elseif left isa SSAValue
            #         ctx.src.code[left.id]
            #     end
            # else
            #     error("incompatible statement `$cond` for QASM")
            # end
            # Parse.Struct_ifstmt
            # ctx.pc
        elseif stmt isa Core.ReturnNode
        else
        end

        pc = ctx.pc
    end
end

function codegen_expr(ctx::QASMCtx, @nospecialize(stmt))
    if is_quantum_statement(stmt)
        type = quantum_stmt_type(stmt)
        if type === :gate
            gate = stmt.args[2]
            locs = stmt.args[3]
            codegen_gate(ctx, gate, locs)
        elseif type === :ctrl
        end
    end
end

function codegen_gate(ctx::QASMCtx, @nospecialize(gate), @nospecialize(locs))
    if gate isa SSAValue
        gate = ctx.src.ssavaluetypes[gate.id]
    end

    if locs isa SSAValue
        locs = ci.ssavaluetypes[locs.id]
    end

    if gate isa Core.Const
        gate = gate.val
    end

    if locs isa SSAValue
        locs = locs.val
    end

    if gate isa RoutineSpec
        routine_name(gate)
    elseif gate isa IntrinsicSpec
        codegen_gate_intrinsic(ctx, gate, locs)
    else
    end
end
