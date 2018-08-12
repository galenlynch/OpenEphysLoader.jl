__precompile__()
module TestContinuous
using Compat, OpenEphysLoader
using Main.TestUtilities, Main.TestOriginal

@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

@static if VERSION >= v"0.7.0-DEV.2575"
    using Random
end


# Helper functions to test OpenEphysLoader's handling of
# continuous files

export test_OEContArray,
    to_block_contents,
    verify_BlockBuffer,
    damaged_file,
    write_continuous,
    bad_blockhead,
    bad_blocktail,
    rand_block_data,
    to_OE_bytes,
    bad_file

### Test array contents ###
function test_OEContArray(
    io::IOStream,
    ::Type{T},
    testtypes::Vector{DataType},
    D::Vector,
    nblock::Integer,
    recno::Integer,
    startsamp::Integer,
) where T<:OEContArray
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
    nblocksamp = OpenEphysLoader.CONT_REC_N_SAMP
    for blockno = 1:fld(nd, nblocksamp)
        block_data, block_body, blockstart =
            to_block_contents(D, blockno, startsamp)
        blockidxes = block_idxes(blockno)
        blockstart = startsamp + blockidxes[1] - 1
        OpenEphysLoader.prepare_block!(A, blockidxes[1])
        @test A.blockno == blockno
        verify_BlockBuffer(A.block,
                           blockstart,
                           recno,
                           block_body,
                           block_data)
    end
end

function block_idxes(blockno::Integer)
    nblocksamp = OpenEphysLoader.CONT_REC_N_SAMP
    return (blockno - 1) * nblocksamp .+ (1:nblocksamp)
end

function to_block_contents(D::Vector, blockno::Integer, startsamp::Integer)
    blockidxes = block_idxes(blockno)
    block_data = D[blockidxes]
    block_body = copy(block_data)
    block_body = reinterpret(UInt8, block_body)
    block_startsamp = startsamp + (blockno - 1) * OpenEphysLoader.CONT_REC_N_SAMP
    return block_data, block_body, block_startsamp
end


function test_OEContArray_contents(
    A::SampleArray{T, C}, D::Vector, varargs...
) where {T<:Real,C}
    @test OpenEphysLoader.block_data(A, 1) == A.block.data[1]
    @test OpenEphysLoader.block_data(A, 1024) == A.block.data[1024]
    @test [OpenEphysLoader.convert_data(A, A.block.data[1])] ==
        sample_conversion(T, A.block.data[1:1])
    verify_samples(copy(A), D)
end
function test_OEContArray_contents(
    A::TimeArray{T, C},
    D::Vector,
    ::Integer,
    startsamp::Integer
) where {T<:Real,C}
    @test OpenEphysLoader.block_data(A, 1) == A.block.timestamp
    @test OpenEphysLoader.block_data(A, 2) == A.block.timestamp + 1
    @test [OpenEphysLoader.convert_data(A, A.block.timestamp)] ==
        time_conversion(T, A.block.timestamp, 1)
    verify_times(copy(A), startsamp, length(D))
end
function test_OEContArray_contents(
    A::RecNoArray{T, C},
    D::Vector,
    recno::Integer,
    ::Integer
) where {T<:Integer,C}
    @test OpenEphysLoader.block_data(A, 1) == recno
    @test OpenEphysLoader.block_data(A, 2) == recno
    @test OpenEphysLoader.convert_data(A, A.block.recordingnumber) ==
        convert(T, recno)
    verify_recnos(copy(A), recno, length(D))
end
function test_OEContArray_contents(
    A::JointArray{Tuple{S,T,R}, C},
    D::Vector,
    recno::Integer,
    startsamp::Integer
) where {S<:Real,T<:Real,R<:Integer,C}
    @test OpenEphysLoader.block_data(A, 1) == (A.block.data[1],
                                               A.block.head.timestamp,
                                               recno)
    @test OpenEphysLoader.block_data(A, 2) == (A.block.data[2],
                                               A.block.head.timestamp + 1,
                                               recno)
    datatup = (
        A.block.data[1],
        A.block.head.timestamp,
        A.block.head.recordingnumber
    )
    answertup = (
        sample_conversion(T, A.block.data[1:1])[1],
        time_conversion(T, A.block.head.timestamp, 1)[1],
        convert(T, recno)
    )
    @test OpenEphysLoader.convert_data(A, datatup) == answertup
    samples = S[tup[1] for tup in A]
    times = T[tup[2] for tup in A]
    recnos = R[tup[3] for tup in A]
    nd = length(D)
    verify_samples(samples, D)
    verify_times(times, startsamp, nd)
    verify_recnos(recnos, recno, nd)
