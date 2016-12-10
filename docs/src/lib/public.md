# Public Documentation #

Documentation for exported functions and types for `OpenEphysLoader.jl`

```@docs
OpenEphysLoader
```

### Array types
All array types are subtypes of the abstract [`OEContArray`](@ref) type.

```@docs
OEContArray
```

The following array types can be used to access different aspects of the data:
```@docs
SampleArray
TimeArray
RecNoArray
JointArray
```
### Information types

The following types provide information about OpenEphys files

```@docs
OriginalHeader
ContinuousFile
```

### Exceptions

```@docs
CorruptedException
```

