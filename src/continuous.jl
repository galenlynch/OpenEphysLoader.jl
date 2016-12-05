# code for loading .continuous files

### Constants ###
const CONT_REC_TIME_BITTYPE = Int64
const CONT_REC_N_SAMP = 1024
const CONT_REC_N_SAMP_BITTYPE = UInt16
const CONT_REC_REC_NO_BITTYPE = UInt16
const CONT_REC_SAMP_BITTYPE = Int16
const CONT_REC_BYTES_PER_SAMP = sizeof(CONT_REC_SAMP_BITTYPE)
const CONT_REC_END_MARKER = UInt8[0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
                                  0x07, 0x08, 0xff]
const CONT_REC_HEAD_SIZE = mapreduce(sizeof, +, [CONT_REC_TIME_BITTYPE,
                             CONT_REC_N_SAMP_BITTYPE, CONT_REC_REC_NO_BITTYPE])
const CONT_REC_BODY_SIZE = CONT_REC_N_SAMP * sizeof(CONT_REC_SAMP_BITTYPE)
const CONT_REC_TAIL_SIZE = sizeof(CONT_REC_END_MARKER)
const CONT_REC_SIZE = CONT_REC_HEAD_SIZE + CONT_REC_BODY_SIZE + CONT_REC_TAIL_SIZE

### Types ###
typealias IntOut Union{Array{Int},  Vector{Vector{Int}}}
typealias ConcreteHeader OriginalHeader{UTF8String, Int, Float64}

type BlockHeader
    timestamp::CONT_REC_TIME_BITTYPE
    nsample::CONT_REC_N_SAMP_BITTYPE
    recordingnumber::CONT_REC_REC_NO_BITTYPE
end
BlockHeader() = BlockHeader(0, 0, 0)

type DataBlock
    head::BlockHeader
    body::Vector{UInt8}
    tail::Vector{UInt8}
end
function DataBlock()
    head = BlockHeader()
    body = Vector{UInt8}(CONT_REC_BODY_SIZE)
    tail =  Vector{UInt8}(CONT_REC_TAIL_SIZE)
    DataBlock(head, body, tail)
end

immutable ContinuousFile{T<: Integer, S<:Integer, H<:OriginalHeader}
    io::IOStream
    block::DataBlock
    blockdata::Vector{CONT_REC_SAMP_BITTYPE}
    blockno::UInt8
    nsample::T
    nblock::S
    header::H
end
function ContinuousFile(io::IOStream, check::Bool = true)
    datalen = stat(io).size - HEADER_N_BYTES
    block = DataBlock()
    blockdata = Vector{CONT_REC_SAMP_BITTYPE}(CONT_REC_N_SAMP)
    fileheader = OriginalHeader(io) # Read header
    nblock = count_blocks(io)
    nsample = count_data(nblock)
    if check
        check_filesize(io)
    end
    return ContinuousFile(io, block, blockdata, 0, nsample, nblock, fileheader)
end
ContinuousFile(file_name::AbstractString; check::Bool = true) =
    ContinuousFile(open(file_name, "r"), check)

abstract OEArray{T, C<:ContinuousFile} <: AbstractArray{T, 1}
rangetypes = ((:SampleArray, Real),
              (:TimeArray, Real),
              (:RecNoArray, Integer))
for (typename, typeparam) = rangetypes
    @eval begin
        immutable $(typename){T<:$(typeparam), C<:ContinuousFile} <: OEArray{T, C}
            contfile::C
        end
        $(typename){T, C<:ContinuousFile}(::Type{T}, contfile::C) = $(typename){T, C}(contfile)
    end
end

immutable JointArray{S,T,R,C<:ContinuousFile} <: OEArray{Tuple{S,T,R}, C}
    samples::SampleArray{S, C}
    times::TimeArray{T, C}
    recnos::RecNoArray{R, C}
    contfile::C

    function JointArray(samples, times, recnos, contfile)
        statstruct = stat(contfile.io)
        statcollection = map(x -> stat(x.contfile.io), (samples, times, recnos))
        samefiles = map(x -> x.inode == statstruct.inode &&
                        x.device == statstruct.device, statcollection)
        all(samefiles) || error("Arrays for JointArray must be from the same file")
        new(samples, times, recnos, contfile)
    end
end
function JointArray{S, T, R, C<:ContinuousFile}(samples::SampleArray{S, C},
                                                times::TimeArray{T, C},
                                                recnos::RecNoArray{R, C},
                                                contfile::C)
    JointArray{S,T,R,C}(samples, times, recnos, contfile)
end
function JointArray(contfile::ContinuousFile)
    samples = SampleArray(Float64, contfile)
    times = TimeArray(Float64, contfile)
    recnos = RecNoArray(Int, contfile)
    return JointArray(samples, times, recnos, contfile)
end

### Array interface ###
length(A::OEArray) = A.contfile.nsample

size(A::OEArray) = (length(A), 1)

linearindexing{T<:OEArray}(::Type{T}) = Base.LinearFast()

setindex!(::OEArray, ::Int) = throw(ReadOnlyMemoryError())

