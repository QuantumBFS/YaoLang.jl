using RBNF
using RBNF: Token

abstract type TargetQASM end
# toplevel QASM
struct TargetQASMTopLevel <: TargetQASM end

# QASM gate decl
struct TargetQASMGate <: TargetQASM end

struct RegMap
    cbits::Dict{Any,Tuple{String,Int}}
    regs_to_locs::Dict{Int,Vector{Int}}
    locs_to_reg_addr::Dict{Int,Tuple{Int,Int}}
end

function RegMap(target, ci::CodeInfo)
    locs_to_regs = Dict{Int,Int}()
    # ssa/slot => (name, size)
    cbits = Dict{Any,Tuple{String,Int}}()

    for (v, stmt) in enumerate(ci.code)
        if stmt isa ReturnNode && isdefined(stmt, :val) && stmt.val isa SSAValue
            ret = ci.code[stmt.val.id]
            if ret isa Expr && ret.head === :new && ret.args[1] <: NamedTuple
                cnames = ret.args[1].parameters[1]
                for i in 1:length(cnames)
                    x = ret.args[i+1]::SSAValue
                    _, size = cbits[x.id]
                    cbits[x.id] = (string(cnames[i]), size)
                end
            end
        end

        is_quantum_statement(stmt) || continue
        qt = quantum_stmt_type(stmt)

        if qt === :measure
            if stmt.head === :(=)
                slot = stmt.args[1]::SlotNumber
                measure_ex = stmt.args[2]
                locs = obtain_ssa_const(measure_ex.args[2], ci)::Locations
                name = string(ci.slotnames[slot.id])
                cbits[slot] = (name, length(locs))
            else
                locs = obtain_ssa_const(stmt.args[2], ci)::Locations
                name = creg_name(v)
                cbits[v] = (name, length(locs))
            end
            # allocate new register for measurements
            allocate_new_qreg!(locs_to_regs, locs)
        elseif qt === :barrier
            locs = obtain_ssa_const(stmt.args[2], ci)::Locations
            record_locations!(target, locs_to_regs, locs)
        elseif qt === :gate
            if stmt.head === :invoke
                locs = obtain_ssa_const(stmt.args[4], ci)::Locations
            elseif stmt.head === :call
                locs = obtain_ssa_const(stmt.args[3], ci)::Locations
            end
            record_locations!(target, locs_to_regs, locs)
        elseif qt === :ctrl
            if stmt.head === :invoke
                locs = obtain_ssa_const(stmt.args[4], ci)::Locations
                ctrl = obtain_ssa_const(stmt.args[5], ci)::CtrlLocations
            elseif stmt.head === :call
                locs = obtain_ssa_const(stmt.args[3], ci)::Locations
                ctrl = obtain_ssa_const(stmt.args[4], ci)::CtrlLocations
            end

            record_locations!(target, locs_to_regs, locs)
            record_locations!(target, locs_to_regs, ctrl.storage)
        end
    end

    regs_to_locs = Dict{Int,Vector{Int}}()
    for (k, r) in locs_to_regs
        locs = get!(regs_to_locs, r, Int[])
        push!(locs, k)
    end

    # loc => reg, addr
    locs_to_reg_addr = Dict{Int,Tuple{Int,Int}}()
    for (r, locs) in regs_to_locs
        sort!(locs)
        for (k, loc) in enumerate(locs)
            locs_to_reg_addr[loc] = (r, k - 1)
        end
    end

    return RegMap(cbits, regs_to_locs, locs_to_reg_addr)
end

mutable struct QASMCodeGenState
    pc::Int
    stmt::Any
    regmap::RegMap

    name::Any
    ssa_cname_map::Any
end

function QASMCodeGenState(target::TargetQASMTopLevel, ci::CodeInfo)
    return QASMCodeGenState(0, nothing, RegMap(target, ci), nothing, nothing)
end

function QASMCodeGenState(target::TargetQASMGate, ci::CodeInfo)
    name, ssa_cname_map = scan_cargs(ci)
    return QASMCodeGenState(0, nothing, RegMap(target, ci), name, ssa_cname_map)
end

# NOTE:
# we can only transform routines satisfy the following:
# 1. locations are constants, in Julia we can calculate locations dynamically
#    but this is not allowed in QASM
# 2. do not contain classical functions calls except for 
# fn = ("sin" | "cos" | "tan" | "exp" | "ln" | "sqrt")
# binop = ('+' | '-' | '*' | '/')
# since QASM's if is actually a GotoIfNot node
# we don't reloop the SSA here, but assume the CodeInfo should
# not contain any GotoNode, which is incompatible with QASM

