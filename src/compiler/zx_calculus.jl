using ZXCalculus
using ZXCalculus: qubit_loc, clifford_simplification
import IRTools: IR
import ZXCalculus: ZXDiagram

function optimize(ir::YaoIR, optimizer::Vector{Symbol} = Symbol[])
    if length(optimizer) > 0 && ir.pure_quantum
        circ = ZXDiagram(ir)
        for opt in optimizer
            if opt === :zx_clifford
                circ = clifford_simplification(circ)
            elseif opt === :zx_teleport
                circ = phase_teleportation(circ)
            end
        end
        new_ir = YaoIR(
            ir.mod,
            ir.name,
            ir.args,
            ir.whereparams,
            IR(circ),
            ir.quantum_blocks,
            ir.pure_quantum,
            ir.qasm_compatible,
        )
        YaoLang.Compiler.update_slots!(new_ir)
        return new_ir
    else
        return ir
    end
end

function IR(circ::ZXDiagram{T,P}) where {T,P}
    qc = QCircuit(circ)
    return IR(qc)
end

function IR(qc::QCircuit)
    ir = IRTools.IR()
    IRTools.return!(ir, nothing)
    push!(ir, IRTools.Statement(Expr(:quantum, :register, :new, gensym(:register))))

    if global_phase(qc) != 0
        push!(ir, IRTools.xcall(YaoLang, :phase, global_phase(qc)))
        push!(ir, IRTools.Statement(Expr(:quantum, :gate, IRTools.var(length(ir)), 1)))
    end
    for g in gates(qc)
        if g.name in (:H, :Z, :X, :S, :T, :Sdag, :Tdag)
            push!(ir, IRTools.Statement(Expr(:quantum, :gate, g.name, g.loc)))
        elseif g.name in (:shift, :Rz, :Rx)
            θ = g.param
            push!(ir, IRTools.xcall(YaoLang, g.name, θ))
            push!(ir, IRTools.Statement(Expr(:quantum, :gate, IRTools.var(length(ir)), g.loc)))
        elseif g.name === :CNOT
            push!(ir, Expr(:quantum, :ctrl, :X, g.loc, g.ctrl))
        elseif g.name === :CZ
            push!(ir, Expr(:quantum, :ctrl, :Z, g.loc, g.ctrl))
        end
    end

    return ir
end

function QCircuit(ir::YaoIR)
    n = count_nqubits(ir)
    qc = QCircuit(n)
    if ir.pure_quantum
        stmts = ir.body.blocks[].stmts
        for stmt in stmts
            ex = stmt.expr
            if ex.head == :quantum
                args = ex.args
                if args[1] == :gate
                    gate = args[2]
                    if !(gate isa Symbol)
                        gate = ir.body[IRTools.var(gate.id)].expr
                    end
                    loc = args[3]
                    zx_push_gate!(qc, loc, gate)
                elseif args[1] == :ctrl
                    gate = args[2]
                    if !(gate isa Symbol)
                        gate = ir.body[IRTools.var(gate.id)].expr
                    end
                    loc = args[3]
                    ctrl = args[4]
                    zx_push_ctrl_gate!(qc, ctrl, loc, gate)
                end
            end
        end
    end
    return qc
end

function ZXDiagram(ir::YaoIR)
    return ZXDiagram(QCircuit(ir))
end

function zx_push_gate!(qc::QCircuit, loc, gate)
    if gate isa Symbol
        if gate in (:H, :X, :Z, :S, :Sdag, :T, :Tdag)
            push_gate!(qc, Val(gate), loc)
        elseif gate === :Y
            push_gate!(qc, Val(:X), loc)
            push_gate!(qc, Val(:Z), loc)
            set_global_phase!(qc, global_phase(qc) + π)
        end
    elseif gate.head === :call
        g, θ = gate.args
        if g isa GlobalRef
            g = g.name
        end
        if g in (:shift, :Rz, :Rx)
            push_gate!(qc, Val(g), loc, θ)
        elseif g === :Ry
            push_gate!(qc, Val(:Sdag), loc)
            push_gate!(qc, Val(:Rx), loc, θ)
            push_gate!(qc, Val(:S), loc)
        end
    end
end

function zx_push_ctrl_gate!(qc::QCircuit, ctrl, loc, gate)
    if gate isa Symbol
        if gate === :Z && ctrl isa Integer
            push_gate!(qc, Val(:CZ), loc, ctrl)
        elseif gate === :X
            if ctrl isa Tuple && length(ctrl) == 2
                a, b = ctrl
                c = loc
                push_gate!(qc, Val(:H), c)
                push_gate!(qc, Val(:CNOT), c, b)
                push_gate!(qc, Val(:Tdag), c)
                push_gate!(qc, Val(:CNOT), c, a)
                push_gate!(qc, Val(:T), c)
                push_gate!(qc, Val(:CNOT), c, b)
                push_gate!(qc, Val(:Tdag), c)
                push_gate!(qc, Val(:CNOT), c, a)
                push_gate!(qc, Val(:T), b)
                push_gate!(qc, Val(:T), c)
                push_gate!(qc, Val(:H), c)
                push_gate!(qc, Val(:CNOT), b, a)
                push_gate!(qc, Val(:T), a)
                push_gate!(qc, Val(:Tdag), b)
                push_gate!(qc, Val(:CNOT), b, a)
            elseif ctrl isa Integer
                push_gate!(qc, Val(:CNOT), loc, ctrl)
            end
        end
    end
end
