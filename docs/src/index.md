# OpenEphysLoader.jl Documentation #

A set of tools to load data files made by
the [OpenEphys GUI](http://www.open-ephys.org/gui/)

!!! note
    
    This module is experimental, and may damage your data. No module
    functions intentionally modify the contents of data files, but use this
    module at your own risk.
    
## Package Features

- Read contents of continuous data files without loading the entire file into memory
- Array interface to sample values, time stamps, and recording numbers
- Flexibly typed output provides access to raw sample values or converted voltage values

## Example Usage
OpenEphysLoader.jl provides array types to access file contents. Values accessed
through these subtypes of [`OEArray`](@ref) have an array interface backed by
file contents, instead of memory.

```@setup loader
docpath = @__FILE__()
docdir = dirname(docpath)
relloadpath = joinpath(docdir, "../test/data")
absloadpath = realpath(relloadpath)
absloadfile = joinpath(absloadpath, "100_AUX1.continuous")
open(absloadfile, "r") do dataio
    global databytes = read(dataio, 3094)
end
path, tmpio = mktemp()
try
    write(tmpio, databytes)
finally
    close(tmpio)
end
```

```@example loader
using OpenEphysLoader
open(path, "r") do io
    A = SampleArray(io)
    A[1:3]
end
```

```@setup loader
rm(path)
```

To pull the entire file contents into memory, use `copy(OEArray)`.


## Library Outline

```@contents
Pages = ["lib/public.md", "lib/internals.md"]
```
