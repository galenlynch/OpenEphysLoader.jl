module TestMetadata
using OpenEphysLoader, Main.TestUtilities, Base.Test

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
        100, # id
        1, # lowcut
        7500, # highcut
        false, # adcs_on
        false, # noiseslicer
        true, # ttl_fastsettle
        false, # dac_ttl
        true, # dac_hpf
        true, # dsp_offset
        0 # dsp_cutoff
    )
    const BITVOLTS = 0.19499999284744263
    channel_1_ans = (
        "CH1",
        0,
        BITVOLTS,
        [1024],
        "100_CH1.continuous"
    )
    channel_2_ans = (
        "CH2",
        1,
        BITVOLTS,
        [1024],
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

    # pre plugin settings
    expermeta = metadata(test_dir)
    settings = expermeta.settings
    test_fields(settings, (info_ans), recording_chain = false)
    @test ! isempty(settings.recording_chain.nodes)
    rhythmnode = settings.recording_chain.nodes[1].content
    test_fields(rhythmnode, rhythm_ans..., channels = false)
    test_fields(rhythmnode.channels[1], channel_1_ans...)
    test_fields(rhythmnode.channels[2], channel_2_ans...)
    @test expermeta.recordings[1].recording_processors[1] == rhythmnode
    test_fields(expermeta, expermeta_ans..., recordings = false, settings = false)
    @test ! isempty(expermeta.recordings)
    test_fields(expermeta.recordings[1], recording_ans..., recording_processors = false)
    @test (show(DevNull, settings.recording_chain); true) # Test that this does not error
    @test (show(DevNull, settings); true)
    @test (show(DevNull, expermeta.recordings[1]); true)
    @test (show(DevNull, expermeta); true)

    #plug in settings
    @test_throws CorruptedException metadata(
        test_dir,
        settingsfile = "plugin_settings.xml",
    )
    @test_throws ErrorException metadata(
        test_dir,
        settingsfile = randstring()
    )
    @test_throws ErrorException metadata(
        test_dir,
        continuousmeta = randstring()
    )

    plugexpermeta = metadata(
        test_dir,
        settingsfile = "plugin_settings.xml",
        continuousmeta = "plugin_Continuous_Data.openephys"
    )
    @test plugexpermeta.settings.info.plugin_api_version == v"3"
end

end # module TestMetaData
