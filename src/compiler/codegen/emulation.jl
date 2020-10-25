struct JuliaASTCtx end

struct EchoReg{B} <: AbstractRegister{B} end
Base.show(io::IO, x::EchoReg) = print(io, "echo register")
EchoReg() = EchoReg{1}()

@generated function execute(spec::RoutineSpec, r::EchoReg, loc::Locations)
    ri = RoutineInfo(spec)
    return codegen_gate(JuliaASTCtx(), ri)
end

@generated function execute(spec::RoutineSpec, r::EchoReg, loc::Locations, ctrl::CtrlLocations)
    ri = RoutineInfo(spec)
    return codegen_ctrl(JuliaASTCtx(), ri)
end

function execute(op::IntrinsicSpec, ::EchoReg, loc::Locations)
    @info "executing $loc => $op"
end

function execute(op::IntrinsicSpec, ::EchoReg, loc::Locations, ctrl::CtrlLocations)
    @info "executing @ctrl $ctrl $loc => $op"
end

function YaoAPI.measure(::EchoReg, locs)
    @info "measure at $locs"
end

@generated function execute(spec::RoutineSpec, r::ArrayReg, loc::Locations)
    ir = YaoIR(spec)
    return codegen_gate(JuliaASTCtx(), ir)
end

@generated function execute(spec::RoutineSpec, r::ArrayReg, loc::Locations, ctrl::CtrlLocations)
    ir = YaoIR(spec)
    return codegen_ctrl(JuliaASTCtx(), ir)
end

function codegen_gate(::JuliaASTCtx, ri::RoutineInfo)
    new = NewCodeInfo(ri)
    insert_slot!(new, 3, :register)
    insert_slot!(new, 4, :locations)
    locations = slot(new, :locations)
    register = slot(new, :register)

    for (v, stmt) in enumerate(new.src.code)
        codeloc = new.src.codelocs[v]
        stmt = update_slots(stmt, new.slotmap)
        e = nothing
        if is_quantum_statement(stmt)
            type = quantum_stmt_type(stmt)
            if type === :gate
                local_location = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                e = Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, local_location)
            elseif type === :ctrl
                local_location = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                local_ctrl = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[4]))
                e = Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, local_location, local_ctrl)
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
                measure_ex = Expr(:call, GlobalRef(YaoAPI, :measure), register, measure_locs)
                if isnothing(cvar)
                    e = measure_ex
                else
                    e = Expr(:(=), cvar, measure_ex)
                end
            else
                # delete other statement
                new.changemap[v] -= 1
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

function codegen_ctrl(::JuliaASTCtx, ir::YaoIR)
    new = NewCodeInfo(ri)
    insert_slot!(new, 3, :register)
    insert_slot!(new, 4, :locations)
    insert_slot!(new, 5, :ctrl)
    register = slot(new, :register)
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
                e = Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, local_location, ctrl)
            elseif type === :ctrl
                local_location = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[3]))
                local_ctrl = insert_stmt!(new, v, Expr(:call, GlobalRef(Base, :getindex), locations, stmt.args[4]))
                real_ctrl = insert_stmt!(new, v, Expr(:call, GlobalRef(YaoLang, :merge_locations), local_ctrl, ctrl))
                e = Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, local_location, real_ctrl)
            elseif type === :measure
                error("cannot use measure under a quantum control context")
            else
                new.changemap[v] -= 1
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
