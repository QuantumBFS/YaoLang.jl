using RBNF
using RBNF: Token

struct QASMLang end

second((a, b)) = b
second(vec::V) where {V<:AbstractArray} = vec[2]

# roses are red
# violets are blue
# pirates are good
RBNF.crate(::Type{Symbol}) = gensym(:qasm)
RBNF.crate(::Type{VersionNumber}) = VersionNumber("0.0.0")

Base.convert(::Type{VersionNumber}, t::Token) = VersionNumber(t.str)
Base.convert(::Type{String}, t::Token) = t.str
Base.convert(::Type{Int}, t::Token{:int}) = Base.parse(Int, t.str)
Base.convert(::Type{Float64}, t::Token{:float64}) = Base.parse(Float64, t.str)
Base.convert(::Type{Symbol}, t::Token{:id}) = Symbol(t.str)
Base.convert(::Type{String}, t::Token{:str}) = String(t.str[2:end-1])
# NOTE: U(sin(pi/4), sin(pi/8))
# is not corrently parsed

print_kw(io::IO, xs...) = printstyled(io, xs...; color=:light_blue)

function print_list(io::IO, list::Vector)
    for k in eachindex(list)
        print_qasm(io, list[k])

        if k != lastindex(list)
            print(io, ", ")
        end
    end
end

print_list(io::IO, x) = print_qasm(io, x)

print_qasm(ast) = print_qasm(stdout, ast)
print_qasm(io::IO) = x->print_qasm(io, x)
print_qasm(io::IO, ::Nothing) = nothing

print_qasm(io::IO, t::Token) = print(io, t.str)

function print_qasm(io::IO, t::Token{:reserved})
    print_kw(io, t.str)
end

function print_qasm(io::IO, stmt::RBNF.Token{:id})
    printstyled(io, stmt.str; color=:light_cyan)
end

function print_qasm(io::IO, stmt::RBNF.Token{:float64})
    printstyled(io, stmt.str; color=:green)
end

function print_qasm(io::IO, stmt::RBNF.Token{:int})
    printstyled(io, stmt.str; color=:green)
end

# NOTE:
# In order to preserve some line number
# we usually don't annote types to AST

struct MainProgram
    version::VersionNumber
    prog::Vector{Any}
end

Base.show(io::IO, x::MainProgram) = print_qasm(io, x)

function print_qasm(io::IO, x::MainProgram)
    printstyled(io, "OPENQASM "; bold=true)
    printstyled(io, x.version.major, ".", x.version.minor; color=:yellow)
    println(io)

    for k in 1:length(x.prog)
        print_qasm(io, x.prog[k])
        
        if k != length(x.prog)
            println(io)
        end
    end
end

struct IfStmt
    left
    right
    body
end

function print_qasm(io::IO, stmt::IfStmt)
    print_kw(io, "if ")
    print(io, "(")
    print_qasm(io, stmt.left)
    print(io, " == ")
    print_qasm(io, stmt.right)
    print(io, ") ")
    print_qasm(io, stmt.body)
end


struct Opaque
    name
    cargs# ::Vector{Any}
    qargs# ::Vector{Any}
end

function print_qasm(io::IO, stmt::Opaque)
    print_kw(io, "opaque ")
    if !isnothing(stmt.cargs)
        print(io, "(")
        print_list(io, stmt.cargs)
        print(io, ") ")
    end
    print_list(io, stmt.qargs)
    print(io, ";")
end

struct Barrier
    qargs# ::Vector{Any}
end

function print_qasm(io::IO, stmt::Barrier)
    print_kw(io, "barrier ")
    print_list(io, stmt.qargs)
    print(io, ";")
end

struct RegDecl
    type
    name
    size
end

function print_qasm(io::IO, stmt::RegDecl)
    print_qasm(io, stmt.type)
    print(io, " ")
    print_qasm(io, stmt.name)
    print(io, "[")
    print_qasm(io, stmt.size)
    print(io, "];")
end

struct Include
    file
end

function print_qasm(io::IO, stmt::Include)
    print_kw(io, "include ")
    print_qasm(io, stmt.file)
    print(io, ";")
end

struct GateDecl
    name
    # we remove type annotations for now
    # due to JuliaLang/julia/issues/38091
    cargs# ::Vector{Any}
    qargs# ::Vector{Any}
end

function print_qasm(io::IO, stmt::GateDecl)
    print_kw(io, "gate ")
    print_qasm(io, stmt.name)

    if !isnothing(stmt.cargs)
        print(io, "(")
        print_list(io, stmt.cargs)
        print(io, ")")
    end

    print(io, " ")
    print_list(io, stmt.qargs)
    print(io, " {")
end

struct Gate
    decl::GateDecl
    body::Vector{Any}
end

function print_qasm(io::IO, stmt::Gate)
    print_qasm(io, stmt.decl)
    println(io)
    for k in 1:length(stmt.body)
        print(io, " "^2)
        print_qasm(io, stmt.body[k])
        println(io)
    end
    println(io, "}")
end

struct Reset
    qarg
end

function print_qasm(io::IO, stmt::Reset)
    print_kw(io, "reset ")
    print_qasm(io, stmt.qarg)
end

struct Measure
    qarg
    carg
end

function print_qasm(io::IO, stmt::Measure)
    print_kw(io, "measure ")
    print_qasm(io, stmt.qarg)
    print_kw(io, " ->")
    print_qasm(io, stmt.carg)
    print(io, ";")
