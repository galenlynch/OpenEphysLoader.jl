# code for the .continuous original files

### Constants ###

const CONT_REC_TIME_BITTYPE = Int64
const CONT_REC_N_SAMP = 1024
const CONT_REC_N_SAMP_BITTYPE = UInt16
const CONT_REC_REC_NO_BITTYPE = UInt16
const CONT_REC_SAMP_BITTYPE = Int16
const CONT_REC_END_MARKER = UInt8[0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
                                  0x07, 0x08, 0xff]
const CONT_REC_HEAD_SIZE = mapreduce(sizeof, +, [CONT_REC_TIME_BITTYPE,
                             CONT_REC_N_SAMP_BITTYPE, CONT_REC_REC_NO_BITTYPE])
const CONT_REC_BODY_SIZE = CONT_REC_N_SAMP * sizeof(CONT_REC_SAMP_BITTYPE)
const CONT_REC_TAIL_SIZE = sizeof(CONT_REC_END_MARKER)
const CONT_REC_SIZE = CONT_REC_HEAD_SIZE + CONT_REC_BODY_SIZE + CONT_REC_TAIL_SIZE

### Types ###
if VERSION < v"0.4-"
    typealias HeaderOut Union(OriginalHeader, Array)
    typealias IntOut Union(Array{Int}, Vector{Vector{Int}})
else
    typealias HeaderOut Union{OriginalHeader, Array}
    typealias IntOut Union{Array{Int},  Vector{Vector{Int}}}
end
typealias ConcreteHeader OriginalHeader{UTF8String, Int, Float64}

immutable ContinuousData{A<:Array, B<:IntOut, H<:HeaderOut} <: OriginalData
    data::A
    timestamps::B
    recordingnumbers::B
    fileheaders::H
end

type ContBlockHeader
    timestamp::CONT_REC_TIME_BITTYPE
    nsample::CONT_REC_N_SAMP_BITTYPE
    recordingnumber::CONT_REC_REC_NO_BITTYPE
end
ContBlockHeader() = ContBlockHeader(0, 0, 0)
function ==(a::ContBlockHeader, b::ContBlockHeader)
    equality = true
    for fld in fieldnames(ContBlockHeader)
        equality = equality && a.(fld) == b.(fld)
    end
    return equality
end

type ContBlockBuff
    blockhead::ContBlockHeader
    bodybuffer::Vector{UInt8}
    blocktail::Vector{UInt8}
end
function ContBlockBuff()
    blockhead = ContBlockHeader()
    bodybuffer = @compat Vector{UInt8}(CONT_REC_BODY_SIZE)
    blocktail = @compat Vector{UInt8}(CONT_REC_TAIL_SIZE)
    ContBlockBuff(blockhead, bodybuffer, blocktail)
end
function ==(a::ContBlockBuff, b::ContBlockBuff)
    equality = true
    for fld in fieldnames(ContBlockBuff)
        equality = equality && a.(fld) == b.(fld) # Recurse on fields
    end
    return equality
end

### exposed functions ###
function loadcontinuous{D}(filepath::String, ::Type{D} = Float64; checktail::Bool = false)
    nblocks = inspect_contfile(filepath)
    nblocks > 0 || throw(UnreadableError("$filepath is unreadable or improperly formatted"))
    data, timestamps, recordingnumbers, fileheader =
        _loadcontinuous(filepath, nblocks, D; checktail = checktail)
    return ContinuousData(data, timestamps, recordingnumbers, fileheader)
end

## Load .continuous files in a directory: may need to be renamed
function loaddirectory{D}(directorypath::String, ::Type{D} = Float64;
         checktail::Bool = false, sortfiles::Bool = true, verbose::Bool = false)
    # Find continuous files
    filenames = readdir(directorypath)
    filenames = filter(matchcontinuous, filenames)
    if sortfiles
        filenames = sort_continuousfiles(filenames)
    end
    # Load continuous files
    data, timestamps, recordingnumbers, fileheaders =
        load_contfiles(filenames, D; checktail = checktail, verbose = verbose)
    return ContinuousData(data, timestamps, recordingnumbers, fileheaders)
end
loaddirectory{D}(::Type{D} = Float64; checktail::Bool = false,
    sortfiles::Bool = true, verbose::Bool = false) = loaddirectory(".", D;
        checktail = checktail, sortfiles = sortfiles, verbose = verbose)
matchcontinuous(str::String) = ismatch(r"\.continuous$", str)

