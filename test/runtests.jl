using YaoLang
using Test

using YaoLang.IBMQ

token = "d7339130578f8cc442dfcf260bee4049dfa25c6aabfd5ab771a693ec5cad1895f61f74f8aab7035c8ffddb83948ca17acef123c9955d9a554e02592eea5f6238"
reg = IBMQ.IBMQReg(;token)

@testset "runtime" begin
    include("runtime/locations.jl")
end

@testset "compiler" begin
    include("compiler/parse.jl")
    include("compiler/utils.jl")
    include("compiler/circuit.jl")
end
