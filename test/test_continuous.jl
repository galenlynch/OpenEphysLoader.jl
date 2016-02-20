using OpenEphys, Base.Test, Compat

### Tests ###

## Test utility functions

# getcont_typeno
chtest = "25_CH10.continuous"
auxtest ="100_AUX3.continuous"
chtype, chno = OpenEphys.getcont_typeno(chtest)
@test chtype == "CH"
@test chno == 10
auxtype, auxno = OpenEphys.getcont_typeno(auxtest)
@test auxtype == "AUX"
@test auxno == 3

# sort_continuousfiles
unsortedfiles = ["25_CH10.continuous", "1_AUX1.continuous", "3_CH3.continuous"]
@test OpenEphys.sort_continuousfiles(unsortedfiles) ==
        ["3_CH3.continuous", "25_CH10.continuous", "1_AUX1.continuous"]

# inspect_contfile
nblocks = 20
block_data = rand(OpenEphys.CONT_REC_SAMP_BITTYPE, nblocks * OpenEphys.CONT_REC_N_SAMP)
@test OpenEphys.inspect_contfile(randstring()) == -1
pathcontext(bad_file) do path
    @test OpenEphys.inspect_contfile(path) == -1
end
pathcontext(write_continuous, block_data) do path
    @test OpenEphys.inspect_contfile(path) == nblocks
end

## Test reading from blocks

# Set up
t = rand(OpenEphys.CONT_REC_TIME_BITTYPE)
rec = rand(OpenEphys.CONT_REC_REC_NO_BITTYPE)
data = rand(OpenEphys.CONT_REC_SAMP_BITTYPE, OpenEphys.CONT_REC_N_SAMP)

# read_contblock_header!
blockhead = OpenEphys.ContBlockHeader()
filecontext(bad_blockhead) do io
    @test OpenEphys.read_contblock_header!(io, blockhead) == false
end
filecontext(good_block, data, t, rec) do io
    @test OpenEphys.read_contblock_header!(io, blockhead) == true
    verify_ContBlockHeader(blockhead, t, rec)
end

# read_contblock! and implicitly read_contblock_tail!
blockbuff = OpenEphys.ContBlockBuff()
filecontext(bad_blockhead) do io
    @test OpenEphys.read_contblock!(io, blockbuff) == false
end
filecontext(bad_blocktail) do io
    @test OpenEphys.read_contblock!(io, blockbuff; checktail = true) == false
    seekstart(io)
    @test OpenEphys.read_contblock!(io, blockbuff) == true # should skip over bad tail
end
filecontext(good_block, data, t, rec) do io
    @test OpenEphys.read_contblock!(io, blockbuff) == true
    seekstart(io)
    @test OpenEphys.read_contblock!(io, blockbuff; checktail = true) == true
    verify_ContBlockHeader(blockbuff.blockhead, t, rec)
    compressed_data = copy(data)
    for idx in eachindex(compressed_data)
        compressed_data[idx] = hton(compressed_data[idx])
    end
    split_data = reinterpret(UInt8, compressed_data)
    @test blockbuff.bodybuffer == split_data
    @test blockbuff.blocktail == OpenEphys.CONT_REC_END_MARKER
end

# parse_blockbuffer!
data_out = Array{Int}(2 * length(data))
time_out = zeros(Int, 2)
rec_out = zeros(Int, 2)
filecontext(good_block, data, t, rec) do io
    OpenEphys.read_contblock!(io, blockbuff)
    OpenEphys.parse_blockbuffer!(blockbuff, data_out, time_out, rec_out, 1)
    old_blockbuff = deepcopy(blockbuff)
    OpenEphys.parse_blockbuffer!(blockbuff, data_out, time_out, rec_out, 1)
    @test blockbuff == old_blockbuff
    ndata = length(data)
    @test data_out[1:ndata] == data
    @test time_out[1] == t
    @test rec_out[1] == rec
    data_out[1:ndata] = 0
    time_out[1] = 0
    rec_out[1] = 0
    OpenEphys.parse_blockbuffer!(blockbuff, data_out, time_out, rec_out, 2)
    @test data_out[1:ndata] == zeros(Int, ndata)
    @test time_out[1] == 0
    @test rec_out[1] == 0
    @test data_out[(ndata+ 1):end] == data
    @test time_out[2] == t
    @test rec_out[2] == rec
end

# read_contbody and read_contbody!
nblocks = 20
data = rand(OpenEphys.CONT_REC_SAMP_BITTYPE, nblocks * OpenEphys.CONT_REC_N_SAMP)
ftime = fld(rand(OpenEphys.CONT_REC_REC_NO_BITTYPE), 2)
rtime = ftime + rand(1:OpenEphys.CONT_REC_N_SAMP)
dtype = Int
contexts = (write_continuous, damaged_file)
for context in contexts
    pathiocontext(context, data, rec, ftime, rtime) do path, io
        test_read_contbody(io, path, data, dtype, ftime, rtime, rec)
    end
end

## Test reading from files

# loadcontinuous and _loadcontinuous
contexts = (write_continuous, damaged_file)
for context in contexts
    pathcontext(context, data, rec, ftime, rtime) do path
        test_loadcontinuous(path, data, rec, ftime, rtime)
    end
end

# load_contfiles
#Vector case
nfile = 5
nblock = rand(1:5, nfile)
data = @compat Vector{Vector{OpenEphys.CONT_REC_SAMP_BITTYPE}}(nfile)
recs = @compat Vector{Int}(nfile)
ftimes = @compat Vector{Int}(nfile)
rtimes = @compat Vector{Int}(nfile)
for fileno = 1:nfile
    data[fileno] = rand(OpenEphys.CONT_REC_SAMP_BITTYPE, nblock[fileno] * OpenEphys.CONT_REC_N_SAMP)
    recs[fileno] = rand(OpenEphys.CONT_REC_REC_NO_BITTYPE)
    ftimes[fileno] = fld(rand(OpenEphys.CONT_REC_TIME_BITTYPE), 2)
    rtimes[fileno] = ftimes[fileno] + rand(1:OpenEphys.CONT_REC_N_SAMP)
end
contexts = (continuous_dir, damaged_dir, corrupt_dir)
for context in contexts
    dircontext(context, data, recs, ftimes, rtimes) do dirpath, filelist
        test_load_contfiles(filelist, Vector, data, recs, ftimes, rtimes)
    end
end
#Matrix case
nblocks = 5
nsamp = nblocks * OpenEphys.CONT_REC_N_SAMP
data = @compat Vector{Vector{OpenEphys.CONT_REC_SAMP_BITTYPE}}(nfile)
recs = rand(OpenEphys.CONT_REC_REC_NO_BITTYPE) * ones(Int, nfile)
ftimes = fld(rand(OpenEphys.CONT_REC_TIME_BITTYPE), 2) * ones(Int, nfile)
rtimes = ftimes + rand(1:OpenEphys.CONT_REC_N_SAMP)
for fileno = 1:nfile
    data[fileno] = rand(OpenEphys.CONT_REC_SAMP_BITTYPE, nblock * OpenEphys.CONT_REC_N_SAMP)
end
contexts = (continuous_dir, damaged_dir)
for context in contexts
    dircontext(context, data, recs, ftimes, rtimes) do dirpath, filelist
        test_load_contfiles(filelist, Matrix, data, recs, ftimes, rtimes)
    end
end
dircontext(corrupt_dir, data, recs, ftimes, rtimes) do dirpath, filelist
    test_load_contfiles_corrupt(filelist, Matrix, data, recs, ftimes, rtimes)
end
