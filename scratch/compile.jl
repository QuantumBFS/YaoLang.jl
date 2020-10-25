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

function typeinf()
    locs = Locations((1, 2, 3))
    ctrl = CtrlLocations((4, ))
    # execute(qft(3), r, locs)
    c = qft(3)
    ir = Compiler.YaoIR(typeof(c))
    method = methods(Compiler.Semantic.gate, Tuple{typeof(c), typeof(locs)})|>first
    method_args = Tuple{typeof(Compiler.Semantic.gate), typeof(c), typeof(locs)}
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
    result = Core.Compiler.InferenceResult(mi)
    world = Core.Compiler.get_world_counter()
    interp = YaoLang.Compiler.YaoInterpreter()
    frame = Core.Compiler.InferenceState(result, Compiler.codeinfo_gate(ir), #=cached=# true, interp)
    Core.Compiler.typeinf_local(interp, frame)
    frame.src    
end


r = Compiler.EchoReg()
locs = Locations((1, 2, 3))
ctrl = CtrlLocations((4, ))
# execute(qft(3), r, locs)
c = qft(3)

ri = @code_yao qft(3)
ci = Compiler.replace_with_execute(ri)
ci.slotnames
Compiler.execute(c, r, locs)

method = methods(Compiler.Semantic.gate, Tuple{typeof(c), typeof(locs)})|>first
method_args = Tuple{typeof(Compiler.Semantic.gate), typeof(c), typeof(locs)}
mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
result = Core.Compiler.InferenceResult(mi)
world = Core.Compiler.get_world_counter()
interp = YaoLang.Compiler.YaoInterpreter()
frame = Core.Compiler.InferenceState(result, Compiler.codeinfo_gate(ir), #=cached=# true, interp)
Core.Compiler.typeinf_local(interp, frame)
frame.src

Core.Compiler.get(Core.Compiler.code_cache(interp), mi, nothing)

