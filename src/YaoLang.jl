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
include("compiler/compiler.jl")
include("compiler/reflection.jl")
include("compiler/primitive.jl")
include("compiler/utils.jl")
include("compiler/kwdefs.jl")
include("compiler/validation.jl")

function __init__()
    TimerOutputs.reset_timer!(to)
    # not sure why this doesn't work inside the module
    IRTools.Inner.printers[:quantum] = function (io, ex)
        get(printers, ex.args[1], print)(io, ex)
    end
end

end

using .Compiler
export @device, @primitive, @code_yao
include("runtime/primitives.jl")

end # module
