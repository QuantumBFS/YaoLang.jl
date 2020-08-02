using YaoLang

src = """
OPENQASM 2.0;
qreg qubits[5];
x qubits[4];
h qubits[4];
h qubits[4];
ccx qubits[0],qubits[3],qubits[4];
h qubits[4];
h qubits[4];
ccx qubits[2],qubits[3],qubits[4];
h qubits[4];
h qubits[4];
cx qubits[3],qubits[4];
h qubits[4];
h qubits[4];
ccx qubits[1],qubits[2],qubits[4];
h qubits[4];
h qubits[4];
cx qubits[2],qubits[4];
h qubits[4];
h qubits[4];
ccx qubits[0],qubits[1],qubits[4];
h qubits[4];
h qubits[4];
cx qubits[1],qubits[4];
cx qubits[0],qubits[4];
"""

ir = YaoLang.Compiler.YaoIR(@__MODULE__, src, "circ")
ir.pure_quantum = YaoLang.Compiler.is_pure_quantum(ir)
new_ir = YaoLang.Compiler.optimize(ir, [:zx_teleport])
