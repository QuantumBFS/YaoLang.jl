Base.iterate(ic::Core.Compiler.IncrementalCompact) = Core.Compiler.iterate(ic)
Base.iterate(ic::Core.Compiler.IncrementalCompact, st) = Core.Compiler.iterate(ic, st)
Base.getindex(ic::Core.Compiler.IncrementalCompact, idx) = Core.Compiler.getindex(ic, idx)
Base.setindex!(ic::Core.Compiler.IncrementalCompact, v, idx) = Core.Compiler.setindex!(ic, v, idx)

Base.getindex(ic::Core.Compiler.Instruction, idx) = Core.Compiler.getindex(ic, idx)
Base.setindex!(ic::Core.Compiler.Instruction, v, idx) = Core.Compiler.setindex!(ic, v, idx)

Base.getindex(ir::Core.Compiler.IRCode, idx) = Core.Compiler.getindex(ir, idx)
Base.setindex!(ir::Core.Compiler.IRCode, v, idx) = Core.Compiler.setindex!(ir, v, idx)


# TODO: we might need a better interface for this when we have more passes
function run_passes(ci::CodeInfo, nargs::Int, sv::OptimizationState, passes::Vector{Symbol})
    # NOTE: these parts are copied from Core.Compiler
    preserve_coverage = coverage_enabled(sv.mod)
    ir = convert_to_ircode(ci, copy_exprargs(ci.code), preserve_coverage, nargs, sv)
    ir = slot2reg(ir, ci, nargs, sv)
    ir = compact!(ir)
    
    ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
    ir = compact!(ir)
    ir = getfield_elim_pass!(ir)
    ir = adce_pass!(ir)
    ir = type_lift_pass!(ir)
    ir = compact!(ir)
    
    # group quantum statements so we can work on
    # larger quantum circuits before we start optimizations
    ir = group_quantum_stmts!(ir)
    ir = propagate_consts_bb!(ir)
    ir = compact!(ir)

    # run quantum passes
    if !isempty(passes)
        ir = convert_to_yaoir(ir)
        
        if :zx in passes
            ir = run_zx_passes(ir)::YaoIR
        end

        ir = ir.ir
    end

    ir = compact!(ir)
    # insert our own passes after Julia's pass
    if Core.Compiler.JLOptions().debug_level == 2
        @timeit "verify 3" (verify_ir(ir); verify_linetable(ir.linetable))
    end
    return ir
end

# NOTE: this is copied from Core.Compiler.optimize to insert our own pass
# the only difference is this function calls our own run_passes function
# we need to update this along Julia compiler versions until Keno implements
# the API for custom optimization passes.
function optimize(opt::OptimizationState, params::YaoOptimizationParams, @nospecialize(result))
    def = opt.linfo.def
    nargs = Int(opt.nargs) - 1
    ir = run_passes(opt.src, nargs, opt, params.passes)
    force_noinline = Core.Compiler._any(@nospecialize(x) -> Core.Compiler.isexpr(x, :meta) && x.args[1] === :noinline, ir.meta)

    # compute inlining and other related optimizations
    if (isa(result, Const) || isconstType(result))
        proven_pure = false
        # must be proven pure to use const_api; otherwise we might skip throwing errors
        # (issue #20704)
        # TODO: Improve this analysis; if a function is marked @pure we should really
        # only care about certain errors (e.g. method errors and type errors).
        if length(ir.stmts) < 10
            proven_pure = true
            for i in 1:length(ir.stmts)
                node = ir.stmts[i]
                stmt = node[:inst]
                if Core.Compiler.stmt_affects_purity(stmt, ir) && !Core.Compiler.stmt_effect_free(stmt, node[:type], ir, ir.sptypes)
                    proven_pure = false
                    break
                end
            end
            if proven_pure
                for fl in opt.src.slotflags
                    if (fl & Core.Compiler.SLOT_USEDUNDEF) != 0
                        proven_pure = false
                        break
                    end
                end
            end
        end
        if proven_pure
            opt.src.pure = true
        end

        if proven_pure
            # use constant calling convention
            # Do not emit `jl_fptr_const_return` if coverage is enabled
            # so that we don't need to add coverage support
            # to the `jl_call_method_internal` fast path
            # Still set pure flag to make sure `inference` tests pass
            # and to possibly enable more optimization in the future
            if !(isa(result, Const) && !is_inlineable_constant(result.val))
                opt.const_api = true
            end
            force_noinline || (opt.src.inlineable = true)
        end
    end

    Core.Compiler.replace_code_newstyle!(opt.src, ir, nargs)

    # determine and cache inlineability
    union_penalties = false
    if !force_noinline
        sig = Core.Compiler.unwrap_unionall(opt.linfo.specTypes)
        if isa(sig, DataType) && sig.name === Tuple.name
            for P in sig.parameters
                P = Core.Compiler.unwrap_unionall(P)
                if isa(P, Union)
                    union_penalties = true
                    break
                end
            end
        else
            force_noinline = true
        end
        if !opt.src.inlineable && result === Union{}
            force_noinline = true
        end
    end
    if force_noinline
        opt.src.inlineable = false
    elseif isa(def, Method)
        if opt.src.inlineable && isdispatchtuple(opt.linfo.specTypes)
            # obey @inline declaration if a dispatch barrier would not help
        else
            bonus = 0
            if result ⊑ Tuple && !isconcretetype(widenconst(result))
                bonus = params.inline_tupleret_bonus
            end
            if opt.src.inlineable
                # For functions declared @inline, increase the cost threshold 20x
                bonus += params.inline_cost_threshold*19
            end
            opt.src.inlineable = isinlineable(def, opt, params, union_penalties, bonus)
        end
    end
    nothing
