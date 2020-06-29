using ZXCalculus

function optimize!(ir::YaoIR)
    circ = to_ZX_diagram(ir)
    clifford_simplify!(circ)
    ir = to_YaoIR(circ)
    return ir
end

# TODO: move this to ZXCalculus.jl
function clifford_simplify!(circ)
    zxg = ZXGraph(circ)
    simplify!(Rule{:lc}(), zxg)
    simplify!(Rule{:p1}(), zxg)
    replace!(Rule{:pab}(), zxg)

    ex_circ = circuit_extraction(zxg)
    return ex_circ
end

function to_ZX_diagram(ir::YaoIR)
    if ir.pure_quantum
        n = count_nqubits(ir)
        circ = ZXDiagram(n)
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
                    ir_push_gate!(circ, loc, gate)
                elseif args[1] == :ctrl
                    gate = args[2]
                    if !(gate isa Symbol)
                        gate = ir.body[IRTools.var(gate.id)].expr
                    end
                    loc = args[3]
                    ctrl = args[4]
                    ir_push_ctrl_gate!(circ, ctrl, loc, gate)
                end
            end
        end
        return circ
    end
end

function ir_push_gate!(circ, loc, gate)
    if gate isa Symbol
        if gate === :H
            push_gate!(circ, Val{:H}(), loc)
        elseif gate === :X
            push_gate!(circ, Val{:X}(), loc, 1//1)
        elseif gate === :Y
            push_gate!(circ, Val{:X}(), loc, 1//1)
            push_gate!(circ, Val{:Z}(), loc, 1//1)
        elseif gate === :Z
            push_gate!(circ, Val{:Z}(), loc, 1//1)
        elseif gate === :T
            push_gate!(circ, Val{:Z}(), loc, 1//4)
        elseif gate === :S
            push_gate!(circ, Val{:Z}(), loc, 1//2)
        end
    elseif gate.head === :call
        g, θ = gate.args
        if g === :shift
            push_gate!(circ, Val{:Z}(), loc, Rational(θ/π))
        elseif g === :Rx
            push_gate!(circ, Val{:X}(), loc, Rational(θ/π))
        elseif g === :Ry
            push_gate!(circ, Val{:Z}(), loc, -1//2)
            push_gate!(circ, Val{:X}(), loc, Rational(θ/π))
            push_gate!(circ, Val{:Z}(), loc, 1//2)
        elseif g === :Rz
            push_gate!(circ, Val{:Z}(), loc, Rational(θ/π))
        end
    end
end

function ir_push_ctrl_gate!(circ, ctrl, loc, gate)
    if gate isa Symbol
        if gate === :Z
            push_ctrl_gate!(circ, Val{:CZ}(), loc, ctrl)
        elseif gate === :X
            push_ctrl_gate!(circ, Val{:CNOT}(), loc, ctrl)
        end
    end
end
