module OpenEphys
# Module to interact with Open Ephys files
import Base: size, linearindexing, getindex, setindex!, length

export
    # types
    OriginalHeader,
    ContinuousData,
    # functions
    loaddirectory,
    loadcontinuous,
    interpolate_timestamps,
    # errors
    UnreadableError

## source files

include("common.jl")
include("original.jl")
include("continuous.jl")

end # module OpenEphys