function allocate_new_qreg!(locs_to_regs, locs)
    if length(locs) == 1
        raw = locs.storage
        get!(locs_to_regs, raw, 1)
    else
        k_reg = maximum(get(locs_to_regs, each, 1) for each in locs) + 1

        for each in locs
            locs_to_regs[each] = k_reg
        end
    end
end

function record_locations!(::TargetQASMTopLevel, locs_to_regs::Dict{Int,Int}, locs::Locations)
    for each in locs
        get!(locs_to_regs, each, 1)
    end
    return locs_to_regs
end

function record_locations!(::TargetQASMGate, locs_to_regs::Dict{Int,Int}, locs::Locations)
    for each in locs
        if !haskey(locs_to_regs, each)
            locs_to_regs[each] = length(keys(locs_to_regs)) + 1
        end
    end
    return locs_to_regs
end

function obtain_ssa_const(@nospecialize(x), ci::CodeInfo)
    if x isa SSAValue
        x = ci.ssavaluetypes[x.id]::Const
        return x.val
    else
        return x
    end
end

function obtain_gate_stmt(@nospecialize(x), ci::CodeInfo)
    if x isa SSAValue
        stmt = ci.code[x.id]
        gt = ci.ssavaluetypes[x.id]
        if gt isa Const
            return gt.val, widenconst(gt)
        else
            return stmt, widenconst(gt)
        end
    elseif x isa Const
        return x.val, typeof(x.val)
    elseif x isa GlobalRef
        gate = Core.Compiler.abstract_eval_global(x.mod, x.name)
        # TODO: move this to parsing time
        if gate === Any
            throw(UndefVarError(x.name))
        end
        return gate.val, widenconst(gate)
    else
        # special value
        return x, typeof(x)
    end
end

qreg_name(idx::Int) = string("qreg_", idx)
creg_name(idx::Int) = string("creg_", idx)

function codegen(target::TargetQASMTopLevel, ci::CodeInfo)
    st = QASMCodeGenState(target, ci)
    prog = Any[]

    # allocate registers
    for (k, locs) in st.regmap.regs_to_locs
        push!(
            prog,
            QASM.Parse.RegDecl(
                Token{:reserved}("qreg"),
                # we probably want to have a better strategy
                # to avoid potential name conflicts
                Token{:id}(qreg_name(k)),
                Token{:int}(string(length(locs))),
            ),
        )
    end

    for (_, (name, size)) in st.regmap.cbits
        pushfirst!(
            prog,
            QASM.Parse.RegDecl(Token{:reserved}("creg"), Token{:id}(name), Token{:int}(string(size))),
        )
    end

    # NOTE: QASM compatible code won't have
    # branches except simple `if x == y` statement
    # as a result, we don't need program counter
    # here, just execute directly
    st.pc = 1
    while st.pc <= length(ci.code)
        inst = nothing
        st.stmt = ci.code[st.pc]
        if st.stmt isa Expr && is_quantum_statement(st.stmt)
            inst = codegen_stmt(target, ci, st)
            st.pc += 1
        elseif st.stmt isa GotoIfNot
            inst = codegen_ifnot(target, ci, st)
        else
            st.pc += 1
        end
        isnothing(inst) || push!(prog, inst)
    end
    return QASM.Parse.MainProgram(v"2.0", prog)
end

function gate_name(spec)
    name = string(routine_name(spec))
    if '#' in name
        name = "__julia_lambda" * replace(name, "#" => "_")
    end
    return name
end

function scan_cargs(ci::CodeInfo)
    v = findfirst(ci.code) do stmt
        @match stmt begin
            Expr(:call, getfield, Argument(2), :variables) => true
            Expr(:call, GlobalRef(Base, :getfield), SlotNumber(2), QuoteNode(:variables)) => true
            _ => false
        end
    end
    # none of the classical parameters are used
    isnothing(v) && return

    @assert !isnothing(ci.parent)
    spec = ci.parent.specTypes.parameters[2]
    tt = Tuple{spec.parameters[1],spec.parameters[2].parameters...}
    ms = methods(routine_stub, tt)
    length(ms) == 1 || error("ambiguous method call")
    method = first(ms)
    carg_names = split(chop(method.slot_syms), '\0')[3:end]
    cargs = Dict{Int,String}()

    for (v, stmt) in enumerate(ci.code)
        name = @match stmt begin
            Expr(:call, getfield, SSAValue(v), k, true) => carg_names[k]
            Expr(:(=), SlotNumber(slot), Expr(:call, GlobalRef(Base, :getindex), SSAValue(v), i)) => string(ci.slotnames[slot])
            _ => nothing
        end

        isnothing(name) && continue
        cargs[v] = name
    end

    return gate_name(spec), cargs
