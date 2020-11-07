using Test
using YaoLang
using YaoLang.Compiler
using YaoLang.Compiler.QASM
using YaoLang.Compiler.QASM.Parse
using RBNF: Token

@testset "qasm parser" begin

    qasm = """OPENQASM 2.0;
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
    creg c2[1];
    U(-1.0, pi/2+3, 3.0) q[2];
    CX q[1], q[2];
    custom(0.3) q[3];
    barrier q;
    h q[0];
    measure q[0] -> c0[0];
    if(c0==1) z q[2];
    u3(0.1 + 0.2, 0.2, 0.3) q[0];
    """

    ast = QASM.Parse.load(qasm)

    @testset "mainprogram" begin
        @test ast isa Parse.MainProgram
        @test ast.version == v"2.0.0"
    end

    @testset "include" begin
        @test ast.prog[1] isa Parse.Include
        @test ast.prog[1].file isa Token{:str}
        @test ast.prog[1].file.str == "\"qelib1.inc\""
    end

    @testset "gate custom(lambda) a" begin
        @test ast.prog[2] isa Parse.Gate
        custom = ast.prog[2]

        @test custom.decl.name isa Token{:id}
        @test custom.decl.name.str == "custom"
        @test length(custom.decl.cargs) == 1
        @test custom.decl.cargs[1] isa Token{:id}
        @test custom.decl.cargs[1].str == "lambda"
        @test length(custom.decl.qargs) == 1
        @test custom.decl.qargs[1] isa Token{:id}
        @test custom.decl.qargs[1].str == "a"

        @test length(custom.body) == 1
        @test custom.body[1] isa Parse.Instruction
        inst = custom.body[1]
        @test inst.name == "u1"
        @test length(inst.cargs) == 1
        @test length(inst.qargs) == 1
        @test inst.cargs[1] isa Tuple
        @test inst.qargs[1] isa Parse.Bit
        carg = inst.cargs[1]
        qarg = inst.qargs[1]
        @test length(carg) == 3
        @test carg[1] isa Parse.FnExp
        @test carg[2] isa Token{:reserved}
        @test carg[3] isa Token{:int}
        @test carg[1].fn === :sin
        @test carg[1].arg.str == "lambda"
        @test carg[2].str == "+"
        @test carg[3].str == "1"
        @test qarg.name.str == "a"
        @test qarg.address === nothing
    end

    @testset "gate g" begin
        @test ast.prog[3] isa Parse.Gate
        g = ast.prog[3]
        @test isempty(g.decl.cargs)
        @test length(g.decl.qargs) == 1
        @test g.decl.qargs[1] isa Token{:id}
        @test g.decl.qargs[1].str == "a"
        @test g.decl.name isa Token{:id}
        @test g.decl.name.str == "g"

        @test length(g.body) == 1
        @test g.body[1] isa Parse.UGate
        ugate = g.body[1]
        @test ugate.qarg isa Parse.Bit
        @test ugate.qarg.name.str == "a"
        @test ugate.qarg.address === nothing
        @test ugate.y isa Token{:int}
        @test ugate.y.str == "0"
        @test ugate.z1.str == "0"
        @test ugate.z2.str == "0"
    end

    @testset "qreg" begin
        @test ast.prog[4] isa Parse.RegDecl
        reg = ast.prog[4]
        @test reg.name isa Token{:id}
        @test reg.name.str == "q"
        @test reg.size isa Token{:int}
        @test reg.size.str == "4"
        @test reg.type isa Token{:reserved}
        @test reg.type.str == "qreg"
    end

    @testset "creg" begin
        @test ast.prog[5] isa Parse.RegDecl
        reg = ast.prog[5]
        @test reg.name isa Token{:id}
        @test reg.name.str == "c1"
        @test reg.size isa Token{:int}
        @test reg.size.str == "1"
        @test reg.type isa Token{:reserved}
        @test reg.type.str == "creg"
    end

    @testset "U" begin
        @test ast.prog[7] isa Parse.UGate
        U = ast.prog[7]
        @test U.qarg isa Parse.Bit
        @test U.y isa Tuple
        @test U.z1 isa Parse.Negative
        @test U.z2 isa Token{:float64}
        @test U.qarg.name.str == "q"
        @test U.qarg.address.str == "2"
        @test U.y[2] isa Token{:reserved}
        @test U.y[2].str == "+"
        @test U.y[1] isa Tuple
        @test U.y[1][1] isa Token{:reserved}
        @test U.y[1][2] isa Token{:reserved}
        @test U.y[1][1].str == "pi"
        @test U.y[1][2].str == "/"
    end

    @testset "CX" begin
        @test ast.prog[8] isa Parse.CXGate
        cx = ast.prog[8]
        @test cx.ctrl isa Parse.Bit
        @test cx.qarg isa Parse.Bit
        @test cx.ctrl.name.str == "q"
        @test cx.qarg.name.str == "q"
        @test cx.ctrl.address.str == "1"
        @test cx.qarg.address.str == "2"
    end

    @testset "inst" begin
        @test ast.prog[9] isa Parse.Instruction
        inst = ast.prog[9]
        @test inst.name == "custom"
        @test inst.cargs[1].str == "0.3"
        @test inst.qargs[1].name.str == "q"
        @test inst.qargs[1].address.str == "3"
    end

    @testset "barrier" begin
        @test ast.prog[10] isa Parse.Barrier
        barrier = ast.prog[10]
        @test length(barrier.qargs) == 1
        @test barrier.qargs[1] isa Parse.Bit
        @test barrier.qargs[1].name.str == "q"
        @test barrier.qargs[1].address === nothing
    end

    @testset "h q[0]" begin
        @test ast.prog[11] isa Parse.Instruction
        @test ast.prog[11].name == "h"
        @test length(ast.prog[11].qargs) == 1
        @test length(ast.prog[11].cargs) == 0
    end

    @testset "measure" begin
        m = ast.prog[12]
        @test m isa Parse.Measure
        @test m.qarg isa Parse.Bit
        @test m.carg isa Parse.Bit
        @test m.qarg.name isa Token{:id}
        @test m.qarg.name.str == "q"
        @test m.carg.name isa Token{:id}
        @test m.carg.name.str == "c0"
        @test m.qarg.address isa Token{:int}
        @test m.carg.address isa Token{:int}
        @test m.qarg.address.str == "0"
        @test m.carg.address.str == "0"
    end

    @testset "ifstmt" begin
        ifstmt = ast.prog[13]
        @test ifstmt isa Parse.IfStmt
        @test ifstmt.left isa Token{:id}
        @test ifstmt.left.str == "c0"
        @test ifstmt.right isa Token{:int}
        @test ifstmt.right.str == "1"
        @test ifstmt.body isa Parse.Instruction
        @test ifstmt.body.name == "z"
        @test length(ifstmt.body.qargs) == 1
        @test length(ifstmt.body.cargs) == 0
        @test ifstmt.body.qargs[1].name.str == "q"
        @test ifstmt.body.qargs[1].address.str == "2"
    end

    @testset "u3" begin
        inst = ast.prog[14]
        @test inst isa Parse.Instruction
        @test inst.name == "u3"
        @test length(inst.cargs) == 3
        @test inst.cargs[1][1].str == "0.1"
        @test inst.cargs[1][2].str == "+"
        @test inst.cargs[1][3].str == "0.2"
        @test inst.cargs[2].str == "0.2"
        @test inst.cargs[3].str == "0.3"
    end

end


