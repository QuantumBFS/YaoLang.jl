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

ast = QASM.Parse.load(qasm_1)
QASM.parse(Main, ast)

qasm_2 = """OPENQASM 2.0;
qreg q[3];
U(-1.0, pi/2+3, 3.0) q[2];
CX q[1], q[2];
custom(lambda) q[0];
"""

ast = QASM.Parse.load(qasm_2)
QASM.parse(Main, ast)

qasm_3 = """OPENQASM 2.0;
qreg q[4];
creg c[4];
x q[0]; 
x q[2];
barrier q;
h q[0];
cu1(pi/2) q[1],q[0];
h q[1];
cu1(pi/4) q[2],q[0];
cu1(pi/2) q[2],q[1];
h q[2];
cu1(pi/8) q[3],q[0];
cu1(pi/4) q[3],q[1];
cu1(pi/2) q[3],q[2];
h q[3];
measure q -> c;
"""

ast = QASM.Parse.load(qasm_3)
QASM.parse(Main, ast)

qasm_4 = """OPENQASM 2.0;
// include "qelib1.inc";
qreg q[3];
creg c0[1];
creg c1[1];
creg c2[1];
// optional post-rotation for state tomography
gate post q { }
u3(0.3,0.2,0.1) q[0];
h q[1];
cx q[1],q[2];
barrier q;
cx q[0],q[1];
h q[0];
measure q[0] -> c0[0];
measure q[1] -> c1[0];
if(c0==1) z q[2];
if(c1==1) x q[2];
post q[2];
measure q[2] -> c2[0];
"""

ast = QASM.Parse.load(qasm_4)
QASM.parse(Main, ast)

qasm_5 = """OPENQASM 2.0;
qreg q[3];
u2(0.3, 0.2) q[0];
u1(0.1) q[0];
u3(0.1, 0.2, 0.3) q[0];
u3(0.1 + 0.2, 0.2, 0.3) q[0];
"""



ast = QASM.Parse.load(qasm_5)
QASM.parse(Main, ast)
record = QASM.scan_registers(ast)

gate = ast.prog[2]
QASM.parse(Main, gate)
QASM.parse(Main, ast)

qasm"""OPENQASM 2.0;
gate g a
{
    U(0,0,0) a;
}

gate g(theta) a
{
    U(0,theta,0) a;
}
"""

circuit = g(2.0)
circuit(Compiler.EchoReg(), Locations(1:3))

circuit = g()
circuit(Compiler.EchoReg(), Locations(1:3))


circuit = qasm"""OPENQASM 2.0;
qreg q[4];
creg c[4];
x q[0]; 
x q[2];
barrier q;
h q[0];
cu1(pi/2) q[1],q[0];
h q[1];
cu1(pi/4) q[2],q[0];
cu1(pi/2) q[2],q[1];
h q[2];
cu1(pi/8) q[3],q[0];
cu1(pi/4) q[3],q[1];
cu1(pi/2) q[3],q[2];
h q[3];
measure q -> c;
"""

ri = @code_yao circuit()

# copied from qelib1.inc
qasm"""OPENQASM 2.0;
gate u3(theta,phi,lambda) q { U(theta,phi,lambda) q; }
// 2-parameter 1-pulse single qubit gate
gate u2(phi,lambda) q { U(pi/2,phi,lambda) q; }
// 1-parameter 0-pulse single qubit gate
gate u1(lambda) q { U(0,0,lambda) q; }
// controlled-NOT
gate cx c,t { CX c,t; }
// idle gate (identity)
"""

circuit = qasm"""OPENQASM 2.0;
// include "qelib1.inc";
qreg q[3];
creg c0[1];
creg c1[1];
creg c2[1];
// optional post-rotation for state tomography
gate post q { }
u3(0.3,0.2,0.1) q[0];
h q[1];
cx q[1],q[2];
barrier q;
cx q[0],q[1];
h q[0];
measure q[0] -> c0[0];
measure q[1] -> c1[0];
if(c0==1) z q[2];
if(c1==1) x q[2];
post q[2];
measure q[2] -> c2[0];
"""

qasm = """OPENQASM 2.0;
// include "qelib1.inc";
qreg q[3];
creg c0[1];
creg c1[1];
creg c2[1];
// optional post-rotation for state tomography
gate post q { }
u3(0.3,0.2,0.1) q[0];
h q[1];
cx q[1],q[2];
barrier q;
cx q[0],q[1];
h q[0];
measure q[0] -> c0[0];
measure q[1] -> c1[0];
if(c0==1) z q[2];
if(c1==1) x q[2];
post q[2];
measure q[2] -> c2[0];
"""

ri = @code_yao circuit()