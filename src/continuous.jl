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
const CONT_REC_BLOCK_SIZE = CONT_REC_HEAD_SIZE + CONT_REC_BODY_SIZE + CONT_REC_TAIL_SIZE

### Types ###
typealias IntOut Union{Array{Int},  Vector{Vector{Int}}}
typealias ConcreteHeader OriginalHeader{UTF8String, Int, Float64}

abstract BlockBuffer

type BlockHeader <: BlockBuffer
    timestamp::CONT_REC_TIME_BITTYPE
    nsample::CONT_REC_N_SAMP_BITTYPE
    recordingnumber::CONT_REC_REC_NO_BITTYPE
end
BlockHeader() = BlockHeader(0, 0, 0)

type DataBlock <: BlockBuffer
    head::BlockHeader
    body::Vector{UInt8}
    data::Vector{CONT_REC_SAMP_BITTYPE}
    tail::Vector{UInt8}
end
function DataBlock()
    head = BlockHeader()
    body = Vector{UInt8}(CONT_REC_BODY_SIZE)
    data = Vector{CONT_REC_SAMP_BITTYPE}(CONT_REC_N_SAMP)
    tail =  Vector{UInt8}(CONT_REC_TAIL_SIZE)
    DataBlock(head, body, data, tail)
end

immutable ContinuousFile{B<:BlockBuffer, T<:Integer, S<:Integer, H<:OriginalHeader}
    io::IOStream
    block::B
    blockno::UInt8
    nsample::T
    nblock::S
    header::H
    check::Bool
end
function ContinuousFile(io::IOStream, check::Bool = true)
    block = DataBlock()
    fileheader = OriginalHeader(io) # Read header
    nblock = count_blocks(io)
    nsample = count_data(nblock)
    if check
        check_filesize(io)
    end
    return ContinuousFile(io, block, 0, nsample, nblock, fileheader, check)
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
    newblock, rel_idx = prepare_block(A.contfile, i)
    if newblock
        read_into!(A.contfile.io, A.contfile.block, A.contfile.blockdata, A.contfile.check)
    end
    return convert_sample(T, A.contfile.blockdata[rel_idx], A.contfile.header.bitvolts)
end

function getindex{T, C}(A::TimeArray{T, C}, i::Integer)
    newblock, rel_idx = prepare_block(A.contfile, i)
    if newblock
        read_into!(A.contfile.io, A.contfile.block.head) # block is now in inconsistent state!
    end
    sampleno = A.contfile.block.head.timestamp + rel_idx - 1
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

function index_in_block(block_start_idx::Integer, i::Integer)
    return block_start_idx > 0 && block_start_idx <= i <= block_start_idx + CONT_REC_N_SAMP - 1
end

function 
function prepare_block(contfile::ContinuousFile, i::Integer)
    start_idx = block_start_index(contfile.blockno)
    newblock = !index_in_block(start_idx, i)
    if newblock
        blockpos = sampno_to_block_pos(i)
        if blockpos != position(contfile.io)
            seek(contfile.io, blockpos)
        end
    end
    rel_idx = i - start_idx + 1
    return newblock, rel_idx
end
### location functions ###
# position is zero-based
sampno_to_block_pos(sampno::Integer) = block_start_pos(sampno_to_block(sampno))

sampno_to_block(sampno::Integer) = div(sampno - 1, CONT_REC_N_SAMP) + 1

block_start_pos(blockno::Integer) = (blockno - 1) * CONT_REC_BLOCK_SIZE + HEADER_N_BYTES

block_start_index(blockno::Integer) = (blockno - 1) * CONT_REC_N_SAMP + 1

### Verification functions ###
function check_filesize(file::IOStream)
    @assert rem(filesize(file) - HEADER_N_BYTES, CONT_REC_BLOCK_SIZE) == 0 "File not the right size"
end

### File access and conversion ###
function read_into!(io::IOStream, block::DataBlock, check::Bool = true)
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
    goodread && convert_block!(block)
    return goodread
end
function read_into!(io::IOStream, head::BlockHeader, check::Bool = true)
    goodread = true
    try
        head.timestamp = read(io, CONT_REC_TIME_BITTYPE)
        head.nsample = read(io, CONT_REC_N_SAMP_BITTYPE)
        if check && head.nsample != CONT_REC_N_SAMP
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

function convert_block!(block::DataBlock)
    contents = reinterpret(CONT_REC_SAMP_BITTYPE, block.body) # readbuff is UInt8
    # Correct for big endianness of this data block
    for idx in eachindex(contents)
        @inbounds contents[idx] = ntoh(contents[idx])
    end
    copy!(contents, block.data)
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
    return div(fsize - HEADER_N_BYTES, CONT_REC_BLOCK_SIZE)
end

count_data(numblocks::Integer) = numblocks * CONT_REC_N_SAMP
count_data(file::IOStream) = count_data(count_blocks(file))
