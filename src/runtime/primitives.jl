export @primitive, primitive_m
export PrimitiveCircuit
# Primitive Routines
struct PrimitiveCircuit{name} end
function Base.show(io::IO, x::PrimitiveCircuit{name}) where name
    print(io, name, " (primitive circuit)")
end

"""
    generate_forward_stub(name::Symbol, op)

Generate forward stub which forward primitive circuit to instruction interfaces.
"""
function generate_forward_stub(name::Symbol, op)
    quoted_name = QuoteNode(name)
    stub = gensym(name)

    return quote
        function $stub(::$(Circuit){$quoted_name}, r::$(AbstractRegister), locs::$(Locations))
            $(YaoBase).instruct!(r, $op, Tuple(locs))
            return r
        end

        function $stub(::$(Circuit){$quoted_name}, r::$(AbstractRegister), locs::$(Locations), ctrl_locs::$(Locations))
            raw_ctrl_locs, ctrl_cfg = decode_sign(ctrl_locs)
            $(YaoBase).instruct!(r, $op, Tuple(locs), raw_ctrl_locs, ctrl_cfg)
            return r
        end

        (::$PrimitiveCircuit{$quoted_name})() = $Circuit{$quoted_name}($stub)
        Core.@__doc__ const $name = $Circuit{$quoted_name}($stub)
    end
end

function primitive_m(x::Symbol)
    generate_forward_stub(x, :(Val($(QuoteNode(x)))))
end

function primitive_m(ex::Expr)
    def = splitdef(ex; throw=false)
    def === nothing && return assign_statement(ex)
    
    haskey(def, :name) || throw(Meta.ParseError("Invalid Syntax: expect a function name"))
    name = def[:name]
    quoted_name = QuoteNode(name)
    stub = gensym(name)
    if haskey(def, :args)
        args = map(rm_annotations, def[:args])
    else
        args = ()
    end

    mat_stub_def = deepcopy(def)
    mat_stub = gensym(:mat)
    mat_stub_def[:name] = mat_stub

    primitive_def = deepcopy(def)
    primitive_def[:name] = :(::$(PrimitiveCircuit{name}))
    primitive_def[:body] = quote
        m = $(Expr(:call, mat_stub, args...))
        return Circuit{$quoted_name}($stub, (m, ))
    end

    circ = gensym(:circ)
    register = gensym(:register)
    locs = gensym(:locs)
    ctrl_locs = gensym(:ctrl_locs)
    matrix = gensym(:m)

    stub_def = Dict{Symbol, Any}()
    stub_def[:name] = stub
    stub_def[:args] = Any[:($circ::Circuit{$quoted_name}), :($register::$AbstractRegister), :($locs::$Locations)]
    stub_def[:body] = quote
        $matrix = $circ.free[1]
        YaoBase.instruct!($register, $matrix, Tuple($locs))
        return $register
    end

    ctrl_stub_def = Dict{Symbol, Any}()
    ctrl_stub_def[:name] = stub
    ctrl_stub_def[:args] = Any[:($circ::Circuit{$quoted_name}), :($register::$AbstractRegister), :($locs::$Locations), :($ctrl_locs::$Locations)]
    ctrl_stub_def[:body] = quote
        $matrix = $circ.free[1]
        raw_ctrl_locs, ctrl_cfg = decode_sign($ctrl_locs)
        YaoBase.instruct!($register, $matrix, Tuple($locs), raw_ctrl_locs, ctrl_cfg)
        return $register
    end

    quote
        $(combinedef(mat_stub_def))
        $(combinedef(stub_def))
        $(combinedef(ctrl_stub_def))
        $(combinedef(primitive_def))
        Core.@__doc__ const $name = $(PrimitiveCircuit{name})()
    end
end

function assign_statement(ex::Expr)
    ex.head === :(=) || throw(Meta.ParseError("Invalid Syntax, expect <primitive gate name> = <matrix expr>, got $ex"))
    ex.args[1] isa Symbol || throw(Meta.ParseError("Invalid Syntax, expect Symbol got $(ex.args[1])"))
    name = ex.args[1]
    matrix_const = gensym(:matrix_const)
    
    return quote
        const $matrix_const = $(esc(ex.args[2]))
        $(generate_forward_stub(name, matrix_const))
    end
end

macro primitive(ex)
    return esc(primitive_m(ex))
end

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

export shift, phase, Rx, Ry, Rz, rot, time_evolution

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
@primitive phase(θ::T) where {T <: Real} = exp(im * θ) * IMatrix{2,T}()
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
@primitive function rot(axis, θ::T, m::Int=size(axis, 1)) where {T <: Real}
    I = IMatrix{m,T}()
    return I * cos(θ / 2) - im * sin(θ / 2) * axis
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
