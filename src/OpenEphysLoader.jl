__precompile__()
"""
Module to read the binary data files created by the OpenEphys GUI

Provides array interfaces to file contents, without loading the entire file into memory
"""
module OpenEphysLoader
# Module to interact with Open Ephys files
using LightXML
import Base: show,
    showcompact,
    size,
    linearindexing,
    getindex,
    setindex!,
    length,
    LightXML: parse_file

export
    # types
    OriginalHeader,
    ContinuousFile,
    OEArray,
    OEContArray,
    SampleArray,
    TimeArray,
    RecNoArray,
    JointArray,
    CorruptedException

## source files
include("metadata.jl")
include("original.jl")
include("continuous.jl")

end # module OpenEphys
