# proposed syntax

ex = quote
    1 => X
    2 => H
end

ex = quote
    function ghz()
        1 => X
        2:4 => H
        control(2, 1 => X)
        control(4, 3 => X)
        control(3, 1 => X)
        control(4, 3 => X)
        1:4 => H
    end
end

ex = quote
    function qft(n::Int)
        1 => H
        for k in 2:n
            control(k, 1 => shift(2π / 2^k))
        end

        if n > 1
            2:n => qft(n - 1)
        end
    end
end

ex = quote
    function qcbm(n::Int, depth::Int, parameters::Matrix)
        for j in 1:depth
            @column for k in 1:n
                k => Rz(parameters[k, j])
                k => Rx(parameters[k+1, j])
                k => Rz(parameters[k+2, j])
            end

            for k in 1:n
                control(k, mod1(k + 1, n) => X)
            end
        end

        @column for k in 1:n
            k => Rz(parameters[k, depth+1])
            k => Rx(parameters[k+1, depth+1])
            k => Rz(parameters[k+2, depth+1])
        end
    end
end


ex = quote
    function phase_estimate(n, m, U)
        1:n => H

        @column for k in 1:n
            p = 2^(k - 1)
            control(k, n+1:n+m => U^p)
        end

        1 => qft'(n)

        # invalid syntax? or just do nothing
        qft'(n)
    end
end


evaluate!(register, qft(3))
