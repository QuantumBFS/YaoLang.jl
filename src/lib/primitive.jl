using YaoArrayRegister, LinearAlgebra

export exec!

"""
    decode_sign(ctrls...)
Decode signs into control sequence on control or inversed control.
"""
decode_sign(ctrls::Int...,) = decode_sign(ctrls)
decode_sign(ctrls::NTuple{N, Int}) where N = tuple(ctrls .|> abs, ctrls .|> sign .|> (x->(1+x)÷2))

"""
    exec!(register, gate[, locs, ctrl_locs])
"""
function exec! end

function exec!(register, gate)
    exec!(register, gate, Base.OneTo(nqubits(register)))
end

function exec!(register, gate, locs, ctrl_locs)
    exec!(register, gate, locs, decode_sign(ctrl_locs)...)
end

for G in [:X, :Y, :Z, :T]
    typename = Symbol(G, :Gate)
    @eval function exec!(register, ::$typename, locs)
        instruct!(register, Val($(QuoteNode(G))), locs) 
    end
    @eval function exec!(register, ::$typename, locs, ctrl_locs, ctrl_configs)
        instruct!(register, Val($(QuoteNode(G))), locs, ctrl_locs, ctrl_configs)
    end
end

function exec!(register, gate::Shift{T}, locs, ctrl_locs, ctrl_config) where T
    M = Diagonal(Complex{T}[1.0, exp(im * gate.theta)])
    instruct!(register, M, locs, ctrl_locs, ctrl_config)
end

function exec!(register, gate::HGate, locs)
    M = ComplexF64[1 1;1 -1] / sqrt(2)
    instruct!(register, M, locs)
end
