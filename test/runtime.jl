using Revise
using YaoIR, YaoArrayRegister
using Test

ex = :(function qft(n::Int)
    1 => H
    for k in 2:n
        control(k, 1=>Shift(2π/2^k))
    end

    if n > 1
        2:n => qft(n-1)
    end
end)

ex = ignore_line_numbers(ex)

YaoIR.create_closure(ex) |> ignore_line_numbers
YaoIR.generate_instruct(ex)


transform(:(1=>H))
compile_to_jl(:r, ir, :locs)

ir = transform(:(control(k, 1=>H))) == Control(:k, GateLocation(1, :H))

transform(:(measure(1, 2)))
transform(:(measure(1:4)))

Measure(:(1:2))