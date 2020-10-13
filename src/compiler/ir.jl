export YaoIR, RoutineInfo

function is_semantic_fn_call(e)
    return e isa Expr && e.head === :call &&
        e.args[1] isa GlobalRef &&
            e.args[1].mod === YaoLang.Compiler.Semantic
end

function convert_to_quantum_head!(ci::CodeInfo)
    for (v, e) in enumerate(ci.code)
        if is_semantic_fn_call(e)
            type = e.args[1].name
            ci.code[v] = Expr(:quantum, e.args[1].name, e.args[2:end]...)
        end
    end
    return ci
end

function quantum_blocks(ir::IR)
    quantum_blocks = UnitRange{Int}[]

    for b in blocks(ir)
        start, stop = 0, 0
        for (v, st) in b
            if is_quantum_statement(st.expr)
                type = quantum_stmt_type(st.expr)
                if type in [:measure, :barrier]
                    push!(quantum_blocks, start:stop+1)
                    start = stop = 0
                else
                    if start > 0
                        stop += 1
                    else
                        start = stop = v.id
                    end
                end
            else
                if start > 0
                    push!(quantum_blocks, start:stop)
                    start = stop = 0
                end
            end
        end

        if start > 0
            push!(quantum_blocks, start:stop)
        end
    end

    return quantum_blocks
end


function permute_stmts(ci::Core.CodeInfo, perm::Vector{Int})
    code = []
    ssavaluetypes = ci.ssavaluetypes isa Vector ? ci.ssavaluetypes[perm] : ci.ssavaluetypes

    for v in perm
        stmt = ci.code[v]

        if stmt isa Expr
            ex = prewalk(stmt) do x
                x isa Core.SSAValue && return Core.SSAValue(findfirst(isequal(x.id), perm))
                return x
            end
            push!(code, ex)
        elseif stmt isa Core.GotoIfNot
            if stmt.cond isa Core.SSAValue
                cond = Core.SSAValue(findfirst(isequal(stmt.cond.id), perm))
            else
                # TODO: figure out which case is this
                # and maybe apply permute to this
                cond = stmt.cond
            end

            dest = findfirst(isequal(stmt.dest), perm)
            push!(code, Core.GotoIfNot(cond, dest))
        elseif stmt isa Core.GotoNode
            push!(code, Core.GotoNode(findfirst(isequal(stmt.label), perm)))
        elseif stmt isa Core.ReturnNode
            if stmt.val isa Core.SSAValue
                push!(code, Core.ReturnNode(Core.SSAValue(findfirst(isequal(stmt.val.id), perm))))
            else
                push!(code, stmt)
            end
        elseif stmt isa Core.SlotNumber
            push!(code, stmt)
        else
            error("unrecognized statement $stmt :: ($(typeof(stmt)))")
        end
    end

    ret = copy(ci)
    ret.code = code
    ret.ssavaluetypes = ssavaluetypes
    return ret
end

function blockstarts(ci::CodeInfo)
    bs = Int[]
    terminator = false
    for i in 1:length(ci.code)
        ex = ci.code[i]
        if isexpr(ex, Core.GotoIfNot)
            push!(bs, ex.dest)
            terminator = true
        elseif isexpr(ex, Core.GotoNode)
            push!(bs, ex.label)
            i < length(ci.code) && push!(bs, i + 1)
            terminator = false
        elseif isexpr(ex, Core.ReturnNode)
            i < length(ci.code) && push!(bs, i + 1)
            terminator = false
        elseif terminator
            push!(bs, i)
            terminator = false
        end
    end
    return sort(unique(bs))
end

