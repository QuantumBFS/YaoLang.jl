```@meta
CurrentModule = YaoLang.Compiler
```

## Introduction

YaoLang is a **Julia compiler extension**. It compiles a subset of Julia programs
to quantum device. As a language aims to solve the two language problem, we want to
provide our solution to the two language problem in quantum programming.

YaoLang extends the native Julia semantics via macros and interpret
these extra semantics via custom interpreter based on Julia's own interpreter
during Julia's own type inference stage then runs our own specific
optimization passes after Julia compiler optimizes the classical parts.

The YaoLang project aims to:

1. compiles native Julia program to quantum devices and quantum device simulators
2. provide an infrastructure for quantum compilation related research.

## Features
### Writing Hybrid Programs

One of the major goal of YaoLang is to represent hybrid programs, which means programs mixed with
classical functions and quantum routines. This is something happens very frequently in practical
quantum computation and all the actual program controls quantum devices can be seen as such a hybrid
program.

In YaoLang, you can use ANY classical Julia program semantics, such as control flows, function calls,
and even other Julia packages. It is fully compatible with native Julia code. The compiler will only
check if the program is compatible with your target machine or not. Here is a QFT example written using
classical control flow:

```julia
@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
end
```

We don't have a real quantum device that supports running YaoLang natively, but ideally we can. Given Julia
itself is actually Just-Ahead-of-Time (JAOT) compiled, there will not be any latency issue when we actually controls the quantum device - YaoLang as a subset of JuliaLang is static itself. It requires
one to write type-stable Julia program in most cases except for native Julia simulator backend.

### QASM Support

You can call QASM code like other Julia FFIs - simple and elegant:

```julia
julia> circuit = qasm"""OPENQASM 2.0;
       include "qelib1.inc";
       gate custom(lambda) a {
           u1(sin(lambda) + 1) a;
       }
       // comment
       gate g a
       {
           U(0,0,0) a;
       }

       qreg q[4];
       creg c1[1];
       U(-1.0, pi/2+3, 3.0) q[2];
       CX q[1], q[2];
       custom(0.3) q[3];
       barrier q;
       h q[0];
       measure q[0] -> c1[0];
       if(c1==1) z q[2];
       u3(0.1 + 0.2, 0.2, 0.3) q[0];
       """
##qasm#702 (generic routine with 1 methods)

julia> YaoLang.@echo circuit()
[ Info: executing 3 => Rz(-1.0)
[ Info: executing 3 => Ry(4.570796326794897)
[ Info: executing 3 => Rz(3.0)
[ Info: executing @ctrl 2 3 => X
[ Info: executing 4 => Rz(0)
[ Info: executing 4 => Ry(0)
[ Info: executing 4 => Rz(1.2955202066613396)
[ Info: executing @barrier 1:4
[ Info: executing 1 => H
[ Info: executing @measure 1
[ Info: executing 1 => Rz(0.30000000000000004)
[ Info: executing 1 => Ry(0.2)
[ Info: executing 1 => Rz(0.3)
(c1 = 0,)
```

this string literal `@qasm_str` (See [string literal section of Julia documentation](https://docs.julialang.org/en/v1/manual/metaprogramming/#Non-Standard-String-Literals)) will create a YaoLang routine
for all the gate declaration and in the and creates a anoymous YaoLang routine for the toplevel QASM program.

### Hybrid Program Optimization

YaoLang can optimize your hybrid program using both Julia and its custom compiler optimization pass.
See optimization section for more details.
