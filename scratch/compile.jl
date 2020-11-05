using YaoLang
using YaoLang.Compiler

@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
    return 1
end

r = Compiler.EchoReg()
locs = Locations((1, 2, 3))
ctrl = CtrlLocations((4, ))
# execute(qft(3), r, locs)
c = qft(3)
spec = qft(3)
ir = Compiler.YaoIR(typeof(spec))

ci = ir.ci
# we need to re-create const-propagation info here
# but maybe we can somehow make this happen inside Julia
code = []
for (v, st) in enumerate(ci.code)
    if st isa Expr && st.head === :invoke
        push!(code, Expr(:call, st.args[2:end]...))
    elseif (st isa Core.ReturnNode) && !isdefined(st, :val)
        # replace unreachable
        push!(code, Core.ReturnNode(Compiler.unreachable))
    else
        push!(code, st)
    end
end
ci.ssavaluetypes = length(code)
ci.code = code

method = methods(Compiler.Semantic.main, Tuple{typeof(c)})|>first
mi = Core.Compiler.specialize_method(method, Tuple{typeof(Compiler.Semantic.main), typeof(c)}, Core.svec())
result = Core.Compiler.InferenceResult(mi)
interp = Compiler.YaoInterpreter()
frame = Core.Compiler.InferenceState(result, ci, #=cached=# true, interp)
Core.Compiler.typeinf_local(interp, frame)
frame.src



function typeinf()
    locs = Locations((1, 2, 3))
    ctrl = CtrlLocations((4, ))
    # execute(qft(3), r, locs)
    c = qft(3)

    method = methods(Compiler.Semantic.gate, Tuple{typeof(c), typeof(locs)})|>first
    method_args = Tuple{typeof(Compiler.Semantic.gate), typeof(c), typeof(locs)}
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
    result = Core.Compiler.InferenceResult(mi)
    world = Core.Compiler.get_world_counter()
    interp = YaoLang.Compiler.YaoInterpreter()
    frame = Core.Compiler.InferenceState(result, #=cached=# false, interp)
    Core.Compiler.typeinf_local(interp, frame)
    frame.src
end


method = methods(Compiler.Semantic.main, Tuple{typeof(c)})|>first
method_args = Tuple{typeof(Compiler.Semantic.main), typeof(c)}
mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
result = Core.Compiler.InferenceResult(mi, Any[Core.Const(Compiler.Semantic.main), Core.Const(c)])
world = Core.Compiler.get_world_counter()
interp = YaoLang.Compiler.YaoInterpreter()
frame = Core.Compiler.InferenceState(result, #=cached=# true, interp)
Core.Compiler.typeinf_local(interp, frame)
Core.Compiler.typeinf_code(interp, method, method_args, Core.svec(), true)
Core.Compiler.typeinf(interp, frame)
frame.src

opt_params = Core.Compiler.OptimizationParams(interp)
opt = Core.Compiler.OptimizationState(frame, opt_params, interp)

def = opt.linfo.def
nargs = Int(opt.nargs) - 1
ci = frame.src
sv = opt
ir = Core.Compiler.convert_to_ircode(ci, Core.Compiler.copy_exprargs(ci.code), false, nargs, opt)
ir = Core.Compiler.slot2reg(ir, ci, nargs, sv)
Core.Compiler.compact!(ir)

todo = Core.Compiler.Pair{Int, Any}[]
state = sv.inlining
idx = 32
stmt = ir.stmts[idx][:inst]
calltype = ir.stmts[idx][:type]
info = ir.stmts[idx][:info]
r = Core.Compiler.process_simple!(ir, todo, idx, sv.inlining)
(sig, invoke_data) = r
info = Core.Compiler.recompute_method_matches(sig.atype, state.params, state.et, state.method_table)
infos = Core.Compiler.MethodMatchInfo[info]
meth = info.results
match = Core.Compiler.first(meth)
case = Core.Compiler.analyze_method!(match, sig.atypes, state.et, state.caches, state.params, calltype)


Core.Compiler.analyze_single_call!(ir, todo, 9, stmt, sig, calltype, infos, state.et, state.caches, state.params)

Core.Compiler.assemble_inline_todo!(ir, sv.inlining)

Core.Compiler.ssa_inlining_pass!(ir, ir.linetable, sv.inlining, false)

frame.src, opt_params, interp

Core.Compiler.optimize(opt, opt_params, result.result)
opt.src.inferred = true


Core.Compiler.typeinf_local(interp, frame)
frame.src
