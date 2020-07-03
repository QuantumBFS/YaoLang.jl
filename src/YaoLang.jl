module YaoLang

using LinearAlgebra
using YaoAPI

include("runtime/locations.jl")
include("runtime/generic_circuit.jl")

module Compiler

using TimerOutputs
const to = TimerOutput()
timings() = (TimerOutputs.print_timer(to); println())
enable_timings() = (TimerOutputs.enable_debug_timings(Compiler); return)

using ExprTools
using IRTools
using IRTools.Inner
using YaoAPI

using IRTools.Inner:
    IR, Block, BasicBlock, Statement, Variable, block, blocks, tab, print_stmt, printargs
using Base.Meta: ParseError

import ..YaoLang
using YaoLang: AbstractLocations, merge_locations, Locations, CtrlLocations, Circuit, PrimitiveCircuit

include("compiler/parse.jl")
include("compiler/ir.jl")
include("compiler/print.jl")
include("compiler/codegen.jl")
include("compiler/optimize.jl")
include("compiler/compiler.jl")
include("compiler/reflection.jl")
include("compiler/primitive.jl")
include("compiler/utils.jl")
include("compiler/kwdefs.jl")
include("compiler/validation.jl")
include("compiler/trace.jl")

include("compiler/zx_calculus.jl")

function __init__()
    TimerOutputs.reset_timer!(to)
end

end

using .Compiler
export @device, @primitive, @code_yao, @quantum
include("runtime/primitives.jl")

end # module
