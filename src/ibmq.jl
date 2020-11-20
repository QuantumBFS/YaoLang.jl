module IBMQ

using YaoCompiler
using IBMQClient
using YaoAPI
using REPL.TerminalMenus
using Crayons.Box
using IBMQClient: AccountInfo, IBMQDevice, DeviceMenu

# RL: qiskit stores it on disk anyway, so I think it's fine for us to
# store it temporarily in a Julia instance just for convenience

"account cache to speed up register creation and queries"
const account_cache = Dict{String, AccountInfo}()

"""
    IBMQReg <: AbstractRegister{1}

A virtual IBM Q register for uploading jobs to IBM Q REST API.
"""
struct IBMQReg <: AbstractRegister{1}
    account::AccountInfo
    device::IBMQDevice

    nshots::Int
    memory_slots::Int
    nqubits::Int

    options::NamedTuple
    # max_credits::Int
    # seed::Int 
    # schema_version::String
    # type::String
    # memory::Bool
    # init_qubits::Bool
    # parameter_binds::Vector
    # parametric_pulses
end

function Base.show(io::IO, m::MIME"text/plain", r::IBMQReg)
    println(io, "IBM Q (virtual) register:")
    show(IOContext(io, :indent=>2), m, r.account)
    println(io)
    println(io)
    show(IOContext(io, :indent=>2), m, r.device)
end

function IBMQReg(;
        token::Union{Nothing, String}=nothing,
        device::Union{Nothing, String}=nothing,
        nshots::Int = 1024,
        memory_slots::Int=-1,
        nqubits::Int=-1, # NOTE: we use nqubits here for consistency
        kw...
        # max_credits::Int = 3,
        # seed::Int = 1,
        # schema_version::String="1.3.0",
        # type::String="QASM",
        # memory::Bool=false,
        # init_qubits::Bool=true,
        # parameter_binds::Vector=[],
        # parametric_pulses=[],
    )

    if token === nothing
        if haskey(ENV, "IBMQ_TOKEN")
            token = ENV["IBMQ_TOKEN"]
        else
            buf = Base.getpass("IBM API token (https://quantum-computing.ibm.com/account)")
            token = read(buf, String)
            Base.shred!(buf)
        end
    end

    global account_cache
    if haskey(account_cache, token)
        account = account_cache[token]
    else
        account = AccountInfo(token)
        account_cache[token] = account
    end

    devices = IBMQClient.devices(account)

    if device === nothing
        menu = DeviceMenu(devices, pagesize=6)
        choice = request("choose a device:", menu)
        if choice < 0
            return
        end
    else
        dev = findfirst(x->x.name == device, devices)
        dev === nothing || error("device \"$device\" is not available.")
    end

    return IBMQReg(
        account, devices[choice], nshots,
        memory_slots, nqubits, NamedTuple(kw),
    )
end

function create_main_qobj(r::IBMQReg, specs::RoutineSpec...)
    target = YaoCompiler.TargetQobjQASM(;
        nshots=r.nshots, max_credits = get(r.options, :max_credits, 3),
        seed=get(r.options, :seed, 1)
    )

    experiments = map(specs) do spec
        # TODO: support parametric routine spec, mark parameters as Const in typeinf
        ci, _ = YaoCompiler.code_yao(YaoCompiler.Semantic.main, spec; optimize=true, passes=[:julia])
        return YaoCompiler.codegen(target, ci)
    end

    qobj = IBMQClient.create_qobj(r.device, experiments...;
        memory_slots=r.memory_slots, shots=r.nshots,
            n_qubits=r.nqubits, r.options...)

    return qobj
end

function submit(r::IBMQReg, specs::RoutineSpec...)
    qobj = create_main_qobj(r, specs...)
    IBMQClient.submit(r.account, r.device, qobj)
end

function YaoCompiler.execute(::typeof(YaoCompiler.Semantic.main), ::IBMQReg, ::RoutineSpec)
    error("IBM Q devices is not fully compatible with YaoLang, please use @ibmq to define and submit jobs with a subset of YaoLang")
end

macro ibmq(ex...)
    return ibmq_m(ex...)
end

function ibmq_m(ex...)
    options = ex[1:end-1]
    kwargs = []
    for opt in options
        opt isa Expr && opt.head === :(=) || error("invalid syntax $opt")
        opt.args[1] in [:nshots, :max_credits, :seed, :schema_version] || error("invalid option: $opt")
        push!(kwargs, Expr(:kw, opt.args[1], opt.args[2]))
    end

    experiment = last(ex)
    experiment isa Expr || error("invalid syntax: $experiment")

    seq = gensym(:seq)
    return quote
        $seq = Any[]
        $(esc(collect_experiments(seq, experiment)))
        r = $IBMQReg(;$(kwargs...))
        $submit(r, $seq...)
        r
    end
end

function collect_experiments(seq::Symbol, @nospecialize(ex))
    ex isa Expr || return ex # skip other things
    ex.head == :call && return :(push!($seq, $ex))

    if ex.head === :block
        return Expr(:block, map(x->collect_experiments(seq, x), ex.args)...)
    elseif ex.head === :for
        return Expr(:for, ex.args[1], collect_experiments(seq, ex.args[2]))
    else
        error("invalid syntax: $ex")
    end
end

end
