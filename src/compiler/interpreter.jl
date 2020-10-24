struct MeasureResult end
# this is a Bool in runtime
# but we need to know this comes from
# a measurement so we can distringuish
# a classical control flow on quantum
# operation
struct QuantumBool end
Base.:(==)(x::MeasureResult, y::Int) = QuantumBool()
Base.:(==)(x::Int, y::MeasureResult) = QuantumBool()

struct YaoInterpreter <: AbstractInterpreter
    native_interpreter::Core.Compiler.NativeInterpreter
end

YaoInterpreter() = YaoInterpreter(Core.Compiler.NativeInterpreter())

InferenceParams(interp::YaoInterpreter) = InferenceParams(interp.native_interpreter)
OptimizationParams(interp::YaoInterpreter) = OptimizationParams(interp.native_interpreter)
Core.Compiler.get_world_counter(interp::YaoInterpreter) = get_world_counter(interp.native_interpreter)
Core.Compiler.get_inference_cache(interp::YaoInterpreter) = get_inference_cache(interp.native_interpreter)
Core.Compiler.code_cache(interp::YaoInterpreter) = Core.Compiler.code_cache(interp.native_interpreter)
Core.Compiler.may_optimize(interp::YaoInterpreter) = Core.Compiler.may_optimize(interp.native_interpreter)
Core.Compiler.may_discard_trees(interp::YaoInterpreter) = Core.Compiler.may_discard_trees(interp.native_interpreter)
Core.Compiler.may_compress(interp::YaoInterpreter) = Core.Compiler.may_compress(interp.native_interpreter)
Core.Compiler.unlock_mi_inference(interp::YaoInterpreter, mi::Core.MethodInstance) = Core.Compiler.unlock_mi_inference(interp.native_interpreter, mi)
Core.Compiler.lock_mi_inference(interp::YaoInterpreter, mi::Core.MethodInstance) = Core.Compiler.lock_mi_inference(interp.native_interpreter, mi)

function Core.Compiler.abstract_eval_statement(interp::YaoInterpreter, @nospecialize(e), vtypes::VarTable, sv::InferenceState)
    is_quantum_statement(e) || return Core.Compiler.abstract_eval_statement(interp.native_interpreter, e, vtypes, sv)
    @show e
    type = quantum_stmt_type(e)
    if type === :measure
        return MeasureResult
    elseif type === :gate || type === :ctrl
        ea = e.args[2:end]
        n = length(ea)
        argtypes = Vector{Any}(undef, n)
        @inbounds for i = 1:n
            ai = Core.Compiler.abstract_eval_value(interp, ea[i], vtypes, sv)
            if ai === Core.Compiler.Bottom
                return Core.Compiler.Bottom
            end
            argtypes[i] = ai
        end
        # call into a quantum routine
        callinfo = abstract_call_quantum(interp, type, ea, argtypes, sv)
        # callinfo = abstract_call(interp, ea, argtypes, sv)
        sv.stmt_info[sv.currpc] = callinfo.info
        t = callinfo.rt
    else
        return Nothing
    end

    # copied from abstract_eval_statement
    @assert !isa(t, TypeVar)
    if isa(t, DataType) && isdefined(t, :instance)
        # replace singleton types with their equivalent Const object
        t = Core.Const(t.instance)
    end
    return t
end

function abstract_call_quantum(interp::YaoInterpreter, type::Symbol, args::Vector{Any}, argtypes::Vector{Any}, sv::InferenceState)
    if type === :gate
        sf = Compiler.Semantic.gate
    else
        sf = Compiler.Semantic.ctrl
    end

    atypes = Core.Compiler.argtypes_to_type(argtypes)
    mt = methods(sf, atypes)
    @assert length(mt) == 1 # this should be true by construction
    method = first(mt)

    atypes = Tuple{typeof(sf), atypes.parameters...}
    mi = Core.Compiler.specialize_method(method, atypes, Core.svec())::Core.MethodInstance
    @show argtypes
    gt = Core.Compiler.widenconst(argtypes[1])
    gt <: IntrinsicSpec && return Core.Compiler.CallMeta(Nothing, nothing)

    # RoutineSpec
    ir = YaoIR(gt)
    edges = Any[]
    # TODO: use cached result
    # code = get(code_cache(interp), mi, nothing)

    # NOTE: this is copied from typeinf_edge
    edge = nothing
    rt = Any
    if !sv.cached && sv.parent === nothing
        # this caller exists to return to the user
        # (if we asked resolve_call_cyle, it might instead detect that there is a cycle that it can't merge)
        frame = false
    else
        frame = Core.Compiler.resolve_call_cycle!(interp, mi, sv)
    end

    if frame === false
        # completely new
        Core.Compiler.lock_mi_inference(interp, mi)
        result = Core.Compiler.InferenceResult(mi)
        
        if type === :gate
            ci = codeinfo_gate(ir)
        elseif type === :ctrl
            ci = codeinfo_ctrl(ir)
        end

        frame = Core.Compiler.InferenceState(result, ci, #=cached=#true, interp) # always use the cache for edge targets
        if frame === nothing
            # can't get the source for this, so we know nothing
            Core.Compiler.unlock_mi_inference(interp, mi)
        end
        if sv.cached || sv.limited # don't involve uncached functions in cycle resolution
            frame.parent = sv
        end
        Core.Compiler.typeinf(interp, frame)
        Core.Compiler.update_valid_age!(frame, sv)
        rt = Core.Compiler.widenconst_bestguess(frame.bestguess)
        edge = frame.inferred ? mi : nothing
    elseif frame === true
        # unresolvable cycle
    else
        frame = frame::InferenceState
        Core.Compiler.update_valid_age!(frame, sv)
        rt = Core.Compiler.widenconst_bestguess(frame.bestguess)
    end

    edgecycle = edge === nothing
    
    if !isnothing(edge)
        push!(edges, edge)
    end

    if !(rt === Any) # adding a new method couldn't refine (widen) this type
        for edge in edges
            Core.Compiler.add_backedge!(edge::Core.MethodInstance, sv)
        end
    end
    return Core.Compiler.CallMeta(rt, nothing)
end

function is_semantic_fn_call(e)
    return e isa Expr && e.head === :call &&
        e.args[1] isa GlobalRef &&
            e.args[1].mod === YaoLang.Compiler.Semantic
end

function convert_to_quantum_head!(ci::CodeInfo)
    for (v, e) in enumerate(ci.code)
        ci.code[v] = convert_to_quantum_head(e)
    end
    return ci
end
