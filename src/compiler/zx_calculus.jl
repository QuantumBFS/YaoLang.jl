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
        new_ir = YaoIR(ir.mod, ir.name, ir.args, ir.whereparams, IR(circ),
            ir.quantum_blocks, ir.pure_quantum, ir.qasm_compatible)
        YaoLang.Compiler.update_slots!(new_ir)
        return new_ir
    else
        return ir
    end
end

function IR(circ::ZXDiagram{T, P}) where {T, P}
    lo = circ.layout
    spider_seq = ZXCalculus.spider_sequence(circ)
    vs = spiders(circ)
    locs = Dict()
    nqubit = lo.nbits
    frontier_v = ones(T, nqubit)
    ir = IRTools.IR()
    IRTools.return!(ir, nothing)
    push!(ir, IRTools.Statement(Expr(:quantum, :register, :new, gensym(:register))))

    while sum([frontier_v[i] <= length(spider_seq[i]) for i = 1:nqubit]) > 0
        for q = 1:nqubit
            if frontier_v[q] <= length(spider_seq[q])
                v = spider_seq[q][frontier_v[q]]
                nb = ZXCalculus.neighbors(circ, v)
                if length(nb) <= 2
                    θ = phase(circ, v) * π
                    if spider_type(circ, v) == ZXCalculus.SpiderType.Z
                        push!(ir, IRTools.xcall(YaoLang, :shift, θ))
                        push!(ir, IRTools.Statement(Expr(:quantum, :gate, IRTools.var(length(ir)), q)))
                    elseif spider_type(circ, v) == ZXCalculus.SpiderType.X
                        push!(ir, IRTools.xcall(YaoLang, :Rx, θ))
                        push!(ir, IRTools.Statement(Expr(:quantum, :gate, IRTools.var(length(ir)), q)))
                    elseif spider_type(circ, v) == ZXCalculus.SpiderType.H
                        push!(ir, IRTools.Statement(Expr(:quantum, :gate, :H, q)))
                    end

                    frontier_v[q] += 1
                elseif length(nb) == 3
                    v1 = nb[[qubit_loc(lo, u) != q for u in nb]][1]
                    if spider_type(circ, v1) == SpiderType.H
                        v1 = setdiff(ZXCalculus.neighbors(circ, v1), [v])[1]
                    end
                    if sum([findfirst(isequal(u), spider_seq[qubit_loc(lo, u)]) != frontier_v[qubit_loc(lo, u)] for u in [v, v1]]) == 0
                        if phase(circ, v) != 0
                            if spider_type(circ, v) == ZXCalculus.SpiderType.Z
                                push!(ir, IRTools.xcall(YaoLang, :shift, phase(circ, v)*π))
                            else
                                push!(ir, IRTools.xcall(YaoLang, :Rx, phase(circ, v)*π))
                            end
                            push!(ir, IRTools.Statement(Expr(:quantum, :gate, IRTools.var(length(ir)), qubit_loc(lo, v))))
                        end
                        if phase(circ, v1) != 0
                            if spider_type(circ, v1) == ZXCalculus.SpiderType.Z
                                push!(ir, IRTools.xcall(YaoLang, :shift, phase(circ, v1)*π))
                            else
                                push!(ir, IRTools.xcall(YaoLang, :Rx, phase(circ, v1)*π))
                            end
                            push!(ir, IRTools.Statement(Expr(:quantum, :gate, IRTools.var(length(ir)), qubit_loc(lo, v1))))
                        end

                        if spider_type(circ, v) == spider_type(circ, v1) == ZXCalculus.SpiderType.Z
                            push!(ir, Expr(:quantum, :ctrl, :Z, qubit_loc(lo, v), qubit_loc(lo, v1)))
                        elseif spider_type(circ, v) == ZXCalculus.SpiderType.Z
                            push!(ir, Expr(:quantum, :ctrl, :X, qubit_loc(lo, v1), qubit_loc(lo, v)))
                        elseif spider_type(circ, v) == ZXCalculus.SpiderType.X
                            push!(ir, Expr(:quantum, :ctrl, :X, qubit_loc(lo, v), qubit_loc(lo, v1)))
                        end
                        for u in [v, v1]
                            frontier_v[qubit_loc(lo, u)] += 1
                        end
                    end
                end
            end
        end
    end
    return ir
end

function ZXDiagram(ir::YaoIR)
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
                    zx_push_gate!(circ, loc, gate)
                elseif args[1] == :ctrl
                    gate = args[2]
                    if !(gate isa Symbol)
                        gate = ir.body[IRTools.var(gate.id)].expr
                    end
                    loc = args[3]
                    ctrl = args[4]
                    zx_push_ctrl_gate!(circ, ctrl, loc, gate)
                end
            end
        end
        return circ
    end
end

function ZXDiagram(::Val{:qasm}, src)
    src = replace(src, r"include \".*\";" => "")
    ir = YaoIR(Val(:qasm), @__MODULE__, src, gensym())
    if is_pure_quantum(ir)
        ir.pure_quantum = true
        zxd = ZXDiagram(ir)
        return zxd
    end
    return ZXDiagram(count_nqubits(ir))
end

function zx_push_gate!(circ, loc, gate)
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
        if g isa GlobalRef
            g = g.name
        end
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

function zx_push_ctrl_gate!(circ, ctrl, loc, gate)
    if gate isa Symbol
        if gate === :Z
            push_ctrl_gate!(circ, Val{:CZ}(), loc, ctrl)
        elseif gate === :X
            if ctrl isa Tuple
                a = ctrl[1]
                b = ctrl[2]
                c = loc
                push_gate!(circ, Val{:H}(), c)
                push_ctrl_gate!(circ, Val{:CNOT}(), c, b)
                push_gate!(circ, Val{:Z}(), c, 7//4)
                push_ctrl_gate!(circ, Val{:CNOT}(), c, a)
                push_gate!(circ, Val{:Z}(), c, 1//4)
                push_ctrl_gate!(circ, Val{:CNOT}(), c, b)
                push_gate!(circ, Val{:Z}(), c, 7//4)
                push_ctrl_gate!(circ, Val{:CNOT}(), c, a)
                push_gate!(circ, Val{:Z}(), b, 1//4)
                push_gate!(circ, Val{:Z}(), c, 1//4)
                push_gate!(circ, Val{:H}(), c)
                push_ctrl_gate!(circ, Val{:CNOT}(), b, a)
                push_gate!(circ, Val{:Z}(), a, 1//4)
                push_gate!(circ, Val{:Z}(), b, 7//4)
                push_ctrl_gate!(circ, Val{:CNOT}(), b, a)
            elseif ctrl isa Integer
                push_ctrl_gate!(circ, Val{:CNOT}(), loc, ctrl)
            end
        end
    end
end
