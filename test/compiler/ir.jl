using Test
using YaoLang
using YaoBase
using YaoLang: parse_ast, GateLocation, Control, Measure, QASTCode, JuliaASTCodegenCtx, transform, ctrl_transform

@testset "parsing" begin
    @testset "basic statement parsing" begin
        ex = quote
            1 => H # gate location
            [1 => H, 3 => X] # construct a list of pairs
            y = 1 => H # create a pair and assign it to variable y

            @ctrl k 2 => H
            @ctrl (i, j) m => X

            ci = @measure k
            cj = @measure k H
            ck = @measure (i, j, k) repeat(3, H)

            1:3 => qft(2, 3)
        end

        dst = parse_ast(ex)

        @test dst.head === :block
        @test dst.args[2] == GateLocation(1, :H)
        @test dst.args[8] == Control(:k, GateLocation(2, :H))
        @test dst.args[10] == Control(:((i, j)), GateLocation(:m, :X))
        @test dst.args[12] == :(ci = $(Measure(:k)))
        @test dst.args[14] == :(cj = $(Measure(:k, :H)))
        @test dst.args[16] == :(ck = $(Measure(:((i, j, k)), :(repeat(3, H)))))
    end

    @testset "gate location statement ambiguity test" begin
        @testset "loop" begin
            ex = quote
                for k in 1:length(θ)
                    k => shift(θ[k])
                end
            end

            dst = parse_ast(ex)
            loop_body = dst.args[2].args[2]
            @test loop_body.args[2] == GateLocation(:k, :(shift(θ[k])))
        end

        @testset "ifelse" begin
            ex = quote
                if n > 1
                    2:n => qft(n - 1)
                end
            end

            dst = parse_ast(ex)
            cond_body = dst.args[2].args[2]
            @test cond_body.args[2] == GateLocation(:(2:n), :(qft(n - 1)))
        end
    end
end


@testset "QASTCode" begin
    ex = :(function qft(n::Int)
    1 => H
    for k in 2:n
        @ctrl k 1 => shift(2π / 2^k)
    end

    if n > 1
        2:n => qft(n - 1)
    end
    end)

    @test_throws Meta.ParseError QASTCode(ex; strict_mode=:pure)
end

@testset "transform(::JuliaASTCodegenCtx, ex)" begin
    ctx = JuliaASTCodegenCtx(:stub, :circ, :r, :locs, :ctrl_locs, Any[])

    ex = :(1 => H)
    dst = parse_ast(ex)

    @test transform(ctx, dst) == :($(YaoLang.evaluate)(H)(r, locs[$(Locations(1))]))
    @test ctrl_transform(ctx, dst) == :($(YaoLang.evaluate)(H)(r, locs[$(Locations(1))], ctrl_locs))

    ex = :(@ctrl 3 2=>H)
    dst = parse_ast(ex)
    @test transform(ctx, dst) == :($(YaoLang.evaluate)(H)(r, locs[$(Locations(2))], locs[$(CtrlLocations(3))]))
    @test ctrl_transform(ctx, dst) == :($(YaoLang.evaluate)(H)(r, locs[$(Locations(2))], merge_locations(ctrl_locs, locs[$(CtrlLocations(3))])))

    ex = :(@measure k)
    dst = parse_ast(ex)
    @test transform(ctx, dst) == :(measure!(r, locs[Locations(k)]))
    ex = :(@measure k operator)
    dst = parse_ast(ex)
    @test transform(ctx, dst) == :(measure!(operator, r, locs[Locations(k)]))

    ex = :(@measure reset_to=1 k operator)
    dst = parse_ast(ex)
    @test transform(ctx, dst) == :(measure!(ResetTo(1), operator, r, locs[Locations(k)]))
    
    ex = :(@measure remove=true k operator)
    dst = parse_ast(ex)
    @test transform(ctx, dst) == :(measure!($(RemoveMeasured()), operator, r, locs[Locations(k)]))
    
    ex = :(@measure blabla=1 k operator)
    @test_throws Meta.ParseError parse_ast(ex)
end
