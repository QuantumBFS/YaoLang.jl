module YaoIR

using ExprTools
using LinearAlgebra
using YaoBase

include("runtime/locations.jl")
include("runtime/generic_circuit.jl")
include("runtime/primitives.jl")

@nospecialize
include("compiler/ir.jl")
include("compiler/compiler.jl")
@specialize

end # module
