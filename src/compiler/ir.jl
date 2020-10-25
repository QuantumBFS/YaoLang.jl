struct NewCodeInfo
    src::CodeInfo
    code::Vector{Any}
    nvariables::Int
    codelocs::Vector{Int32}
    newslots::Dict{Int, Symbol}
    slotnames::Vector{Symbol}
    changemap::Vector{Int}
    slotmap::Vector{Int}

    function NewCodeInfo(ci::CodeInfo, nargs::Int)
        code = []
        codelocs = Int32[]
        newslots = Dict{Int, Symbol}()
        slotnames = copy(ci.slotnames)
        changemap = fill(0, length(ci.code))
        slotmap = fill(0, length(ci.slotnames))
        new(ci, code, nargs + 1, codelocs, newslots, slotnames, changemap, slotmap)
    end
end

source_slot(ci::NewCodeInfo, i::Int) = Core.SlotNumber(i + ci.slotmap[i])

function slot(ci::NewCodeInfo, name::Symbol)
    return Core.SlotNumber(findfirst(isequal(name), ci.slotnames))
end

function unpack_closure!(ci::NewCodeInfo, closure::Int)
    spec = Core.SlotNumber(closure)
    codeloc = ci.src.codelocs[1]
    # unpack closure
    # %1 = get variables
    push!(ci.code, Expr(:call, GlobalRef(Base, :getfield), spec, QuoteNode(:variables)))
    push!(ci.codelocs, codeloc)
    ci.changemap[1] += 1

    # %2 = get parent
    push!(ci.code, Expr(:(=), source_slot(ci, 2), Expr(:call, GlobalRef(Base, :getfield), spec, QuoteNode(:parent))))
    push!(ci.codelocs, codeloc)
    # unpack variables
    for i in 2:ci.nvariables
        push!(ci.code, Expr(:(=), source_slot(ci, i+1), Expr(:call, GlobalRef(Base, :getindex), NewSSAValue(1), i-1)))
        push!(ci.codelocs, codeloc)
    end
    ci.changemap[1] += ci.nvariables
    return ci
end

function insert_slot!(ci::NewCodeInfo, v::Int, slot::Symbol)
    ci.newslots[v] = slot
    insert!(ci.slotnames, v, slot)
    prev = length(filter(x->x<v, keys(ci.newslots)))
    for k in v-prev:length(ci.slotmap)
        ci.slotmap[k] += 1
    end
    return ci
end

function push_stmt!(ci::NewCodeInfo, stmt, codeloc::Int32 = Int32(1))
    push!(ci.code, stmt)
    push!(ci.codelocs, codeloc)
    return ci
end

function insert_stmt!(ci::NewCodeInfo, v::Int, stmt)
    push_stmt!(ci, stmt, ci.src.codelocs[v])
    ci.changemap[v] += 1
    return NewSSAValue(length(ci.code))
end

function update_slots(e, slotmap)
    if e isa Core.SlotNumber
        return Core.SlotNumber(e.id + slotmap[e.id])
    elseif e isa Expr
        return Expr(e.head, map(x->update_slots(x, slotmap), e.args)...)
    elseif e isa Core.NewvarNode
        return Core.NewvarNode(Core.SlotNumber(e.slot.id + slotmap[e.slot.id]))
    else
        return e
    end
end

function finish(ci::NewCodeInfo)
    Core.Compiler.renumber_ir_elements!(ci.code, ci.changemap)
    replace_new_ssavalue!(ci.code)
    new_ci = copy(ci.src)
    new_ci.code = ci.code
    new_ci.codelocs = ci.codelocs
    new_ci.slotnames = ci.slotnames
    new_ci.slotflags = [0x00 for _ in new_ci.slotnames]
    new_ci.inferred = false
    new_ci.inlineable = true
    new_ci.ssavaluetypes = length(ci.code)
    return new_ci
end

function is_quantum_statement(@nospecialize(e))
    e isa Expr || return false

    if e.head === :call
        f = e.args[1]
        f isa GlobalRef && f.mod === Semantic || return false
        return true
    elseif e.head === :invoke
        f = e.args[2]
        f isa GlobalRef && f.mod === Semantic || return false
        return true
    elseif e.head === :(=)
        return is_quantum_statement(e.args[2])
    else
        return false
    end
end

function quantum_stmt_type(e::Expr)
    if e.head === :call
        return e.args[1].name
    elseif e.head === :invoke
        return e.args[2].name
    else
        return quantum_stmt_type(e.args[2])
    end
