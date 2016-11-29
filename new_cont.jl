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

type ContBlockHeader
    timestamp::CONT_REC_TIME_BITTYPE
    nsample::CONT_REC_N_SAMP_BITTYPE
    recordingnumber::CONT_REC_REC_NO_BITTYPE
end
ContBlockHeader() = ContBlockHeader(0, 0, 0)

type ContBlockBuff
    blockhead::ContBlockHeader
    bodybuffer::Vector{UInt8}
    blocktail::Vector{UInt8}
end
function ContBlockBuff()
    blockhead = ContBlockHeader()
    bodybuffer = Vector{UInt8}(CONT_REC_BODY_SIZE)
    blocktail =  Vector{UInt8}(CONT_REC_TAIL_SIZE)
    ContBlockBuff(blockhead, bodybuffer, blocktail)
end

immutable ContinuousFile{T<: Integer, S<:Integer, H<:OriginalHeader}
    io::IOStream
    filemmap::Vector{UInt8}
    blockbuff::ContBlockBuff
    nsample::T
    nblock::S
    header::H
end
function ContinuousFile(io::IOStream, check::Bool = true)
    datalen = stat(io).size - HEADER_N_BYTES
    filemmap = Mmap.mmap(io, Vector{UInt8}, datalen, HEADER_N_BYTES)
    fileheader = OriginalHeader(io) # Read header
    nsample = count_data(io)
    nblock = count_blocks(io)
    if check
        check_filesize(io)
        check_contfile(filemmap, nblock)
    end
    return ContinuousFile(io, filemmap, nsample, nblock, fileheader)
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
    idx = sampno_to_idx(i)
    sample_filebytes = A.contfile.filemmap[idx:idx + CONT_REC_BYTES_PER_SAMP - 1]
    sample = ntoh(reinterpret(CONT_REC_SAMP_BITTYPE, sample_filebytes)[1])
    return convert_sample(T, sample, A.contfile.header.bitvolts)
end

function getindex{T, C}(A::TimeArray{T, C}, i::Integer)
    blockstartpos = block_start_idx(sampno_to_block(i))
    byteidxes = blockstartpos:(blockstartpos + sizeof(CONT_REC_TIME_BITTYPE) - 1)
    sampleno_filebytes = A.contfile.filemmap[byteidxes]
    block_sampleno = reinterpret(CONT_REC_TIME_BITTYPE, sampleno_filebytes)[1]
    sampleno = block_sampleno + (i - 1) % CONT_REC_N_SAMP
    return convert_timepoint(T, sampleno, A.contfile.header.samplerate)
end

function getindex{T, C}(A::RecNoArray{T, C}, i::Integer)
    recno_pos = block_start_idx(sampno_to_block(i)) +
        sizeof(CONT_REC_TIME_BITTYPE) +
        sizeof(CONT_REC_N_SAMP_BITTYPE)
    recno_filebytes = A.contfile.filemmap[recno_pos:recno_pos + sizeof(CONT_REC_REC_NO_BITTYPE) - 1]
    return T(reinterpret(CONT_REC_REC_NO_BITTYPE, recno_filebytes)[1])
end

function getindex(A::JointArray, i::Integer)
    return A.samples[i], A.times[i], A.recnos[i]
end

### location functions ###
function sampno_to_idx(sampno::Integer)
    block_sample_start = block_start_idx(sampno_to_block(sampno)) + CONT_REC_HEAD_SIZE
    return block_sample_start + (sampno - 1) % CONT_REC_N_SAMP * CONT_REC_BYTES_PER_SAMP
end

sampno_to_block(sampno::Integer) = div(sampno - 1, CONT_REC_N_SAMP) + 1

block_start_idx(block_no::Integer) = (block_no - 1) * CONT_REC_SIZE + 1
### Functions for loading from a directory ###
function loaddirectory{D}(directorypath::AbstractString, ::Type{D} = Float64;
         checktail::Bool = false, sortfiles::Bool = true)
    # Find continuous files
    filenames = readdir(directorypath)
    filenames = filter(matchcontinuous, filenames)
    if sortfiles
        filenames = sort_continuousfiles(filenames)
    end
    # Load continuous files
end
loaddirectory{D}(::Type{D} = Float64; checktail::Bool = false,
    sortfiles::Bool = true, verbose::Bool = false) = loaddirectory(".", D;
        checktail = checktail, sortfiles = sortfiles)

matchcontinuous(str::AbstractString) = ismatch(r"\.continuous$", str)

function sort_continuousfiles{T<:ByteString}(filenames::Vector{T})
    nfiles = length(filenames)
    channeltype =  Vector{UTF8String}(nfiles)
    channelno =  Vector{Int}(nfiles)
    for fno in 1:nfiles
        channeltype[fno], channelno[fno] = getcont_typeno(filenames[fno])
    end
    channelno[channeltype .== "AUX"] += 1000 # Make sure aux channels are sorted last
    sortidx = sortperm(channelno)
    return filenames[sortidx]
end

function getcont_typeno(str::AbstractString)
    m = match(r"_(CH|AUX)(\d+)\.", str)
    return m.captures[1]::AbstractString, parse(m.captures[2])::Int
end

### Verification functions ###
function check_filesize(file)
    @assert rem(filesize(file) - HEADER_N_BYTES, CONT_REC_SIZE) == 0 "File not the right size"
end


function check_contfile(filemmap::Vector{UInt8}, nblock::Integer)
    for block in 1:nblock
        @assert verify_contblock_header(filemmap, block) "File corrupt: bad header in block $block"
        @assert verify_contblock_tail(filemmap, block) "File corrupt: bad tail in block $block"
    end
end

function verify_contblock_header(filemmap::Vector{UInt8}, blockno::Integer)
    nsamp_idx = block_start_idx(blockno) + sizeof(CONT_REC_TIME_BITTYPE)
    nsamp_bytes = filemmap[nsamp_idx:nsamp_idx + sizeof(CONT_REC_N_SAMP_BITTYPE) - 1]
    return reinterpret(CONT_REC_N_SAMP_BITTYPE, nsamp_bytes)[1] == CONT_REC_N_SAMP
end

function verify_contblock_tail(filemmap::Vector{UInt8}, blockno::Integer)
    tailstart = block_start_idx(blockno) + CONT_REC_HEAD_SIZE + CONT_REC_BODY_SIZE
    return filemmap[tailstart:tailstart + CONT_REC_TAIL_SIZE - 1] == CONT_REC_END_MARKER
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

function count_blocks(file)
    fsize = stat(file).size
    return div(fsize - HEADER_N_BYTES, CONT_REC_SIZE)
end

count_data(file) = count_blocks(file) * CONT_REC_N_SAMP
