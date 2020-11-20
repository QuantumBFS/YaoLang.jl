using YaoLang
using YaoLang.IBMQ
using IBMQClient
using YaoCompiler
using YaoCompiler.Intrinsics

@device function test(theta)
    1 => X
    2 => X
    @ctrl (1, 2) 3=>X
    @ctrl 1 2=>Rx(theta)
    c = @measure 1:3
    return c
end

@code_yao optimize=true circuit1()

token = "e773394070269e3deace4372ed915c99610ee5a0e3be7b2f821e6889f4f4fe93cafdebcce46009e0ec9dd3ff8dca3ad3eb126b3bc59617ee837f2e120e99f268"
reg = IBMQ.IBMQReg()
job = IBMQ.submit(reg, test())
result = IBMQClient.result(job)

reg = IBMQ.IBMQReg(;nshots=2048)

job = @ibmq nshots=2048 begin
    for i in 1:10
        test()
    end
end
