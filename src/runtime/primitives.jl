export GenericCircuit, evaluate, ctrl_evaluate, @primitive, primitive_m
# Primitive Routines
struct PrimitiveCircuit{name} end
function Base.show(io::IO, x::PrimitiveCircuit{name}) where name
    print(io, name, " (primitive circuit)")
end

export shift
const shift = PrimitiveCircuit{:shift}()
function (::PrimitiveCircuit{:shift})(θ::Real)
    return Circuit{:shift}(shift_stub, (θ, ))
end

function shift_stub(circ::Circuit{:shift}, register::AbstractRegister, locs::Locations)
    m = Diagonal([1.0, exp(im * circ.free[1])])
    YaoBase.instruct!(register, m, Tuple(locs))
    return register
end

function shift_stub(circ::Circuit{:shift}, register::AbstractRegister, locs::Locations, ctrl_locs::Locations)
    m = Diagonal([1.0, exp(im * circ.free[1])])
    raw_ctrl_locs, ctrl_cfg = decode_sign(ctrl_locs)
    YaoBase.instruct!(register, m, Tuple(locs), raw_ctrl_locs, ctrl_cfg)
    return register
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
        const $name = $Circuit{$quoted_name}($stub)
    end
end

function primitive_m(x::Symbol)
    generate_forward_stub(x, :(Val($(QuoteNode(x)))))
end

function primitive_m(ex::Expr)
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
