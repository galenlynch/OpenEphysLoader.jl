# Type system for original files and header constants

# I'm using types as a enum here, consider changing this?
"Abstract class for representing matlab code fragments"
abstract type MatlabData end
"Type for representing Matlab strings"
struct MatStr <: MatlabData end
"Type for representing Matlab integers"
struct MatInt <: MatlabData end
"Type for representing Matlab floatingpoint numbers"
struct MatFloat <: MatlabData end
"Type for representing Matlab floatingpoint numbers"
struct OEDateTime <: MatlabData end
"Type for representing Matlab floatingpoint numbers"
struct MatVersion <: MatlabData end

"Exception type to indicate a malformed data file"
struct CorruptedException <: Exception
    message::String
end
CorruptedException() = CorruptedException("")
Base.showerror(io::IO, e::CorruptedException) = print(io, "Corrupted Exception: ", e.message)

### Constants for parsing header ###
const HEADER_N_BYTES = 1024
const HEADER_DATE_REGEX = r"^(\d{1,2}-\p{L}{3}-\d{4}) ([1-2]?\d)([0-5]\d)([1-5]?\d)"
const HEADER_DATEFORMAT = Dates.DateFormat("d-u-y")
const N_HEADER_LINE = 11

"""
    OriginalHeader(io::IOStream)
Data in the header of binary OpenEphys files.

Will throw [`CorruptedException`](@ref) if header is corrupt,
not an "OpenEphys" data format, or not version 0.4 of the data format.

# Fields

**`format`** is the name of the data format.

**`version`** is the version number of the data format.

**`headerbytes`** is the number of bytes in the header.

**`description`** is a description of the header.

**`created`** is the date and time the file was created.

**`channel`** is the name of the channel used to acquire this data.

**`channeltype`** is the type of channel used to acquire this data.

**`samplerate`** is the sampling rate in Hz.

**`blocklength`** is the length in bytes of each block of data within the file.

**`buffersize`** is the size of the buffer used during acquisition, in bytes.

**`bitvolts`** are the Volts per ADC bit.
"""
struct OriginalHeader
    "Data format"
    format::String
    "Version of data format"
    version::VersionNumber
    "Number of bytes in the header"
    headerbytes::Int
    "Description of the header"
    description::String
    "Time file created"
    created::DateTime
    "Channel name"
    channel::String
    "Channel type"
    channeltype::String
    "Sample rate for file"
    samplerate::Int
    "Length of data blocks in bytes"
    blocklength::Int
    "Size of buffer in bytes"
    buffersize::Int
    "Volts/bit of ADC values"
    bitvolts::Float64

    function OriginalHeader(
        format::String,
        version::VersionNumber,
        headerbytes::Int,
        description::String,
        created::DateTime,
        channel::String,
        channeltype::String,
        samplerate::Int,
        blocklength::Int,
        buffersize::Int,
        bitvolts::Float64
    )
        format == "Open Ephys Data Format" || throw(CorruptedException("Header is malformed"))
        version == v"0.4" || version == v"0.2" || throw(CorruptedException("Header is malformed"))
        return new(
            format,
            version,
            headerbytes,
            description,
            created,
            channel,
            channeltype,
            samplerate,
            blocklength,
            buffersize,
            bitvolts
        )
    end
end

"""
    OriginalHeader(io::IOStream)
Reads the header of the open binary file `io`. Assumes that the stream
is at the beginning of the file.
"""
function OriginalHeader(io::IOStream)
    # Read the header from the IOStream and separate on semicolons
    head = read(io, HEADER_N_BYTES)
    length(head) == HEADER_N_BYTES || throw(CorruptedException("Header is malformed"))
    headstr = transcode(String, head)
    isvalid(headstr) || throw(CorruptedException("Header is malformed"))
    substrs =  Compat.split(headstr, ';', keepempty = false)
    resize!(substrs, N_HEADER_LINE)
    format = parseline(MatStr, substrs[1])
    version = parseline(MatVersion, substrs[2])
    headerbytes = parseline(MatInt, substrs[3])
    description = parseline(MatStr, substrs[4])
    created = parseline(OEDateTime, substrs[5])
    channel = parseline(MatStr, substrs[6])
    channeltype = parseline(MatStr, substrs[7])
    samplerate = parseline(MatInt, substrs[8])
    blocklength = parseline(MatInt, substrs[9])
    buffersize = parseline(MatInt, substrs[10])
    bitvolts = parseline(MatFloat, substrs[11])
    return OriginalHeader(
        format,
        version,
        headerbytes,
        description,
        created,
        channel,
        channeltype,
        samplerate,
        blocklength,
        buffersize,
        bitvolts
    )
end

"Parse a line of Matlab source code"
function parseline end
function parseline(::Type{M}, str::AbstractString) where {M<:MatlabData}
    parseto(parsetarget(M), matread(M, str))
end

parsetarget(::Type{MatStr}) = String
parsetarget(::Type{MatInt}) = Int
parsetarget(::Type{MatFloat}) = Float64
parsetarget(::Type{OEDateTime}) = DateTime
parsetarget(::Type{MatVersion}) = VersionNumber

"Convert a string to the desired type"
function parseto end
parseto(::Type{T}, str::AbstractString) where T = parse(T, str)
function parseto(::Type{DateTime}, str::AbstractString)
    m = match(HEADER_DATE_REGEX, str)
    isa(m, @compat(Nothing)) && throw(CorruptedException("Time created is improperly formatted"))
    d = DateTime(m.captures[1], HEADER_DATEFORMAT)
    local hr, mn, sc
    try
        hr = parse(Int, m.captures[2])
        mn = parse(Int, m.captures[3])
        sc = parse(Int, m.captures[4])
    catch y
        if isa(y, ArgumentError)
            throw(CorruptedException("Time created is improperly formatted"))
        else
            rethrow(y)
        end
    end
    # Check for ambiguous time
    if mapreduce(length, +, m.captures[2:4]) == 5
        if 0 <= rem(hr, 10) <= 5 && 1 <= rem(mn, 10) <= 5 # a 'shifted' parsing would also be valid
            Compat.@warn("Header time ", str, " is ambiguous! Assigning the ambiguous digit to hours.")
        end
    end
    dt = d + Dates.Hour(hr) + Dates.Minute(mn) + Dates.Second(sc)
    return dt
end
parseto(::Type{VersionNumber}, str::AbstractString) = VersionNumber(str)
parseto(::Type{String}, str::AbstractString) = String(str)
parseto(::Type{T}, str::T) where T<:AbstractString = str

"read a Matlab source line"
function matread(::Type{T}, str::S) where {T<:MatlabData, S<:AbstractString}
    m = match(rx(T), str)
    m == nothing && throw(CorruptedException("Cannot parse header"))
    string(m[1])
end

### Matlab regular expressions ###
rx(::Type{MatStr}) = r" = '(.*)'$"
rx(::Type{MatInt}) = r" = (\d*)$"
rx(::Type{MatFloat}) = r" = ([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)$"
rx(::Type{OEDateTime}) = rx(MatStr)
rx(::Type{MatVersion}) = rx(MatFloat)

function show(io::IO, a::O) where O<:OriginalHeader
    fields = fieldnames(O)
    for field in fields
        println(io, field, ": ", getfield(a, field))
    end
end
function showcompact(io::IO, header::OriginalHeader)
    show(IOContext(io, :compact => true), "channel: $(header.channel)")
end
function show(io::IO, headers::Vector{OriginalHeader})
    for header in headers
        println(io, showcompact(header))
    end
end
