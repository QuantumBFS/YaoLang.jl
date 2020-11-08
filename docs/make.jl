using Documenter, YaoLang

makedocs(;
    modules = [YaoLang],
    format = Documenter.HTML(prettyurls = !("local" in ARGS)),
    pages = [
        "Home" => "index.md",
        "Semantics" => "semantics.md",
        "Compilation" => "compilation.md",
        "References" => "references.md",
    ],
    repo = "https://github.com/QuantumBFS/YaoLang.jl",
    sitename = "YaoLang.jl",
)

deploydocs(; repo = "github.com/QuantumBFS/YaoLang.jl")
