using YaoLang
using ExprTools
using YaoLang.Compiler
using Mjolnir

ex = :(function qft(n::Int)
    1=>H
end)

def = splitdef(ex)
Compiler.device_def(def)

ex = :(function (n::Int)
    1=>H
end)
def = splitdef(ex)
Compiler.device_def(def)

ex = :(function (::MyCircuit)(n::Int)
    1 => H
    @ctrl 2 3=>H
end)

def = splitdef(ex)
Compiler.device_def(def)

ex = :(function (self::MyCircuit{T})(n::Int) where T
    1 => H
    @ctrl 2 3=>H
end)
def = splitdef(ex)
Compiler.device_def(def)

ex = :(function (::MyCircuit{T})(n::Int) where T
    1 => H
    @ctrl 2 3=>H
end)
def = splitdef(ex)
Compiler.device_def(def)

struct MyCircuit{T}
    x::Int
end

@device function (::MyCircuit{T})(n::Int) where T
    1 => H
    @ctrl 2 3=>H
end

@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
end

using IRTools
using IRTools.Inner: var
using Mjolnir: frame, Inference, Defaults, @abstract

using Mjolnir: Multi, Numeric, Basic
struct Quantum end

@abstract Quantum RoutineSpec(stub, parent, xs...) = RoutineSpec{typeof(stub), typeof(parent), typeof(xs)}

function Mjolnir.infer_stmt!(::Val{:quantum}, inf, frame, b, f, ip, block, var, st)
    block.ir[var] = Mjolnir.stmt(block[var], type = Mjolnir._union(st.type, Nothing))
    push!(inf.queue, (frame, b, f, ip+1))
    return inf
end

device_fn = qft(3)
ir = YaoIR(typeof(device_fn.stub), Int)

fr = frame(copy(ir.code), Int)
inf = Inference(fr, Multi(Numeric(), Basic(), Quantum()))
Mjolnir.infer!(inf)
fr.ir

c = qft(3)
ir = @code_ir RoutineSpec(c.stub, qft, 3)
fr = frame(copy(ir), Int)
inf = Inference(fr, Multi(Numeric(), Basic(), Quantum()))
Mjolnir.infer!(inf)

fr.ir

function foo(n)
    c = 0
    for i in 1:n
        c += i
    end
    return c
end

ir = @code_ir foo(4)
fr = frame(copy(ir), typeof(foo), Int)

inf = Inference(fr, Multi(Numeric(), Basic(), Quantum()))
Mjolnir.infer!(inf)

using Mjolnir, IRTools

function foo()
    for i in 2:3
        2 + 3
    end
    return
end

ir = @code_ir foo()
Mjolnir.return_type(ir)
