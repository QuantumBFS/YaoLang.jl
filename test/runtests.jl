using YaoIR
using Test

@testset "test locations" begin
    include("locations.jl")
end

@testset "test compiler" begin
    include("compile.jl")
    include("runtime.jl")
end