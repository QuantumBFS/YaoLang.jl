var documenterSearchIndex = {"docs":
[{"location":"compilation/#","page":"Compilation","title":"Compilation","text":"CurrentModule = YaoLang.Compiler","category":"page"},{"location":"compilation/#Compilation-1","page":"Compilation","title":"Compilation","text":"","category":"section"},{"location":"compilation/#","page":"Compilation","title":"Compilation","text":"The compilation framework of YaoLang is designed to be highly extensible, so one can easily extend the semantics as long as there is no ambiguity.","category":"page"},{"location":"compilation/#","page":"Compilation","title":"Compilation","text":"For simple code generation task, one can use Julia native macros directly instead of writing a custom compiler pass. But for more complicated task, one would prefer to add a custom compiler pass.","category":"page"},{"location":"compilation/#Representation-1","page":"Compilation","title":"Representation","text":"","category":"section"},{"location":"compilation/#","page":"Compilation","title":"Compilation","text":"YaoLang is a domain specific language, it embeds its own representation inside the Julia AST and SSA IR.","category":"page"},{"location":"compilation/#","page":"Compilation","title":"Compilation","text":"The Julia AST captured by a macro @device will be first transformed into custom function calls tagged with GlobalRef(YaoLang.Compiler, :node_name). The syntax check will then check if the syntax is correct, then the AST will be compiled into Julia's SSA IR as a CodeInfo object.","category":"page"},{"location":"compilation/#","page":"Compilation","title":"Compilation","text":"Then we transform the CodeInfo object to a quantum SSA IR by inferring the quantum statements, where we call this representation as YaoIR.","category":"page"},{"location":"compilation/#YaoIR-1","page":"Compilation","title":"YaoIR","text":"","category":"section"},{"location":"compilation/#","page":"Compilation","title":"Compilation","text":"The Yao IR annotates our domain specific semantics using a :quantum head, followed by a custom head, such as :gate. For example, 1 => X will be parsed as Expr(:quantum, :gate, :X, 1).","category":"page"},{"location":"compilation/#Compiler-API-References-1","page":"Compilation","title":"Compiler API References","text":"","category":"section"},{"location":"compilation/#","page":"Compilation","title":"Compilation","text":"Modules = [YaoLang.Compiler]","category":"page"},{"location":"compilation/#YaoLang.Compiler.YaoIR","page":"Compilation","title":"YaoLang.Compiler.YaoIR","text":"YaoIR\n\nThe Yao Intermediate Representation. See compilation section for more details.\n\nYaoIR([m::Module=YaoLang.Compiler], ast::Expr)\n\nCreates a YaoIR from Julia AST.\n\n\n\n\n\n","category":"type"},{"location":"compilation/#YaoLang.Compiler.is_qasm_compatible-Tuple{IRTools.Inner.IR}","page":"Compilation","title":"YaoLang.Compiler.is_qasm_compatible","text":"is_qasm_compatible(ir)\n\nCheck if the given expression is compatible with openQASM.\n\n\n\n\n\n","category":"method"},{"location":"compilation/#YaoLang.Compiler.is_quantum-Tuple{IRTools.Inner.Statement}","page":"Compilation","title":"YaoLang.Compiler.is_quantum","text":"is_quantum(ex)\n\nCheck if the given expression is a quantum statement.\n\n\n\n\n\n","category":"method"},{"location":"compilation/#ZXCalculus.gate_count-Tuple{GenericCircuit}","page":"Compilation","title":"ZXCalculus.gate_count","text":"gate_count(circuit)::Dict\n\nCount the number of each primitive instructions in given pure quantum circuit.\n\n\n\n\n\n","category":"method"},{"location":"compilation/#YaoLang.Compiler.@code_yao-Tuple{Any}","page":"Compilation","title":"YaoLang.Compiler.@code_yao","text":"@code_yao <generic circuit call>\n\nEvaluates the arguments to the function call, determines their types, and calls code_yao on the resulting expression.\n\n\n\n\n\n","category":"macro"},{"location":"compilation/#YaoLang.Compiler.@ctrl","page":"Compilation","title":"YaoLang.Compiler.@ctrl","text":"@ctrl k <gate location>\n\nKeyword for controlled gates in quantum circuit. It must be used inside @device. See also @device.\n\n\n\n\n\n","category":"macro"},{"location":"compilation/#YaoLang.Compiler.@device","page":"Compilation","title":"YaoLang.Compiler.@device","text":"@device [options] <generic circuit definition>\n\nEntry for defining a generic quantum program. A generic quantum program is a function takes a set of classical arguments as input and return a quantum program that can be furthur compiled into pulses or other quantum instructions. The quantum program can return classical values from device if return statement is declared explicitly, or it always return nothing, and mutates the quantum register.\n\nSupported Semantics\n\n@ctrl: Keyword for controlled gates in quantum circuit.\n@measure: Keyword for measurement in quantum circuit.\n\nThe function marked by @device can be multiple dispatched like other Julia function. The only difference is that it always returns a quantum circuit object that should be runable on quantum device by feeding it the location of qubits and the pointer to quantum register.\n\nOptions\n\ntarget, compilation target, default is :julia, see Compilation Targets for details.\n\nCompilation Targets\n\n:julia, default target, compiles the program to Julia program.\n:qasm, compiles the program to openQASM.\n\nExample\n\nWe can define a Quantum Fourier Transformation in the following recursive way\n\n@device function qft(n::Int)\n    1 => H\n    for k in 2:n\n        @ctrl k 1=>shift(2π/2^k)\n    end\n\n    if n > 1\n        2:n => qft(n-1)\n    end\nend\n\nThis will give us a generic quantum circuit qft with 1 method.\n\n\n\n\n\n","category":"macro"},{"location":"compilation/#YaoLang.Compiler.@measure","page":"Compilation","title":"YaoLang.Compiler.@measure","text":"@measure <location> [operator] [configuration]\n\nKeyword for measurement in quantum circuit. It must be used inside @device. See also @device.\n\nArguments\n\n<location>: a valid Locations argument to specifiy where to measure the register\n[operator]: Optional, specifiy which operator to measure\n[configuration]: Optional, it can be either:\nremove=true will remove the measured qubits\nreset_to=<bitstring> will reset the measured qubits to given bitstring\n\n\n\n\n\n","category":"macro"},{"location":"compilation/#YaoLang.Compiler.@primitive-Tuple{Any}","page":"Compilation","title":"YaoLang.Compiler.@primitive","text":"@primitive ex\n\nDefine a primitive quantum instruction. ex can be a Symbol, if the corresponding instruction interface of YaoAPI.instruct! is implemented. Or ex can be an assignment statement for constant instructions. Or ex can be a function that returns corresponding matrix given a set of classical parameters.\n\nExample\n\nSince the instructions interface YaoAPI.instruct! of Pauli operators are defined, we can use\n\n@primitive X\n\nto declare a Pauli X primitive instruction.\n\nOr we can also define a Hadamard primitive instruction via its matrix form\n\n@primitive H = [1 1;1 -1]/sqrt(2)\n\nFor parameterized gates, such as phase shift gate, we can define it as\n\n@primitive shift(θ::Real) = Diagonal([1.0, exp(im * θ)])\n\n\n\n\n\n","category":"macro"},{"location":"compilation/#YaoLang.Compiler.@quantum-Tuple{Int64,Any}","page":"Compilation","title":"YaoLang.Compiler.@quantum","text":"@quantum nqubits::Int <generic circuit call>\n\nPartially evaluate all classical parts of the generic circuit.\n\nnote: Note\nThe classical part of the program could result in different circuits if it is not deterministic.\n\n\n\n\n\n","category":"macro"},{"location":"compilation/#YaoLang.Compiler.generate_forward_stub-Tuple{Symbol,Any}","page":"Compilation","title":"YaoLang.Compiler.generate_forward_stub","text":"generate_forward_stub(name::Symbol, op)\n\nGenerate forward stub which forward primitive circuit to instruction interfaces.\n\n\n\n\n\n","category":"method"},{"location":"compilation/#YaoLang.Compiler.mark_quantum-Tuple{IRTools.Inner.IR}","page":"Compilation","title":"YaoLang.Compiler.mark_quantum","text":"mark_quantum(ir::IR)\n\nswap the statement tag with :quantum.\n\n\n\n\n\n","category":"method"},{"location":"compilation/#YaoLang.Compiler.rm_annotations-Tuple{Any}","page":"Compilation","title":"YaoLang.Compiler.rm_annotations","text":"rm_annotations(x)\n\nRemove type annotation of given expression.\n\n\n\n\n\n","category":"method"},{"location":"#","page":"Home","title":"Home","text":"CurrentModule = YaoLang.Compiler","category":"page"},{"location":"#Introduction-1","page":"Home","title":"Introduction","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"YaoLang is a domain specific language (DSL) built based on Julia builtin expression with extended semantic on quantum control, measure and position. Its (extended) syntax is very simple:","category":"page"},{"location":"#Semantics-1","page":"Home","title":"Semantics","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"The semantic of YaoLang tries to make use of Julia semantic as much as possible so you don't feel this is not Julian. But since the quantum circuit has some special semantic that Julia expression cannot express directly, the semantic of Julia expression is extended in YaoLang.","category":"page"},{"location":"#","page":"Home","title":"Home","text":"The point of this new IR is it make use of Julia native control flow directly instead of unroll the loop and conditions into a Julia type, such as Chain, Kron, ConditionBlock in QBIR, which improves the performance and provide possibility of further compiler optimization by analysis done on quantum circuit and classical control flows.","category":"page"},{"location":"#Gate-Position-1","page":"Home","title":"Gate Position","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"gate positions are specific with => at each line, the => operator inside function calls will not be parsed, e.g","category":"page"},{"location":"#","page":"Home","title":"Home","text":"1 => H # apply Hadamard gate on the 1st qubit\nfoo(1=>H) # it means normal Julia pair\n1=>foo(x, y, z) # it will parse foo(x, y, z) as a quantum gate/circuit, but will error later if type inference finds they are not.","category":"page"},{"location":"#","page":"Home","title":"Home","text":"all the gate or circuit's position should be specified by its complete locations, e.g","category":"page"},{"location":"#","page":"Home","title":"Home","text":"1:n => qft(n) # right\n1 => qft(n) # wrong","category":"page"},{"location":"#","page":"Home","title":"Home","text":"but single qubit gates can use multi-location argument to represent repeated locations, e.g","category":"page"},{"location":"#","page":"Home","title":"Home","text":"1:n => H # apply H on 1:n locations","category":"page"},{"location":"#Control-1","page":"Home","title":"Control","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"@ctrl is parsed as a keyword (means you cannot overload it) in each program, like QBIR, its first argument is the control location with signs as control configurations and the second argument is a normal gate position argument introduce above.","category":"page"},{"location":"#Measure-1","page":"Home","title":"Measure","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"@measure is another reserved special function parsed that has specific semantic in the IR (measure the locations passed to it).","category":"page"},{"location":"#Usage-1","page":"Home","title":"Usage","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"using it is pretty simple, just use @device macro to annotate a \"device\" function, like CUDA programming, this device function should not return anything but nothing.","category":"page"},{"location":"#","page":"Home","title":"Home","text":"The compiler will compile this function definition to a generic circuit Circuit with the same name. A generic circuit is a generic quantum program that can be overload with different Julia types, e.g","category":"page"},{"location":"#","page":"Home","title":"Home","text":"@device function qft(n::Int)\n    1 => H\n    for k in 2:n\n        @ctrl k 1=>shift(2π/2^k)\n    end\n\n    if n > 1\n        2:n => qft(n-1)\n    end\nend","category":"page"},{"location":"#","page":"Home","title":"Home","text":"There is no need to worry about global position: everything can be defined locally and we will infer the correct global location later either in compile time or runtime.","category":"page"},{"location":"#","page":"Home","title":"Home","text":"note: all the quantum gates should be annotate with its corresponding locations, or the compiler will not treat it as a quantum gate but instead of the original Julia expression.","category":"page"},{"location":"#Why?-1","page":"Home","title":"Why?","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"There are a few reasons that we need a fully compiled DSL now.","category":"page"},{"location":"#.-Extensibility-1","page":"Home","title":"1. Extensibility","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"Things in YaoBlocks like","category":"page"},{"location":"#","page":"Home","title":"Home","text":"function apply!(r::AbstractRegister, pb::PutBlock{N}) where {N}\n    _check_size(r, pb)\n    instruct!(r, mat_matchreg(r, pb.content), pb.locs)\n    return r\nend\n\n# specialization\nfor G in [:X, :Y, :Z, :T, :S, :Sdag, :Tdag]\n    GT = Expr(:(.), :ConstGate, QuoteNode(Symbol(G, :Gate)))\n    @eval function apply!(r::AbstractRegister, pb::PutBlock{N,C,<:$GT}) where {N,C}\n        _check_size(r, pb)\n        instruct!(r, Val($(QuoteNode(G))), pb.locs)\n        return r\n    end\nend","category":"page"},{"location":"#","page":"Home","title":"Home","text":"cannot be easily extended without define new dispatch on specialized instruction. Similarly, as long as there is a new instruction in low level, one need to redefine the dispatch in YaoBlocks however this is not necessary!","category":"page"},{"location":"#.-Work-with-classical-computers-1","page":"Home","title":"2. Work with classical computers","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"Programs defined in such way are just \"normal\" Julia programs, but quantum devices can be used as accelerator in a similar way comparing to GPU as an optimization.","category":"page"},{"location":"#.-More-elegant-and-better-performance-1","page":"Home","title":"3. More elegant and better performance","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"In YaoBlocks, a large quantum circuit can easily lost its structure if it is controlled, unless the programmer specialize the control block manually. Now we can map local locations into its callee location using the brand new API, thus anything in theory is composable can be executed in such way.","category":"page"},{"location":"#API-References-1","page":"Home","title":"API References","text":"","category":"section"},{"location":"#","page":"Home","title":"Home","text":"Modules = [YaoLang]","category":"page"},{"location":"#YaoLang.H","page":"Home","title":"YaoLang.H","text":"H\n\nThe Hadamard gate.\n\nDefinition\n\nfrac1sqrt2 beginpmatrix\n1  1\n1  -1\nendpmatrix\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Rx","page":"Home","title":"YaoLang.Rx","text":"Rx(theta::Real)\n\nReturn a rotation gate on X axis.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Ry","page":"Home","title":"YaoLang.Ry","text":"Ry(theta::Real)\n\nReturn a rotation gate on Y axis.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Rz","page":"Home","title":"YaoLang.Rz","text":"Rz(theta::Real)\n\nReturn a rotation gate on Z axis.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.T","page":"Home","title":"YaoLang.T","text":"T\n\nThe T gate.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.X","page":"Home","title":"YaoLang.X","text":"X\n\nThe Pauli X gate.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Y","page":"Home","title":"YaoLang.Y","text":"Y\n\nThe Pauli Y gate.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.Z","page":"Home","title":"YaoLang.Z","text":"Z\n\nThe Pauli Z gate.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.phase","page":"Home","title":"YaoLang.phase","text":"phase(theta)\n\nGlobal phase gate.\n\nDefinition\n\nexp(iθ) mathbfI\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.rot","page":"Home","title":"YaoLang.rot","text":"rot(axis, θ::T, m::Int=size(axis, 1)) where {T <: Real}\n\nGeneral rotation gate, axis is the rotation axis, θ is the rotation angle. m is the size of rotation space, default is the size of rotation axis.\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.shift","page":"Home","title":"YaoLang.shift","text":"shift(θ::Real)\n\nPhase shift gate.\n\nDefinition\n\nbeginpmatrix\n1  0\n0  e^(im θ)\nendpmatrix\n\n\n\n\n\n","category":"constant"},{"location":"#YaoLang.GenericCircuit","page":"Home","title":"YaoLang.GenericCircuit","text":"GenericCircuit{name}\n\nGeneric quantum circuit is the quantum counterpart of generic function.\n\n\n\n\n\n","category":"type"},{"location":"#YaoLang.Locations","page":"Home","title":"YaoLang.Locations","text":"Locations <: AbstractLocations\n\nType to annotate locations in quantum circuit.\n\nLocations(x)\n\nCreate a Locations object from a raw location statement. Valid storage types are:\n\nInt: single position\nNTuple{N, Int}: a list of locations\nUnitRange{Int}: contiguous locations\n\nOther types will be converted to the storage type via Tuple.\n\n\n\n\n\n","category":"type"},{"location":"#YaoLang.merge_locations-Tuple{AbstractLocations,AbstractLocations,Vararg{AbstractLocations,N} where N}","page":"Home","title":"YaoLang.merge_locations","text":"merge_locations(locations...)\n\nConstruct a new Locations by merging two or more existing locations.\n\n\n\n\n\n","category":"method"}]
}
