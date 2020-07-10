const codegen_ctxs = Dict{Symbol,Any}()
codegen_ctxs[:julia] = JuliaASTCodegenCtx


function device_m(__module__::Module, ex::Expr; target::Symbol = :julia, optimize::Int=0)
    ir = YaoIR(__module__, ex) #= default parsing pass =#

    # simple validation
    ir.pure_quantum = is_pure_quantum(ir)
    ir.qasm_compatible = is_qasm_compatible(ir)

    # TODO: code optimization/transformation pass
    ir = YaoLang.Compiler.optimize(ir)
    sink_quantum!(ir)
    # TODO: switch compile target

    @timeit_debug to "codegen" code = codegen(codegen_ctxs[target](ir), ir)
    return code
end