end

function codegen(target::TargetQASMGate, ci::CodeInfo)
    st = QASMCodeGenState(target, ci)
    qargs = Any[Token{:id}(qreg_name(k)) for (k, _) in st.regmap.regs_to_locs]
    cargs = Any[Token{:id}(cname) for (_, cname) in st.ssa_cname_map]
    decl = QASM.Parse.GateDecl(Token{:id}(st.name), cargs, qargs)

    prog = Any[]

    # NOTE: QASM compatible code won't have
    # branches except simple `if x == y` statement
    # as a result, we don't need program counter
    # here, just execute directly
    st.pc = 1
    while st.pc <= length(ci.code)
        inst = nothing
        st.stmt = ci.code[st.pc]
        if st.stmt isa Expr && is_quantum_statement(st.stmt)
            inst = codegen_stmt(target, ci, st)
            st.pc += 1
        elseif st.stmt isa GotoIfNot
            inst = codegen_ifnot(target, ci, st)
        else
            st.pc += 1
        end
        isnothing(inst) || push!(prog, inst)
    end
    return QASM.Parse.Gate(decl, prog)
end

function _qasm_name(x)
    if x in [:X, :Y, :Z, :H, :T, :Rx, :Ry, :Rz]
        return lowercase(string(x))
    else
        return string(x)
    end
end

function codegen_stmt(target::TargetQASM, ci::CodeInfo, st::QASMCodeGenState)
    qt = quantum_stmt_type(st.stmt)
    if qt === :gate
        inst = codegen_gate(target, ci, st)
    elseif qt === :ctrl
        inst = codegen_ctrl(target, ci, st)
    elseif qt === :measure
        inst = codegen_measure(target, ci, st)
    elseif qt === :barrier
        inst = codegen_barrier(target, ci, st)
    else
        error("incompatible statement for QASM: $(st.stmt)")
    end
    return inst
end

function index_qreg(r::Int, addr::Int, regmap::RegMap)
    # do not index qreg if it only has one qubit
    if length(regmap.regs_to_locs[r]) == 1 && addr == 0
        return QASM.Parse.Bit(qreg_name(r))
    else
        return QASM.Parse.Bit(qreg_name(r), addr)
    end
end

function codegen_gate(target::TargetQASM, ci::CodeInfo, st::QASMCodeGenState)
    # NOTE: QASM compatible code should have constant location
    if st.stmt.head === :invoke
        gate, gt = obtain_gate_stmt(st.stmt.args[3], ci)
        locs = obtain_ssa_const(st.stmt.args[4], ci)
    elseif st.stmt.head === :call
        gate, gt = obtain_gate_stmt(st.stmt.args[2], ci)
        locs = obtain_ssa_const(st.stmt.args[3], ci)
    end

    gt <: IntrinsicSpec || gt <: RoutineSpec || error("invalid gate type: $gate::$gt")
    name = gate_name(gt)
    cargs = codegen_cargs(target, ci, gate, st)
    qargs = Any[]
    for k in locs
        r, addr = st.regmap.locs_to_reg_addr[k]
        push!(qargs, index_qreg(r, addr, st.regmap))
    end

    return QASM.Parse.Instruction(Token{:id}(_qasm_name(name)), cargs, qargs)
end

function codegen_cargs(::TargetQASMTopLevel, ::CodeInfo, @nospecialize(gate), ::QASMCodeGenState)
    if gate isa RoutineSpec || gate isa IntrinsicSpec
        # constant parameters
        # non-constant parameters in toplevel is not allowed
        return Any[Token{:unnamed}(string(x)) for x in gate.variables]
    else
        error("classical variable in toplevel is not allowed in QASM")
    end
end

