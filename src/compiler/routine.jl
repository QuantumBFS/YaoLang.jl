const compilecache = Dict{UInt, Any}()
const operation_annotation_color = :light_black

"""
    Routine

Abstract type for general YaoLang programs.
"""
abstract type Routine end

"""
    Operation

Abstract type operations on registers. `Operation`s
are objects that can be applied to a register. This
can be a non-parameterized gate, or parameterized gate
with known parameters, or pulses.
"""
abstract type Operation end

struct GenericRoutine{name} <: Routine end
struct IntrinsicRoutine{name} <: Routine end


struct IntrinsicSpec{name, Vars} <: Operation
    variables::Vars

    function IntrinsicSpec{name}(xs...) where name
        new{name, typeof(xs)}(xs)
    end

    function IntrinsicSpec(::IntrinsicRoutine{name}, xs...) where name
        new{name, typeof(xs)}(xs)
    end
end

function Base.show(io::IO, x::IntrinsicSpec{name}) where name
    print(io, name)
    if !isempty(x.variables)
        print(io, "(")
        join(io, x.variables, ", ")
        print(io, ")")
    end
    printstyled(io, " (intrinsic operation)"; color=operation_annotation_color)
    return
end

function Base.show(io::IO, fn::GenericRoutine{name}) where name
    print(io, name)
    printstyled(io, " (generic routine with ", length(methods(fn).ms), " methods)"; color=operation_annotation_color)
end

function Base.show(io::IO, fn::IntrinsicRoutine{name}) where name
    print(io, name)
    printstyled(io, " (intrinsic routine)"; color=operation_annotation_color)
end

# NOTE: kwargs is not supported for now
struct RoutineSpec{P, Vars} <: Operation
    parent::P
    variables::Vars

    function RoutineSpec(parent, vars...)
        new{typeof(parent), typeof(vars)}(parent, vars)
    end
end

function Base.hash(routine::RoutineSpec{P, Vars}, key) where {P, Vars}
    return hash(Tuple{P, Vars}, key)
end

# NOTE: the reason we don't use a gensym
# here for stub function is 
"stub for routine CodeInfo"
struct RoutineStub end

const routine_stub = RoutineStub()

struct Adjoint{P <: Operation} <: Operation
    parent::P
end

Base.adjoint(x::Operation) = Adjoint(x)
Base.adjoint(x::Adjoint) = x.parent

routine_name(x) = routine_name(typeof(x))
routine_name(::Type{<:GenericRoutine{name}}) where name = name
routine_name(::Type{<:IntrinsicRoutine{name}}) where name = name
routine_name(::Type{<:IntrinsicSpec{name}}) where name = name
routine_name(::Type{<:RoutineSpec{P}}) where P = routine_name(P)
routine_name(::Type{<:Adjoint{P}}) where P = Symbol(routine_name(P), "_dag")

struct DeviceError <: Exception
    msg::String
end

"""
Semantic extension for Julia.
"""
module Semantic
using ExprTools
using ..Compiler: DeviceError, Operation, Locations, CtrlLocations

# semantic stubs
const SEMANTIC_STUBS = Symbol[]
const PRESERVED_MACROS = Symbol[]

macro semantic_stub(ex::Expr)
    ex.head === :call || throw(ParseError("expect function call"))
    ex.args[1] isa Symbol || throw(ParseError("stub must be a function"))

    def = Dict{Symbol, Any}()
    name = ex.args[1]
    macroname = Symbol("@$name")
    def[:name] = name
    def[:args] = ex.args[2:end]
    err = DeviceError("@$name is not executed as a quantum program")
    def[:body] = quote
        throw($err)
    end

    quote
        push!(SEMANTIC_STUBS, $(QuoteNode(name)))
        push!(PRESERVED_MACROS, $(QuoteNode(macroname)))
        @noinline $(combinedef(def))
    end |> esc
end

@semantic_stub ctrl(gate::Operation, loc::Locations, ctrl::CtrlLocations)
@semantic_stub gate(gate::Operation, loc::Locations)
@semantic_stub measure(locs::Locations, op; kwargs...)
@semantic_stub barrier(locs::Locations)

end # Semantic

function gate_sugar(ex::Expr)
    is_gate_location(ex) ||
        throw(ParseError("invalid syntax for gate: $ex"))
    return ex.args[3], ex.args[2]
end

