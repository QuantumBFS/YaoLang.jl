using YaoArrayRegister, LinearAlgebra

export exec!

"""
    decode_sign(ctrls...)
Decode signs into control sequence on control or inversed control.
"""
decode_sign(ctrls::Int...,) = decode_sign(ctrls)
decode_sign(ctrls::NTuple{N, Int}) where N = tuple(ctrls .|> abs, ctrls .|> sign .|> (x->(1+x)÷2))

function decode_sign(ctrls::Locations)
    locations, config = decode_sign(ctrls.locations)
    Locations(locations), config
end

"""
    exec!(register, gate[, locs, ctrl_locs])
"""
function exec! end

function exec!(register, gate)
    exec!(register, gate, Locations(Base.OneTo(nqubits(register))))
end

function exec!(register, gate, locs::Locations, ctrl_locs::Locations)
    exec!(register, gate, locs, ctrl_locs)
end

# TODO: rewrite instructs

for G in [:X, :Y, :Z, :T]
    typename = Symbol(G, :Gate)
    @eval function exec!(register, ::$typename, locs::Locations)
        instruct!(register, Val($(QuoteNode(G))), to_tuple(locs))
    end

    @eval function exec!(register, ::$typename, locs::Locations, ctrl_locs::Locations)
        ctrl_locs, ctrl_configs = decode_sign(to_tuple(ctrl_locs))
        locs = to_tuple(locs)
        instruct!(register, Val($(QuoteNode(G))), locs, ctrl_locs, ctrl_configs)
    end
end

function exec!(register, gate::Shift{T}, locs::Locations, ctrl_locs::Locations) where T
    M = Diagonal(Complex{T}[1.0, exp(im * gate.theta)])
    ctrl_locs, ctrl_config = decode_sign(to_tuple(ctrl_locs))
    instruct!(register, M, to_tuple(locs), ctrl_locs, ctrl_config)
end

function exec!(register, gate::HGate, locs::Locations)
    M = ComplexF64[1 1;1 -1] / sqrt(2)
    instruct!(register, M, to_tuple(locs))
end
