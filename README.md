# Open Ephys Loader for Julia

A set of tools to load data written by the OpenEphys GUI

## Requirements
Julia 0.5 or higher

## Usage

### ContinuousFile(file_name::AbstractString; check=true)
Open a .continuous data file at path `file_name` and read its header information

### SampleArray(type::Type{T}, contfile::ContinuousFile, [check::Bool])
Returns an array-like object that accesses the samples in the `contfile` file
without loading the entire file into memory. Samples are converted to the type
specified by `type`, which are converted to input-reffered voltage if `type` is
a FloatingPoint and left as raw sample integers if `type` is an Integer. Manual
conversion to input-referred voltage can be accomplished with the bitvolts field
of the file header. If `check` is true, then each block's contents will be
checked for validity.

### TimeArray(type::Type{T}, contfile::ContinuousFile, [check::Bool])
Returns an array-like object that accesses the time stamps in the `contfile`
file without loading the entire array into memory. Time stamps are converted to
the type specified by `type`, which are converted to seconds if `type` is a
FloatingPoint type, and kept as sample numbers if `type` is an Integer type.

### RecNoArray(type::Type{T}, contfile::ContinuousFile, [check::Bool])
Returns an array-like object that accesses the recording number in the `contfile` file without loading the entire array into memory.

### JointArray(type::Type{T}, contfile::ContinuousFile, [check::Bool])
Returns an array-like object that accesses samples, timestamps, and recording numbers as described above.
