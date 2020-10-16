obtain_code_info(r::RoutineSpec) = obtain_code_info(typeof(r))

function obtain_code_info(::Type{RoutineSpec{P, Sigs}}) where {P, Sigs}
    tt = Tuple{P, Sigs.parameters...}
    ms = methods(routine_stub, tt)
    @assert length(ms) == 1
    method = first(ms)
    method_args = Tuple{RoutineStub, tt.parameters...}
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
    ci = Core.Compiler.retrieve_code_info(mi)
    convert_to_quantum_head!(ci)
    return mi, ci
end

function perform_typeinf(mi::Core.MethodInstance, ci::CodeInfo)
    # type infer
    result = Core.Compiler.InferenceResult(mi)
    world = Core.Compiler.get_world_counter()
    interp = YaoLang.Compiler.YaoInterpreter()
    frame = Core.Compiler.InferenceState(result, ci, #=cached=# true, interp)
    # opt = Core.Compiler.OptimizationState(frame, Core.Compiler.OptimizationParams(interp), interp)
    # nargs = Int(opt.nargs) - 1
    Core.Compiler.typeinf_local(interp, frame)
    # ir = Core.Compiler.convert_to_ircode(ci, Core.Compiler.copy_exprargs(ci.code), false, nargs, opt)
    return result
end

function quantum_blocks(ci::CodeInfo, cfg::CFG)
    quantum_blocks = UnitRange{Int}[]

    for b in cfg.blocks
        start, stop = 0, 0
        for v in b.stmts
            st = ci.code[v]
            if is_quantum_statement(st)
                head = quantum_stmt_type(st)
                if head in [:measure, :barrier]
                    push!(quantum_blocks, start:stop+1)
                    start = stop = 0
                else
                    if start > 0
                        stop += 1
                    else
                        start = stop = v
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

function replace_from_perm(stmt, perm)
    stmt isa Core.SSAValue && return Core.SSAValue(findfirst(isequal(stmt.id), perm))

    if stmt isa Expr
        return Expr(stmt.head, map(x->replace_from_perm(x, perm), stmt.args)...)
    else
        return stmt
    end
end

function permute_stmts(ci::Core.CodeInfo, perm::Vector{Int})
    code = []
    ssavaluetypes = ci.ssavaluetypes isa Vector ? ci.ssavaluetypes[perm] : ci.ssavaluetypes

    for v in perm
        stmt = ci.code[v]

        if stmt isa Expr
            ex = replace_from_perm(stmt, perm)
            push!(code, ex)
        elseif stmt isa Core.GotoIfNot
            if stmt.cond isa Core.SSAValue
                cond = Core.SSAValue(findfirst(isequal(stmt.cond.id), perm))
            else
                # TODO: figure out which case is this
                # and maybe apply permute to this
                cond = stmt.cond
            end

            dest = findfirst(isequal(stmt.dest), perm)
            push!(code, Core.GotoIfNot(cond, dest))
        elseif stmt isa Core.GotoNode
            push!(code, Core.GotoNode(findfirst(isequal(stmt.label), perm)))
        elseif stmt isa Core.ReturnNode
            if stmt.val isa Core.SSAValue
                push!(code, Core.ReturnNode(Core.SSAValue(findfirst(isequal(stmt.val.id), perm))))
            else
                push!(code, stmt)
            end
        elseif stmt isa Core.SlotNumber
            push!(code, stmt)
        else
            error("unrecognized statement $stmt :: ($(typeof(stmt)))")
        end
    end

    ret = copy(ci)
    ret.code = code
    ret.ssavaluetypes = ssavaluetypes
    return ret
end

function group_quantum_stmts_perm(ci::CodeInfo, cfg::CFG)
    perms = Int[]
    cstmts_tape = Int[]
    qstmts_tape = Int[]

    for b in cfg.blocks
        for v in b.stmts
            e = ci.code[v]
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

function group_quantum_stmts(ci::CodeInfo, cfg::CFG)
    perm = group_quantum_stmts_perm(ci, cfg)
    return permute_stmts(ci, perm)
end

function exit_block!(perms::Vector, cstmts_tape::Vector, qstmts_tape::Vector)
    append!(perms, cstmts_tape)
    append!(perms, qstmts_tape)
    empty!(cstmts_tape)
    empty!(qstmts_tape)
    return perms
end

struct YaoIR
    ci::CodeInfo
    cfg::CFG
    # range of stmts contains pure quantum stmts
    blocks::Vector{UnitRange{Int}}
end

# this must be typed
# with quantum head
function YaoIR(ci::CodeInfo)
    cfg = Core.Compiler.compute_basic_blocks(ci.code)
    ci = group_quantum_stmts(ci, cfg)
    return YaoIR(ci, cfg, quantum_blocks(ci, cfg))
end

struct RoutineInfo
    code::YaoIR
    parent
    signature
    spec
end

function RoutineInfo(rs::Type{RoutineSpec{P, Sigs}}) where {P, Sigs}
    mi, ci = obtain_code_info(rs)
    result = perform_typeinf(mi, ci)
    ci = result.result.src
    return RoutineInfo(YaoIR(ci), P, Sigs, rs)
end
