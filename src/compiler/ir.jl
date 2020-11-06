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
    e.head === :quantum && return true
    if e.head === :call
        f = e.args[1]
        f isa Function && parentmodule(f) === Semantic && return true
        f isa GlobalRef && f.mod === Semantic && return true
    elseif e.head === :invoke
        f = e.args[2]
        f isa Function && parentmodule(f) === Semantic && return true
        f isa GlobalRef && f.mod === Semantic && return true
    elseif e.head === :(=)
        return is_quantum_statement(e.args[2])
    end
    return false
end

function quantum_stmt_type(e::Expr)
    if e.head === :call
        e.args[1] isa Function && return nameof(e.args[1])
        return e.args[1].name
    elseif e.head === :invoke
        e.args[2] isa Function && return nameof(e.args[2])
        return e.args[2].name
    elseif e.head === :quantum
        return e.args[1]
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
    ci.edges = Core.MethodInstance[mi]
    return ci, nargs
end

function create_codeinfo(::typeof(Semantic.main), S::Type{<:RoutineSpec})
    ci, nargs = obtain_codeinfo(S)
    new = NewCodeInfo(ci, nargs)
    insert_slot!(new, 2, :spec)
    unpack_closure!(new, 2)

    for (v, stmt) in enumerate(ci.code)
        push_stmt!(new, update_slots(stmt, new.slotmap), ci.codelocs[v])
    end
    return finish(new)
end

function _extract_measure(e)
    if e.head === :(=)
        return e.args[1], e.args[2]
    else
        return nothing, e
    end
end

function create_codeinfo(::typeof(Semantic.gate), S::Type{<:RoutineSpec})
    ci, nargs = obtain_codeinfo(S)
    new = NewCodeInfo(ci, nargs)
    insert_slot!(new, 2, :spec)
    insert_slot!(new, 3, :locations)
    unpack_closure!(new, 2)
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
                cvar, measure = _extract_measure(stmt)
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

function create_codeinfo(::typeof(Semantic.ctrl), S::Type{<:RoutineSpec})
    ci, nargs = obtain_codeinfo(S)
    new = NewCodeInfo(ci, nargs)
    insert_slot!(new, 2, :spec)
    insert_slot!(new, 3, :locations)
    insert_slot!(new, 4, :ctrl)
    unpack_closure!(new, 2)
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


# NOTE: these two functions are mainly compile time stubs
# so we can attach this piece of CodeInfo to certain method
@generated function Semantic.main(spec::RoutineSpec)
    return create_codeinfo(Semantic.main, spec)
end

@generated function Semantic.gate(spec::RoutineSpec, ::Locations)
    return create_codeinfo(Semantic.gate, spec)
end

@generated function Semantic.ctrl(spec::RoutineSpec, ::Locations, ::CtrlLocations)
    return create_codeinfo(Semantic.ctrl, spec)
end

function _prepare_frame(f, spec, args...)
    method = methods(f, Tuple{spec, args...})|>first
    atypes = Tuple{typeof(f), spec, args...}
    mi = Core.Compiler.specialize_method(method, atypes, Core.svec())
    result = Core.Compiler.InferenceResult(mi, Any[Core.Const(f), spec, args...])
    world = Core.Compiler.get_world_counter()
    interp = YaoLang.Compiler.YaoInterpreter(;)
    frame = Core.Compiler.InferenceState(result, #=cached=# true, interp)
    return interp, frame
end
