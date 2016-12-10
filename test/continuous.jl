using OpenEphysLoader, Base.Test
# Helper functions to test OpenEphysLoader's handling of continuous files

### Test interfaces ###
function test_OEArray_interface(A::OEArray)
    @assert !isempty(A) "Tests require a non-empty array"
    @test !isempty(size(A))
    @test !isempty(A[1])
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
function verify_BlockHeader(blockhead::OpenEphysLoader.BlockHeader, t::Integer, rec::Integer)
    @test blockhead.timestamp == t
    @test blockhead.nsample == OpenEphysLoader.CONT_REC_N_SAMP
    @test blockhead.recordingnumber == rec
end

function verify_DataBlock(
    block::OpenEphysLoader.DataBlock,
    t::Integer,
    rec::Integer,
    body::Vector{UInt8},
    data::Vector{OpenEphysLoader.CONT_REC_SAMP_BITTYPE},
)
    verify_BlockHeader(block.head, t, rec)
    @test block.body == body
    @test block.data == data
    @test block.tail == OpenEphysLoader.CONT_REC_END_MARKER
end

### Functions to write .continuous files ###
bad_file(io::IOStream) = write(io, "These aren't the droids you're looking for")

function damaged_file(io::IOStream, args...; kwargs...)
    write_continuous(io, args...; kwargs...)
    bad_blockhead(io)
end

random_continuous_name(chno::Int) = "$(randstring())_$(rand(["CH", "AUX"]))$chno.continuous"
random_continuous_name() = random_continuous_name(rand(1:256))

function write_continuous{T<:Integer}(io::IOStream, d::AbstractArray{T, 1},
                            recno::Integer = 0, ftime::Integer = 1, rtime::Integer = 1)
    l = length(d)
    t = ftime
    nstartpad = Int(rtime - ftime)
    nstartpad < OpenEphysLoader.CONT_REC_N_SAMP || error("Delay between file start and recording is too long")
    nstoppad = mod(-(l + nstartpad), OpenEphysLoader.CONT_REC_N_SAMP)
    nblock = cld(l + nstartpad, OpenEphysLoader.CONT_REC_N_SAMP) # ceiling divide
    if nstoppad > 0 || nstartpad > 0
        padded = zeros(Int, OpenEphysLoader.CONT_REC_N_SAMP * nblock)
        padded[(1 + nstartpad):(end - nstoppad)] = d
    else
        padded = d # no padding needed, renaming for clarity below
    end
    write_original_header(io)
    tblock = ftime
    offset = 0
    for blockno in 1:nblock
        writeblock(io, sub(padded, offset + (1:OpenEphysLoader.CONT_REC_N_SAMP)), tblock, recno)
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

function writeblock(io::IOStream, d::AbstractArray, t::Integer = 1, recno::Integer = 0;
     bad_blockhead::Bool = false, bad_blocktail::Bool = false)
     tmp_data = similar(d, OpenEphysLoader.CONT_REC_SAMP_BITTYPE)
     copy!(tmp_data, d)
     for idx in eachindex(tmp_data)
         @inbounds tmp_data[idx] = hton(tmp_data[idx])
     end
     write(io, OpenEphysLoader.CONT_REC_TIME_BITTYPE(t))
     if bad_blockhead
         write(io, zero(OpenEphysLoader.CONT_REC_N_SAMP_BITTYPE))
     else
         write(io, OpenEphysLoader.CONT_REC_N_SAMP_BITTYPE(OpenEphysLoader.CONT_REC_N_SAMP))
     end
     write(io, OpenEphysLoader.CONT_REC_REC_NO_BITTYPE(recno))
     write(io, tmp_data)
     if bad_blocktail
         write(io, b"razzmatazz")
     else
         write(io, OpenEphysLoader.CONT_REC_END_MARKER)
     end
end

### Utility functions ###
cont_data_conversion{T<:Integer}(::Type{T}, data::Vector) =
    Vector{T}(copy(data))
cont_data_conversion{T<:FloatingPoint}(::Type{T}, data::Vector) =
    0.195 * Vector{T}(copy(data))

function rand_block_data()
    return rand(OpenEphysLoader.CONT_REC_SAMP_BITTYPE, OpenEphysLoader.CONT_REC_N_SAMP)
end

function leaf_types{T<:OEArray}(::Type{T})
    leaves = Array{DataType, 1}()
    rawsubtypes = subtypes(T) # Any type for some reason
    branches = Array{DataType, 1}(length(rawsubtypes))
    copy!(branches, rawsubtypes)
end

