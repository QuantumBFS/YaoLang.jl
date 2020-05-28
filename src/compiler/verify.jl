# TODO: use Cassette to do some runtime check on actual values

"""
    isquantum(ex)

Check if the given expression is a pure quantum circuit.
"""
is_pure_quantum(x) = false

# skip LineNumberNode
is_pure_quantum(x::LineNumberNode) = true

function is_pure_quantum(ex::Expr)
    # no classical function call is allowed
    ex.head === :call && return false
    return all(is_pure_quantum, ex.args)
end

function is_pure_quantum(ex::GateLocation)
    ex.gate isa Symbol && return true
    if ex.gate.head === :call
        for each in ex.gate.args
            # disable classical function call
            if (each isa Expr) && (each.head === :call)
                return false
            end
        end
        return true
    else
        throw(Meta.ParseError("Invalid circuit statement, expect function call or variable, got $ex"))
    end
end

is_pure_quantum(ex::Control) = is_pure_quantum(ex.gate)
is_pure_quantum(::Measure) = true

function hasmeasure(ex::Expr)
    return any(hasmeasure, ex.args)
end

hasmeasure(x) = false
hasmeasure(x::Measure) = true

# TODO: check if qasm compatible
function is_qasm_compat(ex)
    ex
end
