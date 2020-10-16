module QASM

export @qasm_str

using RBNF
using ExprTools
using ..YaoLang

module Parse

using RBNF

struct QASMLang end

second((a, b)) = b
second(vec::V) where {V<:AbstractArray} = vec[2]
# NOTE: U(sin(pi/4), sin(pi/8))
# is not corrently parsed
RBNF.@parser QASMLang begin
    # define ignorances
    ignore{space}
    reserved = ["include"]

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
    u := ['U', '(', theta1 = exp, ',', theta2 = exp, ',', theta3 = exp, ')', arg = argument, ';']
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

end # module Parse

mutable struct VirtualRegister
    type::Symbol
    address::UnitRange{Int}
end

mutable struct RegisterRecord
    map::Dict{String, VirtualRegister}
    nqubits::Int
    ncbits::Int
end

Base.getindex(x::RegisterRecord, key) = x.map[key]
Base.getindex(x::VirtualRegister, xs...) = x.address[xs...]

RegisterRecord() = RegisterRecord(Dict{String, UnitRange{Int}}(), 0, 0)

print_qasm(ast) = print_qasm(stdout, ast)

print_qasm(io::IO, ::Nothing) = nothing

function print_qasm(io::IO, ast::Parse.Struct_mainprogram)
    printstyled(io, "OPENQASM "; bold=true)
    printstyled(io, ast.ver.str; color=:yellow)
    println(io)

    for k in 1:length(ast.prog)
        print_qasm(io, ast.prog[k])
        
        if k != length(ast.prog)
            println(io)
        end
    end
end

function print_qasm(io::IO, stmt::Parse.Struct_decl)
    printstyled(io, stmt.regtype.str; color=:light_blue)
    print(io, " ")
    printstyled(io, stmt.id.str; color=:light_cyan)
    print(io, "[")
    printstyled(io, stmt.int.str; color=:green)
    print(io, "];")
end

function print_qasm(io::IO, stmt::Parse.Struct_inc)
    printstyled(io, "include "; color=:light_blue)
    println(io, stmt.file.str, ";")
end

function print_qasm(io::IO, stmt::Parse.Struct_iduop)
    printstyled(io, stmt.op.str; color=:light_magenta)

    if !isnothing(stmt.lst1)
        print(io, "(")
        print_qasm(io, stmt.lst1)
        print(io, ")")
    end
    print(io, " ")
    print_qasm(io, stmt.lst2)
    print(io, ";")
end

function print_qasm(io::IO, stmt::Parse.Struct_u)
    printstyled(io, "U"; color=:light_magenta)
    print(io, "(")
    print_exp(io, stmt.theta1)
    print(io, ", ")
    print_exp(io, stmt.theta2)
    print(io, ", ")
    print_exp(io, stmt.theta3)
    print(io, ") ")
    print_qasm(io, stmt.arg)
    print(io, ";")
end

function print_qasm(io::IO, stmt::Parse.Struct_cx)
    printstyled(io, "CX "; color=:light_magenta)
    print_qasm(io::IO, stmt.arg1)
    print(io, ", ")
    print_qasm(io::IO, stmt.arg2)
    print(io, ";")
end

function print_qasm(io::IO, stmt::Parse.Struct_argument)
    printstyled(io, stmt.id.str; color=:light_cyan)
    if !isnothing(stmt.arg)
        print(io, "[")
        print_exp(io, stmt.arg)
        print(io, "]")
    end
end

function print_qasm(io::IO, stmt::Parse.Struct_gate)
    printstyled(io, "gate "; color=:light_blue)
    printstyled(io, stmt.decl.id.str; color=:light_magenta)
    if !isnothing(stmt.decl.arglist1)
        print(io, "(")
        print_qasm(io, stmt.decl.arglist1)
        print(io, ")")
    end

    print(io, " ")
    print_qasm(stmt.decl.arglist2)
    println(io, " {")
    for k in 1:length(stmt.goplist)
        print(io, " "^2)
        print_qasm(io, stmt.goplist[k])
        println(io)
    end
    println(io, "}")
end

print_qasm(io::IO, stmt::RBNF.Token) = print_exp(io, stmt)

function print_qasm(io::IO, stmt::Parse.Struct_mixeditem)
    print_qasm(io, stmt.id)

    if !isnothing(stmt.arg)
        print(io, "[")
        print_exp(io, stmt.arg)
        print(io, "]")    
    end
end

function print_exp(io::IO, stmt::Tuple)
    for each in stmt
        print_exp(io, each)
    end
end

print_exp(io::IO, stmt::RBNF.Token) = print(io, stmt.str)

function print_exp(io::IO, stmt::RBNF.Token{:id})
    printstyled(io, stmt.str; color=:light_cyan)
