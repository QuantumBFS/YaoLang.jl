export @code_yao

function code_yao(xs...)
    return
end

"""
    @code_yao <generic circuit call>

Evaluates the arguments to the function call, determines their types, and
calls `code_yao` on the resulting expression.
"""
macro code_yao(ex)
    (ex isa Expr) && (ex.head === :call) || error("expect a generic circuit call")
    return IRTools.xcall(Compiler, :code_yao, ex.args...) |> esc
end