function codegen_cargs(
    target::TargetQASMGate,
    ci::CodeInfo,
    @nospecialize(gate),
    st::QASMCodeGenState,
)
    if gate isa Expr
        # IntrinsicSpec/RoutineSpec take a tuple
        # so we need to find the actual variables
        if gate.head === :new
            variables = gate.args[2]::SSAValue
            var_tuple = ci.code[variables.id]::Expr
            vars = var_tuple.args[2:end]
        elseif gate.head === :call # normal constructor call
            vars = gate.args[2:end]
        end

        cargs = Any[]
        for each in vars
            push!(cargs, codegen_exp(target, ci, each, st))
        end
        return cargs
    elseif gate isa RoutineSpec || gate isa IntrinsicSpec
        # constant parameters
        # non-constant parameters in toplevel is not allowed
        return Any[codegen_exp(target, ci, x, st) for x in gate.variables]
    else
        error("invalid instruction: $gate")
    end
end

# NOTE: toplevel program does not allow non-constant
# classical function calls
function codegen_exp(target::TargetQASM, ci::CodeInfo, @nospecialize(stmt), st::QASMCodeGenState)
    if stmt isa SlotNumber
        return Token{:id}(string(ci.slotnames[stmt.id]))
    end

    if stmt isa SSAValue
        if haskey(st.ssa_cname_map, stmt.id)
            return Token{:id}(st.ssa_cname_map[stmt.id])
        else
            return codegen_exp(target, ci, ci.code[stmt.id], st)
        end
    end

    if stmt isa Int
        return Token{:int}(string(stmt))
    elseif stmt isa AbstractFloat
        return Token{:float64}(string(Float64(stmt)))
    end

    stmt isa Expr || error("classical expression for QASM cannot contain control flow, got $stmt")

    if stmt.head === :call
        if stmt.args[1] isa GlobalRef
            mod, fn_name = stmt.args[1].mod, stmt.args[1].name
            fn = Core.Compiler.abstract_eval_global(mod, fn_name).val
            fn === Any && error("cannot determine function call: $stmt")
        else
            fn = stmt.args[1]
            fn_name = nameof(fn)
        end
        args = stmt.args[2:end]
    elseif stmt.head === :invoke
        fn = stmt.args[2]
        fn_name = stmt.args[1].def.name
        args = stmt.args[3:end]
    else
        error("incompatible expression for QASM: $stmt")
    end

    if fn === Core.Intrinsics.neg_float
        fn_name = :(-)
    end

    if length(args) == 1
        return QASM.Parse.FnExp(fn_name, codegen_exp(target, ci, args[1], st))
    elseif length(args) == 2 # binop
        if (fn === +) || (fn === Core.Intrinsics.add_float) || (fn === Core.Intrinsics.add_int)
            token = Token{:reserved}("+")
        elseif (fn === -) || (fn === Core.Intrinsics.sub_float) || (fn === Core.Intrinsics.sub_int)
            token = Token{:reserved}("-")
        elseif (fn === *) || (fn === Core.Intrinsics.mul_float) || (fn === Core.Intrinsics.mul_int)
            token = Token{:reserved}("*")
        elseif (fn === /) || (fn === Core.Intrinsics.div_float)
            token = Token{:reserved}("/")
        else
            error("incompatible binop for QASM: $fn")
            # token = Token{:reserved}(fn_name)
        end
        return (codegen_exp(target, ci, args[1], st), token, codegen_exp(target, ci, args[2], st))
    else
        error("incompatible function call for QASM: $stmt")
    end
end

function codegen_ctrl(::TargetQASM, ci::CodeInfo, st::QASMCodeGenState)
    # NOTE: QASM compatible code should have constant location
    # QASM compatible code should only contain control X gate
    # as control gates, for other control gates, it should be
    # either decomposed or error, so we will assume the gate
    # is a constant here.
    if st.stmt.head === :invoke
        gate = obtain_ssa_const(st.stmt.args[3], ci)
        locs = obtain_ssa_const(st.stmt.args[4], ci)::Locations
        ctrl = obtain_ssa_const(st.stmt.args[5], ci)::CtrlLocations
    elseif st.stmt.head === :call
        gate = obtain_ssa_const(st.stmt.args[2], ci)
        locs = obtain_ssa_const(st.stmt.args[3], ci)::Locations
        ctrl = obtain_ssa_const(st.stmt.args[4], ci)::CtrlLocations
    end

    if gate === Gate.X && length(ctrl) == 1 && length(locs) == 1
        ctrl.configs[1] || error("inverse ctrl is not supported in QASM backend yet")
        qargs = Any[]
        r, addr = st.regmap.locs_to_reg_addr[ctrl.storage.storage]
        push!(qargs, index_qreg(r, addr, st.regmap))
        r, addr = st.regmap.locs_to_reg_addr[locs.storage]
        push!(qargs, index_qreg(r, addr, st.regmap))
        return QASM.Parse.Instruction(Token{:id}("CX"), Any[], qargs)
    else
        error("invalid control statement for QASM backend, got: $(st.stmt)")
    end
