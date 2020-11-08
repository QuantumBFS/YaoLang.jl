struct YaoInterpreter <: AbstractInterpreter
    native_interpreter::Core.Compiler.NativeInterpreter
    passes::Vector{Symbol}
end

struct YaoOptimizationParams
    native::OptimizationParams
    passes::Vector{Symbol}
end

default_passes() = [:zx]

YaoInterpreter(;passes::Vector{Symbol}=default_passes()) = YaoInterpreter(Core.Compiler.NativeInterpreter(), passes)

InferenceParams(interp::YaoInterpreter) = InferenceParams(interp.native_interpreter)
OptimizationParams(interp::YaoInterpreter) = OptimizationParams(interp.native_interpreter)
YaoOptimizationParams(interp::YaoInterpreter) = YaoOptimizationParams(OptimizationParams(interp), interp.passes)
Core.Compiler.get_world_counter(interp::YaoInterpreter) = get_world_counter(interp.native_interpreter)
Core.Compiler.get_inference_cache(interp::YaoInterpreter) = get_inference_cache(interp.native_interpreter)
Core.Compiler.code_cache(interp::YaoInterpreter) = Core.Compiler.code_cache(interp.native_interpreter)
Core.Compiler.may_optimize(interp::YaoInterpreter) = Core.Compiler.may_optimize(interp.native_interpreter)
Core.Compiler.may_discard_trees(interp::YaoInterpreter) = Core.Compiler.may_discard_trees(interp.native_interpreter)
Core.Compiler.may_compress(interp::YaoInterpreter) = Core.Compiler.may_compress(interp.native_interpreter)
Core.Compiler.unlock_mi_inference(interp::YaoInterpreter, mi::Core.MethodInstance) = Core.Compiler.unlock_mi_inference(interp.native_interpreter, mi)
Core.Compiler.lock_mi_inference(interp::YaoInterpreter, mi::Core.MethodInstance) = Core.Compiler.lock_mi_inference(interp.native_interpreter, mi)
Core.Compiler.add_remark!(interp::YaoInterpreter, st::Core.Compiler.InferenceState, msg::String) = nothing # println(msg)

function Core.Compiler.abstract_eval_statement(interp::YaoInterpreter, @nospecialize(e), vtypes::VarTable, sv::InferenceState)    
    is_quantum_statement(e) || return Core.Compiler.abstract_eval_statement(interp.native_interpreter, e, vtypes, sv)
    qt = quantum_stmt_type(e)

    if qt === :measure
        return Int
    elseif qt === :gate || qt === :ctrl
        ea = e.args
        n = length(ea)
        argtypes = Vector{Any}(undef, n)
        @inbounds for i = 1:n
            ai = Core.Compiler.abstract_eval_value(interp, ea[i], vtypes, sv)
            if ai === Core.Compiler.Bottom
                return Core.Compiler.Bottom
            end
            argtypes[i] = ai
        end
        gt = Core.Compiler.widenconst(argtypes[2])

        gt <: IntrinsicRoutine && return Core.Const(nothing)
        atypes = Core.Compiler.argtypes_to_type(argtypes)

        if qt === :gate
            sf = Compiler.Semantic.gate
        else
            sf = Compiler.Semantic.ctrl
        end

        callinfo = Core.Compiler.abstract_call_gf_by_type(interp, sf, argtypes, atypes, sv)
        sv.stmt_info[sv.currpc] = callinfo.info
        t = callinfo.rt
    else
        return Core.Const(nothing)
    end

    # copied from abstract_eval_statement
    @assert !isa(t, TypeVar)
    if isa(t, DataType) && isdefined(t, :instance)
        # replace singleton types with their equivalent Const object
        t = Core.Const(t.instance)
    end
    return t
end

# NOTE: this is copied from Core.Compiler._typeinf
# to insert our own passes
# Keno says we might not need to do this after 1.7+
# NOTE: most functions are different from Base due to bootstrap
# TODO: only run our passes on quantum routines
function Core.Compiler.typeinf(interp::YaoInterpreter, frame::InferenceState)
    Core.Compiler.typeinf_nocycle(interp, frame) || return false
    # with no active ip's, frame is done
    frames = frame.callers_in_cycle
    isempty(frames) && push!(frames, frame)
    for caller in frames
        @assert !(caller.dont_work_on_me)
        caller.dont_work_on_me = true
    end
    
    for caller in frames
        Core.Compiler.finish(caller, interp)
    end
    # collect results for the new expanded frame
    results = Tuple{InferenceResult, Bool}[ ( frames[i].result,
        frames[i].cached || frames[i].parent !== nothing ) for i in 1:length(frames) ]

    valid_worlds = frame.valid_worlds
    cached = frame.cached
    if cached || frame.parent !== nothing
        for (caller, doopt) in results
            opt = caller.src
            if opt isa OptimizationState
                run_optimizer = doopt && Core.Compiler.may_optimize(interp)
                if run_optimizer
                    if parentmodule(frame.result.linfo.def.sig.parameters[1]) === Semantic
                        optimize(opt, YaoOptimizationParams(interp), caller.result)
                    else
                        Core.Compiler.optimize(opt, OptimizationParams(interp), caller.result)
                    end
                    Core.Compiler.finish(opt.src, interp)
                    # finish updating the result struct
                    Core.Compiler.validate_code_in_debug_mode(opt.linfo, opt.src, "optimized")
                    if opt.const_api
                        if caller.result isa Const
                            caller.src = caller.result
                        else
                            @assert isconstType(caller.result)
                            caller.src = Const(caller.result.parameters[1])
                        end
                    elseif opt.src.inferred
                        caller.src = opt.src::CodeInfo # stash a copy of the code (for inlining)
                    else
                        caller.src = nothing
                    end
                end
                # As a hack the et reuses frame_edges[1] to push any optimization
                # edges into, so we don't need to handle them specially here
                valid_worlds = Core.Compiler.intersect(valid_worlds, opt.inlining.et.valid_worlds.x)
            end
        end
    end
    if Core.Compiler.last(valid_worlds) == Core.Compiler.get_world_counter()
        valid_worlds = Core.Compiler.WorldRange(Core.Compiler.first(valid_worlds), Core.Compiler.typemax(UInt))
    end
    for caller in frames
        caller.valid_worlds = valid_worlds
        caller.src.min_world = Core.Compiler.first(valid_worlds)
        caller.src.max_world = Core.Compiler.last(valid_worlds)
        if cached
            Core.Compiler.cache_result!(interp, caller.result, valid_worlds)
        end
        if Core.Compiler.last(valid_worlds) == Core.Compiler.typemax(UInt)
            # if we aren't cached, we don't need this edge
            # but our caller might, so let's just make it anyways
            for caller in frames
                Core.Compiler.store_backedges(caller)
            end
        end
        # finalize and record the linfo result
        caller.inferred = true
    end
    return true
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
