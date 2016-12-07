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
typealias ConcreteHeader OriginalHeader{String, Int, Float64}

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
    header = OriginalHeader(io) # Read header
    nblock = count_blocks(io)
    nsample = count_data(nblock)
    return ContinuousFile(io, nsample, nblock, header)
end
ContinuousFile(file_name::AbstractString; check::Bool = true) =
    ContinuousFile(open(file_name, "r"), check)

abstract OEArray{T, C<:ContinuousFile, B<:BlockBuffer} <: AbstractArray{T, 1}
arraytypes = ((:SampleArray, Real, DataBlock),
              (:TimeArray, Real, BlockHeader),
              (:RecNoArray, Integer, BlockHeader))
for (typename, typeparam, buffertype) = arraytypes
    @eval begin
        type $(typename){T<:$(typeparam), C<:ContinuousFile, B<:BlockBuffer} <:
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

type JointArray{S<:arraytypes[1][2],
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
    prepare_block(A, i)
    relidx = sampno_to_offset(i)
    data = block_data(A, relidx)
    return convert_data(A, A.contfile.header, data)
end

function prepare_block(A::OEArray, i::Integer)
    blockno = sampno_to_block(i)
    if blockno != A.blockno
        seek_to_block(A.contfile.io, blockno)
        @assert read_into!(A.contfile.io, A.block, A.check) "Could not read block"
        A.blockno = blockno
    end
end

function seek_to_block(io::IOStream, blockno::Integer)
    blockpos = block_start_pos(blockno)
    if blockpos != position(io)
        seek(io, blockpos)
    end
end

function index_in_block(block_start_idx::Integer, i::Integer)
    return block_start_idx > 0 && block_start_idx <= i <= block_start_idx + CONT_REC_N_SAMP - 1
end

### location functions ###
# position is zero-based
sampno_to_block(sampno::Integer) = fld(sampno - 1, CONT_REC_N_SAMP) + 1

sampno_to_offset(sampno::Integer) = mod(sampno - 1, CONT_REC_N_SAMP) + 1

block_start_pos(blockno::Integer) = (blockno - 1) * CONT_REC_BLOCK_SIZE + HEADER_N_BYTES

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
function read_into!(io::IOStream, head::BlockHeader)
    goodread = true
    try
        head.timestamp = read(io, CONT_REC_TIME_BITTYPE)
        head.nsample = read(io, CONT_REC_N_SAMP_BITTYPE)
        goodread = head.nsample == CONT_REC_N_SAMP
        if goodread
            head.recordingnumber = read(io, CONT_REC_REC_NO_BITTYPE)
        end
    catch exception
        if isa(exception, EOFError)
            goodread = false
        else
            rethrow(exception)
        end
    end
    return goodread
end
read_into!(io::IOStream, head::BlockHeader, ::Bool) = read_into!(io, head)

function convert_block!(block::DataBlock)
    contents = reinterpret(CONT_REC_SAMP_BITTYPE, block.body) # readbuff is UInt8
    # Correct for big endianness of this data block
    for idx in eachindex(contents)
        @inbounds contents[idx] = ntoh(contents[idx])
    end
    copy!(block.data, contents)
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

convert_data{A<:OEArray}(::A, H::OriginalHeader, data::Integer) = convert_data(A, H, data)
function convert_data{T<:AbstractFloat, C, B}(::Type{SampleArray{T, C, B}},
                                              H::OriginalHeader, data::Integer)
    return convert(T, data * H.bitvolts)
end
function convert_data{T<:Integer, C, B}(::Type{SampleArray{T, C, B}},
                                              ::OriginalHeader, data::Integer)
    return convert(T, data)
end
function convert_data{T<:AbstractFloat, C, B}(::Type{TimeArray{T, C, B}},
                                              H::OriginalHeader, data::Integer)
    return convert(T, (data - 1) / H.samplerate) # First sample is at time zero
end
function convert_data{T<:Integer, C, B}(::Type{TimeArray{T, C, B}},
                                              H::OriginalHeader, data::Integer)
    return convert(T, data)
end
function convert_data{T, C, B}(::Type{RecNoArray{T, C, B}}, ::OriginalHeader, data::Integer)
    return convert(T, data)
end
function convert_data{S,T,R,C}(::Type{JointArray{S,T,R,C}}, H::OriginalHeader, data::Tuple)
    samp = convert_data(SampleArray{S, C, DataBlock}, H, data[1])
    timestamp = convert_data(TimeArray{T, C, OriginalHeader}, H, data)
    recno = convert_data(RecNoArray{R, C, OriginalHeader}, H, data)
    return samp, timestmap, recno
end

function count_blocks(file::IOStream)
    fsize = stat(file).size
    return div(fsize - HEADER_N_BYTES, CONT_REC_BLOCK_SIZE)
end

count_data(numblocks::Integer) = numblocks * CONT_REC_N_SAMP
count_data(file::IOStream) = count_data(count_blocks(file))