end

function print_exp(io::IO, stmt::RBNF.Token{:real})
    printstyled(io, stmt.str; color=:green)
end

function print_exp(io::IO, stmt::RBNF.Token{:nninteger})
    printstyled(io, stmt.str; color=:green)
end

function print_exp(io::IO, stmt::Parse.Struct_neg)
    print(io, "-")
    print_exp(io, stmt.value)
end

function print_qasm(io::IO, stmt::Tuple)
    for (i, each) in enumerate(stmt)
        print_qasm(io, each)
        if i != lastindex(stmt)
            print(io, ", ")
        end
    end
end

Base.show(io::IO, x::Parse.Struct_mainprogram) = print_qasm(io, x)

function parse(m::Module, source::String)
    ast = Parse.load(source)
    return parse(m, ast)
end

function parse(m::Module, ast::Parse.Struct_mainprogram)
    # check sure minimum compatibility
    @assert v"2.0.0" <= parse_version(ast.ver) < v"3.0.0"

    code = Expr(:block)
    body = Expr(:block)
    routines = []
    record = scan_registers(ast)

    for stmt in ast.prog
        if stmt isa Parse.Struct_decl
            continue
        elseif stmt isa Parse.Struct_gate
            push!(routines, parse(m, stmt))
        elseif stmt isa Parse.Struct_inc
            push!(code.args, parse(m, read(stmt.file.str[2:end-1], String)))
        else
            ex = parse(m, record, stmt)
            if !isnothing(ex)
                push!(body.args, ex)
            end
        end
    end

    # routines
    for each in routines
        push!(code.args, each)
    end

    # main program
    def = Dict{Symbol, Any}(
        :name => gensym(:qasm),
        :body => body,
    )
    push!(code.args, YaoLang.Compiler.device_def(def))
    return code
end

function parse(m::Module, stmt::Parse.Struct_gate)
    name = Symbol(stmt.decl.id.str)
    args = parse_gate_args(stmt.decl.arglist1)
    record = parse_gate_registers(stmt.decl.arglist2)
    body = Expr(:block)

    for each in stmt.goplist
        push!(body.args, parse(m, record, each))
    end
    
    def = Dict(:name=>name, :args=>args, :body=>body)
    return YaoLang.Compiler.device_def(def)
end

mutable struct GateRegisterRecord
    map::Dict
    total::Int
end

GateRegisterRecord() = GateRegisterRecord(Dict(), 0)

function parse_gate_registers(stmt)
    return parse_gate_registers!(GateRegisterRecord(), stmt)
end

function parse_gate_registers!(record, stmt::Tuple)
    for each in stmt
        parse_gate_registers!(record, each)
    end
    return record
end

function parse_gate_registers!(record::GateRegisterRecord, stmt::RBNF.Token)
    haskey(record.map, stmt.str) && throw(Meta.ParseError("duplicated register name $(stmt.str)"))
    record.total += 1
    record.map[stmt.str] = record.total
    return record
end

parse_gate_args(stmt) = parse_gate_args!(Any[], stmt)

function parse_gate_args!(args::Vector, stmt::Tuple)
    for each in stmt
        parse_gate_args!(args, each)
    end
    return args
end

function parse_gate_args!(args::Vector, stmt::RBNF.Token)
    push!(args, Symbol(stmt.str))
    return args
end

parse_gate_args!(args::Vector, ::Nothing) = args

xgate(gate, locs) = Expr(:call, GlobalRef(YaoLang.Compiler.Semantic, :gate), gate, locs)
xctrl(gate, locs, ctrl) = Expr(:call, GlobalRef(YaoLang.Compiler.Semantic, :ctrl), gate, locs, ctrl)

function parse(m::Module, record, stmt::Parse.Struct_u)
    code = Expr(:block)
    locs = parse(m, record, stmt.arg)
    push!(code.args,
        xgate(Expr(:call, GlobalRef(YaoLang, :Rz), parse_exp(stmt.theta1)), locs))
    push!(code.args,
        xgate(Expr(:call, GlobalRef(YaoLang, :Ry), parse_exp(stmt.theta2)), locs))
    push!(code.args,
        xgate(Expr(:call, GlobalRef(YaoLang, :Rz), parse_exp(stmt.theta3)), locs))
    return code
end

function parse(m::Module, record, stmt::Parse.Struct_cx)
    return xctrl(GlobalRef(YaoLang, :X), parse(m, record, stmt.arg2), CtrlLocations(parse(m, record, stmt.arg1)))
end

