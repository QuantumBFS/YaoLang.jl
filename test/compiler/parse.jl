using YaoLang
using YaoLang.Compiler
using IRTools
using IRTools: IR
using IRTools.Inner

using YaoLang.Compiler: build_codeinfo
using IRTools.Inner: update!
using ExprTools

ex = :(
    function qft(n::Int)
        1 => H
        for k in 2:n
            @ctrl k 1 => shift(2π / 2^k)
        end
    
        if n > 1
            2:n => qft(n - 1)
        end
    end
)

@device function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
end

@code_yao qft(3)

ir = YaoIR(ex)

Compiler.codegen_passes[:quantum_circuit](JuliaASTCodegenCtx(ir), ir)

ex = :(function qft(n::Int)
1 => H
for k in 2:n
    1 => shift(2π / 2^k)
end

if n > 1
    2:n => qft(n - 1)
end
end)

ci = Meta.lower(Main, ex).args[]

ci.code

function qft end

ci = Meta.lower(Main, :(function qft(n::T) where {T <: Real} end)).args[]

ci.code