end

function codegen_measure(::TargetQASM, ci::CodeInfo, st::QASMCodeGenState)
    if st.stmt.head === :(=)
        slot = st.stmt.args[1]::SlotNumber
        measure_ex = st.stmt.args[2]
        locs = obtain_ssa_const(measure_ex.args[2], ci)::Locations
        cname, _ = st.regmap.cbits[slot]
    else
        locs = obtain_ssa_const(st.stmt.args[2], ci)::Locations
        cname, _ = st.regmap.cbits[st.pc]
    end

    r, addr = st.regmap.locs_to_reg_addr[first(locs)]

    if length(locs) == 1
        qarg = index_qreg(r, addr, st.regmap)
        return QASM.Parse.Measure(qarg, QASM.Parse.Bit(cname, 0))
    else
        # by construction the registers are the same
        # and is exactly of size length(locs)
        return QASM.Parse.Measure(QASM.Parse.Bit(qreg_name(r)), QASM.Parse.Bit(cname, length(locs)))
    end
end

function codegen_barrier(::TargetQASM, ci::CodeInfo, st::QASMCodeGenState)
    locs = obtain_ssa_const(st.stmt.args[2], ci)::Locations

    qargs = Any[]
    args = Dict{Int,Vector{Int}}()

    for each in locs
        r, addr = st.regmap.locs_to_reg_addr[each]
        addrs = get!(args, r, Int[])
        push!(addrs, addr)
    end

    for (r, addrs) in args
        # do not index qreg explicitly if barrier size
        # is the same with register size
        if length(st.regmap.regs_to_locs[r]) == length(addrs)
            push!(qargs, QASM.Parse.Bit(qreg_name(r)))
        else
            for addr in addrs
                push!(qargs, QASM.Parse.Bit(qreg_name(r), addr))
            end
        end
    end
    return QASM.Parse.Barrier(qargs)
end

function codegen_ifnot(target::TargetQASM, ci::CodeInfo, st::QASMCodeGenState)
    cond = st.stmt.cond::SSAValue
    cond_stmt = ci.code[st.stmt.cond.id]
    # cond_stmt should be Expr(:(==), creg, b)

    creg = cond_stmt.args[2]
    if creg isa SlotNumber
        cname = ci.slotnames[creg.id]
    elseif creg isa SSAValue
        # NOTE:
        # in QASM, this will only be assigned once
        # from measure statement
        # TODO: we might want to make this more general
        # by having an intermediate type MeasureResult
        cname = creg_name(creg.id)
    end

    # move this to validation
    cond_stmt.args[3] isa Int || error("right hand condition must be constant Int for QASM")
    right = cond_stmt.args[3]

    # find the first quantum stmt after goto
    pc′ = st.pc + 1
    local stmt′
    while pc′ <= length(ci.code)
        stmt′ = ci.code[pc′]
        if stmt′ isa Expr
            is_quantum_statement(stmt′)
            break
        else
            # NOTE:
            # we can allow some constant statements
            # but not control flows or other nodes
            error("unexpected statement: $stmt′")
        end
        pc′ += 1
    end

    st.pc = pc′
    st.stmt = stmt′
    body = codegen_stmt(target, ci, st)
    return QASM.Parse.IfStmt(Token{:id}(cname), Token{:int}(string(right)), body)
end

function validate(target::TargetQASM, ci::CodeInfo)
    for (v, stmt) in enumerate(ci)
        if is_quantum_statement(stmt)
        elseif stmt isa GotoIfNot
        elseif stmt isa Expr
            if stmt.head === :call
                validate_call(target, ci, stmt)
            end
        end
        stmt_type = ci.ssavaluetypes[v]

    end
end

# NOTE:
# valid function in QASM compatible program:
# basic math functions:
# fn = ("sin" | "cos" | "tan" | "exp" | "ln" | "sqrt")
# binop = ('+' | '-' | '*' | '/')
function validate_call(::TargetQASM, ci::CodeInfo, stmt::Expr)
    if stmt.args[1] isa GlobalRef
        stmt.mod === Base
        stmt.name in []
    end
end
