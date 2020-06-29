for gate in [:H, :X, :Y, :Z, :T, :S]
    @eval begin
        export $gate
        @primitive $gate
    end
end

"""
    H

The Hadamard gate.

# Definition

```math
\\frac{1}{\\sqrt{2}} \\begin{pmatrix}
1 & 1\\
1 & -1
\\end{pmatrix}
```
"""
H

for gate in [:X, :Y, :Z]
    str = """
    $gate

The Pauli $gate gate.
"""
    @eval @doc $str $gate
end

"""
    T

The T gate.
"""
T

export shift, phase, Rx, Ry, Rz, rot

"""
    shift(θ::Real)

Phase shift gate.

# Definition

```math
\\begin{pmatrix}
1 & 0\\
0 & e^(im θ)
\\end{pmatrix}
```
"""
@primitive shift(θ::Real) = Diagonal([1.0, exp(im * θ)])

"""
    phase(theta)

Global phase gate.

# Definition
```math
exp(iθ) \\mathbf{I}
```
"""
@primitive phase(θ::T) where {T<:Real} = Diagonal(Complex{T}[exp(im * θ), exp(im * θ)])
@primitive Rx(θ::Real) = [cos(θ / 2) -im * sin(θ / 2); -im * sin(θ / 2) cos(θ / 2)]
@primitive Ry(θ::Real) = [cos(θ / 2) -sin(θ / 2); sin(θ / 2) cos(θ / 2)]
@primitive Rz(θ::Real) = Diagonal([-im * sin(θ / 2) + cos(θ / 2), im * sin(θ / 2) + cos(θ / 2)])

for axis in [:X, :Y, :Z]
    gate = Symbol(:R, lowercase(string(axis)))
    str = """
        $gate(theta::Real)

    Return a rotation gate on $axis axis.
    """

    @eval @doc $str $gate
end

# TODO: specialize this on simulators
"""
    rot(axis, θ::T, m::Int=size(axis, 1)) where {T <: Real}

General rotation gate, `axis` is the rotation axis, `θ` is the rotation angle. `m` is the size of rotation space, default
is the size of rotation axis.
"""
@primitive function rot(axis, θ::T, m::Int = size(axis, 1)) where {T<:Real}
    return Diagonal(fill(cos(θ / 2), m)) - im * sin(θ / 2) * axis
end


const expect = PrimitiveCircuit{:expect}()

function (::PrimitiveCircuit{:expect})(op, locations)
    
end

# # TODO: this should be an instruction
# function time_evolution_stub(circ::Circuit{:time_evolution}, register::ArrayReg, locs::Locations)
#     H, dt = circ.free
#     expv!(st, -im*dt, H)
#     return register
# end

# function time_evolution_stub(circ::Circuit{:time_evolution}, register::ArrayReg, locs::Locations, ctrl_locs::Locations)
# end

# function time_evolution_krylov_stub(circ::Circuit{:time_evolution}, register::ArrayReg{1}, lcs::Locations)
#     Ks, H, dt = circ.free
#     st = statevec(register)
#     arnoldi!(Ks, H, st)
#     expv!(st, -im*dt, Ks)
#     return register
# end

# function time_evolution_krylov_stub(circ::Circuit{:time_evolution}, register::ArrayReg, lcs::Locations, ctrl_locs::Locations)
# end

# function (::PrimitiveCircuit{:time_evolution})(H, dt)
#     Circuit{:time_evolution}(time_evolution_stub, (H, dt))
# end

# function (::PrimitiveCircuit{:time_evolution})(Ks, H, dt)
#     Circuit{:time_evolution}(time_evolution_krylov_stub, (Ks, H, dt))
# end

# const time_evolution = PrimitiveCircuit{:time_evolution}()
