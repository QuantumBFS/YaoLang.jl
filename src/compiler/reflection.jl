export @code_qast, code_qast

function code_qast end

macro code_qast(ex)
    (ex isa Expr) && (ex.head === :call) || error("expect a generic circuit call")
    return Expr(:call, code_qast, ex.args...) |> esc
end
