# Type system for original files and header constants

# I'm using types as a enum here, consider changing this?
"Abstract class for representing matlab code fragments"
abstract type MATLABdata end
"Type for representing Matlab strings"
struct MATstr <: MATLABdata end
"Type for representing Matlab integers"
struct MATint <: MATLABdata end
"type for representing Matlab floatingpoint numbers"
struct MATfloat <: MATLABdata end

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
const HEADER_TYPE_MAP = ((MATstr, String), #Format
                        (MATfloat, VersionNumber), #Version
                        (MATint, Int), #headerbytes
                        (MATstr, String), #description
                        (MATstr, DateTime), #created
                        (MATstr, String), #channel
                        (MATstr, String), #channeltype
                        (MATint, Int), #samplerate
                        (MATint, Int), #blocklength
                        (MATint, Int), #buffersize
                        (MATfloat, Float64)) #bitvolts
const HEADER_MATTYPES = [x[1] for x in HEADER_TYPE_MAP]
const HEADER_TARGET_TYPES = [x[2] for x in HEADER_TYPE_MAP]
const N_HEADER_LINE = length(HEADER_TYPE_MAP)

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
    return OriginalHeader(
        map(parseline, zip(HEADER_MATTYPES, HEADER_TARGET_TYPES, substrs))...
    )::OriginalHeader
end

"Parse a line of Matlab source code"
function parseline end
function parseline(
    ::Type{M}, ::Type{T}, str::AbstractString
) where {T, M<:MATLABdata}
    parseto(T, matread(M, str))
end
parseline(tup::Tuple) = parseline(tup...)

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
function matread(::Type{T}, str::S) where {T<:MATLABdata, S<:AbstractString}
    regex = rx(T)
    goodread = false
    local m
    if @compat occursin(regex, str)
        m = match(rx(T), str)
        isempty(m.captures) && throw(CorruptedException("Cannot parse header"))
    end
    return string(m.captures[1])
end

### Matlab regular expressions ###
rx(::Type{MATstr}) = r" = '(.*)'$"
rx(::Type{MATint}) = r" = (\d*)$"
rx(::Type{MATfloat}) = r" = ([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)$"

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