function interpolate_timestamps{D}(timestamps::Vector{Int},
     fileheader::OriginalHeader, ::Type{D} = Float64)
     nblock = fileheader.blocklength
     nstamps = length(timestamps)
     timepoints = @compat Vector{D}(nstamps * nblock)
     for stampno = 1:nstamps
         timepoints[(stampno - 1) * nblock + (1:nblock)] =
            timestamps[stampno] - 1 + (1:nblock)
     end
     @assert fileheader.samplerate > 0
     convert_timepoints!(D, timepoints, fileheader)
end
function interpolate_timestamps{H<:OriginalHeader, T<:Vector{Int}, D}(
            timestamps::Array{T}, head::Array{H}, ::Type{D} = Float64)
    nseries = length(timestamps)
    timepoints = @compat Vector{Vector{D}}(nseries)
    for seriesno = 1:nseries
        timepoints[seriesno] = interpolate_timestamps(timestamps[seriesno], head[seriesno], D)
    end
    return timepoints
end
function interpolate_timestamps{H<:OriginalHeader, T<:Matrix{Int}, D}(
                    timestamps::T, head::Array{H}, ::Type{D})
    if size(timestamps, 2) > 1
        allcolsame = all(timestamps[:,1] .== timestamps)
        allcolsame || error("Matrix timestamps with differing columns not yet implemented")
    end
    interpolate_timestamps(timestamps[:,1], head[1], D)
end
interpolate_timestamps{D}(d::ContinuousData, ::Type{D} = Float64) =
    interpolate_timestamps(d.timestamps, d.fileheaders, D)

### Functions for loading from a directory ###

function sort_continuousfiles{T<:ByteString}(filenames::Vector{T})
    nfiles = length(filenames)
    channeltype = @compat Vector{UTF8String}(nfiles)
    channelno = @compat Vector{Int}(nfiles)
    for fno in 1:nfiles
        channeltype[fno], channelno[fno] = getcont_typeno(filenames[fno])
    end
    channelno[channeltype .== "AUX"] += 1000 # Make sure aux channels are sorted last
    sortidx = sortperm(channelno)
    return filenames[sortidx]
end
function getcont_typeno(str::String)
    m = match(r"_(CH|AUX)(\d+)\.", str)
    return m.captures[1]::String, parse(m.captures[2])::Int
end

# Version for producing a vector of vectors
function load_contfiles{T<:Vector, S<:ByteString}(files::Vector{S}, ::Type{T};
    checktail::Bool = false, verbose::Bool = false)
    # Pre-allocation
    nfiles = length(files)
    data_vec = @compat Vector{T}(nfiles)
    time_vec = @compat Vector{Vector{Int}}(nfiles)
    recno_vec = @compat Vector{Vector{Int}}(nfiles)
    header_vec = @compat Vector{ConcreteHeader}(nfiles)
    # Load each file
    badfiles = Int[] # Empty vector
    for fno in 1:nfiles
        nblocks = inspect_contfile(files[fno])
        if nblocks > 0
            verbose && println("Loading $(files[fno])")
            data_vec[fno], time_vec[fno], recno_vec[fno], header_vec[fno] =
                _loadcontinuous(files[fno], nblocks, eltype(T); checktail = checktail)
        else
            warn("$fno cannot be accessed or is improperly formatted, skipping...")
            push!(badfiles, fno)
        end
    end
    # Clean up
    if !isempty(badfiles)
        deleteat!(data_vec, badfiles)
        deleteat!(time_vec, badfiles)
        deleteat!(recno_vec, badfiles)
        deleteat!(header_vec, badfiles)
    end
    return data_vec, time_vec, recno_vec, header_vec
end
load_contfiles{T<:Real, S<:ByteString}(files::Vector{S}, ::Type{T};
    checktail::Bool = false, verbose::Bool = false) =
        load_contfiles(files, Vector{T}; checktail = checktail, verbose = verbose)

