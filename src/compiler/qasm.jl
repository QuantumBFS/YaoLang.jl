module QASM

export @qasm_str

using RBNF

struct QASMLang end

second((a, b)) = b
second(vec::V) where {V<:AbstractArray} = vec[2]

RBNF.@parser QASMLang begin
    # define ignorances
    ignore{space}

    @grammar
    # define grammars
    mainprogram := ["OPENQASM", ver = real, ';', prog = program]
    program = statement{*}
    statement = (decl | gate | opaque | qop | ifstmt | barrier | inc)
    # stmts
    ifstmt := ["if", '(', l = id, "==", r = nninteger, ')', body = qop]
    opaque := ["opaque", id = id, ['(', [arglist1 = idlist].?, ')'].?, arglist2 = idlist, ';']
    barrier := ["barrier", value = mixedlist]
    decl := [regtype = "qreg" | "creg", id = id, '[', int = nninteger, ']', ';']
    inc := ["include", file = str, ';']
    # gate
    gate := [decl = gatedecl, [goplist = goplist].?, '}']
    gatedecl := ["gate", id = id, ['(', [arglist1 = idlist].?, ')'].?, arglist2 = idlist, '{']

    goplist = (uop | barrier_ids){*}
    barrier_ids := ["barrier", ids = idlist, ';']
    # qop
    qop = (uop | measure | reset)
    reset := ["reset", arg = argument, ';']
    measure := ["measure", arg1 = argument, "->", arg2 = argument, ';']

    uop = (iduop | u | cx)
    iduop := [op = id, ['(', [lst1 = explist].?, ')'].?, lst2 = mixedlist, ';']
    u := ['U', '(', exprs = explist, ')', arg = argument, ';']
    cx := ["CX", arg1 = argument, ',', arg2 = argument, ';']

    idlist = @direct_recur begin
        init = id
        prefix = (recur, (',', id) % second)
    end

    mixeditem := [id = id, ['[', arg = nninteger, ']'].?]
    mixedlist = @direct_recur begin
        init = mixeditem
        prefix = (recur, (',', mixeditem) % second)
    end

    argument := [id = id, ['[', (arg = nninteger), ']'].?]

    explist = @direct_recur begin
        init = exp
        prefix = (recur, (',', exp) % second)
    end

    atom = (real | nninteger | "pi" | id | fnexp) | (['(', exp, ')'] % second) | neg
    fnexp := [fn = fn, '(', arg = exp, ')']
    neg := ['-', value = exp]
    exp = @direct_recur begin
        init = atom
        prefix = (recur, binop, atom)
    end
    fn = ("sin" | "cos" | "tan" | "exp" | "ln" | "sqrt")
    binop = ('+' | '-' | '*' | '/')

    # define tokens
    @token
    id := r"\G[a-z]{1}[A-Za-z0-9_]*"
    real := r"\G([0-9]+\.[0-9]*|[0-9]*\.[0.9]+)([eE][-+]?[0-9]+)?"
    nninteger := r"\G([1-9]+[0-9]*|0)"
    space := r"\G\s+"
    str := @quote ("\"", "\\\"", "\"")
end

function load(src::String)
    ast, _ = RBNF.runparser(mainprogram, RBNF.runlexer(QASMLang, src))
    return ast
end

macro qasm_str(src)
    return qasm_m(__module__, src)
end

function qasm_m(m, src::String)
    return load(src)
end

function qasm_m(m, ex::Expr)
    ex.head === :$ || throw(Meta.ParseError("invalid expression $ex"))
    return load(Base.eval(m, ex.args[1]))
end

end # end module

using IRTools

function scan_registers(ast::QASM.Struct_mainprogram)
    return scan_registers!(
        Dict(:classical => Dict(), :quantum => Dict(), :nqubits => 0, :ncbit => 0),
        ast,
    )
end

function scan_registers!(record::Dict, ast::QASM.Struct_mainprogram)
    for node in ast.prog
        scan_registers!(record, node)
    end
    return record
end

function scan_registers!(record::Dict, ast::QASM.Struct_decl)
    if ast.regtype.str == "qreg"
        record[:quantum][ast.id.str] = (record[:nqubits]+1):(record[:nqubits]+Meta.parse(ast.int.str))
        record[:nqubits] += Meta.parse(ast.int.str)
    else # classical
        record[:classical][ast.id.str] = (record[:ncbits]+1):(record[:ncbits]+Meta.parse(ast.int.str))
        record[:ncbits] += Meta.parse(ast.int.str)
    end
    return record
end
scan_registers!(record::Dict, ast) = record

