module YaoIR
export measure, control

"""
    measure(locations)

Reserved keyword in YaoIR scripts.
"""
function measure end

"""
    control(ctrl_locations, locations => gate)

Reserved keyword in YaoIR scripts.
"""
function control end

# include("match.jl")
include("locations.jl")
include("lib/primitives.jl")

include("compiler/ir.jl")
include("compiler/compile.jl")

end # module
