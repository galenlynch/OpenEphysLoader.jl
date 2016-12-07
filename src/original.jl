# Type system for original files and header constants
const HEADER_N_BYTES = 1024
const HEADER_DATEFORMAT = Dates.DateFormat("d-u-y HHMMSS")

abstract MATLABdata
type MATstr <: MATLABdata end
type MATint <: MATLABdata end
type MATfloat <: MATLABdata end

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

immutable OriginalHeader{T<:AbstractString, S<:Integer, R<:Real}
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
    head = read(io, HEADER_N_BYTES)
    @assert length(head) == HEADER_N_BYTES "Header not complete"
    headstr = transcode(String, head)
    substrs =  split(headstr, ';', keep = false)
    resize!(substrs, N_HEADER_LINE)
    OriginalHeader(
        map(parseline, zip(HEADER_MATTYPES, HEADER_TARGET_TYPES, substrs))...
    )::OriginalHeader{String, Int, Float64}
end

parseline{T, M<:MATLABdata}(::Type{M}, ::Type{T}, str::AbstractString) = parseto(T, matread(M, str))::T
parseline(tup::Tuple) = parseline(tup...)

parseto{T<:Number}(::Type{T}, str::AbstractString) = parse(str)::T
parseto(::Type{DateTime}, str::AbstractString) = DateTime(str, HEADER_DATEFORMAT)
parseto(::Type{VersionNumber}, str::AbstractString) = VersionNumber(str)
parseto(::Type{String}, str::AbstractString) = String(str)
parseto{T<:AbstractString}(::Type{T}, str::T) = str

function matread{T<:MATLABdata, S<:AbstractString}(::Type{T}, str::S)
    regex = rx(T)
    goodread = false
    if ismatch(regex, str)
        m = match(rx(T), str)
        if !isempty(m.captures)
            goodread = true
        end
    end
    @assert goodread "File is corrupt"
    return S(m.captures[1])
end

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
