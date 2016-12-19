const RHYTHM_PROC = "Sources/Rhythm FPGA"
immutable OEChannel{T<:AbstractString}
    name::T
    number::Int
    bitvolts::Float64
    position::Int
    filename::T
end

abstract OEProcessor{T<:AbstractString}
immutable OERhythmProcessor{T<:AbstractString} <: OEProcessor{T}
    id::Int
    channels::Vector{OEChannel{T}}
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

abstract TreeNode{T}
type SignalNode{S<:AbstractString, T<:OEProcessor{S}} <: TreeNode{T}
    content::T
    parent::Int
    children::Vector{Int}
end

abstract Tree{T}
immutable OESignalTree{S<:AbstractString, T<:OEProcessor{S}} <: Tree{T}
    nodes::Vector{SignalNode{S, T}}
end
function OESignalTree(
    chain_e::LightXML.XMLElement;
    recording_names = Set([RHYTHM_PROC])
    )
    childs = child_elements(chain_e)
    for ch_e in childs # Break at first recording processor!
        if name(ch_e) == "PROCESSOR"
            procname = attribute(ch_e, "name", required = true)
            if procname in recording_names
                if procname == RHYTHM_PROC
                    proc = OERhtymProcessor(ch_e)
                    signode = SignalNode(proc, 0, Vector{Int}())
                    return OESignalTree([signode])
                end
            end
        end
    end
end
# Taken from Scott Jones' StackOverflow answer on 4/13/2016
function addchild(tree::OESignalTree, id::Int, processor::OEProcessor)
    1 <= id <= length(tree.nodes) || throw(BoundsError(tree, id))
    push!(tree.nodes, SignalNode(processor, id, Vector{Int}()))
    child_id = length(tree.nodes)
    push!(tree.nodes[id].children, child_id)
    return child
end
children(tree::Tree, id::Int) = tree.nodes[id].children
parent(tree::Tree, id::Int) = tree.nodes[id].parent
function find_by(pred::Function, tree::Tree)
    return find_by(pred, tree, 1)
end
function find_by(pred::Function, tree::Tree, id::Int)
    if pred(tree.nodes[id].content)
        return id
    else
        for child in children(tree, id)
            maybe_match = find_by(pred, tree, child)
            if ! isempty(maybe_match)
                return maybe_match
            end
        end
    end
    return Array{Int}() # Didn't find a match
end

immutable OERecordingMeta{S<:AbstractString, T<:OEProcessor{S}}
    number::Int
    samplerate::Float64
    recording_processors::Vector{T}
end
function OERecordingMeta{S, T}(
        settings::OESettings{S, T}, rec_e::LightXML.XMLElement)
    no_attr = attribute(rec_e, "number", required=true)
    number = parse(Int, no_atter)
    samprate_attr = attribtue(rec_e, "samplerate", required=true)
    samplerate = parse(Float64, samprate_attr)

    proc_es = get_elements_by_tagname(rec_e, "PROCESSOR")
    isempty(proc_es) && error("Could not find PROCESSOR elements")
    nproc = length(proc_es)
    rec_procs = Vector{T}(nproc)

    return OERecordingMeta(number, samplerate, rec_procs)
end

function add_continuous_meta!{S, T}(
    settings::OESettings{S, T},
    exper_e::LightXML.XMLElement
)
    rec_es = get_elements_by_tagname(exper_e, "RECORDING")
    length(rec_es) != 1 && error("Need to change this logic...")
    rec_e = rec_es[1]
    proc_es = get_elements_by_tagname(rec_e, "PROCESSOR")
    isempty(proc_es) && error("Could not find PROCESSOR elements")
    for i, proc_e in enumerate(proc_es)
        match_id = find_matching_proc(settings.recording_chain,
                                      proc_e)
        add_continuous_meta!(settings.recording_chain.nodes[match_id])
    end
end
function add_continuous_meta!(
    proc::OERhythmProcessor,
    proc_e::LightXML.XMLElement
)
    chan_es = get_elements_by_tagname(proc_e, "CHANNEL")
    isempty(chan_es) && error("Could not find CHANNEL elements")
    for i, chan_e in enumerate(chan_es)
        name = attribute(chan_e, "name", required=true)
        name == proc.channels[i].name || error("Channel names don't match!")
        filename = attribute(chan_e, "filename", required=true)
        position_attr = attribute(chan_e, "position", required=true)
        position = parse(Int, position_attr)
        proc.channels[i] = OEChannel(
            proc.channels[i].name,
            proc.channels[i].number,
            proc.channels[i].bitvolts,
            position,
            filename
        )
    end
end

function find_matching_proc(
    sig_chain::OESignalTree,
    proc_e::LightXML.XMLElement
)
    proc_id_attr = attribute(proc_e, "id", required=true)
    proc_id = parse(Int, proc_id_attr)
    pred = x::OERhythmProcessor -> x.id == proc_id
    maybe_match = find_by(pred, sig_chain)
    isempty(maybe_match) && error("Could not find matching processor")
    return maybe_match[1]
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

immutable OESettings{S<:AbstractString, T<:OEProcessor{S}}
    info::OEInfo{S}
    # only processors that lead to recording nodes
    recording_chain::OESignalTree{S, T}
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

immutable OEExperMeta{S<:AbstractString, T<:OEProcessor{S}}
    version::VersionNumber
    experiment_number::Int
    separate_files::Bool
    recordings::Vector{OERecordingMeta{S, T}}
    settings::OESettings{S, T}
end
function OEExperMeta{S, T}(
    settings::OESettings{S, T},
    exper_e::LightXML.XMLElement
)
    # Open document and find EXPERIMENT element
    exper_e = root(xdoc)

    # Get version
    ver_attr = attribute(exper_e, "version", required=true)
    ## Version numbers in OE files are floats, often see 0.400000000000002
    ## Need to extract the "meaningful" part
    ver_reg = r"^(\d+)\.([1-9]\d*?)0*?\d?$"
    m = match(ver_reg, ver_attr)
    ver_str = string(m.match[1], '.', m.match[2])
    ver = VersionNumber(ver_str)

    # Get number
    no_attr = attribtue(exper_e, "number", required=true)
    exper_no = parse(Int, no_attr)

    # Get separatefiles
    separate_attr = attribute(exper_e, "separatefile", required=true)
    separate_files = parse(Int, separate_attr) == 1

    # get recordings
    rec_es = get_elements_by_tagame(exper_e, "RECORDING")
    isempty(rec_es) && error("Could not find RECORDING elements")
    nrec = length(rec_es)
    recordings = Vector{OERecordingMeta{S, T}}(nrec)
    for i, rec_e in enumerate(rec_es)
        recodings[i] = OERecordingMeta(settings, rec_e)
    end

    return OEExperMeta(version,
                       exper_no,
                       separate_files,
                       recordings,
                       settings)
end

function dir_settings(dirpath::AbstractString = pwd();
                      settingsfile = "settings.xml",
                      continuousmeta = "Continuous_Data.openephys")
    settingspath = joinpath(dirpath, settingsfile)
    isfile(settingspath) || error("$settingspath does not exist")
    continuouspath = joinpath(dirpath, continuousmeta)
    isfile(continuouspath) || error("$continuouspath does not exist")
    parse_file(settingspath) do settingsdoc
        settings = OESettings(settingsdoc)
        parse_file(continuouspath) do contdoc
            exper_e = root(contdoc)
            add_continuous_meta!(settings, exper_e)
            exper_meta = OEExperMeta(settings, exper_e)
        end
    end
    return exper_meta
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
