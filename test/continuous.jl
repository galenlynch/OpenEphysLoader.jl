using OpenEphys, Base.Test

typealias UninitializedArray Union{Type{Matrix}, Type{Vector}}

### Helper functions ###
function test_load_contfiles_corrupt{S<:String}(filenames::Vector{S},
    arrtype::Type{Matrix}, data::Vector, recs::Vector, ftimes::Vector,
    rtimes::Vector; kwargs...)
    # first data entry will be put into corrupt file and inaccesible
    clipped_data = data[:, 2:end]
    clipped_recs = recs[2:end]
    clipped_ftimes = ftimes[2:end]
    clipped_rtimes = rtimes[2:end]
    test_load_contfiles(filenames, arrtype, clipped_data, clipped_recs,
                        clipped_ftimes, clipped_rtimes)
end

function test_load_contfiles{S<:String, U<:UninitializedArray}(filenames::Vector{S},
    arrtype::U, data::Array, recs::Vector, ftimes::Vector,
    rtimes::Vector; kwargs...)
    elts = (Float64, Int)
    for elt in elts
        dtype = arrtype{elt} # Make dtype,
        test_load_contfiles(filenames, dtype, data, recs, ftimes, rtimes; kwargs...)
    end
end
function test_load_contfiles{S<:String, T<:Array}(filenames::Vector{S},
    dtype::Type{T}, data::Vector, recs::Vector, ftimes::Vector,
    rtimes::Vector; kwargs...)
    data_out, time_out, recno_out, header_out =
        OpenEphys.load_contfiles(filenames, dtype; kwargs...)
    verify_load_contfiles_output(data_out, time_out, recno_out, header_out, data, recs,
                        ftimes, rtimes)
end
function test_load_contfiles{S<:String, T<:Array}(filenames::Vector{S},
    dtype::Type{T}, data::Matrix, recs::Vector, ftimes::Vector,
    rtimes::Vector; kwargs...)
    @test_throws ErrorException OpenEphys.load_contfiles(filenames, dtype; kwargs...)
end

function verify_load_contfiles_output{T<:Matrix, H<:OriginalHeader}(data_out::T,
    time_out::T, recno_out::Matrix{Int}, header_out::Vector{H},
    data::Vector, recs::Vector, ftimes::Vector, rtimes::Vector)
    for idx in eachindex(data)
        verify_header(header_out[idx])
        verify_continuous_contents(data[idx], ftimes[idx], rtimes[idx], recs[idx],
        data_out[:, idx], time_out[:, idx], recno_out[:, idx])
    end
end
function verify_load_contfiles_output{T<:Vector, H<:OriginalHeader}(data_out::T,
    time_out::Vector{Vector{Int}}, recno_out::Vector{Vector{Int}},
    header_out::Vector{H}, data::Vector, recs::Vector,
    ftimes::Vector, rtimes::Vector)
    for idx in eachindex(data)
        verify_header(header_out[idx])
        verify_continuous_contents(data[idx], ftimes[idx], rtimes[idx], recs[idx],
        data_out[idx], time_out[idx], recno_out[idx])
    end
end

function test_loadcontinuous(path::String, data::AbstractArray, rec::Integer,
                            ftime::Integer, rtime::Integer)
    nblocks = fld(length(data), OpenEphys.CONT_REC_N_SAMP)
    prealloc_times = Vector{Int}(nblocks)
    prealloc_recs = Vector{Int}(nblocks)
    blockbuff = ContBlockBuff()
    for dt in (Int, Float64)
        data_out, t_out, rec_out, fhead =  OpenEphys._loadcontinuous(path, nblocks, dt)
        verify_continuous_contents(data, ftime, rtime, rec, data_out, t_out, rec_out)
        verify_header(fhead)
        contdata = loadcontinuous(path, Int)
        verify_contdata(contdata, data, rec, ftime, rtime)
        prealloc_data = Vector{dt}(length(data))
        fhead, nblocksread = _loadcontinuous!{D}(path,  nblocks, dt,
                        prealloc_data, prealloc_times, prealloc_recs, blockbuff)
        @test nblocksread == nblocks
        verify_header(fhead)
    end