end

verify_samples(A::Vector{T}, D::Vector) where {T} = @test sample_conversion(T, D) == A
function verify_times(A::Vector{T}, startsamp::Integer, nsamp::Integer) where T
   @test time_conversion(T, startsamp, nsamp) == A
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

function test_OEContArray_interface(::Type{T}) where T<:OEContArray
    fields = fieldnames(T)
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
    body::AbstractVector{UInt8},
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
    ::AbstractVector{UInt8},
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

function write_continuous(
    io::IOStream,
    d::AbstractArray{T, 1},
    recno::Integer = 0,
    startsamp::Integer = 1,
    recdelay::Integer = 0
) where T<:Integer
    nd = length(d)
    if recdelay >= OpenEphysLoader.CONT_REC_N_SAMP
        error("Delay between file start and recording is too long")
    end
    nstoppad = mod(-(nd + recdelay), OpenEphysLoader.CONT_REC_N_SAMP)
    nblock = cld(nd + recdelay, OpenEphysLoader.CONT_REC_N_SAMP) # ceiling divide
    if nstoppad > 0 || recdelay > 0
        padded = zeros(Int, OpenEphysLoader.CONT_REC_N_SAMP * nblock)
        padded[(1 + recdelay):(end - nstoppad)] = d
    else
        padded = d # no padding needed, renaming for clarity below
    end
    write_fheader_fun()(io)
    tblock = startsamp
    offset = 0
    for blockno in 1:nblock
        writeblock(
            io,
            view(
                padded,
                offset .+ (1:OpenEphysLoader.CONT_REC_N_SAMP)
            ),
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
    blockdata = rand_block_data()
    writeblock(io, blockdata; bad_blockhead = true)
end

function bad_blocktail(io::IOStream)
    blockdata = rand_block_data()
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
    # write block header
    write(io, OpenEphysLoader.CONT_REC_TIME_BITTYPE(t))
    nsamp_bittype = OpenEphysLoader.CONT_REC_N_SAMP_BITTYPE
    if bad_blockhead
        write(io, zero(nsamp_bittype))
    else
        write(io, nsamp_bittype(OpenEphysLoader.CONT_REC_N_SAMP))
    end
    write(io, OpenEphysLoader.CONT_REC_REC_NO_BITTYPE(recno))

    # Convert data to open ephys format
    oebytes = to_OE_bytes(d)
    # write data
    write(io, oebytes)

    # write tail
    if bad_blocktail
        write(io, b"razzmatazz")
    else
        write(io, OpenEphysLoader.CONT_REC_END_MARKER)
    end
end
function to_OE_bytes(D::AbstractArray{T,1}) where T<:OpenEphysLoader.CONT_REC_SAMP_BITTYPE
    contents = copy(D)
    for i in eachindex(contents)
        @inbounds contents[i] = hton(contents[i])
    end
    oebytes = reinterpret(UInt8, contents)
    return oebytes
end

### Utility functions ###
sample_conversion(::Type{T}, data::AbstractArray{R, 1}) where {T<:Integer, R<:Integer} =
    Vector{T}(copy(data))
sample_conversion(::Type{T}, data::AbstractArray{R, 1}) where {T<:AbstractFloat, R<:Integer} =
    0.195 * Vector{T}(copy(data))
function time_conversion(
    ::Type{T},
    startsamp::Integer,
    nsamp::Integer
) where T<:Integer
    return T[t for t in startsamp:1:(startsamp + nsamp - 1)]
end
function time_conversion(
    ::Type{T},
    startsamp::Integer,
    nsamp::Integer
) where T<:AbstractFloat
    timepoints = (time_conversion(Int, startsamp, nsamp) .- 1) / 30000
    converted_times = similar(timepoints, T)
    @compat copyto!(converted_times, timepoints)
    return converted_times
end

function rand_block_data()
    return rand(
        OpenEphysLoader.CONT_REC_SAMP_BITTYPE,
        OpenEphysLoader.CONT_REC_N_SAMP
    )
end

end
