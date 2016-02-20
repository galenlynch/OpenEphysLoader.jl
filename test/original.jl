using OpenEphys, Base.Test
if VERSION < v"0.4-"
    using Dates
end

### Helper functions ###
function write_original_header(io::IOStream)
    local head
    open(joinpath(dirname(@__FILE__), "data", "header.txt")) do io
        head = readall(io)
    end
    write(io, head)
end
function write_original_header(path::String)
    open(path, "w") do io
        write_original_header(io)
    end
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

# OriginalHeader constructor
filecontext(write_original_header) do io
    header = OriginalHeader(io)
    verify_header(header)
end
