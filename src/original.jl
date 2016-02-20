# Type system for original files and header constants
const HEADER_BITTYPE = Char
const HEADER_STRING_ENCODING = UTF8String
const HEADER_N_BYTES = 1024
const HEADER_DATEFORMAT = Dates.DateFormat("d-u-y HHMMSS")

abstract OriginalData <: OEData
abstract MATLABdata
type MATstr <: MATLABdata end
type MATint <: MATLABdata end
type MATfloat <: MATLABdata end

const HEADER_TYPE_MAP = ((MATstr, UTF8String), #Format
                        (MATfloat, VersionNumber), #Version
                        (MATint, Int), #headerbytes
                        (MATstr, UTF8String), #description
                        (MATstr, DateTime), #created
                        (MATstr, UTF8String), #channel
                        (MATstr, UTF8String), #channeltype
                        (MATint, Int), #samplerate
                        (MATint, Int), #blocklength
                        (MATint, Int), #buffersize
                        (MATfloat, Float64)) #bitvolts
const HEADER_MATTYPES = [x[1] for x in HEADER_TYPE_MAP]
const HEADER_TARGET_TYPES = [x[2] for x in HEADER_TYPE_MAP]
const N_HEADER_LINE = length(HEADER_TYPE_MAP)

immutable OriginalHeader{T<:String, S<:Integer, R<:Real}
    format::T
    version::VersionNumber
    headerbytes::S
    description::T
    created::DateTime
    channel::T
    channeltype::T
    samplerate::S
    blocklength::S
    buffersize::S
    bitvolts::R
end
function OriginalHeader(io::IOStream)
    # Read the header from the IOStream and separate on semicolons
    head = readbytes(io, HEADER_N_BYTES)
    @assert length(head) == HEADER_N_BYTES "Unable to read all of the header"
    headstr = strencoder(HEADER_STRING_ENCODING, head)
    substrs = @compat split(headstr, ';', keep = false)
    resize!(substrs, N_HEADER_LINE)
    OriginalHeader(
        map(parseline, zip(HEADER_MATTYPES, HEADER_TARGET_TYPES, substrs))...
    )::OriginalHeader{UTF8String, Int, Float64}
end
strencoder(::Type{ASCIIString}, strbytes::AbstractArray) = ascii(strbytes)::ASCIIString
strencoder(::Type{UTF8String}, strbytes::AbstractArray) = utf8(strbytes)::UTF8String
parseline{T, M<:MATLABdata}(::Type{M}, ::Type{T}, str::String) = parseto(T, matparse(M, str))::T
parseline(tup::Tuple) = parseline(tup...)
parseto{T<:Number}(::Type{T}, str::String) = parse(str)::T
parseto(::Type{DateTime}, str::String) = DateTime(str, HEADER_DATEFORMAT)
parseto(::Type{UTF8String}, str::String) = utf8(str)::UTF8String
function matparse{T<:MATLABdata, S<:String}(::Type{T}, str::S)
    regex = rx(T)
    goodread = false
    if ismatch(regex, str)
        m = match(rx(T), str)
        if !isempty(m.captures)
            goodread = true
        end
    end
    if goodread
        return m.captures[1]::S
    else
        throw(CorruptionError())
    end
end
rx(::Type{MATstr}) = r" = '(.*)'$"
rx(::Type{MATint}) = r" = (\d*)$"
rx(::Type{MATfloat}) = r" = ([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)$"
if VERSION < v"0.4-"
    parseto(::Type{VersionNumber}, str::String) = VersionNumber(parseversion(str)...)
    parseto{T<:String}(::Type{T}, str::T) = str
    parseto(::Type{ASCIIString}, str::String) = ascii(str)::ASCIIString
    parseversion(str::String) = map(parse, @compat split(str, '.', keep = false))
else
    parseto(::Type{VersionNumber}, str::String) = VersionNumber(str)
    parseto{T<:String}(::Type{T}, str::T) = str
    parseto{T<:String}(::Type{T}, str::String) = T(str)
end

function show(io::IO, a::OriginalHeader)
    fields = fieldnames(a)
    for field in fields
        println(io, "$field: $(a.(field))")
    end
end
showcompact(io::IO, header::OriginalHeader) = show(io, "channel: $(header.channel)")
function show(io::IO, headers::Vector{OriginalHeader})
    for header in headers
        println(io, showcompact(header))
    end
end