function getindex{T, C}(A::SampleArray{T, C}, i::Integer)
    idx = sampno_to_pos(i)
    sample_filebytes = A.contfile.filemmap[idx:idx + CONT_REC_BYTES_PER_SAMP - 1]
    sample = ntoh(reinterpret(CONT_REC_SAMP_BITTYPE, sample_filebytes)[1])
    return convert_sample(T, sample, A.contfile.header.bitvolts)
end

function getindex{T, C}(A::TimeArray{T, C}, i::Integer)
    blockstartpos = block_start_pos(sampno_to_block(i))
    byteidxes = blockstartpos:(blockstartpos + sizeof(CONT_REC_TIME_BITTYPE) - 1)
    sampleno_filebytes = A.contfile.filemmap[byteidxes]
    block_sampleno = reinterpret(CONT_REC_TIME_BITTYPE, sampleno_filebytes)[1]
    sampleno = block_sampleno + (i - 1) % CONT_REC_N_SAMP
    return convert_timepoint(T, sampleno, A.contfile.header.samplerate)
end

function getindex{T, C}(A::RecNoArray{T, C}, i::Integer)
    recno_pos = block_start_pos(sampno_to_block(i)) +
        sizeof(CONT_REC_TIME_BITTYPE) +
        sizeof(CONT_REC_N_SAMP_BITTYPE)
    recno_filebytes = A.contfile.filemmap[recno_pos:recno_pos + sizeof(CONT_REC_REC_NO_BITTYPE) - 1]
    return T(reinterpret(CONT_REC_REC_NO_BITTYPE, recno_filebytes)[1])
end

function getindex(A::JointArray, i::Integer)
    return A.samples[i], A.times[i], A.recnos[i]
end

### location functions ###
# position is zero-based
sampno_to_block_pos(sampno::Integer) = block_start_pos(sampno_to_block(sampno))

sampno_to_block(sampno::Integer) = div(sampno - 1, CONT_REC_N_SAMP) + 1

block_start_pos(block_no::Integer) = (block_no - 1) * CONT_REC_SIZE + CONT_REC_HEAD_SIZE

### Verification functions ###
function check_filesize(file::IOStream)
    @assert rem(filesize(file) - HEADER_N_BYTES, CONT_REC_SIZE) == 0 "File not the right size"
end

### File access and conversion ###
function read_into!(io::IOStream, block::DataBlock, blockdata::Vector{CONT_REC_SAMP_BITTYPE},
               check::Bool)
    goodread = read_into!(io, block, check)
    goodread && convert_block!(block, blockdata)
    return goodread
end
function read_into!(io::IOStream, block::DataBlock, check::Bool = false)
    goodread = read_into!(io, block.head)
    goodread || return goodread
    ## Read the body
    nbytes = readbytes!(io, block.body, CONT_REC_BODY_SIZE)
    goodread = nbytes == CONT_REC_BODY_SIZE
    goodread || return goodread
    if check
        goodread = verify_tail!(io, block.tail)
    else
        skip(io, CONT_REC_TAIL_SIZE)
    end
    return goodread
end
function read_into!(io::IOStream, head::BlockHeader)
    goodread = true
    try
        head.timestamp = read(io, CONT_REC_TIME_BITTYPE)
        head.nsample = read(io, CONT_REC_N_SAMP_BITTYPE)
        if head.nsample != CONT_REC_N_SAMP
            goodread = false
        end
        head.recordingnumber = read(io, CONT_REC_REC_NO_BITTYPE)
    catch exception
        if isa(exception, EOFError)
            goodread = false
        else
            rethrow(exception)
        end
    end
    return goodread
end

function convert_block!(block::DataBlock, blockdata::Vector{CONT_REC_SAMP_BITTYPE})
    contents = reinterpret(CONT_REC_SAMP_BITTYPE, block.body) # readbuff is UInt8
    # Correct for big endianness of this data block
    for idx in eachindex(contents)
        @inbounds contents[idx] = ntoh(contents[idx])
    end
    copy!(contents, blockdata)
end

function verify_tail!(io::IOStream, tail::Vector{UInt8})
    nbytes = readbytes!(io, tail, CONT_REC_TAIL_SIZE)
    goodread = nbytes == CONT_REC_TAIL_SIZE && tail == CONT_REC_END_MARKER
    return goodread
end

### Utility functions ###
function convert_sample{T<:AbstractFloat}(::Type{T}, data::Integer, bitvolts::AbstractFloat)
   return convert(T, data * bitvolts)
end
convert_sample{T<:Integer}(::Type{T}, data::Integer, ::AbstractFloat) = convert(T, data)

function convert_timepoint{T<:AbstractFloat}(::Type{T}, sampleno::Integer, samplerate::Integer)
    return convert(T, (sampleno - 1) / samplerate) # First sample is at time zero
end
convert_timepoint{T<:Integer}(::Type{T}, sampleno::Integer, ::Integer) = convert(T, sampleno)

function count_blocks(file::IOStream)
    fsize = stat(file).size
    return div(fsize - HEADER_N_BYTES, CONT_REC_SIZE)
end

count_data(numblocks::Integer) = numblocks * CONT_REC_N_SAMP
count_data(file::IOStream) = count_data(count_blocks(file))
