using YaoLang
# using YaoLang.Compiler
# using YaoLang.Compiler.QASM
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
// barrier q;
cx q[0],q[1];
h q[0];
measure q[0] -> c0[0];
measure q[1] -> c1[0];
if(c0==1) z q[2];
if(c1==1) x q[2];
post q[2];
measure q[2] -> c2[0];
"""

spec = circuit()
spec = u3(0.3, 0.2, 0.1)
spec = qft(3)
interp, frame = Compiler._prepare_frame(Compiler.Semantic.main, typeof(spec));
Core.Compiler.typeinf(interp, frame)
Compiler.codegen(Compiler.TargetQASMGate(), frame.src)

Core.Compiler.typeinf(interp, frame)


Compiler.codegen(Compiler.TargetQASM(), ci)

Core.Compiler.typeinf_nocycle(interp, frame)
# with no active ip's, frame is done
frames = frame.callers_in_cycle
isempty(frames) && push!(frames, frame)
for caller in frames
    @assert !(caller.dont_work_on_me)
    caller.dont_work_on_me = true
end

for caller in frames
    Core.Compiler.finish(caller, interp)
end
# collect results for the new expanded frame
results = Tuple{Core.Compiler.InferenceResult, Bool}[ ( frames[i].result,
    frames[i].cached || frames[i].parent !== nothing ) for i in 1:length(frames) ]

valid_worlds = frame.valid_worlds
cached = frame.cached
caller, doopt = results[1]
opt = caller.src
def = opt.linfo.def
nargs = Int(opt.nargs) - 1

# run_passes
ci = opt.src
sv = opt
preserve_coverage = Core.Compiler.coverage_enabled(sv.mod)
ir = Core.Compiler.convert_to_ircode(ci, Core.Compiler.copy_exprargs(ci.code), preserve_coverage, nargs, sv)
ir = Core.Compiler.slot2reg(ir, ci, nargs, sv)
ir = Core.Compiler.compact!(ir)
ir = Core.Compiler.ssa_inlining_pass!(ir, ir.linetable, sv.inlining, ci.propagate_inbounds)
ir = Core.Compiler.compact!(ir)
ir = Core.Compiler.getfield_elim_pass!(ir)
ir = Core.Compiler.adce_pass!(ir)
ir = Compiler.group_quantum_stmts!(ir)
ir = Compiler.propagate_consts_bb!(ir)
ir = Core.Compiler.compact!(ir)
ir = Core.Compiler.compact!(ir)

for i in 1:7
    ir[Core.SSAValue(i)] = nothing
end

Core.Compiler.insert_node!(ir, 12, Nothing, Expr(:test, 4), true)
ir

using ZXCalculus

qc = QCircuit(3)
push_gate!(qc, Val(:Rz), 1, 0.3)
push_gate!(qc, Val(:Ry), 1, 0.3)
push_gate!(qc, Val(:Rz), 1, 0.3)
push_gate!(qc, Val(:H), 1, 0.3)
push_gate!(qc, Val(:CNOT), 3, 2)
push_gate!(qc, Val(:CNOT), 2, 1)



ir = Compiler.convert_to_yaoir(ir)
ir = Compiler.run_zx_passes(ir)
Core.Compiler.compact!(ir.ir)


ir.stmts[2][:inst] = nothing
Core.Compiler.insert_node!(ir, 2, Nothing, Expr(:test))

compact = Core.Compiler.IncrementalCompact(ir)
for _ in compact; end
compact.result[1][:inst] = nothing
ir = Core.Compiler.finish(compact)

for each in compact
    @show each
end

Core.Compiler.compact!(ir)

Core.Compiler.insert_node!(ir, 2, Nothing, Expr(:test))
ic = Core.Compiler.IncrementalCompact(ir)
Core.Compiler.getindex(ic, 3)
Base.iterate(ic::Core.Compiler.IncrementalCompact) = Core.Compiler.iterate(ic)
Base.iterate(ic::Core.Compiler.IncrementalCompact, st) = Core.Compiler.iterate(ic, st)

for _ in ic; end
ir = Core.Compiler.complete(ic)

ir[1]