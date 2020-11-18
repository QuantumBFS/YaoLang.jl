using YaoLang
using Test

using YaoLang.IBMQ

@macroexpand IBMQ.@ibmq circuit()

@macroexpand IBMQ.@ibmq begin
    circuit1()
    circuit2()
end

@macroexpand IBMQ.@ibmq begin
    for (a, b) in zip(A, B)
        circuit(a, b)
    end
end

token = "d7339130578f8cc442dfcf260bee4049dfa25c6aabfd5ab771a693ec5cad1895f61f74f8aab7035c8ffddb83948ca17acef123c9955d9a554e02592eea5f6238"
reg = IBMQ.IBMQReg(;token)
using IBMQClient

account = first(values(IBMQ.account_cache))
access_token = first(values(IBMQ.account_cache)).access_token
user_info = IBMQClient.user_info(auth, access_token)

using REPL.TerminalMenus

devices = IBMQClient.devices(account.project, account.access_token)
m = IBMQ.DeviceMenu(devices, pagesize=4)
devices[1]|>dump
request(m)


@testset "runtime" begin
    include("runtime/locations.jl")
end

@testset "compiler" begin
    include("compiler/parse.jl")
    include("compiler/utils.jl")
    include("compiler/circuit.jl")
end
