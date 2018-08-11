# code for loading .continuous files
### Constants ###
const CONT_REC_TIME_BITTYPE = Int64
const CONT_REC_N_SAMP = 1024
const CONT_REC_N_SAMP_BITTYPE = UInt16
const CONT_REC_REC_NO_BITTYPE = UInt16
const CONT_REC_SAMP_BITTYPE = Int16
const CONT_REC_BYTES_PER_SAMP = sizeof(CONT_REC_SAMP_BITTYPE)
const CONT_REC_END_MARKER = UInt8[0x00, 0x01, 0x02, 0x03, 0x04,
                                  0x05, 0x06, 0x07, 0x08, 0xff]
const CONT_REC_HEAD_SIZE = mapreduce(sizeof, +, [CONT_REC_TIME_BITTYPE,
                             CONT_REC_N_SAMP_BITTYPE, CONT_REC_REC_NO_BITTYPE])
const CONT_REC_BODY_SIZE = CONT_REC_N_SAMP * sizeof(CONT_REC_SAMP_BITTYPE)
const CONT_REC_TAIL_SIZE = sizeof(CONT_REC_END_MARKER)
const CONT_REC_BLOCK_SIZE = CONT_REC_HEAD_SIZE + CONT_REC_BODY_SIZE +
    CONT_REC_TAIL_SIZE

### Types ###
"Type to buffer continuous file contents"
abstract type BlockBuffer end

"Represents the header of each data block"
mutable struct BlockHeader <: BlockBuffer
    timestamp::CONT_REC_TIME_BITTYPE
    nsample::CONT_REC_N_SAMP_BITTYPE
    recordingnumber::CONT_REC_REC_NO_BITTYPE
end
BlockHeader() = BlockHeader(0, 0, 0)

"Represents the entirety of a data block"
mutable struct DataBlock <: BlockBuffer
    head::BlockHeader
    body::Vector{UInt8}
    data::Vector{CONT_REC_SAMP_BITTYPE}
    tail::Vector{UInt8}
    function DataBlock(
        head::BlockHeader,
        body::Vector{UInt8},
        data::Vector{CONT_REC_SAMP_BITTYPE},
        tail::Vector{UInt8}
    )
        length(body) == CONT_REC_BODY_SIZE || error("body length must be ", CONT_REC_BODY_SIZE)
        length(data) == CONT_REC_N_SAMP || error("data length must be ", CONT_REC_N_SAMP)
        length(tail) == CONT_REC_TAIL_SIZE || error("data length must be ", CONT_REC_TAIL_SIZE)
        return new(head, body, data, tail)
    end
end
function DataBlock()
    head = BlockHeader()
    body = Vector{UInt8}(CONT_REC_BODY_SIZE)
    data = Vector{CONT_REC_SAMP_BITTYPE}(CONT_REC_N_SAMP)
    tail =  Vector{UInt8}(CONT_REC_TAIL_SIZE)
    DataBlock(head, body, data, tail)
end

"""
    ContinuousFile(io::IOStream)
Type for an open continuous file.

# Fields

**`io`** `IOStream` object.

**`filepath`** Path to underlying file, possibly empty

**`nsample`** number of samples in a file.

**`nblock`** number of data blocks in a file.

**`header`** [`OriginalHeader`](@ref) of the current file.
"""
struct ContinuousFile{T<:Integer, S<:Integer, H<:OriginalHeader}
    "IOStream for open continuous file"
    io::IOStream
    "Path to file, possibly empty"
    filepath::String
    "Number of samples in file"
    nsample::T
    "Number of data blocks in file"
    nblock::S
    "File header"
    header::H
end
function ContinuousFile(io::IOStream, filepath::AbstractString = "")
    header = OriginalHeader(io) # Read header
    nblock = count_blocks(io)
    nsample = count_data(nblock)
    return ContinuousFile(io, string(filepath), nsample, nblock, header)
end

"""
Abstract array for file-backed OpenEphys data.

All subtypes support a ready-only array interface and should
be constructable with a single IOStream argument.
"""
abstract type OEArray{T} <: AbstractArray{T, 1} end

setindex!(::OEArray, ::Int) = throw(ReadOnlyMemoryError())