end

function group_quantum_stmts_perm(ir::IRCode)
    perms = Int[]
    cstmts_tape = Int[]
    qstmts_tape = Int[]

    for b in ir.cfg.blocks
        for v in b.stmts
            e = ir.stmts[v][:inst]
            if is_quantum_statement(e)
                if quantum_stmt_type(e) in [:measure, :barrier]
                    exit_block!(perms, cstmts_tape, qstmts_tape)
                    push!(perms, v)
                else
                    push!(qstmts_tape, v)
                end
            elseif e isa Core.ReturnNode || e isa Core.GotoIfNot || e isa Core.GotoNode
                exit_block!(perms, cstmts_tape, qstmts_tape)
                push!(cstmts_tape, v)
            elseif e isa Expr && e.head === :enter
                exit_block!(perms, cstmts_tape, qstmts_tape)
                push!(cstmts_tape, v)
            else
                push!(cstmts_tape, v)
            end
        end

        exit_block!(perms, cstmts_tape, qstmts_tape)
    end

    append!(perms, cstmts_tape)
    append!(perms, qstmts_tape)
    
    return perms # permute_stmts(ci, perms)
end

function permute_stmts!(stmt::InstructionStream, perm::Vector{Int})
    inst = []

    for v in perm
        e = stmt.inst[v]

        if e isa Expr
            ex = replace_from_perm(e, perm)
            push!(inst, ex)
        elseif e isa Core.GotoIfNot
            if e.cond isa Core.SSAValue
                cond = Core.SSAValue(findfirst(isequal(e.cond.id), perm))
            else
                # TODO: figure out which case is this
                # and maybe apply permute to this
                cond = e.cond
            end

            dest = findfirst(isequal(e.dest), perm)
            push!(inst, Core.GotoIfNot(cond, dest))
        elseif e isa Core.GotoNode
            push!(inst, Core.GotoNode(findfirst(isequal(e.label), perm)))
        elseif e isa Core.ReturnNode
            if isdefined(e, :val) && e.val isa Core.SSAValue
                push!(inst, Core.ReturnNode(Core.SSAValue(findfirst(isequal(e.val.id), perm))))
            else
                push!(inst, e)
            end
        else
            # RL: I think
            # other nodes won't contain SSAValue
            # let's just ignore them, but if we
            # find any we can add them here
            push!(inst, e)
            # if e isa Core.SlotNumber
            #     push!(inst, e)
            # elseif e isa Core.NewvarNode
            #     push!(inst, e)
            # else
            # end
            # error("unrecognized statement $e :: ($(typeof(e)))")
        end
    end

    copyto!(stmt.inst, inst)
    permute!(stmt.flag, perm)
    permute!(stmt.line, perm)
    permute!(stmt.type, perm)
    permute!(stmt.flag, perm)
    return stmt
