__precompile__()
module OpenEphysLoader
# Module to interact with Open Ephys files
import Base: show, showcompact, size, linearindexing, getindex, setindex!, length

export
    # types
    OriginalHeader,
    SampleArray,
    TimeArray,
    RecNoArray,
    JointArray,
    CorruptedException

## source files
include("original.jl")
include("continuous.jl")

end # module OpenEphys
