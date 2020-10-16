module YaoLang

using LinearAlgebra
using YaoAPI

include("runtime/locations.jl")

module Compiler

using TimerOutputs
const to = TimerOutput()
timings() = (TimerOutputs.print_timer(to); println())
enable_timings() = (TimerOutputs.enable_debug_timings(Compiler); return)

using ExprTools
using YaoAPI
using YaoArrayRegister

using Core: CodeInfo, SSAValue
using Core.Compiler: InferenceParams, OptimizationParams, AbstractInterpreter, VarTable, InferenceState, CFG, NewSSAValue
using Core.Compiler: get_world_counter, get_inference_cache

using Base.Meta: ParseError

import ..YaoLang
using YaoLang: AbstractLocations, merge_locations, Locations, CtrlLocations

export Routine, GenericRoutine, IntrinsicRoutine, RoutineSpec, IntrinsicSpec, @ctrl, @measure, @gate, @barrier, @device

include("compiler/utils.jl")
include("compiler/routine.jl")
include("compiler/interpreter.jl")
include("compiler/ir.jl")
include("compiler/codegen/emulation.jl")
include("compiler/intrinsics.jl")
include("compiler/qasm.jl")
# include("compiler/optimize.jl")
# include("compiler/reflection.jl")
# include("compiler/validation.jl")
# include("compiler/trace.jl")
# include("compiler/zx_calculus.jl")

# function __init__()
#     TimerOutputs.reset_timer!(to)
# end

end

using .Compiler
export @device, @gate, @ctrl, @measure, @barrier

include("runtime/intrinsics.jl")

end # module
