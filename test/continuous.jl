using OpenEphysLoader, Base.Test
# Helper functions to test OpenEphysLoader's handling of continuous files

### Test array contents ###
function test_OEContArray{T<:OEContArray}(
    io::IOStream,
    ::Type{T},
    testtypes::Vector{DataType}
    D::Vector,
    nblock::Integer,
    recno::Integer,
    startsamp::Integer,
)
    test_OEContArray_interface(T)
    seekstart(io)
    A = T(io)
    test_OEContArray_parts(A, D, nblock, recno, startsamp)
    test_OEContArray(A, D, recno, startsamp)
    for t in testtypes
        seekstart(io)
        A = T(t, io)
        test_OEContArray(A, D, recno, startsamp)
    end
end
function test_OEContArray(
    A::OEContArray,
    D::Vector,
    recno::Integer,
    startsamp::Integer
)
    test_OEArray_interface(A)
    test_OEContArray_contents(A, D, recno, startsamp)
end

function test_OEContArray_parts(
    A::OEContArray,
    D::Vector,
    nblock::Integer,
    recno::Integer,
    startsamp::Integer
)
    nd = length(D)
    verify_ContinuousFile(A.contfile, nd, nblock)
    for blockno = 1:fld(nd, nblocksamp)
        block_data, block_oebytes, blockstart = to_block_contents(D, blockno)
        blockidxes = block_idxes(blockno)
        blockstart = startsamp + blockidxes[1] - 1
        tmp = A[blockidxes[1]] # need to load data into the BlockBuffer
        verify_BlockBuffer(A.block,
                           blockstart,
                           recno,
                           block_oebytes,
                           block_data)
    end
end

function block_idxes(blockno::Integer)
    nblocksamp = OpenEphysLoader.CONT_REC_N_SAMP
    return (blockno - 1) * nblocksamp + (1:nblocksamp)
end

function to_block_contents(D::Vector, blockno::Integer)
    blockidxes = block_idxes(blockno)
    block_data = D[blockidxes]
    block_oebytes = to_OE_bytes(block_data)
    return block_data, block_oebytes, blockstart
end


function test_OEContArray_contents{T<:Real,C}(
    A::SampleArray{T, C}, D::Vector, varargs...
)
    verify_samples(copy(A), D)
end
function test_OEContArray_contents{T<:Real,C}(
    A::TimeArray{T, C},
    D::Vector,
    ::Integer,
    startsamp::Integer
)
    verify_times(copy(A), startsamp, length(D))
end
function test_OEContArray_contents{T<:Integer,C}(
    A::RecNoArray{T, C},
    D::Vector,
    recno::Integer,
    ::Integer
)
    verify_recnos(copy(A), recno, length(D))
end
function test_OEContArray_contents{S,T,R,C}(
    A::JointArray{Tuple{S,T,R}, C},
    D::Vector,
    recno::Integer,
    startsamp::Integer
)
    samples = S[tup[1] for tup in A]
    times = T[tup[2] for tup in A]
    recnos = R[tup[3] for tup in A]
    nd = length(D)
    verify_samples(samples, D)
    verify_times(times, startsamp, nd)
    verify_recnos(recnos, recno, nd)
end

verify_samples{T}(A::Vector{T}, D::Vector) = @test cont_data_conversion(T, D) == A
function verify_times{T}(A::Vector{T}, startsamp::Integer, nsamp::Integer)
   @test cont_time_conversion(T, startsamp, nsamp) == A
end
function verify_recnos(A::Vector, recno::Integer, nsamp::Integer)
    @test fill(recno, (nsamp,)) == A
end

### Test interfaces ###
function test_OEArray_interface(A::OEArray)
    @assert !isempty(A) "Tests require a non-empty array"
    @test !isempty(size(A))
    @test !isempty(A[1])
    @test !isempty(A[end])
    @test isa(eltype(A), Type)
    @test !isempty(length(A))
    @test_throws ErrorException A[1] = A[1]
end

function test_OEContArray_interface{T<:OEContArray}(::Type{T})
    fields = getfields(T)
    @test :contfile in fields
    @test :block in fields
    @test :blockno in fields
    @test :check in fields
    @test !isempty(methods(T, (IOStream,)))
end

### Verify data types ###
function verify_BlockBuffer(
    block::OpenEphysLoader.DataBlock,
    t::Integer,
    rec::Integer,
    body::Vector{UInt8},
    data::Vector{OpenEphysLoader.CONT_REC_SAMP_BITTYPE},
)
    verify_BlockBuffer(block.head, t, rec)
    @test block.body == body
    @test block.data == data
    @test block.tail == OpenEphysLoader.CONT_REC_END_MARKER
end
function verify_BlockBuffer(
    block::OpenEphysLoader.BlockHeader,
    t::Integer,
    rec::Integer,
    ::Vector{UInt8},
    ::Vector{OpenEphysLoader.CONT_REC_SAMP_BITTYPE},
)
    verify_BlockBuffer(block, t, rec)