function group_quantum_stmts(ci::Core.CodeInfo, bs::Vector{Int})
    perms = Int[]
    prev_block = 0
    current_block = 0
    cstmts_tape = Int[]
    qstmts_tape = Int[]

    for (v, e) in enumerate(ci.code)
        if v in bs
            current_block += 1
        end
    
        if current_block > prev_block
            exit_block!(perms, cstmts_tape, qstmts_tape)
            prev_block = current_block
        end

        if is_quantum_statement(e)
            if quantum_stmt_type(e) in [:measure, :barrier]
                exit_block!(perms, cstmts_tape, qstmts_tape)
                push!(perms, v)
            else
                push!(qstmts_tape, v)
            end
        elseif e isa Core.ReturnNode
            exit_block!(perms, cstmts_tape, qstmts_tape)
            push!(cstmts_tape, v)
        else
            push!(cstmts_tape, v)
        end
    end

    append!(perms, cstmts_tape)
    append!(perms, qstmts_tape)
    
    return perms # permute_stmts(ci, perms)
end

function exit_block!(perms::Vector, cstmts_tape::Vector, qstmts_tape::Vector)
    append!(perms, cstmts_tape)
    append!(perms, qstmts_tape)
    empty!(cstmts_tape)
    empty!(qstmts_tape)
    return perms
end

# NOTE: this is similar to IR(ci, nargs)
# but we do our own type infer
# so we need to attach these info to the IR
# so we copy this part from IRTools and modify it
function typed_ir(ci::CodeInfo, nargs::Int, meta=nothing)
    bs = blockstarts(ci)
    # group quantum statements
    perms = group_quantum_stmts(ci, bs)
    ci = permute_stmts(ci, perms)
    # start converting to IR
    ir = IR(Core.LineInfoNode[ci.linetable...], meta = meta)
    _rename = Dict()
    rename(ex) = prewalk(ex) do x
        haskey(_rename, x) && return _rename[x]
        x isa Core.SlotNumber && return Inner.Slot(slotname(ci, x))
        return x
    end

    for i in 1:nargs
        type = isnothing(ci.slottypes) ? Any : ci.slottypes[i]
        _rename[Core.SlotNumber(i)] = argument!(ir; type)
    end

    for i in 1:length(ci.code)
        i in bs && block!(ir)
        ex = ci.code[i]
        if ex isa Core.NewvarNode
            continue
        elseif isexpr(ex, :enter) # NOTE: not sure if this will appear in typed IR
            _rename[Core.SSAValue(i)] = push!(ir, Expr(:enter, findfirst(isequal(ex.args[1]), bs)+1))
        elseif isexpr(ex, Core.GotoNode)
            branch!(ir, findfirst(==(ex.label), bs)+1)
        elseif isexpr(ex, Core.GotoIfNot)
            branch!(ir, findfirst(==(ex.dest), bs)+1, unless = rename(ex.cond))
        elseif isexpr(ex, Core.ReturnNode)
            if isdefined(ex, :val)
                return!(ir, rename(ex.val))
            else
                return!(ir, IRTools.unreachable)
            end
        else
            # @show _rename
            # @show i
            # @show ex
            # @show rename(ex)
            v = push!(ir, Statement(rename(ex); line = ci.codelocs[i], type=ci.ssavaluetypes[i]))
            # @show v
            _rename[Core.SSAValue(i)] = v
        end
    end
    return ir
end

struct YaoIR
    code::IR
    # range of stmts contains pure quantum stmts
    blocks::Vector{UnitRange{Int}}

    function YaoIR(code::IR, blocks::Vector{UnitRange{Int}})
        validate(code)
        return new(code, blocks)
    end
end

# YaoIR(types...) = YaoIR(IR(types...))
# YaoIR(fn::GenericRoutine, xs...) = Base.typesof(xs)
function validate(code)
end

function YaoIR(ci::CodeInfo, nargs::Int, meta=nothing)
    code = typed_ir(ci, nargs, meta)
    return YaoIR(code, quantum_blocks(code))
end

# NOTE: we store CodeInfo for now
# since we may still want some info from Julia
# but should consider to make this simpler later
struct RoutineInfo
    code::YaoIR
    ci::CodeInfo
    routine
    signature
end