end

function replace_from_perm(stmt, perm)
    stmt isa Core.SSAValue && return Core.SSAValue(findfirst(isequal(stmt.id), perm))

    if stmt isa Expr
        return Expr(stmt.head, map(x->replace_from_perm(x, perm), stmt.args)...)
    else
        return stmt
    end
end

function exit_block!(perms::Vector, cstmts_tape::Vector, qstmts_tape::Vector)
    append!(perms, cstmts_tape)
    append!(perms, qstmts_tape)
    empty!(cstmts_tape)
    empty!(qstmts_tape)
    return perms
end

function group_quantum_stmts!(ir::IRCode)
    perm = group_quantum_stmts_perm(ir)
    permute_stmts!(ir.stmts, perm)
    return ir
end

# NOTE: this perform simple constant propagation
# inside basic blocks to get better format of
# the quantum statements
function propagate_consts_bb!(ir::IRCode)
    for (i, e) in enumerate(ir.stmts.inst)
        val = abstract_eval_statement(e, ir)
        # update if it's a constant
        if val isa Const
            ir.stmts.type[i] = val
        end
    end

    for (i, e) in enumerate(ir.stmts.inst)
        e isa Expr || continue
        if e.head === :call
            ea = e.args
            n = length(ea)
            args = Vector{Any}(undef, n)
            @inbounds for i in 1:n
                ai = abstract_eval_value(ea[i], ir)
                if ai isa Const
                    args[i] = ai.val
                else
                    args[i] = ea[i]
                end
            end

            ir.stmts.inst[i] = Expr(e.head, args...)
        elseif e.head === :invoke
            ea = e.args[2:end]
            n = length(ea)
            args = Vector{Any}(undef, n)
            @inbounds for i in 1:n
                ai = abstract_eval_value(ea[i], ir)
                if ai isa Const
                    args[i] = ai.val
                else
                    args[i] = ea[i]
                end
            end
            ir.stmts.inst[i] = Expr(:invoke, e.args[1], args...)
        end
    end
    return ir
end

function abstract_eval_statement(@nospecialize(e), ir::IRCode)
    e isa Expr || return abstract_eval_special_value(e, ir)
    e = e::Expr
    is_quantum_statement(e) && return Any
    if e.head === :call
        ea = e.args
        n = length(ea)
        args = Vector{Any}(undef, n)
        @inbounds for i = 1:n
            ai = abstract_eval_value(ea[i], ir)
            # the return value is unlikely to be
            # constant if the argument is non-constant
            # after inlining
            if !(ai isa Const)
                return Any
            end
            args[i] = ai.val
        end
        f = args[1]
        try
            return Const(f(args[2:end]...))
        catch
        end
    elseif e.head === :new
        t = Core.Compiler.instanceof_tfunc(abstract_eval_value(e.args[1], ir))[1]
        if isconcretetype(t) && !t.mutable
            args = Vector{Any}(undef, length(e.args)-1)
            for i = 2:length(e.args)
                at = abstract_eval_value(e.args[i], ir)
                if at isa Const
                    args[i-1] = at.val
                else
                    return Any
                end
            end
            return Const(ccall(:jl_new_structv, Any, (Any, Ptr{Cvoid}, UInt32), t, args, length(args)))
        end
    end
    return Any
end

function abstract_eval_special_value(@nospecialize(e), ir::IRCode)
    if isa(e, QuoteNode)
        return Const((e::QuoteNode).value)
    elseif isa(e, SSAValue)
        return abstract_eval_ssavalue(e, ir)
    elseif isa(e, Slot)
        return ir.argtypes[slot_id(e)]
    elseif isa(e, GlobalRef)
        return Core.Compiler.abstract_eval_global(e.mod, e.name)
    elseif isa(e, Core.PhiNode)
        return Any
    elseif isa(e, Core.PhiCNode)
        return Any
    end

    return Const(e)
end

function abstract_eval_ssavalue(e::SSAValue, ir::IRCode)
    t = ir.stmts.type[e.id]
    t isa Const && return t
    return Any # we don't need non-constants
end

