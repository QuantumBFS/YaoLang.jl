export H, shift

const X = IntrinsicSpec{:X}()
const Y = IntrinsicSpec{:Y}()
const Z = IntrinsicSpec{:Z}()
const H = IntrinsicSpec{:H}()
const S = IntrinsicSpec{:S}()
const shift = IntrinsicRoutine{:shift}()
const Rx = IntrinsicRoutine{:Rx}()
const Ry = IntrinsicRoutine{:Ry}()
const Rz = IntrinsicRoutine{:Rz}()

Base.adjoint(::IntrinsicSpec{:H}) = H
Base.adjoint(s::IntrinsicSpec{:shift}) = IntrinsicSpec{:shift}(adjoint(s.variables[1]))

function (p::IntrinsicRoutine{:shift})(theta::Real)
    return IntrinsicSpec(p, theta)
end