"""
Abstract array for file-backed continuous OpenEphys data.

Will throw [`CorruptedException`](@ref) if the data file has
a corrupt [`OriginalHeader`](@ref), is not the correct size
for an `.continuous` file, or contains corrupt data blocks.

Subtype of abstract type [`OEArray`](@ref) are read only,
and have with the following fields:

# Fields

**`contfile`** [`ContinuousFile`](@ref) for the current file.

**`block`** buffer object for the data blocks in the file.

**`blockno`** the current block being access in the file.

**`check`** `Bool` to check each data block's validity.
"""
abstract type OEContArray{T, C<:ContinuousFile} <: OEArray{T} end
### Stuff for code generation ###
sampletype = Real
timetype = Real
rectype = Integer
jointtype = Tuple{sampletype, timetype, rectype}
arraytypes = ((:SampleArray, sampletype, DataBlock, Float64),
              (:TimeArray, timetype, BlockHeader, Float64),
              (:RecNoArray, rectype, BlockHeader, Int),
              (:JointArray, jointtype, DataBlock, Tuple{Float64, Float64, Int}))
### Generate array datatypes ###
for (typename, typeparam, buffertype, defaulttype) = arraytypes
    @eval begin
        mutable struct $(typename){T<:$(typeparam), C<:ContinuousFile} <: OEContArray{T, C}
            contfile::C
            block::$(buffertype)
            blockno::UInt
            check::Bool
        end
        function $(typename)(
            ::Type{T}, contfile::C, check::Bool = true
        ) where {T, C<:ContinuousFile}
            if check
                if ! check_filesize(contfile.io)
                    throw(CorruptedException(string(
                        "\nThe size of this file indicates that it cannot be well-formed.\n",
                        "This likely means that the last data block is missing samples.\n",
                        "HINT: To attempt access to the remaining contents of this file, use:\n",
                        $(typename),
                        "(T, io, false) to turn off this check."
                    )))
                end
            end
            block = $(buffertype)()
            return $(typename){T, C}(contfile, block, 0, check)
        end
        function $(typename)(
            ::Type{T},
            io::IOStream,
            check::Bool = true,
            filepath::AbstractString = ""
        ) where {T}
            return $(typename)(T, ContinuousFile(io, filepath), check)
        end
        function $(typename)(
            ::Type{T},
            filepath::AbstractString,
            check::Bool = true
        ) where {T}
            ior = open(filepath, "r")
            atexit(() -> close(ior))
            return $(typename)(T, ior, check, filepath)
        end
        function $(typename)(firstarg::Union{IO, AbstractString}, args...)
            return $(typename)($(defaulttype), firstarg, args...)
        end
    end
end

const arrayargs = "([type::Type{T},] file::Union{IO, String}, [check::Bool, filepath::String])"
const arraypreamble =
    "Subtype of [`OEContArray`](@ref) to provide file backed access to OpenEphys"
@doc """
    SampleArray$arrayargs
$arraypreamble sample values. If `type` is a floating
point type, then the sample value will be converted to voltage (in uV). Otherwise,
the sample values will remain the raw ADC integer readings.
""" SampleArray
@doc """
    TimeArray$arrayargs
$arraypreamble time stamps. If `type` is a floating
point type, then the time stamps will be converted to seconds. Otherwise,
the time stamp will be the sample number.
""" TimeArray
@doc """
    RecNoArray$arrayargs
$arraypreamble numbers.
""" RecNoArray
@doc """
    JointArray$arrayargs
$arraypreamble data. Returns a tuple of type `type`, whose
values represent `(samplevalue, timestamp, recordingnumber)`. For a description of
each, see [`SampleArray`](@ref), [`TimeArray`](@ref), and [`RecNoArray`](@ref),
respectively.
""" JointArray

### Array interface ###
length(A::OEContArray) = A.contfile.nsample

size(A::OEContArray) = (length(A),)

Base.IndexStyle(::Type{T}) where {T<:OEContArray} = IndexLinear()


function getindex(A::OEContArray, i::Integer)
    prepare_block!(A, i)
    relidx = sampno_to_offset(i)
    data = block_data(A, relidx)
    return convert_data(A, data)
end

### Array helper functions ###
"Load data block if necessary"
function prepare_block!(A::OEContArray, i::Integer)
    blockno = sampno_to_block(i)
    if blockno != A.blockno
        seek_to_block(A.contfile.io, blockno)
        goodread = read_into!(A.contfile.io, A.block, A.check)
        goodread || throw(CorruptedException("Data block $blockno is malformed"))
        A.blockno = blockno
    end
    nothing
