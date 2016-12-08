__precompile__()
module OpenEphysLoader
# Module to interact with Open Ephys files
import Base: show, showcompact, size, linearindexing, getindex, setindex!, length

export
    # types
    OriginalHeader,
    ContinuousFile,
    SampleArray,
    TimeArray,
    RecNoArray,
    JointArray

## source files
include("common.jl")
include("original.jl")
include("continuous.jl")

end # module OpenEphys