function RoutineInfo(routine, stub, sigs)
    method = first(methods(stub)) # this is garuanteed by construction
    method_args = Tuple{typeof(stub), sigs.parameters...}
    mi = Core.Compiler.specialize_method(method, method_args, Core.svec())
    ci = Core.Compiler.retrieve_code_info(mi)
    YaoLang.Compiler.convert_to_quantum_head!(ci)

    # type infer
    result = Core.Compiler.InferenceResult(mi)
    world = Core.Compiler.get_world_counter()
    interp = YaoLang.Compiler.YaoInterpreter()
    frame = Core.Compiler.InferenceState(result, ci, #=cached=# true, interp)
    Core.Compiler.typeinf_local(interp, frame)
    ci = result.result.src

    nargs = length(sigs.parameters)
    return RoutineInfo(YaoIR(ci, nargs+1), ci, routine, sigs)
end

function RoutineInfo(::Type{RoutineSpec{P, Sigs, Stub}}) where {P, Sigs, Stub}
    return RoutineInfo(P, Stub.instance, Sigs)
end

# export YaoIR

# struct Intrinsic
#     name::Symbol
#     sigs
# end

# """
#     YaoIR

# The Yao Intermediate Representation. See compilation section for more details.

#     YaoIR([m::Module=YaoLang.Compiler], ast::Expr)

# Creates a `YaoIR` from Julia AST.
# """
# mutable struct YaoIR
#     mod::Module
#     name::Any
#     args::Vector{Any}
#     whereparams::Vector{Any}
#     body::IR
#     quantum_blocks::Any # Vector{Tuple{Int, UnitRange{Int}}}
#     pure_quantum::Bool
#     qasm_compatible::Bool
# end

# function YaoIR(m::Module, ast::Expr)
#     defs = splitdef(ast; throw = false)
#     defs === nothing && throw(ParseError("expect function definition"))

#     # potentially we could have code transform pass
#     # on frontend AST as well here, but not necessary
#     # for now, and all syntax related things should
#     # go into to_function transformation
#     ex = to_function(m, defs[:body])
#     lowered_ast = Meta.lower(m, ex)

#     if lowered_ast === nothing
#         body = IR()
#     else
#         body = IR(lowered_ast.args[], 0)
#     end

#     ir = YaoIR(
#         m,
#         defs[:name],
#         get(defs, :args, Any[]),
#         get(defs, :whereparams, Any[]),
#         mark_quantum(body),
#         nothing,
#         false,
#         false,
#     )
#     update_slots!(ir)
#     return ir
# end

# YaoIR(ast::Expr) = YaoIR(@__MODULE__, ast)

# function Base.copy(ir::YaoIR)
#     YaoIR(
#         ir.mod,
#         ir.name isa Expr ? copy(ir.name) : ir.name,
#         copy(ir.args),
#         copy(ir.whereparams),
#         copy(ir.body),
#         ir.quantum_blocks === nothing ? nothing : copy(ir.quantum_blocks),
#         ir.pure_quantum,
#         ir.qasm_compatible,
#     )
# end

# """
#     mark_quantum(ir::IR)

# swap the statement tag with `:quantum`.
# """
# function mark_quantum(ir::IR)
#     for (v, st) in ir
#         if (st.expr isa Expr) && (st.expr.head === :call) && (st.expr.args[1] isa GlobalRef)
#             ref = st.expr.args[1]
#             if ref.mod === Compiler && ref.name in RESERVED
#                 ir[v] = Statement(st; expr = Expr(:quantum, ref.name, st.expr.args[2:end]...))
#             end
#         end

#         # mark quantum meta
#         if (st.expr isa Expr) && (st.expr.head === :meta) && (st.expr.args[1] in RESERVED)
#             ir[v] = Statement(st; expr = Expr(:quantum, st.expr.args...))
#         end
#     end
#     return ir
# end


# function update_slots!(ir::YaoIR)
#     fn_args = arguements(ir)
#     for (v, st) in ir.body
#         if st.expr isa Expr
#             args = Any[]
#             for each in st.expr.args
#                 if each in fn_args
#                     push!(args, IRTools.Slot(each))
#                 else
#                     push!(args, each)
#                 end
#             end
#             ir.body[v] = Statement(st; expr = Expr(st.expr.head, args...))
#         elseif (st.expr isa Symbol) && (st.expr in fn_args)
#             ir.body[v] = Statement(st; expr = IRTools.Slot(st.expr))
#         end
#     end
#     return ir
# end