function parse(m::Module, record, stmt::Parse.Struct_iduop)
    op = stmt.op.str
    # NOTE: these are not intrinsic function in QASM
    # users need qelib1.inc to get the definition
    # but for convenience we treat them as intrinsic
    # function here in YaoLang, since they are predefined
    # as stdlib in YaoLang.

    # isnothing(stmt.lst1) || throw(Meta.ParseError("$op gate should not have classical parameters"))
    if op == "x"
        xgate(YaoLang.X, parse_locations(record, stmt.lst2))
    elseif op == "y"
        xgate(YaoLang.Y, parse_locations(record, stmt.lst2))
    elseif op == "z"
        xgate(YaoLang.Z, parse_locations(record, stmt.lst2))
    elseif op == "h"
        xgate(YaoLang.H, parse_locations(record, stmt.lst2))
    elseif op == "s"
        xgate(YaoLang.S, parse_locations(record, stmt.lst2))
    elseif op == "ccx"
        locs = parse_locations(record, stmt.lst2)
        xctrl(YaoLang.X, locs[3], CtrlLocations(locs[1:2]))
    else # some user defined routine
        if isnothing(stmt.lst1)
            gate = Expr(:call, GlobalRef(m, Symbol(op)))
        else
            gate = Expr(:call, GlobalRef(m, Symbol(op)), parse_exp(stmt.lst1))
        end
        xgate(gate, parse_locations(record, stmt.lst2))
    end
end

function parse(m::Module, record::RegisterRecord, stmt::Parse.Struct_argument)
    address = Base.parse(Int, stmt.arg.str)
    return Locations(record[stmt.id.str][address + 1])
end

function parse(m::Module, record::GateRegisterRecord, stmt::Parse.Struct_argument)
    return Locations(record.map[stmt.id.str])
end

function parse_exp(stmt::Parse.Struct_neg)
    return -parse_exp(stmt.value)
end

function parse_exp(stmt::RBNF.Token{:real})
    return Base.parse(Float64, stmt.str)
end

function parse_exp(stmt::RBNF.Token{:nninteger})
    return Base.parse(Int, stmt.str)
end

function parse_exp(stmt::RBNF.Token{:id})
    if stmt.str == "pi"
        return Base.pi
    else
        return Symbol(stmt.str)
    end
end

function parse_exp(stmt::RBNF.Token{:unnamed})
    return Symbol(stmt.str)
end

function parse_exp(stmt::Tuple)
    length(stmt) == 3 || throw(Meta.ParseError("unrecognized expression: $stmt"))
    stmt[2]::RBNF.Token
    if stmt[2].str in ("+" , "-" , "*" , "/")
        return Expr(:call, Symbol(stmt[2].str), parse_exp(stmt[1]), parse_exp(stmt[3]))
    else
        throw(Meta.ParseError("unrecognized expression: $stmt"))
    end
end

function parse_locations(record, stmt)
    return Locations(parse_locations!(Int[], record, stmt)...)
end

function parse_locations!(locs::Vector, record, stmt::Tuple)
    for each in stmt
        parse_locations!(locs, record, each)
    end
    return locs
end

function parse_locations!(locs::Vector, record::RegisterRecord, stmt::Parse.Struct_mixeditem)
    address = Base.parse(Int, stmt.arg.str)
    push!(locs, record[stmt.id.str][address + 1])
    return locs
end

function parse_locations!(locs::Vector, record::GateRegisterRecord, stmt::Parse.Struct_mixeditem)
    push!(locs, record.map[stmt.id.str])
    return locs
end

function parse_version(token::RBNF.Token)
    return VersionNumber(token.str)
end

function scan_registers(ast::Parse.Struct_mainprogram)
    return scan_registers!(RegisterRecord(), ast)
end

function scan_registers!(record::RegisterRecord, ast::Parse.Struct_mainprogram)
    for stmt in ast.prog
        scan_registers!(record, stmt)
    end
    return record
end

function scan_registers!(record::RegisterRecord, ast::Parse.Struct_decl)
    nbits = Meta.parse(ast.int.str)
    nqubits = record.nqubits
    ncbits = record.ncbits

    if ast.regtype.str == "qreg"
        record.map[ast.id.str] = VirtualRegister(:quantum, (nqubits+1):(nqubits+nbits))
        record.nqubits += nbits
    else # classical
        record.map[ast.id.str] = VirtualRegister(:classical, (ncbits+1):(ncbits+nbits))
        record.ncbits += nbits
    end
    return record
end

scan_registers!(record::RegisterRecord, ast) = record

macro qasm_str(source::String)
    return esc(parse(__module__, source))
end

macro qasm_str(source::Expr)
    source.head === :string || error("expect a String")

    args = map(source.args) do x
        x isa String && return x
        return Base.eval(__module__, x)
    end

    return esc(parse(__module__, join(args)))
end

end # end module
