module TestMetadata
using OpenEphysLoader, TestUtilities, Base.Test

test_dir = joinpath(dirname(@__FILE__), "data")

@testset "Metadata" begin
    info_ans = (
        v"0.3.5",
        v"0",
        DateTime(2015, 7, 21, 14, 50, 12),
        "Windows 7",
        "RIGDESK"
    )
    plugin_info_ans = (
        v"0.4.1",
        v"3",
        DateTime(2016, 10, 21, 14, 19, 52),
        "Windows 8",
        "GLWORKSTATION"
    )

    rhythm_ans = (
        100,
        1,
        7500,
        false,
        false,
        true,
        false,
        true,
        true,
        0
    )
    const BITVOLTS = 0.19499999284744263
    channel_1_ans = (
        "CH1",
        0,
        BITVOLTS,
        1024,
        "100_CH1.continuous"
    )
    channel_2_ans = (
        "CH2",
        0,
        BITVOLTS,
        1024,
        "100_CH2.continuous"
    )

    expermeta_ans = (
        v"0.4.0",
        1,
        false
    )

    recording_ans = (
        0,
        30000
    )

    expermeta = dir_settings(test_dir)
    settings = expermeta.settings
    test_fields(settings, (info_ans), recording_chain = false)
    @test ! isempty(settings.recording_chain.nodes)
    rhythmnode = settings.recording_chain.nodes[1].content
    test_fields(rhythmnode, rhythm_ans, channels = false)
    test_fields(rhythmnode.channels[1], channel_1_ans)
    test_fields(rhythmnode.channels[2], channel_2_ans)
    @test expermeta.recordings[1].recording_processors[1] == rhythmnode
    test_fields(expermeta, expermeta_ans, recordings = false, settings = false)
    @test ! isempty(expermeta.recordings)
    test_fields(expermeta.recordings[1], recording_ans, recording_processors = false)
end

end # module TestMetaData
