using YaoLang
using Test

@testset "runtime" begin
    include("runtime/locations.jl")
end

# @testset "compiler" begin
#     include("compiler/circuit.jl")
#     include("compiler/validation.jl")
#     include("compiler/zx_calculus.jl")
#     include("compiler/qasm.jl")
#     include("compiler/utils.jl")
# end