end

function test_read_contbody(io::IOStream, path::String, data::Vector,
     dtype::DataType, ftime::Integer, rtime::Integer, rec::Integer)
    skip(io, OpenEphys.HEADER_N_BYTES)
    nblocks = OpenEphys.inspect_contfile(path)
    data_out, t_out, rec_out = OpenEphys.read_contbody(io, nblocks, dtype)
    verify_continuous_contents(data, ftime, rtime, rec, data_out, t_out, rec_out)
end

function verify_ContBlockHeader(blockhead::OpenEphys.ContBlockHeader, t::Integer, rec::Integer)
    @test blockhead.timestamp == t
    @test blockhead.nsample == OpenEphys.CONT_REC_N_SAMP
    @test blockhead.recordingnumber == rec
end

function verify_contdata(contdata::ContinuousData, data::Vector,
    rec::Integer, ftime::Integer, rtime::Integer)
    data_out =  contdata.data
    t_out = contdata.timestamps
    rec_out = contdata.recordingnumbers
    fhead = contdata.fileheaders
    verify_continuous_contents(data, ftime, rtime, rec, data_out, t_out, rec_out)
    verify_header(fhead)
end

function verify_continuous_contents(data::Vector, ftime::Integer,
                                rtime::Integer, rec::Integer,
                                data_out::Vector, t_out::Vector{Int},
                                rec_out::Vector{Int})
    nstartzeros = Int(rtime - ftime)
    verify_continuous_contents_data(data, data_out, nstartzeros)
    ngoodblocks = length(t_out)
    @test t_out == ftime + Int[OpenEphys.CONT_REC_N_SAMP * x for x in 0:(ngoodblocks - 1)]
    @test rec_out == fill(rec, ngoodblocks)
end
function verify_continuous_contents_data{T}(data::Vector,
                                        data_out::Vector{T}, nstartzeros::Integer)
    ndata = length(data)
    lastdata_idx = nstartzeros + ndata
    @test data_out[nstartzeros + (1:ndata)] == cont_data_conversion(T, data)
    @test data_out[1:nstartzeros] == zeros(T, nstartzeros)
    if lastdata_idx < ndata
        n_data_out = length(data_out)
        @test data_out[(lastdata_idx + 1):end] == zeros(T, n_data_out - lastdata_idx)
    end
end
cont_data_conversion{T<:Integer}(::Type{T}, data::Vector) =
    Vector{T}(copy(data))
cont_data_conversion{T<:FloatingPoint}(::Type{T}, data::Vector) =
    0.195 * Vector{T}(copy(data))

bad_file(io::IOStream) = write(io, "These aren't the droids you're looking for")
function damaged_file(io::IOStream, args...; kwargs...)
    write_continuous(io, args...; kwargs...)
    bad_blockhead(io)
end
good_block(io::IOStream, d::AbstractArray, t::Integer, r::Integer) = writeblock(io, d, t, r)
function bad_blockhead(io::IOStream)
    blockdata = rand(OpenEphys.CONT_REC_SAMP_BITTYPE, OpenEphys.CONT_REC_N_SAMP)
    writeblock(io, blockdata; bad_blockhead = true)
end
function bad_blocktail(io::IOStream)
    blockdata = rand(OpenEphys.CONT_REC_SAMP_BITTYPE, OpenEphys.CONT_REC_N_SAMP)
    writeblock(io, blockdata; bad_blocktail = true)
end

function continuous_dir(dirpath::String, d::AbstractArray, recno::Vector, ftime::Vector, rtime::Vector)
    nfile = length(d)
    filenames = Vector{ASCIIString}(nfile)
    for fileno = 1:nfile
        filenames[fileno] = joinpath(dirpath, random_continuous_name(fileno))
        open(filenames[fileno], "w") do io
            write_continuous(io, d[fileno], recno[fileno], ftime[fileno], rtime[fileno])
        end
    end
    return filenames
