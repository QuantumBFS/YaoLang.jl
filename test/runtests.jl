using YaoIR
using Test

@testset "runtime" begin
    include("runtime/locations.jl")
end

@testset "compiler" begin
    include("compiler/ir.jl")
end