function YaoIR(m::Module, ast::QASM.Struct_mainprogram, fname = gensym(:qasm))
    prog = ast.prog
    regs = scan_registers(ast)
    qregs = regs[:quantum]
    cregs = regs[:classical]

    ir = IRTools.IR()
    IRTools.return!(ir, nothing)
    push!(ir, Expr(:quantum, :register, :new, gensym(:register)))
    for stmt in prog
        if stmt isa QASM.Struct_iduop
            op = stmt.op.str
            op_locs = extract_locs(stmt.lst2, qregs)
            op_args = extract_args(stmt.lst1)
            yao_stmt = to_YaoLang_stmt(op, op_locs, op_args)
            push!(ir, yao_stmt)
        elseif stmt isa QASM.Struct_u
            ex1 = stmt.exprs[1][1]
            ex2 = stmt.exprs[1][2]
            ex3 = stmt.exprs[2]
            theta = eval(Meta.parse(eval_expr(ex1)))
            phi = eval(Meta.parse(eval_expr(ex2)))
            lambda = eval(Meta.parse(eval_expr(ex3)))
            op_locs = extract_locs(stmt.arg, qregs)
            op_args = (theta, phi, lambda)
            yao_stmts = to_YaoLang_stmt("U", op_locs, op_args)
            for yao_stmt in yao_stmts
                push!(ir, yao_stmt)
            end
        elseif stmt isa QASM.Struct_cx
            locs = [extract_locs(stmt.arg1, qregs)[], extract_locs(stmt.arg2, qregs)[]]
            yao_stmt = to_YaoLang_stmt("CX", locs)
            push!(ir, yao_stmt)
        end
    end

    yaoir = YaoIR(m, fname, Any[], Any[], ir, nothing, false, false)
    update_slots!(yaoir)
    yaoir.pure_quantum = is_pure_quantum(yaoir)
    return yaoir
end

function to_YaoLang_stmt(op, locs, args = nothing)
    if op == "h"
        return Expr(:quantum, :gate, :H, locs[1])
    elseif op == "x"
        return Expr(:quantum, :gate, :X, locs[1])
    elseif op == "y"
        return Expr(:quantum, :gate, :Y, locs[1])
    elseif op == "z"
        return Expr(:quantum, :gate, :Z, locs[1])
    elseif op == "s"
        return Expr(:quantum, :gate, :S, locs[1])
    elseif op == "sdg"
        return Expr(:quantum, :gate, :Sdag, locs[1])
    elseif op == "t"
        return Expr(:quantum, :gate, :T, locs[1])
    elseif op == "tdg"
        return Expr(:quantum, :gate, :Tdag, locs[1])
    elseif op == "rx"
        return Expr(:quantum, :gate, IRTools.xcall(YaoLang, :Rx, args[1]), locs[1])
    elseif op == "ry"
        return Expr(:quantum, :gate, IRTools.xcall(YaoLang, :Ry, args[1]), locs[1])
    elseif op == "rz"
        return Expr(:quantum, :gate, IRTools.xcall(YaoLang, :Rz, args[1]), locs[1])
    elseif op == "cz"
        return Expr(:quantum, :ctrl, :Z, locs[2], locs[1])
    elseif op == "cx"
        return Expr(:quantum, :ctrl, :X, locs[2], locs[1])
    elseif op == "ccx"
        return Expr(:quantum, :ctrl, :X, locs[3], (locs[1], locs[2]))
    elseif op == "U"
        return (
            Expr(:quantum, :gate, IRTools.xcall(YaoLang, :Rz, args[3]), locs[1]),
            Expr(:quantum, :gate, IRTools.xcall(YaoLang, :Ry, args[2]), locs[1]),
            Expr(:quantum, :gate, IRTools.xcall(YaoLang, :Rz, args[1]), locs[1]),
        )
    elseif op == "CX"
        return Expr(:quantum, :ctrl, :X, locs[2], locs[1])
    else
        return
    end
end

function eval_expr(ex)
    s = ""
    if ex isa QASM.Struct_neg
        return "-" * eval_expr(ex.value)
    end
    if ex isa QASM.RBNF.Token
        if ex.str == "pi"
            return s * "π"
        end
        return s * ex.str
    end
    for sub_ex in ex
        s = s * eval_expr(sub_ex)
    end
    return "(" * s * ")"
end

function extract_args(lst)
    # TODO: Analyse the AST
end

function extract_locs(lst, qregs)
    if lst isa QASM.Struct_mixeditem
        if lst.arg isa Nothing
            return collect(qregs[lst.id.str])
        else
            return [qregs[lst.id.str][Meta.parse(lst.arg.str)+1]]
        end
    elseif lst isa QASM.Struct_argument
        return [qregs[lst.id.str][Meta.parse(lst.arg.str)+1]]
    else
        return [extract_locs(lst[1], qregs); extract_locs(lst[2], qregs)]
    end
end
