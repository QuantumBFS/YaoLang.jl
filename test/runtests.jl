using YaoLang
using Test

@testset "runtime" begin
    include("runtime/locations.jl")
end

@testset "compiler" begin
    include("compiler/parse.jl")
    include("compiler/utils.jl")
end
