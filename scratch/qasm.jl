using YaoLang
using YaoLang.Compiler
using YaoLang.Compiler.QASM
using RBNF

qasm_1 = """OPENQASM 2.0;
gate custom(lambda) a {
    u1(lambda) a;
}

gate g a
{
    U(0,0,0) a;
}

qreg q[4];
U(-1.0, pi/2+3, 3.0) q[2];
CX q[1], q[2];
custom(lambda) q[3];
"""

qasm_2 = """OPENQASM 2.0;
qreg q[3];
U(-1.0, pi/2+3, 3.0) q[2];
CX q[1], q[2];
custom(lambda) q[0];
"""

ast = QASM.Parse.load(qasm_1)
record = QASM.scan_registers(ast)

gate = ast.prog[2]
QASM.parse(Main, gate)
QASM.parse(Main, ast)



ast.prog[2].theta1

ast.prog[1]

RBNF.runlexer(QASM.Parse.QASMLang, qasm_1)