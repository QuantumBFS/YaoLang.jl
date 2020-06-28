export @device, @ctrl, @measure

"""
    @device [options] <generic circuit definition>

Entry for defining a generic quantum program. A generic quantum program is a function takes
a set of classical arguments as input and return a quantum program that can be furthur compiled
into pulses or other quantum instructions. The quantum program can return classical values from
device if `return` statement is declared explicitly, or it always return nothing, and mutates the
quantum register.

# Supported Semantics

- [`@ctrl`](@ref): Keyword for controlled gates in quantum circuit.
- [`@measure`](@ref): Keyword for measurement in quantum circuit.

The function marked by `@device` can be multiple dispatched like other Julia function. The only difference
is that it always returns a quantum circuit object that should be runable on quantum device by feeding it
the location of qubits and the pointer to quantum register.

# Options

- `target`, compilation target, default is `:julia`, see **Compilation Targets** for details.

## Compilation Targets

- `:julia`, default target, compiles the program to Julia program.
- `:qasm`, compiles the program to [openQASM](https://github.com/Qiskit/openqasm).

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
macro device end

macro device(ex)
    return esc(device_m(__module__, ex))
end

macro device(args...)
    options = args[1:end-1]
    ex = args[end]

    kwargs = Pair[]
    for each in options
        if (each isa Expr) && (each.head === :(=))
            each.args[2] isa QuoteNode || throw(ParseError("expect a Symbol, got $(each.args[2])"))
            push!(kwargs, each.args[1] => each.args[2].value)
        else
            throw(Meta.ParseError("Invalid Syntax, expect a compile option, got $each"))
        end
    end

    return esc(device_m(__module__, ex; kwargs...))
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

"""
    @expect <location> [operator]

Keyword for expectation in quantum circuit. It must be used inside `@device`. See also [`@device`](@ref).

# Arguments

- `<location>`: a valid `Locations` argument to specifiy where to measure the register
- `[operator]`: Optional, specifiy which operator to measure
"""
macro expect end
