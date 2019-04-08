# OpenEphysLoader.jl Documentation #

A set of tools to load data files made by
the [Open Ephys GUI](http://www.open-ephys.org/gui/)

## Package Features

- Provides easy access to sample values, time stamps, and recording numbers through an Array interface.
- Data can be accessed in their raw form, or converted to voltage and seconds.
- Accessing a data file does not require loading the entirety of its contents into RAM.
- Provides tools to read the metadata for Open Ephys recordings.

## Example Usage
Data in a file can be accessed by creating a [`SampleArray`](@ref), [`TimeArray`](@ref),
or [`JointArray`](@ref).
These arrays can be constructed with a `IOStream` at the beginning of an open
`.continuous` data file, or alternatively the name of a `.continuous` file.

### Accessing sample values
For this example, we will demonstrate how to access sample values using `SampleArray`.

```@setup loader
docdir = pwd()
relloadpath = joinpath(docdir, "../../test/data")
datadir = realpath(relloadpath)
absloadfile = joinpath(datadir, "100_AUX1.continuous")
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
io = open(path, "r") # Where 'path' is the path to a .continuous file
A = SampleArray(io) # A is a regular julia matrix
A[1:3] # Show the first three sampled voltages (in uV) in the file
```

Once constructed, `SampleArray` objects can be used like a normal Julia array.

Sample values are stored in .continuous files as ADC codes (`Int16` codes for the RHD2000 family),
which OpenEphysLoader.jl automatically converts to voltages by default.
In order to access the raw ADC codes, pass an integer type (ADC reads are `Int16` for the RHD2000 family)
as the first argument when constructing a [`SampleArray`](@ref):

```@example loader
seek(io, 0) # IOStream neeeds to be at the beginning of the data file
A = SampleArray(Int16, io)
A[1:3]
```

If a floating point type is specified, the ADC codes are converted into voltages.
If no sample type is specified, then the default is `Float64`.

Here we moved the `IOStream` back to the beginning of the file, because we used this `IOStream`
for our previous example. When using the REPL, if you reuse `IOStream` objects to create
new OpenEphysLoader arrays, you must return the `IOStream` to the beginning of the file.

### Accessing time stamps

Time stamps can be accessed with [`TimeArray`](@ref).

Accessing the time stamps returns sample time by default, but the raw
sample numbers can be easily accessed as well:

```@example loader
io = open(path, "r")
B = TimeArray(io) # Time of each sample in seconds, equivalent to TimeArray(Float64, io)
B[1]
```

```@example loader
io = open(path, "r")
B = TimeArray(Int64, io) # sample number for each sample
B[1]
```

### Accessing all information about a sample

[`JointArray`](@ref) provides access to the sample value, timestamp, and recording number for each sample.
If you want to access both the time stamps and values for samples in a data file, it is most efficient to
use a [`JointArray`](@ref):

```@example loader
io = open(path, "r")
C = JointArray(io) # Time of each sample in seconds
(sampval, timestamp, recno) = C[1] # Access information about the first sample
```

Elements of the `JointArray` are three-tuples, which can be destructured as shown above.

```@example loader
sampval # inspect the destructured sample value from above
```

### Copying file contents into RAM

Arrays in OpenEphysLoader.jl access the data directly from disk. In order to pull the contents into memory,
Create a regular Julia `Array` from OpenEphysLoader.jl arrays.

```@example loader
io = open(path, "r")
A = SampleArray(Int16, io) # Elements of A will be read from disk
D = collect(A) # This will copy the entire contents of A into a regular Julia array in RAM
D[1:3]
```
## Recording metadata
The metadata of recordings can be accessed using the [`metadata`](@ref) function:

```@example loader
using OpenEphysLoader
meta = metadata(datadir) # Where datadir is the path to your recording directory
```

## Dealing with corrupted files

For whatever reason, Open Ephys seems to regularly produce data files that are missing
samples at the end of the file. Because this library will by default check each file for corruption before
attempting to access its data,
such files will fail to open with a [`CorruptedException`](@ref).

In order to access the samples that are intact, use the optional third parameter of [`SampleArray`](@ref) to disable
checking for corruption prior to opening a file:

```@example loader
io = open(path, "r")
A = SampleArray(Float64, io, false)
A[1:3]
```

```@setup loader
rm(path)
```

Another common cause of receiving `CorruptedException` when opening a file is using an `IOStream` that is not
at the beginning of the file. Either use a new `IOStream` object, or return the `IOStream` to the beginning of
file with `seek(io, 0)` where `io` is the name of the `IOStream` variable.

## Library Outline

```@contents
Pages = ["lib/public.md", "lib/internals.md"]
```
