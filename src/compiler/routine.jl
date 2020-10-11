export Routine, GenericRoutine, IntrinsicRoutine, RoutineSpec, @ctrl, @measure, @gate, @barrier, @device

const compilecache = Dict{UInt, Any}()

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
        new{name, typeof(xs)}(parent, xs)
    end
end

function Base.show(io::IO, x::IntrinsicSpec{name}) where name
    return show(io, name, " (intrinsic operation)")
end

export H, shift
const H = IntrinsicSpec{:H}()
const shift = IntrinsicRoutine{:shift}()

Base.adjoint(::IntrinsicSpec{:H}) = H
Base.adjoint(s::IntrinsicSpec{:shift}) = IntrinsicSpec{:shift}(adjoint(s.variables[1]))

function (p::IntrinsicRoutine{:shift})(theta::Real)
    return IntrinsicSpec(p, theta)
end

function Base.show(io::IO, fn::GenericRoutine{name}) where name
    print(io, name, " (generic routine with ", length(methods(fn).ms), " methods)")
end

function Base.show(io::IO, fn::IntrinsicRoutine{name}) where name
    print(io, name, " (intrinsic routine)")
end

# NOTE: kwargs is not supported for now
struct RoutineSpec{P, Vars, Stub} <: Operation
    stub::Stub
    parent::P
    variables::Vars

    function RoutineSpec(stub, parent, vars...)
        new{typeof(parent), typeof(vars), typeof(stub)}(stub, parent, vars)
    end
end

function Base.hash(routine::RoutineSpec{P, Vars}, key) where {P, Vars}
    return hash(Tuple{P, Vars}, key)
end

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
    err = DeviceError("@$name should be called inside @device macro")
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
@semantic_stub barrier()

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

macro barrier()
    return esc(Expr(:call, GlobalRef(Semantic, :barrier)))
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
    if haskey(def, :name)
        if def[:name] isa Symbol
            return def_function(def)
        else
            return def_struct(def)
        end
    else
        return def_function(def)
    end
end

function def_function(def::Dict)
    args = get(def, :args, Any[])
    device_def, stub_def, code = _initialize_code(def)
    stub_name = stub_def[:name]
    name = get(def, :name, gensym(:device))
    self = gensym(:self)
    device_def[:name] = :($self::$GenericRoutine{$(QuoteNode(name))})
    device_def[:body] = quote
        $RoutineSpec($stub_name, $self, $(rm_annotations.(args)...))
    end

    push!(code.args, combinedef(stub_def))
    push!(code.args, combinedef(device_def))
    # create global symbol
    push!(code.args, :(const $name = $GenericRoutine{$(QuoteNode(name))}() ))
    push!(code.args, name)
    return code
end

function def_struct(def::Dict)
    args = copy(get(def, :args, Any[]))
    device_def, stub_def, code = _initialize_code(def)
    stub_name = stub_def[:name]
    self = rm_annotations(def[:name])
    self_annotation = annotations(def[:name])

    if isnothing(self)
        self = gensym(:self)
        device_def[:name] = :($self::$self_annotation)
    else
        device_def[:name] = def[:name]
    end

    pushfirst!(args, :($self::$self_annotation))
    stub_def[:args] = args
    device_def[:body] = quote
        $RoutineSpec($stub_name, $self, $(rm_annotations.(args)...))
    end

    push!(code.args, combinedef(stub_def))
    push!(code.args, combinedef(device_def))
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

function _initialize_code(def::Dict)
    code = Expr(:block)
    device_def = copy(def)
    stub_def = copy(def)
    stub_def[:name] = gensym(:device_stub)
    stub_def[:body] = preprocess_device_gate_syntax(def[:body])
    return device_def, stub_def, code
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

# # TODO: use CUDA's approach to trigger recompilation
# @generated function (routine::RoutineSpec)(r::AbstractRegister, locs::Locations)
#     ci = cached_compilation(routine, r, locs)
# end

# @generated function (routine::RoutineSpec)(r::AbstractRegister, locs::Locations, ctrl_locs::Locations)
#     ci = cached_compilation(routine, r, locs, ctrl_locs)
# end

