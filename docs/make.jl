using Documenter, YaoIR

makedocs(;
    modules = [YaoIR],
    format = Documenter.HTML(),
    pages = ["Home" => "index.md"],
    repo = "https://github.com/QuantumBFS/YaoIR.jl",
    sitename = "YaoIR.jl",
)

deploydocs(; repo = "github.com/QuantumBFS/YaoIR.jl")
