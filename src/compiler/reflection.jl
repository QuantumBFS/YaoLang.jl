export @code_yao, @code_qasm

"""
    @code_yao <generic routine call>

Evaluates the arguments to the function call, determines their types, and
calls `code_yao` on the resulting expression.
"""
macro code_yao(ex)
    (ex isa Expr) && (ex.head === :call) || error("expect a generic circuit call")
    esc(Expr(:call, GlobalRef(Compiler, :RoutineInfo), :(typeof($ex))))
end

function code_qasm_m(ex, routine=false)
    (ex isa Expr) && (ex.head === :call) || error("expect a generic circuit call")
    ri = gensym(:routine_info)
    quote
        $ri = $(Expr(:call, GlobalRef(Compiler, :RoutineInfo), :(typeof($ex))))
        $(GlobalRef(Compiler, :codegen_qasm))($ri; routine=$routine)
    end
end


"""
    @code_qasm [routine=false] <generic routine call>

Return the corresponding QASM code of given routine call. It will only
generates the QASM for the generic routine by default. One can also generate
all the routine get called by setting `routine=true`.
"""
macro code_qasm(ex)
    esc(code_qasm_m(ex))
end

macro code_qasm(option, ex)
    option isa Expr && option.head === :(=) && option.args[1] === :routine || error("invalid option $option")
    option.args[2] isa Bool || error("option value should be a constant Bool")
    return esc(code_qasm_m(ex, option.args[2]))
end
