using Compat, OpenEphysLoader
using Main.TestUtilities, Main.TestContinuous

@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

@testset "Continuous" begin
    ### Tests ###
    samps_per_block = OpenEphysLoader.CONT_REC_N_SAMP
    cont_rec_block_size = OpenEphysLoader.CONT_REC_BLOCK_SIZE
    # sampno_to_block
    @test OpenEphysLoader.sampno_to_block(1) == 1
    @test OpenEphysLoader.sampno_to_block(samps_per_block) == 1
    @test OpenEphysLoader.sampno_to_block(samps_per_block + 1) == 2
    @test OpenEphysLoader.sampno_to_block(0) == 0

    # sampno_to_offset
    @test OpenEphysLoader.sampno_to_offset(1) == 1
    @test OpenEphysLoader.sampno_to_offset(2) == 2
    @test OpenEphysLoader.sampno_to_offset(samps_per_block) ==
        samps_per_block
    @test OpenEphysLoader.sampno_to_offset(samps_per_block + 1) == 1

    # block_start_pos
    @test OpenEphysLoader.block_start_pos(1) == 1024
    @test OpenEphysLoader.block_start_pos(2) == 3094

    # pos_to_blockno
    @test_throws ArgumentError OpenEphysLoader.pos_to_blockno(-1)
    @test OpenEphysLoader.pos_to_blockno(0) == 0
    @test OpenEphysLoader.pos_to_blockno(1023) == 0
    @test OpenEphysLoader.pos_to_blockno(1024) == 1
    @test OpenEphysLoader.pos_to_blockno(1025) == 1
    @test OpenEphysLoader.pos_to_blockno(1024 + cont_rec_block_size) == 2

    # blockno_to_start_sampno
    @test OpenEphysLoader.blockno_to_start_sampno(1) == 1
    @test OpenEphysLoader.blockno_to_start_sampno(2) == 1025


    # verify_tail!
    badtail = b"razzmatazz"
    tailarr = Vector{UInt8}(undef, 10)
    filecontext(writeio -> write(writeio, badtail)) do io
        @test OpenEphysLoader.verify_tail!(io, tailarr) == false
    end
    write_block_end = io -> write(io,
                                  OpenEphysLoader.CONT_REC_END_MARKER)
    filecontext(write_block_end) do io
        @test OpenEphysLoader.verify_tail!(io, tailarr) == true
    end

    testblockhead = OpenEphysLoader.BlockHeader()
    testblock = OpenEphysLoader.DataBlock()
    # Data conversion
    blockdata = rand_block_data()
    @compat copyto!(testblock.body, to_OE_bytes(blockdata))
    OpenEphysLoader.convert_block!(testblock)
    @test testblock.data == blockdata

    # Test continuous interfaces
    # Test sample iterator
    nblock = 2
    testdata = vcat([rand_block_data() for i = 1:nblock]...)
    recno = OpenEphysLoader.CONT_REC_REC_NO_BITTYPE(0)
    startsamp = OpenEphysLoader.CONT_REC_TIME_BITTYPE(1)
    filecontext(write_continuous, testdata, recno, startsamp) do io
        # counting utilities
        @test OpenEphysLoader.count_data(io) == length(testdata)

        @test OpenEphysLoader.count_blocks(io) == nblock

        @test OpenEphysLoader.check_filesize(io)

        # File seeking
        OpenEphysLoader.seek_to_block(io, 2)
        @test position(io) == 3094
        OpenEphysLoader.seek_to_block(io, 1)
        @test position(io) == 1024

        # Block header reading
        @test OpenEphysLoader.read_into!(io, testblockhead)
        verify_BlockBuffer(testblockhead, startsamp, recno)

        # Block buffering
        OpenEphysLoader.seek_to_block(io, 1)
        @test OpenEphysLoader.read_into!(io, testblock, true)
        block_data, block_body, block_startsamp =
            to_block_contents(testdata, 1, startsamp)
        verify_BlockBuffer(
            testblock,
            block_startsamp,
            recno,
            block_body,
            block_data
        )

        # Test array types
        sampletypes = [Int,
                       OpenEphysLoader.CONT_REC_SAMP_BITTYPE,
                       Float64]
        test_OEContArray(io,
                         SampleArray,
                         sampletypes,
                         testdata,
                         nblock,
                         recno,
                         startsamp)
        test_OEContArray(io,
                         TimeArray,
                         sampletypes,
                         testdata,
                         nblock,
                         recno,
                         startsamp)
        recnotypes = [Int]
        test_OEContArray(io,
                         RecNoArray,
                         recnotypes,
                         testdata,
                         nblock,
                         recno,
                         startsamp)
        jointtypes = [Tuple{Float64, Float64, Int}, Tuple{Int, Int, Int}]
        test_OEContArray(io,
                         JointArray,
                         jointtypes,
                         testdata,
                         nblock,
                         recno,
                         startsamp)
    end

    # Totally destroyed file
    OEContArrayTypes = [SampleArray, TimeArray, RecNoArray, JointArray]
    filecontext(bad_file) do io
        # check_filesize
        @test ! OpenEphysLoader.check_filesize(io)

        # read_into!
        @test ! OpenEphysLoader.read_into!(io, testblockhead)
        seekstart(io)
        @test ! OpenEphysLoader.read_into!(io, testblock, true)

        # ContinuousFile constructor
        seekstart(io)
        @test_throws CorruptedException ContinuousFile(io)

        # Array constructors
        for t in OEContArrayTypes
            seekstart(io)
            @test_throws CorruptedException t(io)
        end
    end

    # Test reading from blocks
    filecontext(bad_blockhead) do io
        @test ! OpenEphysLoader.read_into!(io, testblockhead)
        seekstart(io)
        @test ! OpenEphysLoader.read_into!(io, testblock, true)
    end

    filecontext(bad_blocktail) do io
        @test OpenEphysLoader.read_into!(io, testblockhead)
        seekstart(io)
        @test ! OpenEphysLoader.read_into!(io, testblock, true)
        seekstart(io)
        @test OpenEphysLoader.read_into!(io, testblock, false)
    end

    filecontext(damaged_file, testdata, recno, startsamp) do io
        for t in OEContArrayTypes
            seekstart(io)
            A = t(io)
            @test_throws(CorruptedException,
                         OpenEphysLoader.prepare_block!(A, 3073))
            @test_throws CorruptedException A[end]
        end
    end
end
