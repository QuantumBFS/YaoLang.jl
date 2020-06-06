const codegen_ctxs = Dict{Symbol, Any}()
codegen_ctxs[:julia] = JuliaASTCodegenCtx


function device_m(__module__::Module, ex::Expr; target::Symbol=:julia, mode::Symbol=:hybrid)
    ir = YaoIR(__module__, ex, mode) #= default parsing pass =#

    # TODO: code optimization/transformation pass
    # TODO: switch compile target

    return codegen(codegen_ctxs[target](ir), ir)
end
