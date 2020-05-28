## Introduction

YaoLang is a domain specific language (DSL) built based on
Julia builtin expression with extended semantic on quantum control, measure and position. Its (extended) syntax is very simple:

### Semantics

The semantic of YaoLang tries to make use of Julia semantic as much as possible so you don't feel this
is not Julian. But since the quantum circuit has some
special semantic that Julia expression cannot express
directly, the semantic of Julia expression is extended in YaoLang.

The point of this new IR is it make use of Julia native
control flow directly instead of unroll the loop and conditions into a Julia type, such as `Chain`, `Kron`,
`ConditionBlock` in QBIR, which improves the performance and provide possibility of further compiler
optimization by analysis done on quantum circuit and classical control flows.

#### Gate Position
gate positions are specific with `=>` at each line,
the `=>` operator inside function calls will not be
parsed, e.g


```jl
1 => H # apply Hadamard gate on the 1st qubit
foo(1=>H) # it means normal Julia pair
1=>foo(x, y, z) # it will parse foo(x, y, z) as a quantum gate/circuit, but will error later if type inference finds they are not.
```

all the gate or circuit's position should be specified by its complete locations, e.g

```jl
1:n => qft(n) # right
1 => qft(n) # wrong
```

but single qubit gates can use multi-location argument
to represent repeated locations, e.g

```jl
1:n => H # apply H on 1:n locations
```

#### Control

`@ctrl` is parsed as a keyword (means you cannot overload it) in each program, like QBIR, its first argument is the control
location with signs as control configurations and the second argument is a normal gate position argument introduce above.

#### Measure

`@measure` is another reserved special function parsed that has specific semantic in the IR (measure the locations passed to it).

### Usage

using it is pretty simple, just use `@device` macro to annotate a "device" function, like CUDA programming, this device function should not return anything but `nothing`.

The compiler will compile this function definition to
a generic circuit `Circuit` with the same name. A generic circuit is a generic quantum program that can
be overload with different Julia types, e.g

```jl
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

**There is no need to worry about global position**: everything can be defined locally and we will infer the correct global location
later either in compile time or runtime.

note: all the quantum gates should be annotate with its corresponding locations, or the compiler will not
treat it as a quantum gate but instead of the original Julia expression.

## Why?

There are a few reasons that we need a fully compiled DSL now.

### 1. Extensibility

Things in YaoBlocks like

```
function apply!(r::AbstractRegister, pb::PutBlock{N}) where {N}
    _check_size(r, pb)
    instruct!(r, mat_matchreg(r, pb.content), pb.locs)
    return r
end

# specialization
for G in [:X, :Y, :Z, :T, :S, :Sdag, :Tdag]
    GT = Expr(:(.), :ConstGate, QuoteNode(Symbol(G, :Gate)))
    @eval function apply!(r::AbstractRegister, pb::PutBlock{N,C,<:$GT}) where {N,C}
        _check_size(r, pb)
        instruct!(r, Val($(QuoteNode(G))), pb.locs)
        return r
    end
end
```

cannot be easily extended without define new dispatch on specialized instruction. Similarly, as long as there is a new instruction in low level, one need to redefine the dispatch in `YaoBlocks` however this is not necessary!

### 2. Work with classical computers
Programs defined in such way are just "normal" Julia programs, but quantum devices can be used as accelerator in a similar way comparing to GPU as an optimization.

### 3. More elegant and better performance
In YaoBlocks, a large quantum circuit can easily lost its structure if it is controlled, unless the programmer specialize the control block manually. Now we can map local locations into its callee location using the brand new API, thus anything in theory is composable can be executed in such way.


## API References

```@autodocs
Modules = [YaoLang]
```
