export replace_with_execute

using YaoArrayRegister

@generated function execute(::RoutineSpec{P, Sigs, Stub}, r::ArrayReg, loc::Locations) where {P, Sigs, Stub}
    ri = RoutineInfo(RoutineSpec{P, Sigs, Stub})
    return IRTools.Inner.update!(copy(ri.ci), replace_with_execute(ri))
end

function execute_stmt(e::Expr, register, locs)
    
end

function replace_with_execute(ri::RoutineInfo)
    ir = IR(ri.code.code.lines; meta=ri.code.code.meta)
    _rename = Dict()
    rename(ex) = prewalk(ex) do x
        haskey(_rename, x) && return _rename[x]
        return x
    end

    self = argument!(ir)
    register = argument!(ir)
    locs = argument!(ir)
    vars = push!(ir, Statement(IRTools.xcall(:getfield, self, :variables)))

    for i in 1:length(ri.signature.parameters)
        old = ri.code.code.blocks[1].args[i+1]
        _rename[old] = push!(ir, Statement(IRTools.xcall(:getindex, vars, i)))
    end

    count = 0
    ssavalues = keys(ri.code.code)
    for i in 1:length(ri.code.code.blocks)
        bb = ri.code.code.blocks[i]
        for stmt in bb.stmts
            count += 1
            e = rename(stmt.expr)
            if is_quantum_statement(e)
                type = quantum_stmt_type(e)
                # we ignore things like barrier in runtime
                if type === :gate
                    local_locs = push!(ir, Statement(IRTools.xcall(:getindex, locs, e.args[3])))
                    e = Expr(:call, GlobalRef(Compiler, :execute), e.args[2], register, local_locs)
                elseif type === :ctrl
                    local_locs = push!(ir, Statement(IRTools.xcall(:getindex, locs, e.args[3])))
                    local_ctrl = push!(ir, Statement(IRTools.xcall(:getindex, locs, e.args[4])))
                    e = Expr(:call, GlobalRef(Compiler, :execute), e.args[2], register, local_locs, local_ctrl)
                elseif type === :measure
                    error("not implemented yet")
                    # return Expr(:call, GlobalRef(Compiler, :measure), e.args[2], e.args[3], e.args[4])
                else
                    continue
                end
            end
            v = push!(ir, Statement(e; stmt.line))
            _rename[ssavalues[count]] = v
        end
        
        for br in bb.branches
            branch!(ir, br.block, rename.(br.args)...; unless=rename(br.condition))
        end

        if i != length(ri.code.code.blocks)
            block!(ir)
        end
    end
    return ir
end

function replace_with_ctrl_execute(ri::RoutineSpec)
end
