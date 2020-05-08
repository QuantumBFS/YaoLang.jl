using YaoIR
using YaoArrayRegister
using Flux.Optimise
using LinearAlgebra

@device function qcbm(n::Int, depth::Int, ps::Vector)
    count = 1
    @inbounds for k in 1:n
        k => Rx(ps[count])
        k => Rz(ps[count+1])
        count += 2
    end

    @inbounds for j in 1:depth-1
        for k in 1:n
            @ctrl k mod1(k+1, n) => X
        end

        for k in 1:n
            k => Rz(ps[count])
            k => Rx(ps[count+1])
            k => Rz(ps[count+2])
            count += 3
        end
    end

    # last layer
    for k in 1:n
        @ctrl k mod1(k+1, n) => X
    end

    @inbounds for k in 1:n
        k => Rz(ps[count])
        k => Rx(ps[count+1])
        count += 2
    end
end

mRx(θ::Real) = [cos(θ / 2) -im * sin(θ / 2); -im * sin(θ / 2) cos(θ / 2)]
mRz(θ::Real) = Diagonal([-im * sin(θ / 2) + cos(θ / 2), im * sin(θ / 2) + cos(θ / 2)])

function baseline(r, n::Int, depth::Int, ps::Vector)
    # count = 1
    # @inbounds for k in 1:n
    #     instruct!(r, mRx(ps[count]), (k, ))
    #     instruct!(r, mRz(ps[count+1]), (k, ))
    #     count += 2
    # end

    @inbounds for j in 1:depth-1
        for k in 1:n
            instruct!(r, Val(:X), (mod1(k+1, n), ), (k, ), (1, ))
        end

        # for k in 1:n
        #     instruct!(r, mRz(ps[count]), (k, ))
        #     instruct!(r, mRx(ps[count+1]), (k, ))
        #     instruct!(r, mRz(ps[count+2]), (k, ))
        #     count += 3
        # end
    end

    for k in 1:n
        instruct!(r, Val(:X), (mod1(k+1, n), ), (k, ), (1, ))
    end

    # @inbounds for k in 1:n
    #     instruct!(r, mRz(ps[count]), (k, ))
    #     instruct!(r, mRx(ps[count+1]), (k, ))
    #     count += 2
    # end
    return r
end

function baseline2(r, n::Int, depth::Int, ps::Vector)
    # count = 1
    # @inbounds for k in 1:n
    #     instruct!(r, mRx(ps[count]), Locations(k))
    #     instruct!(r, mRz(ps[count+1]), Locations(k))
    #     count += 2
    # end

    @inbounds for j in 1:depth-1
        for k in 1:n
            instruct!(r, Val(:X), Locations(mod1(k+1, n)), Locations(k), (true, ))
        end

        # for k in 1:n
        #     instruct!(r, mRz(ps[count]), Locations(k))
        #     instruct!(r, mRx(ps[count+1]), Locations(k))
        #     instruct!(r, mRz(ps[count+2]), Locations(k))
        #     count += 3
        # end
    end

    for k in 1:n
        instruct!(r, Val(:X), Locations(mod1(k+1, n)), Locations(k), (true, ))
    end

    # @inbounds for k in 1:n
    #     instruct!(r, mRz(ps[count]), Locations(k))
    #     instruct!(r, mRx(ps[count+1]), Locations(k))
    #     count += 2
    # end
    return r
end

function baseline3(r, n::Int, depth::Int, ps::Vector, locs)
    # count = 1
    # @inbounds for k in 1:n
    #     instruct!(r, mRx(ps[count]), Locations(k))
    #     instruct!(r, mRz(ps[count+1]), Locations(k))
    #     count += 2
    # end

    @inbounds for j in 1:depth-1
        for k in 1:n
            instruct!(r, Val(:X), locs[Locations(mod1(k+1, n))], locs[Locations(k)], (true, ))
        end

        # for k in 1:n
        #     instruct!(r, mRz(ps[count]), Locations(k))
        #     instruct!(r, mRx(ps[count+1]), Locations(k))
        #     instruct!(r, mRz(ps[count+2]), Locations(k))
        #     count += 3
        # end
    end

    for k in 1:n
        instruct!(r, Val(:X), locs[Locations(mod1(k+1, n))], locs[Locations(k)], (true, ))
    end

    # @inbounds for k in 1:n
    #     instruct!(r, mRz(ps[count]), Locations(k))
    #     instruct!(r, mRx(ps[count+1]), Locations(k))
    #     count += 2
    # end
    return r
end

function nparameters(n, depth)
    2n + 3n * (depth-1) + 2n
end

function shift_gradient(qcbm, n, depth, κ, ps::Vector, ptrain)
    ∇ps = similar(ps)
    prob = probs(zero_state(n) |> qcbm(n, depth, ps))

    @inbounds for k in eachindex(ps)
        x = ps[k]
        ps[k] = x - π/2
        prob_negative = probs(zero_state(n) |> qcbm(n, depth, ps))
        ps[k] = x + π/2
        prob_positive = probs(zero_state(n) |> qcbm(n, depth, ps))
        ps[k] = x
        grad_pos = kexpect(κ, prob, prob_positive) - kexpect(κ, prob, prob_negative)
        grad_neg = kexpect(κ, ptrain, prob_positive) - kexpect(κ, ptrain, prob_negative)
        ∇ps[k] = grad_pos - grad_neg
    end
    return ∇ps
end

struct RBFKernel
    σ::Float64
    m::Matrix{Float64}
end

function RBFKernel(σ::Float64, space)
    dx2 = (space .- space').^2
    return RBFKernel(σ, exp.(-1/2σ * dx2))
end

kexpect(κ::RBFKernel, x, y) = x' * κ.m * y

function loss(κ, qcbm, n, depth, ps, target)
    p = probs(zero_state(n) |> qcbm(n, depth, ps)) - target
    return kexpect(κ, p, p)
end

function gaussian_pdf(x, μ::Real, σ::Real)
    pl = @. 1 / sqrt(2pi * σ^2) * exp(-(x - μ)^2 / (2 * σ^2))
    pl / sum(pl)
end

function train(qcbm, n, depth, ps, κ, opt, target)
    history = Float64[]
    for _ in 1:100
        push!(history, loss(κ, qcbm, n, depth, ps, target))
        Optimise.update!(opt, ps, shift_gradient(qcbm, n, depth, κ, ps, target))
    end
    return history
end

n, depth = 10, 10
pg = gaussian_pdf(1:1<<n, 1<<(n-1)-0.5, 1<<4);
κ = RBFKernel(0.25, 0:2^n-1)
opt = ADAM()
ps = rand(nparameters(n, depth))
train(qcbm, n, depth, ps, κ, opt, pg)
