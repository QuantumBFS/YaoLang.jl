using YaoIR

p = @pattern $x + 1

p = :($(Variable(:x)) + 1)
t = :(2 + 1)

match!(Dict(), p, t)

macro pattern(ex)
    return esc(ex)
end


ex = @macroexpand @pattern $_ + 1

ex.args[2].args[1]