end
function verify_BlockBuffer(
    block::OpenEphysLoader.BlockHeader,
    t::Integer,
    rec::Integer
)
    @test block.timestamp == t
    @test block.nsample == OpenEphysLoader.CONT_REC_N_SAMP
    @test block.recordingnumber == rec
end

function verify_ContinuousFile(C::ContinuousFile, nsample::Integer, nblock::Integer)
    @test isopen(C.io) && !eof(C.io)
    @test C.nsample == nsample
    @test C.nblock == nblock
    verify_header(C.header)
end

### Functions to write .continuous files ###
bad_file(io::IOStream) = write(io, "These aren't the droids you're looking for")

function damaged_file(io::IOStream, args...; kwargs...)
    write_continuous(io, args...; kwargs...)
    bad_blockhead(io)
end

function write_continuous{T<:Integer}(
    io::IOStream,
    d::AbstractArray{T, 1},
    recno::Integer = 0,
    startsamp::Integer = 1,
    recdelay::Integer = 0
)
    l = length(d)
    t = startsamp
    if recdelay < OpenEphysLoader.CONT_REC_N_SAMP
        error("Delay between file start and recording is too long")
    end
    nstoppad = mod(-(l + recdelay), OpenEphysLoader.CONT_REC_N_SAMP)
    nblock = cld(l + recdelay, OpenEphysLoader.CONT_REC_N_SAMP) # ceiling divide
    if nstoppad > 0 || recdelay > 0
        padded = zeros(Int, OpenEphysLoader.CONT_REC_N_SAMP * nblock)
        padded[(1 + recdelay):(end - nstoppad)] = d
    else
        padded = d # no padding needed, renaming for clarity below
    end
    write_original_header(io)
    tblock = startsamp
    offset = 0
    for blockno in 1:nblock
        writeblock(
            io,
            view(padded, offset + (1:OpenEphysLoader.CONT_REC_N_SAMP)),
            tblock,
            recno
        )
        tblock += OpenEphysLoader.CONT_REC_N_SAMP
        offset += OpenEphysLoader.CONT_REC_N_SAMP
    end
end
function write_continuous(path::String, args...)
    open(path, "w") do io
        write_continuous(io, args...)
    end
end

### Functions to write data blocks ###
good_block(io::IOStream, d::AbstractArray, t::Integer, r::Integer) = writeblock(io, d, t, r)

function bad_blockhead(io::IOStream)
    blockdata = rand(OpenEphysLoader.CONT_REC_SAMP_BITTYPE, OpenEphysLoader.CONT_REC_N_SAMP)
    writeblock(io, blockdata; bad_blockhead = true)
end

function bad_blocktail(io::IOStream)
    blockdata = rand(OpenEphysLoader.CONT_REC_SAMP_BITTYPE, OpenEphysLoader.CONT_REC_N_SAMP)
    writeblock(io, blockdata; bad_blocktail = true)
end

function writeblock(
    io::IOStream,
    d::AbstractArray,
    t::Integer = 1,
    recno::Integer = 0;
    bad_blockhead::Bool = false,
    bad_blocktail::Bool = false
)
    # Convert data to open ephys format
    oebytes = to_OE_bytes(d)
    # write block header
    write(io, OpenEphysLoader.CONT_REC_TIME_BITTYPE(t))
    if bad_blockhead
        write(io, zero(OpenEphysLoader.CONT_REC_N_SAMP_BITTYPE))
    else
        nsamp_bittype = OpenEphysLoader.CONT_REC_N_SAMP_BITTYPE
        write(io, nsamp_bittype(OpenEphysLoader.CONT_REC_N_SAMP))
    end
    write(io, OpenEphysLoader.CONT_REC_REC_NO_BITTYPE(recno))
    # write data
    write(io, oebytes)
    # write tail
    if bad_blocktail
        write(io, b"razzmatazz")
    else
        write(io, OpenEphysLoader.CONT_REC_END_MARKER)
    end
end
function to_OE_bytes(D::AbstractArray)
    oebytes = similar(D, OpenEphysLoader.CONT_REC_SAMP_BITTYPE)
    copy!(oebytes, D)
    for i in eachindex(oebytes)
        @inbounds oebytes[i] = hton(oebytes[i])
    end
    return oebytes
end

### Utility functions ###
cont_data_conversion{T<:Integer}(::Type{T}, data::AbstractArray{T, 1}) =
    Vector{T}(copy(data))
cont_data_conversion{T<:AbstractFloat}(::Type{T}, data::AbstractArray{T, 1}) =
    0.195 * Vector{T}(copy(data))
function cont_time_conversion(T<:Integer)(
    ::Type{T},
    startsamp::Integer,
    nsamp::Integer
)
    return convert(T, startsamp:1:(startsamp + nsamp - 1))
end
function cont_time_conversion(T<:AbstractFloat)(
    ::Type{T},
    startsamp::Integer,
    nsamp::Integer
)
    timepoints = (cont_time_converstion(Int, startsamp, nsamp) - 1) / 30000
    return convert(T, timepoints)
end

function rand_block_data()
    return rand(OpenEphysLoader.CONT_REC_SAMP_BITTYPE, OpenEphysLoader.CONT_REC_N_SAMP)
end
