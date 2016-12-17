const RHYTHM_PROC = "Sources/Rhythm FPGA"
immutable OEChannel{T<:AbstractString}
    name::T
    number::Int
    bitvolts::Float64
    position::Int
    filename::T
end

abstract OEProcessor{T<:OEChannel}
immutable OERhythmProcessor{T<:OEChannel} <: OEProcessor{T}
    id::Int
    channels::Vector{T}
    lowcut::Float64
    highcut::Float64
    adcs_on::Bool
    noiseslicer::Bool
    ttl_fastsettle::Bool
    dac_ttl::Bool
    dac_hpf::Bool
    dsp_offset::Bool
    dsp_cutoff::Float64
end
function OERhythmProcessor(proc_e::LightXML.XMLElement)
    id_attr = attribute(proc_e, "NodeId", required = true)
    id = parse(Int, id_attr)

    channels = channel_arr(proc_e)

    # Editor
    editor_e = find_element(proc_e, "EDITOR")
    isa(editor_e, Void) && error("Could not find EDITOR element")
    ## Get attribute strings
    lowcut_attr = attribute(editor_e, "LowCut", required=true)
    highcut_attr = attribute(editor_e, "HighCut", required=true)
    adcs_on_attr = attribute(editor_e, "ADCsOn", required=true)
    noiseslicer_attr = attribute(editor_e, "NoiseSlicer", required=true)
    ttl_fastsettle_attr = attribute(editor_e, "TTLFastSettle", required=true)
    dac_ttl_attr = attribute(editor_e, "DAC_TTL", required=true)
    dac_hpf_attr = attribute(editor_e, "DAC_HPF", required=true)
    dsp_offset_attr = attribute(editor_e, "DSPOffset", required=true)
    dsp_cutoff_attr = attribute(editor_e, "DSPCutoffFreq", required=true)
    ## parse attribute strings
    lowcut = parse(Float64, lowcut_attr)
    highcut = parse(Float64, highcut_attr)
    adcs_on = parse(Int, adcs_on_attr) == 1
    noiseslicer = parse(Int, noiseslicer_attr) == 1
    ttl_fastsettle = parse(Int, ttl_fastsettle_attr) == 1
    dac_ttl = parse(Int, dac_ttl_attr) == 1
    dac_hpf = parse(Int, dac_hpf_attr) == 1
    dsp_offset = parse(Int, dsp_offset_attr) == 1
    dsp_cutoff = parse(Float64, dsp_cutoff_attr)

    return OERhythmProcessor(
        id,
        channels,
        lowcut,
        highcut,
        adcs_on,
        noiseslicer,
        ttl_fastsettle,
        dac_ttl,
        dac_hpf,
        dsp_offset,
        dsp_cutoff
    )
end

abstract TreeNode
type SignalNode{T<:OEProcessor} <: TreeNode
    processor::T
    parent::Int
    children::Vector{Int}
end

abstract Tree
immutable OESignalTree{T<:SignalNode} <: Tree
    signalnodes::Array{T}
end
function OESignalTree(
    chain_e::LightXML.XMLElement;
    recording_names = Set([RHYTHM_PROC])
    )
    children = child_elements(chain_e)
    for ch_e in children # Break at first recording processor!
        if name(ch_e) == "PROCESSOR"
            procname = attribute(ch_e, "name", required = true)
            if procname in recording_names
                if procname == RHYTHM_PROC
                    proc = OERhtymProcessor(ch_e)
                    signode = SignalNode(proc, 0, Vector{Int}())
                    return OESignalTree([signode])
                break
            end
        end
    end
end

immutable OERecordingMeta{T<:OEProcessor}
    number::Int
    samplerate::Float64
    recording_processors::Vector{T}
end

immutable OEInfo{T<:AbstractString}
    version::VersionNumber
    plugin_api_version::VersionNumber
    datetime::DateTime
    os::T
    machine::T
end
function OEInfo(info_e::LightXML.XMLElement)
    contents = map(content, child_elements(info_e))
    gui_version = VersionNumber(contents[1])
    plugin_api = VersionNumber(contents[2])
    datetime = DateTime(contents[3])
    return OEInfo(gui_version,
                  plug_api,
                  datetime,
                  contents[4],
                  contents[5])
end

immutable OESettings{T<:OEInfo, U<:OESignalTree}
    info::T
    # only processors that lead to recording nodes
    recording_signalchain::U
end
function OESettings(xdoc::LightXML.XMLDocument)
    settings_e = root(xdoc)
    @assert name(settings_e) == "SETTINGS" "Not a settings xml"
    info_e = find_element(settings_e, "INFO")
    isa(info_e, Void) && error("Could not find INFO element")
    info = OEInfo(info_e)
    chain_e = find_element(settings_e, "SIGNALCHAIN")
    isa(chain_e, Void) && error("Could not find SIGNALCHAIN element")
    signaltree = OESignalTree(chain_e)
    return OESettings(info, signaltree)
end

immutable OEExperMeta{T<:OERecordingMeta}
    version::VersionNumber
    experimentNumber::Int
    separateFiles::Bool
    recordings::Vector{T}
    settings::OESettings
end

function dir_settings(dirpath::AbstractString = pwd();
                      settingsfile = "settings.xml",
                      continuousmeta = "Continuous_Data.openephys")
    settingspath = joinpath(dirpath, settingsfile)
    isfile(settingspath) || error("$settingspath does not exist")
    continuouspath = joinpath(dirpath, continuousmeta)
    isfile(continuouspath) ||
        error("$continuouspath does not exist")
    settingsdoc = parse_file(settingspath)
    continuousdoc = parse_file(continuouspath)

    return OEExperMeta
end

function parse_file(f::Function, args...)
    xdoc = parse_file(args...)
    try
        f(xdoc)
    finally
        free(xdoc)
    end
end

function channel_arr(proc_e::LightXML::XMLElement)
    # Assumes that channels are sorted!
    # Channels
    channel_vec = get_elements_by_tagname(proc_e, "CHANNEL")
    isempty(channel_vec) && error("Could not find CHANNEL elements")
    nchan = length(channel_vec)
    chan_rec = fill(false, nchan)
    chnos = Array{Int}(nchan)
    for i, chan_e in enumerate(channel_vec)
        sel_e = find_element(chan_e, "SELECTIONSTATE")
        isa(sel_e, Void) && error("Could not find SELECTIONSTATE element")
        record_attr = attribute(sel_e, "record", required=true)
        record = parse(Int, bitvolt_attr)
        record == 1 && chan_rec[i] = true
        if chan_rec[i]
            chno_attr = attribute(chan_e, "number", required=true)
            chno = parse(Int, chno_attr)
            chnos[i] = chno
        end
    end
    nrec = sum(chan_rec)

    # Channel info
    ch_info_e = find_element(proc_e, "CHANNEL_INFO")
    isa(ch_info_e, Void) && error("Could not find CHANNEL_INFO element")
    chinfo_children = collect(child_elements(ch_info_e))
    channels = Array{OEChannel}(nrec)
    recno = 1
    for i, chan_e in enumerate(chinfo_children)
        if chan_rec[i]
            info_chno_attr = attribute(chan_e, "number", required = true)
            info_chno = parse(Int, info_chno_attr)
            @assert info_chno == chnos[i] "Channels not in same order"
            chname = attribtue(chan_e, "name", required = true)
            bitvolt_attr = attribute(chan_e, "gain", required = true)
            bitvolts = parse(Float64, bitvolt_attr)
            channels[recno] =
                OEChannel{String}(chname, info_chno, bitvolts, 0, "")
            recno += 1
        end
    end

    return channels
end
