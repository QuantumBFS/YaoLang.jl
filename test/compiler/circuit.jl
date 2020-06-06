using YaoLang
using IRTools
using IRTools: IR
using YaoArrayRegister
using FFTW
using Test

@macroexpand @device function qft(n::Int)
    1 => H
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

ex = :(for k in 2:n
    shift(2π / 2^k)
end)

r = rand_state(4)
c = qft(4)

ir = YaoLang.@code_yao qft(4)
@code_warntype c(r)

ci1 = @code_lowered c.fn(c, r, Locations(1:4))
@code_warntype c.fn(c, r, Locations(1:4))

@code_llvm c.fn(c, r, Locations(1:4))


ex = :(function qft_stub(r::AbstractRegister, locs::Locations)
    return
end)

function qft_stub(circ, r::AbstractRegister, locs::Locations)
    n = circ.free[1]
    for k in 2:n
        gate = shift(2π / 2^k)
        gate(r, locs[Locations(1)], locs[Locations(k)])
    end
    return
end

ci2 = @code_lowered qft_stub(c, r, Locations(1:4))

ir = IR()

IRTools.argument!(ir)
r = IRTools.argument!(ir)
locs = IRTools.argument!(ir)

push!(ir, IRTools.Statement(:($(GlobalRef(Base, :getproperty))($YaoArrayRegister, :instruct!))))
gate = push!(ir, :(Val(:H)))
raw_locs = push!(ir, :(Tuple($locs)))
push!(ir, Expr(:call, IRTools.var(1), r, gate, raw_locs))
IRTools.return!(ir, nothing)


ci = Meta.lower(Main, ex)
ci2 = Meta.lower(Main, ex2)
IRTools.Inner.update!(ci.args[1].code[end-1].args[end], ir)

ci = ci.args[]
ci2 = ci2.args[]

for k in 1:length(ci.code)
    println("code[", k, "]", ci.code[k] == ci2.code[k])
end

ci.code[7].args[1:2] == ci2.code[7].args[1:2]
ci = ci.code[7].args[end]
ci2 = ci2.code[7].args[end]
for each in fieldnames(Core.CodeInfo)
    println(each, " ", getfield(ci, each) == getfield(ci2, each))
end

ci.code
ci2.code

ci.slotflags
ci2.slotflags

ci.slotnames
ci2.slotnames

eval(ci)

@code_typed qft_stub(rand_state(4), Locations(1))


@device mode = :pure function hadamard()
    1 => H
end

@testset "example/hadamard" begin
    ir = @code_yao hadamard()
    @test ir.strict_mode == :pure
    r = rand_state(1)
    @test (copy(r) |> hadamard()) ≈ (copy(r) |> H())
end

@testset "example/qft" begin
    r = rand_state(4)
    state_vec = statevec(r)
    a = invorder!(copy(r)) |> qft(4)
    kv = ifft(state_vec) * sqrt(length(state_vec))
    @test statevec(a) ≈ kv

    circ = qft(4)
    @test circ(1:4) == ((1:4) => circ)
    @test ((1:4) => circ)(copy(r)) == circ(1:4)(copy(r))
    @test ((1, 2, 3, 4) => circ)(copy(r)) == circ(1:4)(copy(r))
end
