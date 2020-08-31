using RBNF

struct QASMLang end

second((a, b)) = b
second(vec::V) where V <: AbstractArray = vec[2]

RBNF.@parser QASMLang begin
    # define ignorances
    ignore{space}

    @grammar
    # define grammars
    mainprogram := ["OPENQASM", ver=real, ';', prog=program]
    program     = statement{*}
    statement   = (decl | gate | opaque | qop | ifstmt | barrier)
    # stmts
    ifstmt      := ["if", '(', l=id, "==", r=nninteger, ')', body=qop]
    opaque      := ["opaque", id=id, ['(', [arglist1=idlist].?, ')'].? , arglist2=idlist, ';']
    barrier     := ["barrier", value=mixedlist]
    decl        := [regtype="qreg" | "creg", id=id, '[', int=nninteger, ']', ';']

    # gate
    gate        := [decl=gatedecl, [goplist=goplist].?, '}']
    gatedecl    := ["gate", id=id, ['(', [arglist1=idlist].?, ')'].?, arglist2=idlist, '{']

    goplist     = (uop |barrier_ids){*}
    barrier_ids := ["barrier", ids=idlist, ';']
    # qop
    qop         = (uop | measure | reset)
    reset       := ["reset", arg=argument, ';']
    measure     := ["measure", arg1=argument, "->", arg2=argument, ';']

    uop         = (iduop | u | cx)
    iduop      := [op=id, ['(', [lst1=explist].?, ')'].?, lst2=mixedlist, ';']
    u          := ['U', '(', exprs=explist, ')', arg=argument, ';']
    cx         := ["CX", arg1=argument, ',', arg2=argument, ';']

    idlist     = @direct_recur begin
        init = id
        prefix = (recur, (',', id) % second)
    end

    mixeditem   := [id=id, ['[', arg=nninteger, ']'].?]
    mixedlist   = @direct_recur begin
        init = mixeditem
        prefix = (recur, (',', mixeditem) % second)
    end

    argument   := [id=id, ['[', (arg=nninteger), ']'].?]

    explist    = @direct_recur begin
        init = exp
        prefix = (recur,  (',', exp) % second)
    end

    atom       = (real | nninteger | "pi" | id | fnexp) | (['(', exp, ')'] % second) | neg
    fnexp      := [fn=fn, '(', arg=exp, ')']
    neg        := ['-', value=exp]
    exp        = @direct_recur begin
        init = atom
        prefix = (recur, binop, atom)
    end
    fn         = ("sin" | "cos" | "tan" | "exp" | "ln" | "sqrt")
    binop      = ('+' | '-' | '*' | '/')

    # define tokens
    @token
    id        := r"\G[a-z]{1}[A-Za-z0-9_]*"
    real      := r"\G([0-9]+\.[0-9]*|[0-9]*\.[0.9]+)([eE][-+]?[0-9]+)?"
    nninteger := r"\G([1-9]+[0-9]*|0)"
    space     := r"\G\s+"
end

function YaoIR(::Val{:qasm}, m::Module, src::String, func_name::Symbol)
    ast, ctx = RBNF.runparser(mainprogram, RBNF.runlexer(QASMLang, src))
    prog = ast.prog
    qregs = extract_qreg(prog)
    yaolang_prog = "function $func_name()\n"
    for stmt in prog
        if stmt isa Struct_iduop
            op = stmt.op.str
            op_args = extract_args(stmt.lst1)
            op_locs = extract_locs(stmt.lst2, qregs)
            yaolang_prog *= to_YaoLang_prog(op, op_locs, op_args)
        elseif stmt isa Struct_u
            ex1 = stmt.exprs[1][1]
            ex2 = stmt.exprs[1][2]
            ex3 = stmt.exprs[2]
            theta = eval(Meta.parse(eval_expr(ex1)))
            phi = eval(Meta.parse(eval_expr(ex2)))
            lambda = eval(Meta.parse(eval_expr(ex3)))
            op_locs = extract_locs(stmt.arg, qregs)
            op_args = [theta, phi, lambda]
            yaolang_prog *= to_YaoLang_prog("U", op_locs, op_args)
        elseif stmt isa Struct_cx
            op_locs = [extract_locs(stmt.arg1, qregs)[], extract_locs(stmt.arg2, qregs)[]]
            yaolang_prog *= to_YaoLang_prog("CX", op_locs)
        end
    end
    yaolang_prog *= "end"
    ex = Meta.parse(yaolang_prog)
    return YaoIR(m, ex)
end

function to_YaoLang_prog(op, locs, args = nothing)
    if op == "h"
        return "    $(locs[]) => H\n"
    elseif op == "x"
        return "    $(locs[]) => X\n"
    elseif op == "y"
        return "    $(locs[]) => Y\n"
    elseif op == "z"
        return "    $(locs[]) => Z\n"
    elseif op == "s"
        return "    $(locs[]) => S\n"
    elseif op == "sdg"
        return "    $(locs[]) => shift(\$(3*π/2))\n"
    elseif op == "t"
        return "    $(locs[]) => T\n"
    elseif op == "tdg"
        return "    $(locs[]) => shift(\$(7*π/4))\n"
    elseif op == "rx"
        return "    $(locs[]) => Rx($(args[]))\n"
    elseif op == "ry"
        return "    $(locs[]) => Ry($(args[]))\n"
    elseif op == "rz"
        return "    $(locs[]) => Rz($(args[]))\n"
    elseif op == "cz"
        return "    @ctrl $(locs[1]) $(locs[2]) => Z\n"
    elseif op == "cx"
        return "    @ctrl $(locs[1]) $(locs[2]) => X\n"
    elseif op == "ccx"
        return "    @ctrl \$($(locs[1]), $(locs[2])) $(locs[3]) => X\n"
    elseif op == "U"
        return "    $(locs[]) => Rz($(args[3]))\n    $(locs[]) => Ry($(args[2]))\n    $(locs[]) => Rz($(args[1]))\n"
    elseif op == "CX"
        return "    @ctrl $(locs[1]) $(locs[2]) => X\n"
    else
        return ""
    end
end

function eval_expr(ex)
    s = ""
    if ex isa Struct_neg
        return "-" * eval_expr(ex.value)
    end
    if ex isa RBNF.Token
        if ex.str == "pi"
            return s*"π"
        end
        return s*ex.str
    end
    for sub_ex in ex
        s = s*eval_expr(sub_ex)
    end
    return "("*s*")"
end

function extract_args(lst)
    # TODO: Analyse the AST
end

function extract_locs(lst, qregs)
    if lst isa Struct_mixeditem
        if lst.arg isa Nothing
            return collect(qregs[lst.id.str])
        else
            return [qregs[lst.id.str][Meta.parse(lst.arg.str)+1]]
        end
    elseif lst isa Struct_argument
        return [qregs[lst.id.str][Meta.parse(lst.arg.str)+1]]
    else
        return [extract_locs(lst[1], qregs); extract_locs(lst[2], qregs)]
    end
end

function extract_qreg(prog)
    qregs = Dict{String, UnitRange{Int}}()
    nqubits = 1
    for stmt in prog
        if stmt isa Struct_decl && stmt.regtype.str == "qreg"
            qreg_id = stmt.id.str
            qreg_nqubit = Meta.parse(stmt.int.str)
            qregs[qreg_id] = nqubits:(nqubits + qreg_nqubit - 1)
            nqubits += qreg_nqubit
        end
    end
    return qregs
end
