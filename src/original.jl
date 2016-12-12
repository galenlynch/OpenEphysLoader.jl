# Type system for original files and header constants
"""
Abstract array for file-backed OpenEphys data.

All subtypes support a ready-only array interface and should
be constructable with a single IOStream argument.
"""
abstract OEArray{T} <: AbstractArray{T, 1}
# I'm using types as a enum here, consider changing this?
"Abstract class for representing matlab code fragments"
abstract MATLABdata
"Type for representing Matlab strings"
type MATstr <: MATLABdata end
"Type for representing Matlab integers"
type MATint <: MATLABdata end
"type for representing Matlab floatingpoint numbers"
type MATfloat <: MATLABdata end

"Exception type to indicate a malformed data file"
type CorruptedException <: Exception end

### Constants for parsing header ###
const HEADER_N_BYTES = 1024
const HEADER_DATEFORMAT = Dates.DateFormat("d-u-y HHMMSS")
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
immutable OriginalHeader{T<:AbstractString, S<:Integer, R<:Real}
    "Data format"
    format::T
    "Version of data format"
    version::VersionNumber
    "Number of bytes in the header"
    headerbytes::S
    "Description of the header"
    description::T
    "Time file created"
    created::DateTime
    "Channel name"
    channel::T
    "Channel type"
    channeltype::T
    "Sample rate for file"
    samplerate::S
    "Length of data blocks in bytes"
    blocklength::S
    "Size of buffer in bytes"
    buffersize::S
    "Volts/bit of ADC values"
    bitvolts::R

    function OriginalHeader(
        format::T,
        version::VersionNumber,
        headerbytes::S,
        description::T,
        created::DateTime,
        channel::T,
        channeltype::T,
        samplerate::S,
        blocklength::S,
        buffersize::S,
        bitvolts::R
    )
        format == "Open Ephys Data Format" || throw(CorruptedException())
        version == v"0.4" || throw(CorruptedException())
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

function OriginalHeader{T,S,R}(
    format::T,
    version::VersionNumber,
    headerbytes::S,
    description::T,
    created::DateTime,
    channel::T,
    channeltype::T,
    samplerate::S,
    blocklength::S,
    buffersize::S,
    bitvolts::R
)
    return OriginalHeader{T,S,R}(
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

"""
    OriginalHeader(io::IOStream)
Reads the header of the open binary file `io`. Assumes that the stream
is at the beginning of the file.
"""
function OriginalHeader(io::IOStream)
    # Read the header from the IOStream and separate on semicolons
    head = read(io, HEADER_N_BYTES)
    length(head) == HEADER_N_BYTES || throw(CorruptedException())
    headstr = transcode(String, head)
    isvalid(headstr) || throw(CorruptedException())
    substrs =  split(headstr, ';', keep = false)
    resize!(substrs, N_HEADER_LINE)
    return OriginalHeader(
        map(parseline, zip(HEADER_MATTYPES, HEADER_TARGET_TYPES, substrs))...
    )::OriginalHeader{String, Int, Float64}
end

"Parse a line of Matlab source code"
function parseline end
parseline{T, M<:MATLABdata}(::Type{M}, ::Type{T}, str::AbstractString) = parseto(T, matread(M, str))::T
parseline(tup::Tuple) = parseline(tup...)

"Convert a string to the desired type"
function parseto end
parseto{T<:Number}(::Type{T}, str::AbstractString) = parse(str)::T
parseto(::Type{DateTime}, str::AbstractString) = DateTime(str, HEADER_DATEFORMAT)
parseto(::Type{VersionNumber}, str::AbstractString) = VersionNumber(str)
parseto(::Type{String}, str::AbstractString) = String(str)
parseto{T<:AbstractString}(::Type{T}, str::T) = str

"read a Matlab source line"
function matread{T<:MATLABdata, S<:AbstractString}(::Type{T}, str::S)
    regex = rx(T)
    goodread = false
    local m
    if ismatch(regex, str)
        m = match(rx(T), str)
        isempty(m.captures) && throw(CorruptedException())
    end
    return S(m.captures[1])
end

### Matlab regular expressions ###
rx(::Type{MATstr}) = r" = '(.*)'$"
rx(::Type{MATint}) = r" = (\d*)$"
rx(::Type{MATfloat}) = r" = ([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)$"

function show(io::IO, a::OriginalHeader)
    fields = fieldnames(a)
    for field in fields
        println(io, "$field: $(getfield(a, field))")
    end
end
showcompact(io::IO, header::OriginalHeader) = show(io, "channel: $(header.channel)")
function show(io::IO, headers::Vector{OriginalHeader})
    for header in headers
        println(io, showcompact(header))
    end
end
