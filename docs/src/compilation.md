```@meta
CurrentModule = YaoLang.Compiler
```

# Compilation

The compilation framework of YaoLang is designed to be highly extensible, so one can easily extend the semantics
as long as there is no ambiguity.

For simple code generation task, one can use Julia native macros directly instead of writing a custom compiler pass.
But for more complicated task, one would prefer to add a custom compiler pass.

## Representation

`YaoLang` is a domain specific language, it embeds its own representation inside the Julia AST and SSA IR.

The Julia AST captured by a macro [`@device`](@ref) will be first transformed into custom function calls tagged with
`GlobalRef(YaoLang.Compiler, :node_name)`. The syntax check will then check if the syntax is correct, then
the AST will be compiled into Julia's SSA IR as a `CodeInfo` object.

Then we transform the `CodeInfo` object to a quantum SSA IR by inferring the quantum statements, where we call this
representation as [`YaoIR`](@ref).

### YaoIR

The Yao IR annotates our domain specific semantics using a `:quantum` head, followed by a custom head, such as `:gate`.
For example, `1 => X` will be parsed as `Expr(:quantum, :gate, :X, 1)`.

## Compiler API References

```@autodocs
Modules = [YaoLang.Compiler]
```