# Version for producing matrix of data
function load_contfiles{T<:Matrix, S<:ByteString}(files::Vector{S}, ::Type{T};
    checktail::Bool = false, verbose::Bool = false) # Can throw UnreadableError
    ## Check for bad files and ensure that making a matrix is possible
    nfiles = length(files)
    nblocks = @compat Vector{Int}(nfiles)
    badfiles = Int[] # Empty vector
    for fno in 1:nfiles
        nblocks[fno] = inspect_contfile(files[fno])
        if nblocks[fno] < 0
            warn("$(files[fno]) is unreadable or improperly formatted, skipping...")
            push!(badfiles, fno)
        end
    end
    if !isempty(badfiles) # clean up
        nfiles -= length(badfiles)
        deleteat!(nblocks, badfiles)
        badfiles = Int[]
    end
    all(nblocks[1] .== nblocks) || error("Files must have the same amount of data to make an array")
    dir_nblocks = nblocks[1] # size of all files in this directory
    data_mat, time_mat, recno_mat, header_vec =
                allocate_contfile_output(dir_nblocks, nfiles, T)
    blockbuff = ContBlockBuff()
    for fno in 1:nfiles
        verbose && println("Loading $(files[fno])")
        dataview = sub(data_mat, :, fno)
        timeview = sub(time_mat, :, fno)
        recview = sub(recno_mat, :, fno)
        header_vec[fno], nblocksread =
            _loadcontinuous!(files[fno], dir_nblocks, eltype(T), dataview, timeview,
                recview, blockbuff; checktail = checktail)
        if nblocksread < dir_nblocks
            warn("$(files[fno]) is corrupt, and cannot be recovered with matrix output.
                Use vector output to recover partial data.")
            push!(badfiles, fno)
        end
    end
    if !isempty(badfiles) # Clean up if necessary
        # Allocate smaller containers for the data
        ngoodfiles = nfiles - length(badfiles)
        new_data_mat, new_time_mat, new_recno_mat, new_header_vec =
                    allocate_contfile_output(dir_nblocks, ngoodfiles, T)
        # Move good data to the new containers
        goodidx = setdiff(1:nfiles, badfiles)
        for (newidx, goodidx) in enumerate(goodidx)
            new_data_mat[:, newidx] = data_mat[:, goodidx]
            new_time_mat[:, newidx] = time_mat[:, goodidx]
            new_recno_mat[:, newidx] = recno_mat[:, goodidx]
            new_header_vec[newidx] = header_vec[goodidx]
        end
        # Replace the output containers (containing partial data) with good data
        data_mat = new_data_mat
        time_mat = new_time_mat
        recno_mat = new_recno_mat
        header_vec = new_header_vec
    end
    return data_mat, time_mat, recno_mat, header_vec
end
function allocate_contfile_output{T<:Matrix}(nblocks::Integer, nfiles::Integer, ::Type{T})
    nsamples = nblocks * CONT_REC_N_SAMP
    data_mat = @compat T(nsamples, nfiles)
    time_mat = @compat Array{Int, 2}(nblocks, nfiles)
    recno_mat = @compat Array{Int, 2}(nblocks, nfiles)
    header_vec = @compat Vector{ConcreteHeader}(nfiles)
    return data_mat, time_mat, recno_mat, header_vec
end

function _loadcontinuous{D}(filepath::String, nblocks::Int, ::Type{D} = Float64;
    checktail::Bool = false)
    # Data vectors
    data = @compat Vector{D}(nblocks * CONT_REC_N_SAMP) # Number of samples
    timestamps = @compat Vector{Int}(nblocks)
    recordingnumbers = @compat Vector{Int}(nblocks)
    blockbuff  = ContBlockBuff()
    fileheader, nblocksread = _loadcontinuous!(filepath, nblocks, D, data,
                timestamps, recordingnumbers, blockbuff; checktail = checktail)
    if nblocksread < nblocks
        warn("Record $(nblocksread + 1) in $filepath is corrupt, returning partial data")
        resize!(data, nblocksread * CONT_REC_N_SAMP)
        resize!(timestamps, nblocksread)
        resize!(recordingnumbers, nblocksread)
    end
    return data, timestamps, recordingnumbers, fileheader
end
# version of loadcontinuous for internal use: mutates existing data arrays
function _loadcontinuous!{D}(filepath::String,  nblocks::Int, ::Type{D},
    data::AbstractArray, timestamps::AbstractArray, recordingnumbers::AbstractArray,
    blockbuff::ContBlockBuff; checktail::Bool = false)
    io = open(filepath)
    local fileheader
    try # Ensure that file will be closed
        fileheader = OriginalHeader(io)
        nblocksread = read_contbody!(io, nblocks, data, timestamps, recordingnumbers,
                    blockbuff; checktail = checktail)
    finally
        close(io)
    end
    convertdata!(D, data, fileheader)
    return fileheader, nblocksread
end

### Read body of file ###
function read_contbody!(io::IOStream, nblocks::Integer,
                        data::AbstractArray, timestamps::AbstractArray,
                        recordingnumbers::AbstractArray, blockbuff::ContBlockBuff;
                         checktail::Bool = false)
    blockbuff  = ContBlockBuff()
    # Loop over data blocks and extract data
    local blockno::Int # Keep this variable if try block fails
    goodread = true
    for blockno in 1:nblocks
        goodread = read_contblock!(io, blockbuff; checktail = checktail)
        goodread || break
        parse_blockbuffer!(blockbuff, data, timestamps, recordingnumbers, blockno)
    end
    nblocksread = blockno
    if !goodread
        nblocksread -= 1
    end
    return nblocksread
end

function parse_blockbuffer!(blockbuff::ContBlockBuff, data::AbstractArray,
    timestamps::AbstractArray, recordingnumbers::AbstractArray, blockno::Integer)
    databuff = copy(blockbuff.bodybuffer)
    databuff = reinterpret(CONT_REC_SAMP_BITTYPE, databuff) # readbuff is UInt8
    # Correct for big endianness of this data block
    for idx in eachindex(databuff)
        @inbounds databuff[idx] = ntoh(databuff[idx])
    end
    offset = (blockno - 1) * CONT_REC_N_SAMP
    data[offset + (1:CONT_REC_N_SAMP)] = databuff # Place block data into output
    timestamps[blockno] = blockbuff.blockhead.timestamp
    recordingnumbers[blockno] = blockbuff.blockhead.recordingnumber
end

function read_contblock!(io::IOStream, blockbuff::ContBlockBuff; checktail::Bool = false)
    goodread = read_contblock_header!(io, blockbuff.blockhead)
    ## Read the body
    nbytes = readbytes!(io, blockbuff.bodybuffer, CONT_REC_BODY_SIZE) # Read block body into buffer
    if nbytes != CONT_REC_BODY_SIZE
        goodread = false
    end
    if checktail
        goodread = goodread && read_contblock_tail!(io, blockbuff.blocktail)
    else
        skip(io, CONT_REC_TAIL_SIZE)
    end
    return goodread
end

function read_contblock_header!(io::IOStream, blockhead::ContBlockHeader)
    goodread = true
    try
        blockhead.timestamp = read(io, CONT_REC_TIME_BITTYPE)
        blockhead.nsample = read(io, CONT_REC_N_SAMP_BITTYPE)
        if blockhead.nsample != CONT_REC_N_SAMP
            goodread = false
        end
        blockhead.recordingnumber = read(io, CONT_REC_REC_NO_BITTYPE)
    catch exception
        if isa(exception, EOFError)
            goodread = false
        else
            rethrow(exception)
        end
    end
    return goodread
end

function read_contblock_tail!(io::IOStream, blocktail::Vector{UInt8})
    goodread = true
    nbytes = readbytes!(io, blocktail, CONT_REC_TAIL_SIZE)
    if nbytes != CONT_REC_TAIL_SIZE || blocktail != CONT_REC_END_MARKER
        goodread = false
    end
    return goodread
end

### Utility functions ###

function convertdata!{D<:FloatingPoint}(::Type{D}, data::AbstractArray, fileheader::OriginalHeader)
    broadcast!(*, data, data, fileheader.bitvolts) # Multiply data by scalar in place
end
convertdata!{D<:Integer}(::Type{D}, data::AbstractArray, fileheader::OriginalHeader) = nothing

function convert_timepoints!{T<:FloatingPoint}(::Type{T}, timepoints::AbstractArray, fileheader::OriginalHeader)
    broadcast!(*, timepoints, timepoints, 1/fileheader.samplerate) # Multiply data by scalar in place
end
convert_timepoints!{T<:Integer}(::Type{T}, timepoints::AbstractArray, fileheader::OriginalHeader) = nothing

function inspect_contfile(filepath::String)
    nblocks = -1 # Indicates bad file
    if isfile(filepath) && isreadable(filepath)
        fsize = filesize(filepath)
        if rem(fsize - HEADER_N_BYTES, CONT_REC_SIZE) == 0
            nblocks = div((fsize - HEADER_N_BYTES), CONT_REC_SIZE)
        end
    end
    return nblocks::Int # Number of blocks
end

function show(io::IO, d::ContinuousData)
    for fld in (:data, :timestamps, :recordingnumbers)
        println(io, "$fld:")
        Base.showlimited(io, d.(fld))
        print(io, '\n')
    end
    println(io, "fileheaders:")
    Base.showlimited(io, d.fileheaders)
end
