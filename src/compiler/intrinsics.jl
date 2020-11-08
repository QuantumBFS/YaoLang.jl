export @intrinsic

# NOTE:
# we only define basic staff for now
# but in principal we should generate simulation
# instruction and QASM directly from here
# since these are not real "intrinsic" APIs

macro intrinsic(ex)
    return esc(intrinsic_m(ex))
end

function intrinsic_m(name::Symbol)
    return quote
        Core.@__doc__ const $name = $IntrinsicSpec{$(QuoteNode(name))}()
    end
end

function intrinsic_m(ex::Expr)
    ex.head === :call || error("expect a function call or a symbol")
    name = ex.args[1]::Symbol

    return quote
        Core.@__doc__ const $name = $IntrinsicRoutine{$(QuoteNode(name))}()

        function (self::$IntrinsicRoutine{$(QuoteNode(name))})($(ex.args[2:end]...))
            return $IntrinsicSpec(self, $(rm_annotations.(ex.args[2:end])...))
        end
    end
end

module Gate

using ..Compiler: @intrinsic
export X, Y, Z, H, S, T, shift, Rx, Ry, Rz

@intrinsic X
@intrinsic Y
@intrinsic Z
@intrinsic H
@intrinsic S
@intrinsic T

@intrinsic shift(θ::Real)
@intrinsic Rx(θ::Real)
@intrinsic Ry(θ::Real)
@intrinsic Rz(θ::Real)

end
