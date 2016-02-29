module OpenEphys
# Module to interact with Open Ephys files

if VERSION < v"0.4-"
    using Dates
end

import Base: show, showerror, showcompact, ==

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
