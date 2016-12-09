using OpenEphysLoader, Base.Test

### Helper functions ###
function write_original_header_fun(nbytes::Integer = 1024)
    local head
    open(joinpath(dirname(@__FILE__), "data", "header.txt")) do readio
        head = readstring(readio)
    end
    trunchead = head[1:nbytes]
    return io::IOStream -> write(io, trunchead)
end

function write_bad_header_fun(nbytes::Integer = 1024)
    baddata = rand(UInt8, nbytes)
    return io::IOStream -> write(io, baddata)
end

function verify_header(header::OriginalHeader)
    @test header.format == "Open Ephys Data Format"
    @test header.version == v"0.4"
    @test header.headerbytes == 1024
    @test header.description == "each record contains one 64-bit timestamp, one 16-bit sample count (N), 1 uint16 recordingNumber, N 16-bit samples, and one 10-byte record marker (0 1 2 3 4 5 6 7 8 255)"
    @test header.created == DateTime("21-Jul-2015 145012", Dates.DateFormat("d-u-y HHMMSS"))
    @test header.channel == "CH30"
    @test header.channeltype == "Continuous"
    @test header.samplerate == 30000
    @test header.blocklength == 1024
    @test header.buffersize == 1024
    @test_approx_eq header.bitvolts 0.195
end

### Tests ###
# matread

# OriginalHeader constructor
filecontext(write_original_header_fun()) do io
    header = OriginalHeader(io)
    verify_header(header)
end

# truncated header
filecontext(write_original_header_fun(512)) do io
    @test_throws CorruptedException OriginalHeader(io)
end

# Header with bad content
filecontext(write_bad_header_fun()) do io
    @test_throws CorruptedException OriginalHeader(io)
end
