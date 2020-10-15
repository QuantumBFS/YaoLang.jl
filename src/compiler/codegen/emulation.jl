export replace_with_execute
using Core.Compiler: NewSSAValue
using Core: SSAValue
using YaoArrayRegister

function execute(::IntrinsicSpec{:H}, r::ArrayReg, loc::Locations)
    println("executing H")
    return
end

function execute(::IntrinsicSpec{:H}, r::ArrayReg, loc::Locations, ctrl::CtrlLocations)
    println("executing ctrl H")
    return
end

function execute(inst::IntrinsicSpec{:shift}, r::ArrayReg, loc::Locations)
    println("executing shift(", inst.variables[1], ")")
    return
end

function execute(inst::IntrinsicSpec{:shift}, r::ArrayReg, loc::Locations, ctrl::CtrlLocations)
    println("executing ctrl shift(", inst.variables[1], ")")
    return
end

@generated function execute(spec::RoutineSpec, r::ArrayReg, loc::Locations)
    ri = RoutineInfo(spec)
    return replace_with_execute(ri)
end

@generated function execute(spec::RoutineSpec, r::ArrayReg, loc::Locations, ctrl::CtrlLocations)
    ri = RoutineInfo(spec)
    return replace_with_ctrl_execute(ri)
end

function update_slots(e, element_map)
    if e isa Core.SlotNumber
        return get(element_map, e, e)
    elseif e isa Expr
        return Expr(e.head, map(x->update_slots(x, element_map), e.args)...)
    else
        return e
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

function unpack_closure!(code::Vector, codelocs::Vector{Int32}, ri::RoutineInfo, changemap, args)
    codeloc = ri.code.ci.codelocs[1]
    spec = Core.SlotNumber(2)

    # %1 = get variables
    push!(code, Expr(:call, GlobalRef(Base, :getfield), spec, QuoteNode(:variables)))
    push!(codelocs, codeloc)
    changemap[1] += 1
    
    # %2 = get parent
    push!(code, Expr(:(=), args[1], Expr(:call, GlobalRef(Base, :getfield), spec, QuoteNode(:parent))))
    push!(codelocs, codeloc)
    changemap[1] += 1

    # unpack variables
    for i in 1:length(ri.signature.parameters)
        push!(code, Expr(:(=), args[i+1], Expr(:call, GlobalRef(Base, :getindex), NewSSAValue(1), i)))
        push!(codelocs, codeloc)
    end
    changemap[1] += length(ri.signature.parameters)
    return code
end

function pushback_slots!(slotnames::Vector, slotmap::Dict, args, ri::RoutineInfo)
    n_execute_args = length(slotnames)
    for (id, slot) in enumerate(ri.code.ci.slotnames[2:end]) # don't insert #self#
        push!(slotnames, slot)
        slotmap[Core.SlotNumber(id + 1)] = Core.SlotNumber(id + n_execute_args)
        push!(args, Core.SlotNumber(id + n_execute_args))
    end
end

function setup_codeinfo!(code::Vector, codelocs::Vector{Int32}, changemap, slotnames, ri::RoutineInfo)
    # renumber ssa
    Core.Compiler.renumber_ir_elements!(code, changemap)
    replace_new_ssavalue!(code)
    ci = copy(ri.code.ci)
    ci.code = code
    ci.codelocs = codelocs
    ci.slotnames = slotnames
    ci.slotflags = [0x00 for _ in slotnames]
    ci.inferred = false
    ci.inlineable = true
    ci.ssavaluetypes = length(ci.code)

    method = first(methods(ri.parent.instance, ri.signature))
    method_args = Tuple{ri.parent, ri.signature.parameters...}
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
    ci.edges = Core.MethodInstance[mi]
    return ci
end

function replace_with_execute(ri::RoutineInfo)
    code = []
    codelocs = Int32[]
    slotnames = Symbol[Symbol("#self#"), :spec, :register, :locations]
    changemap = fill(0, length(ri.code.ci.code))
    slotmap = Dict{Core.SlotNumber, Core.SlotNumber}()
    spec = Core.SlotNumber(2)
    register = Core.SlotNumber(3)
    locations = Core.SlotNumber(4)
    args = Core.SlotNumber[]

    pushback_slots!(slotnames, slotmap, args, ri)
    unpack_closure!(code, codelocs, ri, changemap, args)

    for (v, stmt) in enumerate(ri.code.ci.code)
        codeloc = ri.code.ci.codelocs[v]
        if is_quantum_statement(stmt)
            type = quantum_stmt_type(stmt)
            if type === :gate
                push!(code, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                push!(codelocs, codeloc)
                local_location = NewSSAValue(length(code))
                changemap[v] += 1
                e = Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, local_location)
            elseif type === :ctrl
                push!(code, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                push!(codelocs, codeloc)
                local_location = NewSSAValue(length(code))
                push!(code, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[4]))
                push!(codelocs, codeloc)
                local_ctrl = NewSSAValue(length(code))
                changemap[v] += 2
                e = Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, local_location, local_ctrl)
            elseif type === :measure
                error("not supported yet")
                # Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, stmt.args[3], stmt.args[4])
            end
        else
            e = update_slots(stmt, slotmap)
        end
        push!(codelocs, codeloc)
        push!(code, e)
    end

    return setup_codeinfo!(code, codelocs, changemap, slotnames, ri)
end

function replace_with_ctrl_execute(ri::RoutineInfo)
    code = []
    codelocs = Int32[]
    slotnames = Symbol[Symbol("#self#"), :spec, :register, :locations, :ctrl]
    changemap = fill(0, length(ri.code.ci.code))
    slotmap = Dict()
    spec = Core.SlotNumber(2)
    register = Core.SlotNumber(3)
    locations = Core.SlotNumber(4)
    ctrl = Core.SlotNumber(5)
    args = Core.SlotNumber[]

    pushback_slots!(slotnames, slotmap, args, ri)
    unpack_closure!(code, codelocs, ri, changemap, args)

    for (v, stmt) in enumerate(ri.code.ci.code)
        codeloc = ri.code.ci.codelocs[v]
        if is_quantum_statement(stmt)
            type = quantum_stmt_type(stmt)
            if type === :gate
                push!(code, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                push!(codelocs, codeloc)
                local_location = NewSSAValue(length(code))
                changemap[v] += 1
                e = Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, local_location, ctrl)
            elseif type === :ctrl
                push!(code, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                push!(codelocs, codeloc)
                local_location = NewSSAValue(length(code))
                push!(code, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[4]))
                push!(codelocs, codeloc)
                local_ctrl = NewSSAValue(length(code))
                push!(code, Expr(:call, GlobalRef(YaoLang, :merge_locations), local_ctrl, ctrl))
                push!(codelocs, codeloc)
                changemap[v] += 3
                real_ctrl = NewSSAValue(length(code))
                e = Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, local_location, real_ctrl)
            elseif type === :measure
                error("measurement should not be controlled by quantum operation")
            end
        else
            e = update_slots(stmt, slotmap)
        end
        push!(codelocs, codeloc)
        push!(code, e)
    end

    return setup_codeinfo!(code, codelocs, changemap, slotnames, ri)
end
