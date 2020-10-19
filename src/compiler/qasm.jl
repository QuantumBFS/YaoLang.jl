module QASM

export @qasm_str

using RBNF
using ExprTools
using ..YaoLang

module Parse

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

# work around JuliaLang/julia/issues/38091
function _force_any(x)
    if isnothing(x)
        return Any[]
    else
        return Vector{Any}(x)
    end
end

struct MainProgram
    version::VersionNumber
    prog::Vector{Any}

    MainProgram(version, prog) = new(version, Vector{Any}(prog))
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
    cargs::Vector{Any}
    qargs::Vector{Any}

    function Opaque(name, cargs, qargs)
        new(name, _force_any(cargs), _force_any(qargs))
    end
end

function print_qasm(io::IO, stmt::Opaque)
    print_kw(io, "opaque ")
    if !isempty(stmt.cargs)
        print(io, "(")
        print_list(io, stmt.cargs)
        print(io, ") ")
    end
    print_list(io, stmt.qargs)
    print(io, ";")
end

struct Barrier
    qargs::Vector{Any}

    function Barrier(qargs)
        new(_force_any(qargs))
    end
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
    cargs::Vector{Any}
    qargs::Vector{Any}
    
    function GateDecl(name, cargs, qargs)
        new(name, _force_any(cargs), _force_any(qargs))
    end
end

function print_qasm(io::IO, stmt::GateDecl)
    print_kw(io, "gate ")
    print_qasm(io, stmt.name)

    if !isempty(stmt.cargs)
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
    cargs::Vector{Any}
    qargs::Vector{Any}

    function Instruction(name, cargs, qargs)
        new(name, _force_any(cargs), _force_any(qargs))
    end
end

function print_qasm(io::IO, stmt::Instruction)
    printstyled(io, stmt.name; color=:light_magenta)

    if !isempty(stmt.cargs)
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

function Bit(name::String, address::Int)
    Bit(Token{:id}(name), Token{:int}(string(address)))
end

Bit(name::String) = Bit(Token{:id}(name), nothing)

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

RBNF.@parser QASMLang begin
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

mutable struct GateRegisterRecord
    map::Dict
    total::Int
end

Base.getindex(x::RegisterRecord, key) = x.map[key]
Base.getindex(x::VirtualRegister, xs...) = x.address[xs...]

RegisterRecord() = RegisterRecord(Dict{String, UnitRange{Int}}(), 0, 0)
GateRegisterRecord() = GateRegisterRecord(Dict(), 0)

struct Ctx
    m::Module
    record
end

function parse(m::Module, source::String)
    ast = Parse.load(source)
    return parse(m, ast)
end

# tokens don't need context
parse(::Ctx, x::RBNF.Token) = parse(x)

parse(x::RBNF.Token{:unnamed}) = Symbol(x.str)

function parse(x::RBNF.Token{:id})
    x.str == "pi" && return Base.pi
    return Symbol(x.str)
end

function parse(x::RBNF.Token{:float64})
    return Base.parse(Float64, x.str)
end

function parse(x::RBNF.Token{:int})
    return Base.parse(Int, x.str)
end

parse_list(::Ctx, ::Nothing) = Any[]
parse_list(ctx::Ctx, x) = Any[parse(ctx, x)]

function parse_list(ctx::Ctx, xs::Vector)
    [parse(ctx, each) for each in xs]
end

function parse(m::Module, ast::Parse.MainProgram)
    # check sure minimum compatibility
    @assert v"2.0.0" <= ast.version < v"3.0.0"

    code = Expr(:block)
    body = Expr(:block)
    routines = []
    record = scan_registers(ast)
    ctx = Ctx(m, record)

    for stmt in ast.prog
        if stmt isa Parse.RegDecl
            continue
        elseif stmt isa Parse.Gate
            push!(routines, parse(ctx, stmt))
        elseif stmt isa Parse.Include
            push!(code.args, parse(ctx, read(stmt.file.str[2:end-1], String)))
        else
            ex = parse(ctx, stmt)
            if !isnothing(ex)
                push!(body.args, ex)
            end
        end
    end

    # if there are classical registers
    # return them in a NamedTuple
    ret = Expr(:tuple)
    for (k, r) in record.map
        if r.type === :classical
            name = Symbol(k)
            push!(ret.args, Expr(:(=), name, name))
        end
    end

    if !isempty(body.args)
        if isempty(ret.args)
            push!(body.args, :(return))
        else
            push!(body.args, :(return $ret))
        end
    end

    # routines
    for each in routines
        push!(code.args, each)
    end

    # create an anoymous routine
    # if there are global statements
    if !isempty(body.args)
        def = Dict{Symbol, Any}(
            :name => gensym(:qasm),
            :body => body,
        )
        push!(code.args, YaoLang.Compiler.device_def(def))
    end
    return code
end

function parse(ctx::Ctx, stmt::Parse.Gate)
    name = parse(stmt.decl.name)
    args = parse_list(ctx, stmt.decl.cargs)
    record = parse_gate_registers(stmt.decl.qargs)
    body = Expr(:block)
    new_ctx = Ctx(ctx.m, record)

    for each in stmt.body
        push!(body.args, parse(new_ctx, each))
    end

    def = Dict(:name=>name, :args=>args, :body=>body)
    return YaoLang.Compiler.device_def(def)
end

function parse_gate_registers(stmt::Vector)
    record = GateRegisterRecord()
    for each in stmt
        haskey(record.map, each.str) && throw(Meta.ParseError("duplicated register name $(each.str)"))
        record.total += 1
        record.map[each.str] = record.total
    end
    return record