end

"Move io to data block"
function seek_to_block(io::IOStream, blockno::Integer)
    blockpos = block_start_pos(blockno)
    if blockpos != position(io)
        seek(io, blockpos)
    end
end

### location functions ###
sampno_to_block(sampno::Integer) = fld(sampno - 1, CONT_REC_N_SAMP) + 1

sampno_to_offset(sampno::Integer) = mod(sampno - 1, CONT_REC_N_SAMP) + 1

function block_start_pos(blockno::Integer)
    return (blockno - 1) * CONT_REC_BLOCK_SIZE + HEADER_N_BYTES
end

function pos_to_blockno(pos::Integer)
    if pos < 0
        throw(ArgumentError("Invalid position"))
    elseif pos < HEADER_N_BYTES
        blockno = 0
    else
        blockno = fld(pos - HEADER_N_BYTES, CONT_REC_BLOCK_SIZE) + 1
    end
    return blockno
end

blockno_to_start_sampno(blockno::Integer) = (blockno - 1) * CONT_REC_N_SAMP + 1

### File access and conversion ###
"Read file data block into data block buffer"
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
"Read block header into header buffer"
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

"Convert the wacky data format in OpenEphys continuous files"
function convert_block!(block::DataBlock)
    ptr = Ptr{CONT_REC_SAMP_BITTYPE}(pointer(block.body))
    if ENDIAN_BOM == 0x04030201
        # Host is little endian: Always true for now
        # Correct for big endianness of this data block
        for idx in 1:CONT_REC_N_SAMP
            unsafe_store!(ptr, ntoh(unsafe_load(ptr, idx)), idx)
        end
    end
    unsafe_copy!(pointer(block.data), ptr, CONT_REC_N_SAMP)
    return block.data
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

### Methods to convert raw values into desired ones ##
convert_data(OE::A, data) where {A<:OEContArray} = convert_data(A, OE.contfile.header, data)
function convert_data(
    ::Type{SampleArray{T, C}}, H::OriginalHeader, data::Integer
) where {T<:AbstractFloat, C}
    return convert(T, data * H.bitvolts)
end
function convert_data(
    ::Type{SampleArray{T, C}}, ::OriginalHeader, data::Integer
) where {T<:Integer, C}
    return convert(T, data)
end
function convert_data(
    ::Type{TimeArray{T, C}}, H::OriginalHeader, data::Integer
) where {T<:AbstractFloat, C}
    return convert(T, (data - 1) / H.samplerate) # First sample is at time zero
end
function convert_data(
    ::Type{TimeArray{T, C}}, ::OriginalHeader, data::Integer
) where {T<:Integer, C}
    return convert(T, data)
end
function convert_data(::Type{RecNoArray{T, C}}, ::OriginalHeader, data::Integer) where {T, C}
    return convert(T, data)
end
function convert_data(
    ::Type{JointArray{Tuple{S,T,R},C}}, H::OriginalHeader, data::Tuple
) where {S<:sampletype,T<:timetype,R<:rectype,C}
    samp = convert_data(SampleArray{S, C}, H, data[1])
    timestamp = convert_data(TimeArray{T, C}, H, data[2])
    recno = convert_data(RecNoArray{R, C}, H, data[3])
    return samp, timestamp, recno
end

### Verification methods ###
"Verify end of block marker"
function verify_tail!(io::IOStream, tail::Vector{UInt8})
    nbytes = readbytes!(io, tail, CONT_REC_TAIL_SIZE)
    goodread = nbytes == CONT_REC_TAIL_SIZE && tail == CONT_REC_END_MARKER
    return goodread
end

"Check that file could be comprised of header and complete data blocks"
function check_filesize(file::IOStream)
    filesizeok = rem(filesize(file) - HEADER_N_BYTES, CONT_REC_BLOCK_SIZE) == 0
end

### Utility methods ###
function count_blocks(file::IOStream)
    fsize = stat(file).size
    return div(fsize - HEADER_N_BYTES, CONT_REC_BLOCK_SIZE)
end

count_data(numblocks::Integer) = numblocks * CONT_REC_N_SAMP
count_data(file::IOStream) = count_data(count_blocks(file))
