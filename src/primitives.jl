export PrimitiveGate
export X, Y, Z, H, T, S, Rx, Ry, Rz, Shift
abstract type PrimitiveGate end
abstract type ConstantGate <: PrimitiveGate end

struct XGate <: ConstantGate end
struct YGate <: ConstantGate end
struct ZGate <: ConstantGate end
struct HGate <: ConstantGate end
struct TGate <: ConstantGate end
struct SGate <: ConstantGate end

const X = XGate()
const Y = YGate()
const Z = ZGate()
const H = HGate()
const T = TGate()
const S = SGate()

Base.show(io::IO, x::ConstantGate) = print(io, nameof(x)[1:end-4])

struct Rx{T} <: PrimitiveGate
    theta::T
end

struct Ry{T} <: PrimitiveGate
    theta::T
end

struct Rz{T} <: PrimitiveGate
    theta::T
end

export Shift
struct Shift{T} <: PrimitiveGate
    theta::T
end