end

semantic_gate(gate, locs) = Expr(:call, GlobalRef(YaoLang.Compiler.Semantic, :gate), gate, locs)
semantic_ctrl(gate, locs, ctrl) = Expr(:call, GlobalRef(YaoLang.Compiler.Semantic, :ctrl), gate, locs, ctrl)

function parse(ctx::Ctx, stmt::Parse.UGate)
    code = Expr(:block)
    locs = parse(ctx, stmt.qarg)
    push!(code.args,
        semantic_gate(Expr(:call, GlobalRef(YaoLang, :Rz), parse(ctx, stmt.z1)), locs))
    push!(code.args,
        semantic_gate(Expr(:call, GlobalRef(YaoLang, :Ry), parse(ctx, stmt.y)), locs))
    push!(code.args,
        semantic_gate(Expr(:call, GlobalRef(YaoLang, :Rz), parse(ctx, stmt.z2)), locs))
    return code
end

function parse(ctx::Ctx, stmt::Parse.CXGate)
    return semantic_ctrl(GlobalRef(YaoLang, :X), parse(ctx, stmt.qarg), CtrlLocations(parse(ctx, stmt.ctrl)))
end

function parse(ctx::Ctx, stmt::Parse.IfStmt)
    return :(
        if $(parse(ctx, stmt.left)) == $(parse(ctx, stmt.right))
            $(parse(ctx, stmt.body))
        end
    )
end

function parse(ctx::Ctx, stmt::Parse.Measure)
    locs = parse(ctx, stmt.qarg)
    name = parse(ctx, stmt.carg)
    return Expr(:(=), name, Expr(:call, GlobalRef(YaoLang.Compiler.Semantic, :measure), locs))
end

function parse(ctx::Ctx, stmt::Parse.Barrier)
    return Expr(:call,
        GlobalRef(YaoLang.Compiler.Semantic, :barrier),
        parse_locations(ctx, stmt.qargs)
    )
end

function parse(ctx::Ctx, stmt::Parse.Instruction)
    op = stmt.name
    # NOTE: these are not intrinsic function in QASM
    # users need qelib1.inc to get the definition
    # but for convenience we treat them as intrinsic
    # function here in YaoLang, since they are predefined
    # as stdlib in YaoLang.

    # isnothing(stmt.lst1) || throw(Meta.ParseError("$op gate should not have classical parameters"))
    locs = parse_locations(ctx, stmt.qargs)

    if op == "x"
        semantic_gate(YaoLang.X, locs)
    elseif op == "y"
        semantic_gate(YaoLang.Y, locs)
    elseif op == "z"
        semantic_gate(YaoLang.Z, locs)
    elseif op == "h"
        semantic_gate(YaoLang.H, locs)
    elseif op == "s"
        semantic_gate(YaoLang.S, locs)
    elseif op == "ccx"
        semantic_ctrl(YaoLang.X, locs[3], CtrlLocations(locs[1:2]))
    else # some user defined routine
        gate = Expr(:call, GlobalRef(ctx.m, Symbol(op)), parse_list(ctx, stmt.cargs)...)
        semantic_gate(gate, locs)
    end
end

function parse_locations(ctx, stmts::Vector)
    locs = map(stmts) do stmt
        parse(ctx, stmt)
    end
    return merge_locations(locs...)
end

function parse(ctx::Ctx, stmt::Parse.Bit)
    record = ctx.record
    if record isa RegisterRecord
        r = record[stmt.name.str]
        r.type === :classical && return Symbol(stmt.name.str)

        if isnothing(stmt.address)
            return Locations(r[:])
        else
            address = parse(stmt.address)
            return Locations(r[address + 1])
        end
    else
        return Locations(record.map[stmt.name.str])
    end
end

parse(ctx::Ctx, stmt::Parse.Negative) = -parse(ctx, stmt.value)

function parse(ctx::Ctx, stmt::Tuple)
    length(stmt) == 3 || throw(Meta.ParseError("unrecognized expression: $stmt"))
    stmt[2]::RBNF.Token
    if stmt[2].str in ("+" , "-" , "*" , "/")
        return Expr(:call, Symbol(stmt[2].str), parse(ctx, stmt[1]), parse(ctx, stmt[3]))
    else
        throw(Meta.ParseError("unrecognized expression: $stmt"))
    end
end

function scan_registers(ast::Parse.MainProgram)
    return scan_registers!(RegisterRecord(), ast)
end

function scan_registers!(record::RegisterRecord, ast::Parse.MainProgram)
    for stmt in ast.prog
        scan_registers!(record, stmt)
    end
    return record
end

function scan_registers!(record::RegisterRecord, ast::Parse.RegDecl)
    nbits = parse(ast.size)
    nqubits = record.nqubits
    ncbits = record.ncbits

    if ast.type.str == "qreg"
        record.map[ast.name.str] = VirtualRegister(:quantum, (nqubits+1):(nqubits+nbits))
        record.nqubits += nbits
    else # classical
        record.map[ast.name.str] = VirtualRegister(:classical, (ncbits+1):(ncbits+nbits))
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

macro include_str(path)
    if path isa Expr
        path.head === :string || error("expect a String")
        file = map(path.args) do x
            x isa String && return x
            return Base.eval(__module__, x)
        end |> join
    elseif path isa String
        file = path
    else
        error("expect a String")
    end

    return esc(parse(__module__, read(file, String)))
end

end # end module
