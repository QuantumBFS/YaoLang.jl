var documenterSearchIndex = {"docs":
[{"location":"#Introduction-1","page":"Home","title":"Introduction","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"YaoLang is a domain specific language (DSL) built based on Julia builtin expression with extended semantic on quantum control, measure and position. Its (extended) syntax is very simple:","category":"page"},{"location":"#Semantics-1","page":"Home","title":"Semantics","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"The semantic of YaoLang tries to make use of Julia semantic as much as possible so you don't feel this is not Julian. But since the quantum circuit has some special semantic that Julia expression cannot express directly, the semantic of Julia expression is extended in YaoLang.","category":"page"},{"location":"#","page":"Home","title":"Home","text":"The point of this new IR is it make use of Julia native control flow directly instead of unroll the loop and conditions into a Julia type, such as Chain, Kron, ConditionBlock in QBIR, which improves the performance and provide possibility of further compiler optimization by analysis done on quantum circuit and classical control flows.","category":"page"},{"location":"#Gate-Position-1","page":"Home","title":"Gate Position","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"gate positions are specific with => at each line, the => operator inside function calls will not be parsed, e.g","category":"page"},{"location":"#","page":"Home","title":"Home","text":"1 => H # apply Hadamard gate on the 1st qubit\nfoo(1=>H) # it means normal Julia pair\n1=>foo(x, y, z) # it will parse foo(x, y, z) as a quantum gate/circuit, but will error later if type inference finds they are not.","category":"page"},{"location":"#","page":"Home","title":"Home","text":"all the gate or circuit's position should be specified by its complete locations, e.g","category":"page"},{"location":"#","page":"Home","title":"Home","text":"1:n => qft(n) # right\n1 => qft(n) # wrong","category":"page"},{"location":"#","page":"Home","title":"Home","text":"but single qubit gates can use multi-location argument to represent repeated locations, e.g","category":"page"},{"location":"#","page":"Home","title":"Home","text":"1:n => H # apply H on 1:n locations","category":"page"},{"location":"#Control-1","page":"Home","title":"Control","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"@ctrl is parsed as a keyword (means you cannot overload it) in each program, like QBIR, its first argument is the control location with signs as control configurations and the second argument is a normal gate position argument introduce above.","category":"page"},{"location":"#Measure-1","page":"Home","title":"Measure","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"@measure is another reserved special function parsed that has specific semantic in the IR (measure the locations passed to it).","category":"page"},{"location":"#Usage-1","page":"Home","title":"Usage","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"using it is pretty simple, just use @device macro to annotate a \"device\" function, like CUDA programming, this device function should not return anything but nothing.","category":"page"},{"location":"#","page":"Home","title":"Home","text":"The compiler will compile this function definition to a generic circuit Circuit with the same name. A generic circuit is a generic quantum program that can be overload with different Julia types, e.g","category":"page"},{"location":"#","page":"Home","title":"Home","text":"@device function qft(n::Int)\n    1 => H\n    for k in 2:n\n        @ctrl k 1=>shift(2π/2^k)\n    end\n\n    if n > 1\n        2:n => qft(n-1)\n    end\nend","category":"page"},{"location":"#","page":"Home","title":"Home","text":"There is no need to worry about global position: everything can be defined locally and we will infer the correct global location later either in compile time or runtime.","category":"page"},{"location":"#","page":"Home","title":"Home","text":"note: all the quantum gates should be annotate with its corresponding locations, or the compiler will not treat it as a quantum gate but instead of the original Julia expression.","category":"page"},{"location":"#Why?-1","page":"Home","title":"Why?","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"There are a few reasons that we need a fully compiled DSL now.","category":"page"},{"location":"#.-Extensibility-1","page":"Home","title":"1. Extensibility","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"Things in YaoBlocks like","category":"page"},{"location":"#","page":"Home","title":"Home","text":"function apply!(r::AbstractRegister, pb::PutBlock{N}) where {N}\n    _check_size(r, pb)\n    instruct!(r, mat_matchreg(r, pb.content), pb.locs)\n    return r\nend\n\n# specialization\nfor G in [:X, :Y, :Z, :T, :S, :Sdag, :Tdag]\n    GT = Expr(:(.), :ConstGate, QuoteNode(Symbol(G, :Gate)))\n    @eval function apply!(r::AbstractRegister, pb::PutBlock{N,C,<:$GT}) where {N,C}\n        _check_size(r, pb)\n        instruct!(r, Val($(QuoteNode(G))), pb.locs)\n        return r\n    end\nend","category":"page"},{"location":"#","page":"Home","title":"Home","text":"cannot be easily extended without define new dispatch on specialized instruction. Similarly, as long as there is a new instruction in low level, one need to redefine the dispatch in YaoBlocks however this is not necessary!","category":"page"},{"location":"#.-Work-with-classical-computers-1","page":"Home","title":"2. Work with classical computers","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"Programs defined in such way are just \"normal\" Julia programs, but quantum devices can be used as accelerator in a similar way comparing to GPU as an optimization.","category":"page"},{"location":"#.-More-elegant-and-better-performance-1","page":"Home","title":"3. More elegant and better performance","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"In YaoBlocks, a large quantum circuit can easily lost its structure if it is controlled, unless the programmer specialize the control block manually. Now we can map local locations into its callee location using the brand new API, thus anything in theory is composable can be executed in such way.","category":"page"},{"location":"#API-References-1","page":"Home","title":"API References","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"Modules = [YaoLang]","category":"page"},{"location":"#YaoLang.H","page":"Home","title":"YaoLang.H","text":"H\n\nThe Hadamard gate.\n\nDefinition\n\nfrac1sqrt2 beginpmatrix\n1  1\n1  -1\nendpmatrix\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Rx","page":"Home","title":"YaoLang.Rx","text":"Rx(theta::Real)\n\nReturn a rotation gate on X axis.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Ry","page":"Home","title":"YaoLang.Ry","text":"Ry(theta::Real)\n\nReturn a rotation gate on Y axis.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Rz","page":"Home","title":"YaoLang.Rz","text":"Rz(theta::Real)\n\nReturn a rotation gate on Z axis.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.T","page":"Home","title":"YaoLang.T","text":"T\n\nThe T gate.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.X","page":"Home","title":"YaoLang.X","text":"X\n\nThe Pauli X gate.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Y","page":"Home","title":"YaoLang.Y","text":"Y\n\nThe Pauli Y gate.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Z","page":"Home","title":"YaoLang.Z","text":"Z\n\nThe Pauli Z gate.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.phase","page":"Home","title":"YaoLang.phase","text":"phase(theta)\n\nGlobal phase gate.\n\nDefinition\n\nexp(iθ) mathbfI\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.rot","page":"Home","title":"YaoLang.rot","text":"rot(axis, θ::T, m::Int=size(axis, 1)) where {T <: Real}\n\nGeneral rotation gate, axis is the rotation axis, θ is the rotation angle. m is the size of rotation space, default is the size of rotation axis.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.shift","page":"Home","title":"YaoLang.shift","text":"shift(θ::Real)\n\nPhase shift gate.\n\nDefinition\n\nbeginpmatrix\n1  0\n0  e^(im θ)\nendpmatrix\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.GenericCircuit","page":"Home","title":"YaoLang.GenericCircuit","text":"GenericCircuit{name}\n\nGeneric quantum circuit is the quantum counterpart of generic function.\n\n\n\n\n\n","category":"type"},{"location":"#YaoLang.Locations","page":"Home","title":"YaoLang.Locations","text":"Locations <: AbstractLocations\n\nType to annotate locations in quantum circuit.\n\nLocations(x)\n\nCreate a Locations object from a raw location statement. Valid storage types are:\n\nInt: single position\nNTuple{N, Int}: a list of locations\nUnitRange{Int}: contiguous locations\n\nOther types will be converted to the storage type via Tuple.\n\n\n\n\n\n","category":"type"},{"location":"#YaoLang.merge_locations-Tuple{AbstractLocations,AbstractLocations,Vararg{AbstractLocations,N} where N}","page":"Home","title":"YaoLang.merge_locations","text":"merge_locations(locations...)\n\nConstruct a new Locations by merging two or more existing locations.\n\n\n\n\n\n","category":"method"}]
}