using YaoLang
using YaoLang.Compiler
using ExprTools
using IRTools
using IRTools: IR
using YaoArrayRegister
using FFTW
using Test

@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
end

# h q[0];
# cu1(pi/2) q[1],q[0];
# h q[1];
# cu1(pi/4) q[2],q[0];
# cu1(pi/2) q[2],q[1];
# h q[2];
# cu1(pi/8) q[3],q[0];
# cu1(pi/4) q[3],q[1];
# cu1(pi/2) q[3],q[2];
# h q[3];

@device mode = :qasm function qft4()
    1 => H
    @ctrl 2 1 => shift(π / 2)
    @ctrl 3 1 => shift(π / 4)
    @ctrl 4 1 => shift(π / 8)

    2 => H
    @ctrl 3 2 => shift(π / 2)
    @ctrl 4 2 => shift(π / 4)

    3 => H
    @ctrl 4 3 => shift(π / 2)

    4 => H
end

@device mode = :pure function hadamard()
    1 => H
end

@testset "example/qft" begin
    r = rand_state(4)
    state_vec = statevec(r)
    a = invorder!(copy(r)) |> qft(4)
    kv = ifft(state_vec) * sqrt(length(state_vec))
    @test statevec(a) ≈ kv

    circ = qft(4)
    ir = @code_yao qft4()
    @test is_qasm_compatible(ir)
end

@testset "example/hadamard" begin
    ir = @code_yao hadamard()
    @test ir.mode == :pure
    r = rand_state(1)
    @test (copy(r) |> hadamard()) ≈ (copy(r) |> H())
end

@device mode = :pure function pure_qft4()
    1 => H
    @ctrl 2 1 => shift($(π / 2))
    @ctrl 3 1 => shift($(π / 4))
    @ctrl 4 1 => shift($(π / 8))

    2 => H
    @ctrl 3 2 => shift($(π / 2))
    @ctrl 4 2 => shift($(π / 4))

    3 => H
    @ctrl 4 3 => shift($(π / 2))

    4 => H
end

@testset "\$ eval" begin
    ir = @code_yao pure_qft4()
    @test is_pure_quantum(ir)
end

@device function check_return(k::Int)
    c = @measure k
    return c
end

@testset "measure" begin
    r = ArrayReg(bit"000") + ArrayReg(bit"010") + ArrayReg(bit"110")
    @test bit"0" == check_return(1)(r)
end

@testset "printing" begin
    ir = @code_yao qft(3)
    println(ir)
end

@device function single_qubit_layer(configs::AbstractVector, gateset = (X, Y, Z))
    @inbounds for k in 1:size(configs, 1)
        idx = configs[k]
        if idx > 0
            k => gateset[idx]
        end
    end
end

@testset "default value (#19)" begin
    configs = rand(1:3, 4)
    gateset = (X, Y, Z)
    c = single_qubit_layer(configs)
    println(@code_yao single_qubit_layer(configs))
    r = rand_state(4)
    r1 = copy(r) |> c
    r2 = copy(r)
    for k in 1:4
        r2 |> gateset[configs[k]](Locations(k))
    end
    @test r1 ≈ r2
end

struct Foo
    a::Int
    b::Int
end

@device function (b::Foo)(theta)
    @ctrl b.a b.b => shift(theta)
    theta
end

@testset "callable" begin
    m = Foo(1, 2)
    r = rand_state(4)
    r1 = copy(r) |> m(1.2)
    r2 = copy(r) |> shift(1.2)(1, 2)
    @test r1 ≈ r2
end

@testset "purify" begin
    pure_qft = @quantum 3 qft(3)
    @test is_pure_quantum(@code_yao pure_qft())
end