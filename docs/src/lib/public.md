# Public Documentation #

Documentation for exported functions and types for `OpenEphysLoader.jl`

```@docs
OpenEphysLoader
```

### Array types

All array types are subtypes of the abstract type [`OEArray`](@ref), and
data from continuous files are subtypes of the abstract type 
[`OEContArray`](@ref).

```@docs
OEArray
OEContArray
```

The following array types can be used to access different aspects of the
data:

```@docs
SampleArray
TimeArray
RecNoArray
```

Alternatively, all three aspects can be accessed simultaneously:

```@docs
JointArray
```

### Information types

The following types provide information about OpenEphys files

```@docs
OriginalHeader
ContinuousFile
```

### Recording metadata

Information about the recording session can be gathered from the 
`settings.xml` and `Continuous_Data.openephys` files by using the 
[`metadata`](@ref) function. The contents of the metadata files are 
contained in the [`OEExperMeta`](@ref) datatype.

```@docs
metadata
OEExperMeta
OESettings
OEInfo
OERecordingMeta
OEProcessor
OERhythmProcessor
OEChannel
```

### Exceptions

```@docs
CorruptedException
```

