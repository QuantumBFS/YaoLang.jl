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
using MLStyle
using YaoAPI
using BitBasis
using ZXCalculus

using Core: CodeInfo, SSAValue, Const, Slot, GotoIfNot, GotoNode, SlotNumber, Argument, ReturnNode
using Core.Compiler: InferenceParams, InferenceResult, OptimizationParams, OptimizationState,
    AbstractInterpreter, VarTable, InferenceState, CFG, NewSSAValue, IRCode,
    InstructionStream
using Core.Compiler: get_world_counter, get_inference_cache, may_optimize,
    isconstType, isconcretetype, widenconst, isdispatchtuple, isinlineable,
    is_inlineable_constant, copy_exprargs, convert_to_ircode, coverage_enabled,
    # Julia passes
    compact!, ssa_inlining_pass!, getfield_elim_pass!, adce_pass!, type_lift_pass!,
    verify_linetable, verify_ir, slot2reg

using Base.Meta: ParseError

import ..YaoLang
using YaoLang: AbstractLocations, merge_locations, Locations, CtrlLocations

export Routine, GenericRoutine, IntrinsicRoutine, RoutineSpec, IntrinsicSpec, @ctrl, @measure, @gate, @barrier, @device
export routine_name

include("compiler/utils.jl")
include("compiler/routine.jl")
include("compiler/intrinsics.jl")
include("compiler/qasm.jl")

# compiler internal extensions
include("compiler/interpreter.jl")
include("compiler/ir.jl")
include("compiler/optimize.jl")

# code generators
include("compiler/codegen/emulation.jl")
include("compiler/codegen/qasm.jl")

include("compiler/reflection.jl")
include("compiler/tools.jl")
# include("compiler/validation.jl")
# include("compiler/trace.jl")

# function __init__()
#     TimerOutputs.reset_timer!(to)
# end

end

using .Compiler
export @device, @gate, @ctrl, @measure, @barrier

# reflections
export @code_yao, @code_qasm

export gate_count

using .Compiler.QASM: @qasm_str
export @qasm_str

using .Compiler: Gate
export Gate

end # module
