using YaoLang
using YaoLang.Compiler
using YaoLang.Compiler: device_m, enable_timings, timings

# enable_timings()

ex = :(function qft(n::Int)
           1 => H
           for k in 2:n
               @ctrl k 1=>shift(2π / 2^k)
           end

           if n > 1
               2:n => qft(n - 1)
           end
       end)

@time device_m(@__MODULE__, ex);

# timings()