end

function _replace_new_ssavalue(e)
    if e isa NewSSAValue
        return SSAValue(e.id)
    elseif e isa Expr
        return Expr(e.head, map(_replace_new_ssavalue, e.args)...)
    elseif e isa Core.GotoIfNot
        cond = e.cond
        if cond isa NewSSAValue
            cond = SSAValue(cond.id)
        end
        return Core.GotoIfNot(cond, e.dest)
    elseif e isa Core.ReturnNode && isdefined(e, :val) && isa(e.val, NewSSAValue)
        return Core.ReturnNode(SSAValue(e.val.id))
    else
        return e
    end
end

function replace_new_ssavalue!(code::Vector)
    for idx in 1:length(code)
        code[idx] = _replace_new_ssavalue(code[idx])
    end
    return code
end

function obtain_codeinfo(::Type{RoutineSpec{P, Sigs}}) where {P, Sigs}
    nargs = length(Sigs.parameters)
    tt = Tuple{P, Sigs.parameters...}
    ms = methods(routine_stub, tt)
    @assert length(ms) == 1
    method = first(ms)
    method_args = Tuple{RoutineStub, tt.parameters...}
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
    ci = Core.Compiler.retrieve_code_info(mi)

    name = routine_name(P)
    linetable = Any[]
    for lineinfo in ci.linetable
        push!(linetable, Core.LineInfoNode(lineinfo.module, name, lineinfo.file, lineinfo.line, lineinfo.inlined_at))
    end
    ci.linetable = linetable
    return ci, nargs
end

function create_codeinfo(::Type{Spec}) where {Spec <: RoutineSpec}
    ci, nargs = obtain_codeinfo(Spec)
    return create_codeinfo(ci, nargs)
end

function create_codeinfo(ci::CodeInfo, nargs::Int)
    new = NewCodeInfo(ci, nargs)
    insert_slot!(new, 2, :spec)
    unpack_closure!(new, 2)

    for (v, stmt) in enumerate(ci.code)
        push_stmt!(new, update_slots(stmt, new.slotmap), ci.codelocs[v])
    end
    return finish(new)
end

function quantum_blocks(ci::CodeInfo, cfg::CFG)
    quantum_blocks = UnitRange{Int}[]
    last_stmt_is_measure_or_barrier = false

    for b in cfg.blocks
        start, stop = 0, 0
        for v in b.stmts
            st = ci.code[v]
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
        else
            # RL: I think
            # other nodes won't contain SSAValue
            # let's just ignore them, but if we
            # find any we can add them here
            push!(code, stmt)
            # if stmt isa Core.SlotNumber
            #     push!(code, stmt)
            # elseif stmt isa Core.NewvarNode
            #     push!(code, stmt)
            # else
            # end
            # error("unrecognized statement $stmt :: ($(typeof(stmt)))")
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

# NOTE:
# YaoIR contains the SSA IR with quantum blocks for function
# λ(spec, location)
struct YaoIR
    ci::CodeInfo
    cfg::CFG
    # range of stmts contains pure quantum stmts
    blocks::Vector{UnitRange{Int}}
end

function YaoIR(::Type{Spec}) where {Spec <: RoutineSpec}
    ci = create_codeinfo(Spec)
    cfg = Core.Compiler.compute_basic_blocks(ci.code)
    ci = group_quantum_stmts(ci, cfg)
    return YaoIR(ci, cfg, quantum_blocks(ci, cfg))
end

function Base.show(io::IO, ri::YaoIR)
    println(io, "quantum blocks:")
    println(io, ri.blocks)
    print(io, ri.ci)
end

struct RoutineInfo
    code::YaoIR
    nargs::Int
    edges::Vector{Any}
    parent
    signature
    spec
end

function RoutineInfo(rs::Type{RoutineSpec{P, Sigs}}) where {P, Sigs}
    code = YaoIR(rs)
    edges = Any[]
    return RoutineInfo(code, length(Sigs.parameters), edges, P, Sigs, rs)
end

NewCodeInfo(ri::RoutineInfo) = NewCodeInfo(ri.code.ci, ri.nargs)

