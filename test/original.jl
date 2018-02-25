module TestOriginal
using OpenEphysLoader, Main.TestUtilities, Base.Test

export write_fheader_fun,
    verify_header

### Helper functions ###
function write_bad_fheader(badtype::Symbol, nbytes::Integer = 1024)
    local outfun
    if badtype == :version
        outfun = write_fheader_fun(nbytes, "header_wrongversion.txt")
    elseif badtype == :format
        outfun = write_fheader_fun(nbytes, "header_wrongformat.txt")
    elseif badtype == :noise
        baddata = rand(UInt8, nbytes)
        outfun = io::IOStream -> write(io, baddata)
    else
        error("badtype unrecognized")
    end
    return outfun
end

function write_fheader_fun(
    nbytes::Integer = 1024,
    headerfile::String = "header.txt"
)
    local head
    headerpath = joinpath(dirname(@__FILE__), "data", headerfile)
    @assert isfile(headerpath) "Could not load header file"
    open(headerpath, "r") do readio
        @assert stat(readio).size >= nbytes "Header not long enough"
        head = readstring(readio)
    end
    trunchead = head[1:nbytes]
    return io::IOStream -> write(io, trunchead)
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
    @test isapprox(header.bitvolts, 0.195)
end

### Tests ###
@testset "OriginalHeader" begin
    # OriginalHeader constructor
    filecontext(write_fheader_fun()) do io
        header = OriginalHeader(io)
        verify_header(header)
        @test (show(DevNull, header); true) # test that it does not error
        @test (showcompact(DevNull, header); true)
    end

    @test (showerror(DevNull, CorruptedException("test")); true)

    # truncated header
    filecontext(write_fheader_fun(512)) do io
        @test_throws CorruptedException OriginalHeader(io)
    end

    # Header with bad content
    filecontext(write_bad_fheader(:noise)) do io
        @test_throws CorruptedException OriginalHeader(io)
    end

    filecontext(write_bad_fheader(:version)) do io
        @test_throws CorruptedException OriginalHeader(io)
    end

    filecontext(write_bad_fheader(:format)) do io
        @test_throws CorruptedException OriginalHeader(io)
    end
end

end
