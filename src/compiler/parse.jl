export to_function
using Core: GlobalRef

const RESERVED = [:gate, :ctrl, :measure, :register]

function to_function(m::Module, ex)
    # parse macros first
    ex = eval_stmts(m, ex)
    ex = to_control(ex)
    ex = to_measure(ex)
    ex = to_gate_location(ex)

    quote
        $(Expr(:meta, :register, :new, gensym(:register)))
        $ex
        # force return nothing if no return declared
        return
    end
end

function eval_stmts(m, ex)
    ex isa Expr || return ex
    if ex.head === :$
        return Base.eval(m, ex.args[1])
    else
        return Expr(ex.head, map(x -> eval_stmts(m, x), ex.args)...)
    end
end

function is_gate_location(ex)
    ex isa Expr || return false
    return (ex.head === :call) && (ex.args[1] == :(=>))
end

function to_gate_location(ex)
    ex isa Expr || return ex
    if is_gate_location(ex)
        location = ex.args[2]
        gate = ex.args[3]
        return Expr(:call, GlobalRef(Compiler, :gate), gate, location)
    end

    if ex.head in [:block, :if, :for, :macrocall] #= make @inbounds etc. work =#
        return Expr(ex.head, map(to_gate_location, ex.args)...)
    end
    return ex
end

function to_control(ex)
    ex isa Expr || return ex
    if (ex.head === :macrocall) && (ex.args[1] == Symbol("@ctrl"))
        length(ex.args) == 4 || throw(ParseError("@ctrl expect 2 argument, got $(length(ex.args)-2)"))

        ctrl_location = ex.args[3]
        gate_ex = ex.args[4]

        if is_gate_location(gate_ex)
            location = gate_ex.args[2]
            gate = gate_ex.args[3]
            return Expr(:call, GlobalRef(Compiler, :ctrl), gate, location, ctrl_location)
        else
            throw(ParseError("@ctrl expect location=>gate at 2nd argument, got $gate_ex"))
        end
    end

    return Expr(ex.head, map(to_control, ex.args)...)
end

function to_measure(ex)
    ex isa Expr || return ex

    if (ex.head === :macrocall) && (ex.args[1] == Symbol("@measure"))
        length(ex.args) > 2 || throw(ParseError("@measure expect at least 1 argument, got $ex"))
        args = []
        parameters = []
        for each in ex.args[3:end]
            if is_measure_kwarg(each)
                push!(parameters, Expr(:kw, each...))
            else
                push!(args, each)
            end
        end

        length(parameters) <= 1 ||
            throw(ParseError("@measure takes only 1 keyword argument, got $(length(parameters))"))
        return Expr(:call, GlobalRef(Compiler, :measure), Expr(:parameters, parameters...), args...)
    end

    return Expr(ex.head, map(to_measure, ex.args)...)
end

function is_measure_kwarg(ex)
    ex isa Expr || return false
    ex.head == :(=) && ex.args[1] in [:reset_to, :remove]
end
