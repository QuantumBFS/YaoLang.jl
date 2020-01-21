using YaoBase
using YaoArrayRegister, LinearAlgebra

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

function evaluate!(register::AbstractRegister, gate)
    return evaluate!(register, gate, Locations(Base.OneTo(nqubits(register))))
end

# do runtime evaluatation if G as a symbol that is not specialized
@generated function evaluate!(register::AbstractRegister, gate::Val{G}, locs::Locations, ctrl_locs::Locations) where G
    :(evaluate!(register, $G, locs, ctrl_locs))
end

@generated function evaluate!(register::AbstractRegister, gate::Val{G}, locs::Locations) where G
    :(evaluate!(register, $G, locs))
end

# general matrix method
function evaluate!(register::AbstractRegister, gate::AbstractMatrix, locs::Locations)
    instruct!(register, gate, to_tuple(locs))
    return register
end

function evaluate!(register::AbstractRegister, gate::AbstractMatrix, locs::Locations, ctrl_locs::Locations)
    ctrl_locs, ctrl_configs = decode_sign(to_tuple(ctrl_locs))
    locs = to_tuple(locs)
    instruct!(register, gate, locs, ctrl_locs, ctrl_configs)
    return register
end

function evaluate!(register::AbstractRegister, gate::HGate, locs::Locations)
    instruct!(register, YaoBase.Const.H, to_tuple(locs))
end

# primitive instructions
# TODO: rewrite instructs
for G in [:X, :Y, :Z, :T]

    @eval function evaluate!(register::AbstractRegister, gate::Val{$G}, locs::Locations)
        instruct!(register, gate, to_tuple(locs))
        return register
    end

    @eval function evaluate!(register::AbstractRegister, gate::Val{$G}, locs::Locations, ctrl_locs::Locations)
        ctrl_locs, ctrl_configs = decode_sign(to_tuple(ctrl_locs))
        locs = to_tuple(locs)
        instruct!(register, gate, locs, ctrl_locs, ctrl_configs)
        return register
    end

end