# handle location mapping
function codeinfo_gate(ri::RoutineInfo)
    new = NewCodeInfo(ri)
    insert_slot!(new, 3, :locations)
    locations = slot(new, :locations)

    for (v, stmt) in enumerate(new.src.code)
        codeloc = new.src.codelocs[v]
        stmt = update_slots(stmt, new.slotmap)
        e = nothing
        if is_quantum_statement(stmt)
            type = quantum_stmt_type(stmt)
            if type === :gate
                local_location = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                e = Expr(:call, GlobalRef(Semantic, :gate), stmt.args[2], local_location)
            elseif type === :ctrl
                local_location = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                local_ctrl = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[4]))
                e = Expr(:call, GlobalRef(Semantic, :ctrl), stmt.args[2], local_location, local_ctrl)
            elseif type === :measure
                if stmt.head === :(=)
                    cvar = stmt.args[1]
                    measure = stmt.args[2]
                else
                    cvar = nothing
                    measure = stmt
                end

                # no location specified
                if length(measure.args) == 2
                    measure_locs = locations
                else
                    measure_locs = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                end

                # TODO: handle measure operator
                measure_ex = Expr(:call, GlobalRef(Semantic, :measure), measure_locs)
                if isnothing(cvar)
                    e = measure_ex
                else
                    e = Expr(:(=), cvar, measure_ex)
                end
            elseif type === :barrier
                local_location = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[2]))
                e = Expr(:call, GlobalRef(Semantic, :barrier), local_location)
            end
        end

        if isnothing(e)
            push_stmt!(new, stmt, codeloc)
        else
            push_stmt!(new, e, codeloc)
        end
    end
    return finish(new)
end

function codeinfo_ctrl(ri::RoutineInfo)
    new = NewCodeInfo(ri.code.ci, ri.nargs)
    insert_slot!(new, 3, :locations)
    insert_slot!(new, 4, :ctrl)
    locations = slot(new, :locations)
    ctrl = slot(new, :ctrl)

    for (v, stmt) in enumerate(new.src.code)
        codeloc = new.src.codelocs[v]
        stmt = update_slots(stmt, new.slotmap)
        e = nothing
        if is_quantum_statement(stmt)
            type = quantum_stmt_type(stmt)
            if type === :gate
                local_location = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                e = Expr(:call, GlobalRef(Semantic, :ctrl), stmt.args[2], local_location, ctrl)
            elseif type === :ctrl
                local_location = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                local_ctrl = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[4]))
                real_ctrl = insert_stmt!(new, v, Expr(:call, GlobalRef(YaoLang, :merge_locations), local_ctrl, ctrl))
                e = Expr(:call, GlobalRef(Semantic, :ctrl), stmt.args[2], local_location, real_ctrl)
            elseif type === :measure
                error("cannot use measure under a quantum control context")
            elseif type === :barrier
                local_location = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[2]))
                e = Expr(:call, GlobalRef(Semantic, :barrier), local_location)
            end
        end

        if isnothing(e)
            push_stmt!(new, stmt, codeloc)
        else
            push_stmt!(new, e, codeloc)
        end
    end
    return finish(new)
end

function Base.show(io::IO, ri::RoutineInfo)
    println(io, ri.spec)
    print(io, ri.code)
end

function typeinf_stub(spec::RoutineSpec) end

function perform_typeinf(ri::RoutineInfo)
    method = first(methods(typeinf_stub))
    method_args = Tuple{typeof(typeinf_stub), ri.spec}
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
    result = Core.Compiler.InferenceResult(mi)
    world = Core.Compiler.get_world_counter()
    interp = YaoLang.Compiler.YaoInterpreter()
    frame = Core.Compiler.InferenceState(result, ri.code.ci, #=cached=# true, interp)
    Core.Compiler.typeinf_local(interp, frame)

    for tt in ri.code.ci.ssavaluetypes
        T = Core.Compiler.widenconst(tt)
        if T <: RoutineSpec || T <: IntrinsicSpec
            push!(ri.edges, T)
        end
    end

    ri.code.ci.inferred = true
    return ri
end

# NOTE: these two functions are mainly compile time stubs
# so we can attach this piece of CodeInfo to certain method
@generated function Semantic.main(spec::RoutineSpec)
    ri = RoutineInfo(spec)
    return ri.code.ci
end

@generated function Semantic.gate(spec::RoutineSpec, ::Locations)
    ri = RoutineInfo(spec)
    return codeinfo_gate(ri)
end

@generated function Semantic.ctrl(spec::RoutineSpec, ::Locations, ::CtrlLocations)
    ri = RoutineInfo(spec)
    return codeinfo_ctrl(ri)
end
