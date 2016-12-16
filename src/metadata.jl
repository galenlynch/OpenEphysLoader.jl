const RHYTHM_PROC = "Sources/Rhythm FPGA"
immutable OEChannel{T<:AbstractString}
    name::T
    number::Int
    bitvolts::Float64
    position::Int
    filename::T
end
function OEChannel{T<:AbstractString}(
    name::T,
    number::Int,
    bitvolts::Float64
)
    return OEChannel{T}(name, number, bitvolts, 0, T(""))
end

abstract OEProcessor{T<:OEChannel}
immutable OERhythmProcessor{T<:OEChannel} <: OEProcessor{T}
    id::Int
    channels::Vector{T}
    lowcut::Float64
    highcut::Float64
    adcs_on::Bool
    noiseslicer::Bool
    dac_ttl::Bool
    dac_hpf::Bool
    dsp_offset::Bool
    dsp_cutoff::Float64
end
function OERhythmProcessor(proc_e::LightXML.XMLElement)
    id = attribute(proc_e, "NodeId", required = true)
    ch_info_e = find_element(proc_e, "CHANNEL_INFO")
    isempty(ch_info_e) && error("Could not find CHANNEL_INFO element")
    chan_children = collect(child_elements(ch_info_e))
    chans = Array{OEChannel}(length(chan_children))
    for i, chan_e in enumerate(chan_children)
        chno_attr = attribute(chan_e, "number", required = true)
        chno = parse(Int, chno_attr)
        chname = attribtue(chan_e, "name", required = true)
        bitvolt_attr = attribute(chan_e, "gain", required = true)
        bitvolts = parse(Float64, bitvolt_attr)
        chans[i] = OEChannel(chname, chno, bitvolts)
    end


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
    isempty(info_e) && error("Could not find INFO element")
    info = OEInfo(info_e)
    chain_e = find_element(settings_e, "SIGNALCHAIN")
    isempty(chain_e) && error("Could not find SIGNALCHAIN element")
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
