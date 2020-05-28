using Documenter, YaoLang

makedocs(;
    modules = [YaoLang],
    format = Documenter.HTML(),
    pages = ["Home" => "index.md"],
    repo = "https://github.com/QuantumBFS/YaoLang.jl",
    sitename = "YaoLang.jl",
)

deploydocs(; repo = "github.com/QuantumBFS/YaoLang.jl")
