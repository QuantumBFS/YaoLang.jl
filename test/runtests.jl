using YaoLang
using Test
using FFTW
using YaoArrayRegister

@testset "runtime" begin
    include("runtime/locations.jl")
end

@testset "compiler" begin
    include("compiler/circuit.jl")
end
