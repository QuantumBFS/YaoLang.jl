const codegen_ctxs = Dict{Symbol, Any}()
codegen_ctxs[:julia] = JuliaASTCodegenCtx


function device_m(__module__::Module, ex::Expr; target::Symbol=:julia, mode::Symbol=:hybrid)
    ir = YaoIR(__module__, ex, mode) #= default parsing pass =#

    # simple validation
    if mode === :pure
        is_pure_quantum(ir) ||
            throw(ParseError("expect pure quantum statement, remove mode=:pure, or remove all classical statement"))
    elseif mode === :qasm
        is_qasm_compatible(ir) ||
            throw(ParseError("expect qasm compatible statement, remove mode=:qasm, or move all uncompatible statement"))
    end

    # TODO: code optimization/transformation pass
    # TODO: switch compile target

    @timeit_debug to "codegen" begin
        code = codegen(codegen_ctxs[target](ir), ir)
    end
    return code
end