end

function damaged_dir(dirpath::String, d::AbstractArray, recno::Vector, ftime::Vector, rtime::Vector)
    filenames = continuous_dir(dirpath, d, recno, ftime, rtime)
    badpath = joinpath(dirpath, random_continuous_name(length(filenames) + 1))
    open(badpath, "w") do io
        bad_file(io)
    end
    return vcat(filenames; badpath)
end

function corrupt_dir(dirpath::String, d::AbstractArray, recno::Vector, ftime::Vector, rtime::Vector)
    filenames = continuous_dir(dirpath, d[2:end], recno[2:end], ftime[2:end], rtime[2:end])
    corruptpath = joinpath(dirpath, random_continuous_name(length(filenames)))
    open(tmppath, "w") do io
        damaged_file(io, d[1], recno[1], ftime[1], rtime[1])
    end
    return vcat(filenames; badpath)
end

function random_continuous_name(chno::Int)
    return "$(randstring())_$(rand(["CH", "AUX"]))$chno.continuous"
end
random_continuous_name() = random_continuous_name(rand(1:256))

function write_continuous{T<:Integer}(io::IOStream, d::AbstractArray{T, 1},
                            recno::Integer = 0, ftime::Integer = 1, rtime::Integer = 1)
    l = length(d)
    t = ftime
    nstartpad = Int(rtime - ftime)
    nstartpad < OpenEphys.CONT_REC_N_SAMP || error("Delay between file start and recording is too long")
    nstoppad = mod(-(l + nstartpad), OpenEphys.CONT_REC_N_SAMP)
    nblock = cld(l + nstartpad, OpenEphys.CONT_REC_N_SAMP) # ceiling divide
    if nstoppad > 0 || nstartpad > 0
        padded = zeros(Int, OpenEphys.CONT_REC_N_SAMP * nblock)
        padded[(1 + nstartpad):(end - nstoppad)] = d
    else
        padded = d # no padding needed, renaming for clarity below
    end
    write_original_header(io)
    tblock = ftime
    offset = 0
    for blockno in 1:nblock
        writeblock(io, sub(padded, offset + (1:OpenEphys.CONT_REC_N_SAMP)), tblock, recno)
        tblock += OpenEphys.CONT_REC_N_SAMP
        offset += OpenEphys.CONT_REC_N_SAMP
    end
end
function write_continuous(path::String, d::AbstractArray{Int, 1},
                    recno::Integer = 0, ftime::Integer = 1, rtime::Integer = 1)
    open(path, "w") do io
        write_continuous(io, d, recno, ftime, rtime; bad_blockhead = bad_blockhead,
        bad_blocktail = bad_blocktail)
    end
end

function writeblock(io::IOStream, d::AbstractArray, t::Integer = 1, recno::Integer = 0;
     bad_blockhead::Bool = false, bad_blocktail::Bool = false)
     tmp_data = similar(d, OpenEphys.CONT_REC_SAMP_BITTYPE)
     copy!(tmp_data, d)
     for idx in eachindex(tmp_data)
         @inbounds tmp_data[idx] = hton(tmp_data[idx])
     end
     write(io, OpenEphys.CONT_REC_TIME_BITTYPE(t))
     if bad_blockhead
         write(io, zero(OpenEphys.CONT_REC_N_SAMP_BITTYPE))
     else
         write(io, OpenEphys.CONT_REC_N_SAMP_BITTYPE(OpenEphys.CONT_REC_N_SAMP))
     end
     write(io, OpenEphys.CONT_REC_REC_NO_BITTYPE(recno))
     write(io, tmp_data)
     if bad_blocktail
         write(io, b"razzmatazz")
     else
         write(io, OpenEphys.CONT_REC_END_MARKER)
     end
end