function abstract_eval_value(@nospecialize(e), ir::IRCode)
    if e isa Expr
        return abstract_eval_value_expr(e, ir)
    else
        return abstract_eval_special_value(e, ir)
    end
end

function abstract_eval_value_expr(e::Expr, ir::IRCode)
    if e.head === :static_parameter
        n = e.args[1]
        t = Any
        if 1 <= n <= length(ir.sptypes)
            t = ir.sptypes[n]
        end
        return t
    elseif e.head === :boundscheck
        return Bool
    else
        return Any
    end
end

struct YaoIR
    ir::IRCode
    qb::Vector{UnitRange{Int}}
end

function compute_quantum_blocks(ir::IRCode)
    quantum_blocks = UnitRange{Int}[]
    last_stmt_is_measure_or_barrier = false

    for b in ir.cfg.blocks
        start, stop = 0, 0
        for v in b.stmts
            st = ir.stmts[v][:inst]
            if is_quantum_statement(st)
                if start > 0
                    stop += 1
                else
                    start = stop = v
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

function convert_to_yaoir(ir::IRCode)
    quantum_blocks = compute_quantum_blocks(ir)
    return YaoIR(ir, quantum_blocks)
end

function count_qubits(ir::YaoIR)
    min_loc, max_loc = 0, 0
    for (v, e) in enumerate(ir.ir.stmts.inst)
        minmax = find_minmax_locations(e, ir)

        # non-constant location
        if minmax === false
            return
        end

        if !isnothing(minmax)
            min_loc = min(minmax[1], min_loc)
            max_loc = max(minmax[2], max_loc)
        end
    end
    return max_loc - min_loc
end

function find_minmax_locations(@nospecialize(e), ir::YaoIR)
    if e isa Locations
        return minimum(e.storage), maximum(e.storage)
    elseif e isa Expr
        min_loc, max_loc = 0, 0
        for each in e.args
            minmax = find_minmax_locations(each, ir)
            if isnothing(minmax)
                continue
            elseif minmax === false
                return false
            else
                min_loc = min(minmax[1], min_loc)
                max_loc = max(minmax[2], max_loc)
            end
        end
        return min_loc, max_loc
    elseif e isa SSAValue && ir.ir.stmts.type[e.id] <: AbstractLocations
        return false
    else
        return
    end
end

function map_virtual_location_expr(@nospecialize(e), regmap)
    qt = quantum_stmt_type(e)
    if qt === :gate
        loc = e.args[2]
    elseif qt === :ctrl
        loc = e.args[2]
        ctrl = e.args[3]
    elseif qt === :barrier
        e.args[2]
    elseif qt === :measure
    else
        error("unknown quantum statement: $tt")
    end
end

function map_virtual_location(@nospecialize(loc), regmap)
    if loc isa AbstractLocations
        return loc
    else
        # TODO: use a custom type
        regmap[length(keys(regmap)) + 1] = loc
        return Locations
    end
end

