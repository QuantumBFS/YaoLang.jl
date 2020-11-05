# NOTE:
# emulation always execute the program directly
# we will use another entrance for optimized program
# emulation

struct EchoReg{B} <: AbstractRegister{B} end
Base.show(io::IO, x::EchoReg) = print(io, "echo register")
EchoReg() = EchoReg{1}()

@generated function execute(spec::RoutineSpec, r::EchoReg, loc::Locations)
    return codegen_ast(Semantic.gate, spec)
end

@generated function execute(spec::RoutineSpec, r::EchoReg, loc::Locations, ctrl::CtrlLocations)
    return codegen_ast(Semantic.ctrl, spec)
end

# this doesn't work yet, need to eval a typed IR
# @generated function optimized_execute(spec::RoutineSpec, r::EchoReg, loc::Locations)
#     ci = create_codeinfo(Semantic.gate, spec)
#     ir = YaoIR(r, Semantic.gate, spec, loc)
#     ir = optimize(ir)
#     return replace_with_execute(ir.ci)
# end

# @generated function optimized_execute(spec::RoutineSpec, r::EchoReg, loc::Locations, ctrl::CtrlLocations)
#     return codegen_optimized_ast(Semantic.ctrl, spec)
# end

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
    return codegen_ast(Semantic.gate, spec)
end

@generated function execute(spec::RoutineSpec, r::ArrayReg, loc::Locations, ctrl::CtrlLocations)
    return codegen_ast(Semantic.ctrl, spec)
end

# function codegen_optimized_ast(f, S::Type{<:RoutineSpec})
#     ci = create_codeinfo(f, S)
#     ci = optimize(f, ci)
#     return replace_with_execute(ci)
# end

function codegen_ast(f, S::Type{<:RoutineSpec})
    ci = create_codeinfo(f, S)
    return replace_with_execute(ci)
end

function replace_with_execute(ci::CodeInfo)
    # NOTE: we won't unpack variables here, so nargs doesn't matter
    new = NewCodeInfo(ci, 0)
    insert_slot!(new, 3, :register)
    register = slot(new, :register)

    for (v, stmt) in enumerate(ci.code)
        stmt = update_slots(stmt, new.slotmap)
        codeloc = new.src.codelocs[v]
        if is_quantum_statement(stmt)
            t = quantum_stmt_type(stmt)
            if t === :measure
                cvar, measure =  _extract_measure(stmt)
                push_stmt!(new, Expr(:call, GlobalRef(YaoAPI, :measure!), register, measure.args[2:end]...), codeloc)
            elseif t === :gate || t === :ctrl
                push_stmt!(new, Expr(:call, GlobalRef(Compiler, :execute), stmt.args[2], register, stmt.args[3:end]...), codeloc)
            else
                # delete other statement
                new.changemap[v] -= 1
            end
        else
            push_stmt!(new, stmt, codeloc)
        end
    end

    return finish(new)
end
