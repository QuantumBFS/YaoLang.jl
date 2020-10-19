using YaoLang
using YaoLang.Compiler
using YaoLang.Compiler.QASM
using YaoLang.Compiler.QASM.Parse
using RBNF
using RBNF: Token

qasm"""OPENQASM 2.0;
gate u3(theta,phi,lambda) q { U(theta,phi,lambda) q; }
// 2-parameter 1-pulse single qubit gate
gate u2(phi,lambda) q { U(pi/2,phi,lambda) q; }
// 1-parameter 0-pulse single qubit gate
gate u1(lambda) q { U(0,0,lambda) q; }
// controlled-NOT
gate cx c,t { CX c,t; }
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

ri = @code_yao circuit()

Parse.MainProgram(v"2.0", [])