function run_zx_passes(ir::YaoIR)
    n = count_qubits(ir)
    # NOTE: we can't optimize
    # non-constant location program
    isnothing(n) && return ir

    compact = Core.Compiler.IncrementalCompact(ir.ir, true)
    for b in ir.qb
        qc = QCircuit(n)
        # if there is no quantum terminator
        # this will be the first classical
        # terminator
        first_terminator = nothing
        for v in b
            e = ir.ir.stmts[v][:inst]
            qt = quantum_stmt_type(e)
            if qt === :gate
                e.args[3] isa IntrinsicSpec || break
                e.args[4] isa Locations || break
                # if can't convert to ZXDiagram, stop
                zx_push_gate!(qc, e.args[3], e.args[4]) || break
                # set old stmts to nothing
                compact[v] = nothing
            elseif qt === :ctrl
                e.args[3] isa IntrinsicSpec || break
                e.args[4] isa Locations || break
                e.args[5] isa CtrlLocations || break
                zx_push_gate!(qc, e.args[3], e.args[4], e.args[5]) || break
                compact[v] = nothing
            elseif qt === :measure || qt === :barrier
                # we attach terminator after optimization
                if isnothing(first_terminator)
                    first_terminator = v
                end
            end
        end

        if isnothing(first_terminator)
            first_terminator = last(b)
        end

        zxd = ZXDiagram(qc)
        # ZX passes
        phase_teleportation(zxd)
        clifford_simplification(zxd)

        # TODO: we might want to check if
        # the result circuit is simpler indeed
        qc = QCircuit(zxd)
        for g in ZXCalculus.gates(qc)
            if g.name in (:H, :Z, :X, :S, :T, :Sdag, :Tdag)
                spec = IntrinsicSpec{g.name}()
                mi = specialize_gate(typeof(spec), Locations{Int})
                e = Expr(:invoke, mi, Semantic.gate, spec, Locations(g.loc))
            elseif g.name in (:shift, :Rz, :Rx)
                spec = IntrinsicSpec{g.name}(g.param)
                mi = specialize_gate(typeof(spec), Locations{Int})
                e = Expr(:invoke, mi, Semantic.gate, spec, Locations(g.loc))
            elseif g.name === :CNOT
                mi = specialize_ctrl(typeof(YaoLang.X), Locations{Int}, CtrlLocations{Int})
                e = Expr(:invoke, mi, Semantic.ctrl, YaoLang.X, Locations(g.loc), CtrlLocations(g.ctrl))
            elseif g.name === :CZ
                mi = specialize_ctrl(typeof(YaoLang.Z), Locations{Int}, CtrlLocations{Int})
                e = Expr(:invoke, mi, Semantic.ctrl, YaoLang.Z, Locations(g.loc), CtrlLocations(g.ctrl))
            else
                error("unknown gate $g")
            end
            Core.Compiler.insert_node!(compact, SSAValue(first_terminator), Nothing, e)
        end
    end
    for _ in compact; end
    new = Core.Compiler.finish(compact)
    return YaoIR(new, compute_quantum_blocks(new))
end

function specialize_gate(spec, loc)
    atypes = Tuple{typeof(Semantic.gate), spec, loc}
    if spec <: IntrinsicSpec
        method = first(methods(Semantic.gate, Tuple{IntrinsicSpec, Locations}))
    elseif spec <: RoutineSpec
        method = first(methods(Semantic.gate, Tuple{RoutineSpec, Locations}))
    end

    return Core.Compiler.specialize_method(method, atypes, Core.svec())
end

function specialize_ctrl(spec, loc, ctrl)
    atypes = Tuple{typeof(Semantic.ctrl), spec, loc, ctrl}
    if spec <: IntrinsicSpec
        method = first(methods(Semantic.ctrl, Tuple{IntrinsicSpec, Locations, CtrlLocations}))
    elseif spec <: RoutineSpec
        method = first(methods(Semantic.ctrl, Tuple{RoutineSpec, Locations, CtrlLocations}))
    end

    return Core.Compiler.specialize_method(method, atypes, Core.svec())
end

function zx_push_gate!(qc::QCircuit, gate::IntrinsicSpec, locs::Locations)
    name = routine_name(gate)

    # NOTE: locs can be UnitRange etc. for instruction
    # remember to expand it
    for each in locs
        if name in (:H, :X, :Z, :S, :Sdag, :T, :Tdag)
            push_gate!(qc, QGate(name, each))
        elseif name === :Y
            push_gate!(qc, QGate(:X, each))
            push_gate!(qc, QGate(:Z, each))
        elseif name in (:Rz, :Rx, :shift)
            push_gate!(qc, QGate(name, each; param=gate.variables[1]))
        elseif name === :Ry
            push_gate!(qc, QGate(:Sdag, each))
            push_gate!(qc, QGate(:Rx, each; param=gate.variables[1]))
            push_gate!(qc, QGate(:S, each))
        else
            return false
        end
    end
    return true
end

function zx_push_gate!(qc::QCircuit, gate::IntrinsicSpec, locs::Locations, ctrl::CtrlLocations)
    name = routine_name(gate)
    ctrl = ctrl.storage.storage

    for each in locs
        if name === :Z
            push_gate!(qc, QGate(:CZ, each; ctrl=ctrl))
        elseif name === :X
            if ctrl isa Tuple && length(ctrl) == 2
                a, b = ctrl
                c = each
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
            elseif ctrl isa Int
                push_gate!(qc, Val(:CNOT), each, ctrl)
            end
        else
            return false
        end
    end

    return true
end
