module YaoLang

using MLStyle
using LinearAlgebra
using YaoAPI

include("runtime/locations.jl")
include("runtime/generic_circuit.jl")

module Compiler

    using ExprTools
    using IRTools
    using IRTools.Inner
    using YaoAPI

    using IRTools.Inner: IR, Block, BasicBlock, Statement, Variable,
        block, blocks, tab, print_stmt, printargs
    using Base.Meta: ParseError

    import ..YaoLang
    using YaoLang: AbstractLocations, merge_locations,
        Locations, CtrlLocations, Circuit, PrimitiveCircuit

    include("compiler/parse.jl")
    include("compiler/ir.jl")
    include("compiler/print.jl")
    include("compiler/codegen.jl")
    include("compiler/compiler.jl")
    include("compiler/reflection.jl")
    include("compiler/primitive.jl")
    # include("compiler/verify.jl")
    include("compiler/utils.jl")
    include("compiler/kwdefs.jl")

    function __init__()
        # not sure why this doesn't work inside the module
        IRTools.Inner.printers[:quantum] = function (io, ex)
            get(printers, ex.args[1], print)(io, ex)
        end    
    end

end

using .Compiler
export @device, @primitive

include("runtime/primitives.jl")

end # module
