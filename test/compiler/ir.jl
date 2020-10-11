using Core.Compiler
import Core.Compiler: InferenceParams, OptimizationParams, get_world_counter, get_inference_cache

"""
    @infer_function interp foo(1, 2) [show_steps=true] [show_ir=false]

Infer a function call using the given interpreter object, return
the inference object.  Set keyword arguments to modify verbosity:

* Set `show_steps` to `true` to see the `InferenceResult` step by step.
* Set `show_ir` to `true` to see the final type-inferred Julia IR.
"""
macro infer_function(interp, func_call, kwarg_exs...)
    if !isa(func_call, Expr) || func_call.head != :call
        error("@infer_function requires a function call")
    end

    local func = func_call.args[1]
    local args = func_call.args[2:end]
    kwargs = []
    for ex in kwarg_exs
        if ex isa Expr && ex.head === :(=) && ex.args[1] isa Symbol
            push!(kwargs, first(ex.args) => last(ex.args))
        else
            error("Invalid @infer_function kwarg $(ex)")
        end
    end
    return quote
        infer_function($(esc(interp)), $(esc(func)), typeof.(($(args)...,)); $(esc(kwargs))...)
    end
end

function infer_function(interp, f, tt; show_steps::Bool=false, show_ir::Bool=false)
    # Find all methods that are applicable to these types
    fms = methods(f, tt)
    if length(fms) != 1
        error("Unable to find single applicable method for $f with types $tt")
    end

    # Take the first applicable method
    method = first(fms)

    # Build argument tuple
    method_args = Tuple{typeof(f), tt...}

    # Grab the appropriate method instance for these types
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())

    # Construct InferenceResult to hold the result,
    result = Core.Compiler.InferenceResult(mi)
    if show_steps
        @info("Initial result, before inference: ", result)
    end

    # Create an InferenceState to begin inference, give it a world that is always newest
    world = Core.Compiler.get_world_counter()
    frame = Core.Compiler.InferenceState(result, #=cached=# true, interp)

    # Run type inference on this frame.  Because the interpreter is embedded
    # within this InferenceResult, we don't need to pass the interpreter in.
    Core.Compiler.typeinf_local(interp, frame)
    # if show_steps
    #     @info("Ending result, post-inference: ", result)
    # end
    # if show_ir
    #     @info("Inferred source: ", result.result.src)
    # end

    # # Give the result back
    # return result
end

function foo(x, y)
    return x + y * x
end

native_interpreter = Core.Compiler.NativeInterpreter()
inferred = @infer_function native_interpreter foo(1.0, 2.0) show_steps=true show_ir=true

infer_function(native_interpreter, foo, (Float64, Float64))

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
end

c = qft(3)

method = first(methods(c.stub, (Int, )))
method_args = Tuple{typeof(c.stub), Int}
mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
result = Core.Compiler.InferenceResult(mi)
world = Core.Compiler.get_world_counter()
frame = Core.Compiler.InferenceState(result, #=cached=# true, native_interpreter)

Core.MethodInstance

@generated function foo(x)
    # fake sin ci
    method = first(methods(sin, (x, )))
    method_args = Tuple{typeof(sin), x}
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
    ci = Core.Compiler.retrieve_code_info(mi)
    result = Core.Compiler.InferenceResult(mi)
    world = Core.Compiler.get_world_counter()
    interp = Core.Compiler.NativeInterpreter()
    frame = Core.Compiler.InferenceState(result, ci, #=cached=# true, interp)
    Core.Compiler.typeinf_local(interp, frame)
    ci = result.result.src
    ci.inferred = true
    return ci
end

@code_typed foo(2)

x = Int
method = first(methods(sin, (x, )))
method_args = Tuple{typeof(sin), x}
mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
ci = Core.Compiler.retrieve_code_info(mi)
result = Core.Compiler.InferenceResult(mi)
world = Core.Compiler.get_world_counter()
interp = Core.Compiler.NativeInterpreter()
frame = Core.Compiler.InferenceState(result, ci, #=cached=# true, interp)
Core.Compiler.typeinf_local(interp, frame)
ci = result.result.src

f_method = first(methods(foo, (x, )))
mi = Core.Compiler.specialize_method(f_method, method_args, Core.svec())

ci.inferred = true
