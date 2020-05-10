export @device, @ctrl, @measure

"""
    @device [strict=false] <generic circuit definition>

Entry for defining a generic quantum program. A generic quantum program is a function takes
a set of classical arguments as input and return a quantum circuit that can be furthur compiled
into pulses or other quantum instructions.

# Supported Semantics

- [`@ctrl`](@ref): Keyword for controlled gates in quantum circuit.
- [`@measure`](@ref): Keyword for measurement in quantum circuit.

The function marked by `@device` can be multiple dispatched like other Julia function. The only difference
is that it always returns a quantum circuit object that should be runable on quantum device by feeding it
the location of qubits and the pointer to quantum register.

# Example

We can define a Quantum Fourier Transformation in the following recursive way

```julia
@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1=>shift(2π/2^k)
    end

    if n > 1
        2:n => qft(n-1)
    end
end
```

This will give us a generic quantum circuit `qft` with 1 method.
"""
macro device(ex)
    return esc(device_m(ex))
end

macro device(option, ex)
    if (option isa Expr) && (option.head === :(=)) && (option.args[1] == :strict)
        return esc(device_m(ex, option.args[2]))
    else
        throw(Meta.ParseError("Invalid Syntax, expect a compile option"))
    end
end

"""
    @ctrl k <gate location>

Keyword for controlled gates in quantum circuit. It must be used inside `@device`. See also [`@device`](@ref).
"""
macro ctrl end

"""
    @measure <location> [operator] [configuration]

Keyword for measurement in quantum circuit. It must be used inside `@device`. See also [`@device`](@ref).

# Arguments

- `<location>`: a valid `Locations` argument to specifiy where to measure the register
- `[operator]`: Optional, specifiy which operator to measure
- `[configuration]`: Optional, it can be either:
    - `remove=true` will remove the measured qubits
    - `reset_to=<bitstring>` will reset the measured qubits to given bitstring
"""
macro measure end