function gate_m(ex::Expr)
    gate, locs = gate_sugar(ex)
    return :($(GlobalRef(Semantic, :gate))($gate, $Locations($locs)))
end

function ctrl_m(ctrl, ex::Expr)
    gate, locs = gate_sugar(ex)
    return :($(GlobalRef(Semantic, :ctrl))($gate, $Locations($locs), $CtrlLocations($ctrl)))
end

macro ctrl(ctrl, ex::Expr)
    return esc(ctrl_m(ctrl, ex))
end

macro gate(ex::Expr)
    return esc(gate_m(ex))
end

macro measure(args...)
    length(args) || throw(ArgumentError("@meausre expects at most 3 arguments"))
    
    # kwargs
    option = Expr(:parameters)
    args = []
    for each in args
        if each isa Expr && each.head == :(=)
            key, val = each.args
            if key === :reset_to
                option = Expr(:parameters, Expr(:kw, key, val))
            elseif key === :remove
                val isa Bool || throw(ArgumentError("`remove` keyword argument should be a constant value"))
                option = Expr(:parameters, Expr(:kw, key, val))
            else
                throw(ParseError("unknown measurement option $(each)"))
            end
        else
            push!(args, each)
        end
    end

    locs = :($Locations($(args[1])))
    if length(args) == 1 # only has location
        return Expr(:call, GlobalRef(Semantic, :measure), option, locs, nothing)
    elseif length(args) == 2 # has operator
        return Expr(:call, GlobalRef(Semantic, :measure), option, locs, args[2])
    end
end

macro barrier(locs)
    return esc(Expr(:call, GlobalRef(Semantic, :barrier), locs))
end

macro device(ex::Expr)
    def = splitdef(ex; throw=false)

    if isnothing(def)
        ex.head === :call || throw(ParseError("invalid syntax of @device: $ex"))
        return esc(device_call(ex))
    end
    return esc(device_def(def))
end

macro device(ex...)
    call = ex[end]
    kwargs = ex[1:end-1]
    return esc(device_call(call, kwargs))
end

# frontend, only handles some syntax sugars
function device_def(def::Dict)
    args = get(def, :args, Any[])
    stub_def = copy(def)
    device_def = copy(def)
    code = Expr(:block)
    isfunction = !(haskey(def, :name) && !(def[:name] isa Symbol))

    if haskey(def, :name) && !(def[:name] isa Symbol)
        self = rm_annotations(def[:name])
        self_annotation = annotations(def[:name])
        name = nothing
    else
        self = gensym(:self)
        name = get(def, :name, gensym(:device))
        self_annotation = GenericRoutine{name}
    end

    device_def[:name] = :($self::$self_annotation)
    device_def[:body] = quote
        $RoutineSpec($self, $(rm_annotations.(args)...))
    end

    stub_def[:name] = :(::$RoutineStub)
    stub_def[:args] = [:($self::$self_annotation), args...]
    stub_def[:body] = preprocess_device_gate_syntax(def[:body])

    push!(code.args, combinedef(device_def))
    push!(code.args, combinedef(stub_def))
    
    if !isnothing(name)
        push!(code.args, :(const $name = $self_annotation() ))
    end

    push!(code.args, name)
    return code
end

function preprocess_device_gate_syntax(ex)
    ex isa Expr || return ex
    if is_gate_location(ex)
        location = ex.args[2]
        gate = ex.args[3]
        return Expr(:call, GlobalRef(Semantic, :gate), gate, :($Locations($location)))
    end

    #= make @inbounds etc. work =#
    # exclude YaoLang macros
    if ex.head in [:block, :if, :for] || (ex.head === :macrocall && !is_preserved_macro(ex))
        return Expr(ex.head, map(preprocess_device_gate_syntax, ex.args)...)
    end
    return ex
end

function device_call(ex::Expr, kwargs)
end

function is_gate_location(ex)
    ex isa Expr || return false
    return (ex.head === :call) && (ex.args[1] == :(=>))
end

function is_preserved_macro(ex::Expr)
    ex.head === :macrocall || return false
    return ex.args[1] in Semantic.PRESERVED_MACROS
end

function (spec::RoutineSpec)(r::AbstractRegister, locs::Locations)
    return execute(spec, r, locs)
end

function (spec::RoutineSpec)(r::AbstractRegister, locs::Locations, ctrl::CtrlLocations)
    return execute(spec, r, locs, ctrl)
end
