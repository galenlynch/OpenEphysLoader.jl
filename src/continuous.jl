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

immutable ContinuousFile{T<:Integer, S<:Integer, H<:OriginalHeader}
    io::IOStream
    nsample::T
    nblock::S
    header::H
end
function ContinuousFile(io::IOStream, check::Bool = true)
    block = DataBlock()
    fileheader = OriginalHeader(io) # Read header
    nblock = count_blocks(io)
    nsample = count_data(nblock)
    return ContinuousFile(io, block, 0, nsample, nblock, fileheader, check)
end
ContinuousFile(file_name::AbstractString; check::Bool = true) =
    ContinuousFile(open(file_name, "r"), check)

abstract OEArray{T, C<:ContinuousFile, B<:BlockBuffer} <: AbstractArray{T, 1}
arraytypes = ((:SampleArray, Real, DataBlock),
              (:TimeArray, Real, BlockHeader),
              (:RecNoArray, Integer, BlockHeader))
for (typename, typeparam, buffertype) = arraytypes
    @eval begin
        immutable $(typename){T<:$(typeparam), C<:ContinuousFile, B<:BlockBuffer} <:
            OEArray{T, C, B}
            contfile::C
            block::B
            blockno::UInt
            check::Bool
        end
        function $(typename){T, C<:ContinuousFile}(::Type{T}, contfile::C, check::Bool = true)
            if check
                check_filesize(contfile.io)
            end
            block = $(buffertype)()
            return $(typename){T, C, $(buffertype)}(contfile, block, 0, check)
        end
    end
end

immutable JointArray{S<:arraytypes[1][2],
                     T<:arraytypes[2][2],
                     R<:arraytypes[3][2],
                     C<:ContinuousFile} <: OEArray{Tuple{S,T,R}, C}
    contfile::C
    block::DataBlock
    blockno::UInt
    check::Bool
end
function JointArray(contfile::ContinuousFile, check::Bool = true)
    block = DataBlock()
    blockno = 0
    if check
        check_filesize(contfile.io)
    end
    return JointArray(contfile, block, blockno, check)
end

### Array interface ###
length(A::OEArray) = A.contfile.nsample

size(A::OEArray) = (length(A), 1)

linearindexing{T<:OEArray}(::Type{T}) = Base.LinearFast()

setindex!(::OEArray, ::Int) = throw(ReadOnlyMemoryError())

function getindex(A::OEArray, i::Integer)
    rel_idx = prepare_block(A, i)
    data = block_data(A, rel_idx)
    header = get_block_header(A.block)
    return convert_data(A, header, data)
end

function getindex(A::JointArray, i::Integer)
    return A.samples[i], A.times[i], A.recnos[i]
end

function prepare_block(A::OEArray, i::Integer)
    newblock, rel_idx = relative_block_index(A.blockno, i)
    if newblock
        seek_to_containing_block(A.contfile.io, i)
        read_into!(A.contfile.io, A.block, A.check)
    end
    return rel_idx
end

function relative_block_index(blockno::Integer, i::Integer)
    start_idx = block_start_index(blockno)
    newblock = !index_in_block(start_idx, i)
    rel_idx = i - start_idx + 1
    return newblock, rel_idx
end

function seek_to_containing_block(io::IOStream, i::Integer)
    blockpos = sampno_to_block_pos(i)
    if blockpos != position(io)
        seek(io, blockpos)
    end
end

function index_in_block(block_start_idx::Integer, i::Integer)
    return block_start_idx > 0 && block_start_idx <= i <= block_start_idx + CONT_REC_N_SAMP - 1
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
block_data(A::SampleArray, rel_idx::Integer) = A.block.data[rel_idx]
block_data(A::TimeArray, rel_idx::Integer) = A.block.timestamp + rel_idx - 1
block_data(A::RecNoArray, ::Integer) = A.block.recordingnumber
function block_data(A::JointArray, rel_idx::Integer)
    sample = A.block.data[rel_idx]
    timestamp = A.block.head.timestamp + rel_idx - 1
    recno = A.block.head.recordingnumber
    return sample, timestamp, recno
end

get_block_header(H::BlockHeader) = H
get_block_header(D::DataBlock) = D.head
function convert_data{T<:AbstractFloat, C, B}(::Type{SampleArray{T, C, B}},
                                              H::BlockHeader, data::Integer)
    return convert(T, data * H.bitvolts)
end
function convert_data{T<:Integer, C, B}(::Type{SampleArray{T, C, B}},
                                              ::BlockHeader, data::Integer)
    return convert(T, data)
end
function convert_data{T<:AbstractFloat, C, B}(::Type{TimeArray{T, C, B}},
                                              H::BlockHeader, data::Integer)
    return convert(T, (data - 1) / H.samplerate) # First sample is at time zero
end
function convert_data{T<:Integer, C, B}(::Type{TimeArray{T, C, B}},
                                              H::BlockHeader, data::Integer)
    return convert(T, data)
end
function convert_data{T, C, B}(::Type{RecNoArray{T, C, B}}, ::BlockHeader, data::Integer)
    return convert(T, data)
end
function convert_data{S,T,R,C}(::Type{JointArray{S,T,R,C}}, H::BlockHeader, data::Tuple)
    samp = convert_data(SampleArray{S, C, DataBlock}, H, data[1])
    timestamp = convert_data(TimeArray{T, C, BlockHeader}, H, data)
    recno = convert_data(RecNoArray{R, C, BlockHeader}, H, data)
    return samp, timestmap, recno
end

function count_blocks(file::IOStream)
    fsize = stat(file).size
    return div(fsize - HEADER_N_BYTES, CONT_REC_BLOCK_SIZE)
end

count_data(numblocks::Integer) = numblocks * CONT_REC_N_SAMP
count_data(file::IOStream) = count_data(count_blocks(file))
