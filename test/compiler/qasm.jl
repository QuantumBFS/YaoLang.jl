using YaoLang, YaoArrayRegister
using Test

qasm_0 = """
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

qasm_1 = """OPENQASM 2.0;
qreg q[3];
x q[2];
ccx q[0], q[2], q[1];
x q[2];
ccx q[2], q[1], q[0];
cx q[2], q[0];
x q[2];
ccx q[0], q[2], q[1];
ccx q[0], q[2], q[1];
"""

qasm_2 = """OPENQASM 2.0;
qreg q[3];
ccx q[0], q[1], q[2];
ccx q[0], q[1], q[2];
ccx q[1], q[0], q[2];
x q[0];
ccx q[1], q[0], q[2];
ccx q[2], q[1], q[0];
ccx q[2], q[1], q[0];
ccx q[1], q[0], q[2];
"""

qasm_3 = """OPENQASM 2.0;
qreg q[3];
ccx q[1], q[2], q[0];
x q[0];
x q[1];
ccx q[1], q[0], q[2];
ccx q[1], q[0], q[2];
ccx q[1], q[0], q[2];
ccx q[0], q[1], q[2];
ccx q[0], q[2], q[1];
"""

qasm_4 = """OPENQASM 2.0;
qreg q[3];
ccx q[1], q[2], q[0];
x q[1];
ccx q[2], q[1], q[0];
ccx q[2], q[1], q[0];
ccx q[0], q[1], q[2];
ccx q[0], q[2], q[1];
ccx q[2], q[0], q[1];
cx q[1], q[2];
"""

srcs = [qasm_0, qasm_1, qasm_2, qasm_3, qasm_4]
for src in srcs
    ast = YaoLang.Compiler.QASM.load(src)
    ir_original = YaoLang.Compiler.YaoIR(@__MODULE__, ast, :circ_original)
    ir_optimized = YaoLang.Compiler.YaoIR(@__MODULE__, ast, :circ_optimized)
    ir_optimized = YaoLang.Compiler.optimize(ir_optimized, [:zx_teleport])
    code_original =
        YaoLang.Compiler.codegen(YaoLang.Compiler.JuliaASTCodegenCtx(ir_original), ir_original)
    code_optimized =
        YaoLang.Compiler.codegen(YaoLang.Compiler.JuliaASTCodegenCtx(ir_optimized), ir_optimized)

    eval(code_original)
    eval(code_optimized)

    nbits = YaoLang.Compiler.count_nqubits(ir_original)

    circ_or = circ_original()
    circ_op = circ_optimized()

    r_or = rand_state(nbits)
    r_op = copy(r_or)
    r_or |> circ_or
    r_op |> circ_op

    @test fidelity(r_or, r_op) ≈ 1
end
