export @code_yao, @code_qasm

"""
    @code_yao <generic circuit call>

Evaluates the arguments to the function call, determines their types, and
calls `code_yao` on the resulting expression.
"""
macro code_yao(ex)
    (ex isa Expr) && (ex.head === :call) || error("expect a generic circuit call")    
    esc(Expr(:call, GlobalRef(Compiler, :RoutineInfo), :(typeof($ex))))
end

macro code_qasm(ex)
    (ex isa Expr) && (ex.head === :call) || error("expect a generic circuit call")
    ri = gensym(:routine_info)
    quote
        $ri = $(Expr(:call, GlobalRef(Compiler, :RoutineInfo), :(typeof($ex))))
        $(Expr(:call, GlobalRef(Compiler, :codegen_qasm), ri))
    end |> esc
end
