using Revise, YaoIR, YaoArrayRegister

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

ir = transform(ex)


transform(:(1=>H))
compile_to_jl(:r, ir, :locs)
