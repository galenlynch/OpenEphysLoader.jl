### code for loading .continuous files
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
function ContinuousFile(io::IOStream)
    header = OriginalHeader(io) # Read header
    nblock = count_blocks(io)
    nsample = count_data(nblock)
    return ContinuousFile(io, nsample, nblock, header)
end
ContinuousFile(file_name::AbstractString; check::Bool = true) =
    ContinuousFile(open(file_name, "r"), check)

abstract OEArray{T, C<:ContinuousFile} <: AbstractArray{T, 1}
sampletype = Real
timetype = Real
rectype = Integer
jointtype = Tuple{sampletype, timetype, rectype}
arraytypes = ((:SampleArray, sampletype, DataBlock),
              (:TimeArray, timetype, BlockHeader),
              (:RecNoArray, rectype, BlockHeader),
              (:JointArray, jointtype, DataBlock))
for (typename, typeparam, buffertype) = arraytypes
    @eval begin
        type $(typename){T<:$(typeparam), C<:ContinuousFile} <:
            OEArray{T, C}
            contfile::C
            block::$(buffertype)
            blockno::UInt
            check::Bool
        end
        function $(typename){T, C<:ContinuousFile}(::Type{T}, contfile::C, check::Bool = true)
            if check
                check_filesize(contfile.io)
            end
            block = $(buffertype)()
            return $(typename){T, C}(contfile, block, 0, check)
        end
    end
end
function JointArray{C<:ContinuousFile}(contfile::C, check::Bool=true)
    return JointArray(Tuple{Float64, Float64, Int}, contfile, check)
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
    return convert_data(A, data)
end

### Array helper functions ###
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

### location functions ###
sampno_to_block(sampno::Integer) = fld(sampno - 1, CONT_REC_N_SAMP) + 1

sampno_to_offset(sampno::Integer) = mod(sampno - 1, CONT_REC_N_SAMP) + 1

block_start_pos(blockno::Integer) = (blockno - 1) * CONT_REC_BLOCK_SIZE + HEADER_N_BYTES

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

### Methods to access data in buffer ###
block_data(A::SampleArray, rel_idx::Integer) = A.block.data[rel_idx]
block_data(A::TimeArray, rel_idx::Integer) = A.block.timestamp + rel_idx - 1
block_data(A::RecNoArray, ::Integer) = A.block.recordingnumber
function block_data(A::JointArray, rel_idx::Integer)
    sample = A.block.data[rel_idx]
    timestamp = A.block.head.timestamp + rel_idx - 1
    recno = A.block.head.recordingnumber
    return sample, timestamp, recno
end

convert_data{A<:OEArray}(OE::A, data) = convert_data(A, OE.contfile.header, data)
function convert_data{T<:AbstractFloat, C}(::Type{SampleArray{T, C}},
                                              H::OriginalHeader, data::Integer)
    return convert(T, data * H.bitvolts)
end
function convert_data{T<:Integer, C}(::Type{SampleArray{T, C}},
                                              ::OriginalHeader, data::Integer)
    return convert(T, data)
end
function convert_data{T<:AbstractFloat, C}(::Type{TimeArray{T, C}},
                                              H::OriginalHeader, data::Integer)
    return convert(T, (data - 1) / H.samplerate) # First sample is at time zero
end
function convert_data{T<:Integer, C}(::Type{TimeArray{T, C}},
                                              ::OriginalHeader, data::Integer)
    return convert(T, data)
end
function convert_data{T, C}(::Type{RecNoArray{T, C}}, ::OriginalHeader, data::Integer)
    return convert(T, data)
end
function convert_data{S<:sampletype,T<:timetype,R<:rectype,C}(
    ::Type{JointArray{Tuple{S,T,R},C}}, H::OriginalHeader, data::Tuple)
    samp = convert_data(SampleArray{S, C}, H, data[1])
    timestamp = convert_data(TimeArray{T, C}, H, data[2])
    recno = convert_data(RecNoArray{R, C}, H, data[3])
    return samp, timestamp, recno
end

### Verification methods ###
function verify_tail!(io::IOStream, tail::Vector{UInt8})
    nbytes = readbytes!(io, tail, CONT_REC_TAIL_SIZE)
    goodread = nbytes == CONT_REC_TAIL_SIZE && tail == CONT_REC_END_MARKER
    return goodread
end

function check_filesize(file::IOStream)
    @assert rem(filesize(file) - HEADER_N_BYTES, CONT_REC_BLOCK_SIZE) == 0 "File not the right size"
end

### Utility methods ###
function count_blocks(file::IOStream)
    fsize = stat(file).size
    return div(fsize - HEADER_N_BYTES, CONT_REC_BLOCK_SIZE)
end

count_data(numblocks::Integer) = numblocks * CONT_REC_N_SAMP
count_data(file::IOStream) = count_data(count_blocks(file))