end

struct Instruction
    name::String
    cargs
    qargs
end

function print_qasm(io::IO, stmt::Instruction)
    printstyled(io, stmt.name; color=:light_magenta)

    if !isnothing(stmt.cargs)
        print(io, "(")
        print_list(io, stmt.cargs)
        print(io, ")")
    end
    print(io, " ")
    print_list(io, stmt.qargs)
    print(io, ";")
end

struct UGate
    z1
    y
    z2
    qarg
end

function print_qasm(io::IO, stmt::UGate)
    print_kw(io, "U")
    print(io, "(")
    print_qasm(io, stmt.z1)
    print(io, ", ")
    print_qasm(io, stmt.y)
    print(io, ", ")
    print_qasm(io, stmt.z2)
    print(io, ") ")
    print_qasm(io, stmt.qarg)
    print(io, ";")
end

struct CXGate
    ctrl
    qarg
end

function print_qasm(io::IO, stmt::CXGate)
    print_kw(io, "CX ")
    print_qasm(io, stmt.ctrl)
    print(io, ", ")
    print_qasm(io, stmt.qarg)
    print(io, ";")
end

struct Bit
    name
    address
end

function print_qasm(io::IO, stmt::Bit)
    print_qasm(io, stmt.name)
    if !isnothing(stmt.address)
        print(io, "[")
        print_qasm(io, stmt.address)
        print(io, "]")
    end
end

struct FnExp
    fn::Symbol
    arg
end

function print_qasm(io::IO, stmt::FnExp)
    print(io, fn)
    print(io, "(")
    print_qasm(io, stmt.arg)
    print(io, ")")
end

struct Negative
    value
end

function print_qasm(io::IO, stmt::Negative)
    print(io, "-")
    print_qasm(io, stmt.value)
end

# exp
function print_qasm(io::IO, stmt::Tuple)
    foreach(print_qasm(io), stmt)
end

RBNF.typename(::Type{QASMLang}, name::Symbol) = Symbol(:S_, name)

ex = @macroexpand RBNF.@parser QASMLang begin
    # define ignorances
    ignore{space, comment}
    reserved = ["include", "measure", "barrier", "if", "->"]

    @grammar
    # define grammars
    mainprogram::MainProgram := ["OPENQASM", version = float64, ';', prog = program]
    program = statement{*}
    statement = (regdecl | gate | opaque | qop | ifstmt | barrier | inc)
    # stmts
    ifstmt::IfStmt := ["if", '(', left = id, "==", right = int, ')', body = qop]
    opaque::Opaque := ["opaque", name = id, ['(', [cargs = idlist].?, ')'].?, qargs = idlist, ';']
    barrier::Barrier := ["barrier", qargs = bitlist, ';']
    regdecl::RegDecl := [type = "qreg" | "creg", name = id, '[', size = int, ']', ';']
    inc::Include := ["include", file = str, ';']
    # gate
    gate::Gate := [decl = gatedecl, [body = goplist].?, '}']
    gatedecl::GateDecl := ["gate", name = id, ['(', [cargs = idlist].?, ')'].?, qargs = idlist, '{']

    goplist = (uop | barrier){*}

    # qop
    qop = (uop | measure | reset)
    reset::Reset := ["reset", qarg = bit, ';']
    measure::Measure := ["measure", qarg = bit, "->", carg = bit, ';']

    uop = (inst | ugate | csemantic_gate)
    inst::Instruction := [name = id, ['(', [cargs = explist].?, ')'].?, qargs = bitlist, ';']
    ugate::UGate := ['U', '(', z1 = exp, ',', y = exp, ',', z2 = exp, ')', qarg = bit, ';']
    csemantic_gate::CXGate := ["CX", ctrl = bit, ',', qarg = bit, ';']

    idlist = @direct_recur begin
        init = [id]
        prefix = [recur..., (',', id) % second]
    end

    bit::Bit := [name = id, ['[', address = int, ']'].?]
    bitlist = @direct_recur begin
        init = [bit]
        prefix = [recur..., (',', bit) % second]
    end

    explist = @direct_recur begin
        init = [exp]
        prefix = [recur..., (',', exp) % second]
    end

    item = (float64 | int | "pi" | id | fnexp) | (['(', exp, ')'] % second) | neg
    fnexp::FnExp := [fn = fn, '(', arg = exp, ')']
    neg::Negative := ['-', value = exp]
    exp = @direct_recur begin
        init = item
        prefix = (recur, binop, item)
    end
    fn = ("sin" | "cos" | "tan" | "exp" | "ln" | "sqrt")
    binop = ('+' | '-' | '*' | '/')

    # define tokens
    @token
    id := r"\G[a-z]{1}[A-Za-z0-9_]*"
    float64 := r"\G([0-9]+\.[0-9]*|[0-9]*\.[0.9]+)([eE][-+]?[0-9]+)?"
    int := r"\G([1-9]+[0-9]*|0)"
    space := r"\G\s+"
    comment := r"\G//.*"
    str := @quote ("\"", "\\\"", "\"")
end

function load(src::String)
    ast, _ = RBNF.runparser(mainprogram, RBNF.runlexer(QASMLang, src))
    return ast
end

qasm_1 = """OPENQASM 2.0;
"""

load(qasm_1)

write("parse.jl", repr(ex))