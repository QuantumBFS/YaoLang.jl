export TraceTape, recover_ast

struct TraceTape{B} <: AbstractRegister{B}
    commands::NTuple{B,Vector{Any}}
end

TraceTape() = TraceTape{1}((Any[],))

function trace!(tape::TraceTape{1}, stmt)
    push!(tape.commands[1], stmt)
end

function Base.show(io::IO, tape::TraceTape{1})
    for ex in tape.commands[1]
        printstyled(io, ex.args[1]; color = :light_blue, bold = true)
        print(io, " ")
        join(io, string.(ex.args[2:end]), " ")
        println(io)
    end
end

function recover_ast(tape::TraceTape{1})
    ex = Expr(:block)
    for each in tape.commands[1]
        if each.args[1] === :gate
            push!(ex.args, Expr(:call, :(=>), each.args[3], each.args[2]))
        elseif each.args[1] === :ctrl
            push!(
                ex.args,
                Expr(
                    :macrocall,
                    Symbol("@ctrl"),
                    LineNumberNode(@__LINE__, @__FILE__),
                    each.args[3],
                    Expr(:call, :(=>), each.args[3], each.args[2]),
                ),
            )
        elseif each.args[1] === :measure
            # push!(ex.args,
            #     Expr(:macrocall, Symbol("@measure"),
            #         LineNumberNode(@__LINE__, @__FILE__),
            #         ex.args...
            #     )
            # )
        end
    end
    return ex
end

function YaoIR(m::Module, tape::TraceTape{1}, name = gensym())
    ast = recover_ast(tape)
    lowered_ast = Meta.lower(m, to_function(m, ast))
    if lowered_ast === nothing
        body = IR()
    else
        body = IR(lowered_ast.args[], 0)
    end

    ir = YaoIR(m, name, Any[], Any[], mark_quantum(body), true, true)
    update_slots!(ir)
    return ir
end

function quantum_m(m::Module, n::Int, ex)
    if !((ex isa Expr) && (ex.head === :call))
        throw(ParseError("expect a call statement"))
    end

    name = gensym(Symbol(ex.args[1]))
    quote
        old_ir = $(esc(IRTools.xcall(YaoLang, :code_yao, ex.args...)))
        if $(GlobalRef(YaoLang, :is_pure_quantum))(old_ir)
            $(esc(ex.args[1]))
        else
            tape = $TraceTape()
            $(esc(ex))(tape, $Locations(1:$n))
            ir = $YaoIR($m, tape, $(QuoteNode(name)))
            $(GlobalRef(Base, :eval))($m, codegen(ir))
            $(esc(name))
        end
    end
end

export @quantum

"""
    @quantum nqubits::Int <generic circuit call>

Partially evaluate all classical parts of the generic circuit.

!!! note
    The classical part of the program could result in
    different circuits if it is not deterministic.
"""
macro quantum(n::Int, ex)
    return quantum_m(__module__, n, ex)
end
