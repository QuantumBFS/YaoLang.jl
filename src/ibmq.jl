module IBMQ

using YaoCompiler
using IBMQClient
using YaoAPI
using REPL.TerminalMenus

mutable struct AccountInfo
    access_token::String
    auth::IBMQClient.AuthAPI
    service::IBMQClient.ServiceAPI
    project::IBMQClient.ProjectAPI
end

const account_cache = Dict{String, AccountInfo}()

struct IBMQReg <: AbstractRegister{1}
    device::IBMQClient.IBMQDevice    
end

function IBMQReg(;token::Union{Nothing, String}=nothing)
    if token === nothing
        if haskey(ENV, "IBMQ_TOKEN")
            token = ENV["IBMQ_TOKEN"]
        else
            buf = Base.getpass("IBM API token (https://quantum-computing.ibm.com/account)")
            token = read(buf, String)
            Base.shred!(buf)
        end
    end

    auth = IBMQClient.AuthAPI()
    response = IBMQClient.login(auth, token)
    access_token = response["id"]
    user_info = IBMQClient.user_info(auth, access_token)
    service = IBMQClient.ServiceAPI(user_info["urls"]["http"])
    user_hub = first(IBMQClient.user_hubs(service, access_token))
    project = IBMQClient.ProjectAPI(service.endpoint, user_hub.hub, user_hub.group, user_hub.project)

    global  account_cache
    account_cache[access_token] = AccountInfo(access_token, auth, service, project)

    devices = IBMQClient.devices(project, access_token)
    menu = RadioMenu(map(x->x.name, devices), pagesize=4)
    choice = request("choose a device:", menu)
    return IBMQReg(devices[choice])
end

# macro ibmq(ex...)
# end

# function ibmq_m(ex)
#     quote
#         spec = $ex
#         ci, = @code_yao optimize=true spec
#         target = YaoCompiler.TargetQobjQASM()
#         qobj = YaoCompiler.codegen(target, ci)

#         response = IBMQClient.create_remote_job(project, devices[3], access_token)
#     end
# end


# params = rand(10)
# @ibmq nshots=1024 begin
#     for (α,β,γ) in params
#         circuit(α, β, γ)
#     end
# end

end
