const DATEFORMATSTR = "d u y H:M:S"
const RHYTHM_PROC = "Sources/Rhythm FPGA"

### Types ###
"""
    OEChannel{T<:AbstractString}
Type for continuous recording channel metadata

# Fields

**`name`** `T<:AbstractString` of channel name

**`number`** `Int` of channel number in GUI

**`bitvolts`** `Float64` of volts per ADC bit

**`position`** `Int` position of data in file.

**`filename`** `T<:AbstractString` name of associated `.continuous` file
"""
immutable OEChannel{T<:AbstractString}
    name::T
    number::Int
    bitvolts::Float64
    position::Int
    filename::T
end

"""
    OEProcessor{T<:AbstractString}
Abstract type for recording Open Ephys processors.
"""
abstract OEProcessor{T<:AbstractString}

"""
    OERhythmProcessor{T<:AbstractString}(proc_e::LightXML.XMLElement)
Type for Rhythm processor metadata, subtype of [`OEProcessor`](@ref).

Construct with XML element for processor.

# Fields

**`id`** `Int` of processor ID in GUI

**`lowcut`** `Float64` of low pass filter cutoff on headstages

**`highcut`** `Float64` of high pass filter cutoff on headstages

**`adcs_on`** `Bool` `true` if ADCs on

**`noiseslicer`** `Bool` `true` if noiseslicer used for ADC

**`ttl_fastsettle`** `Bool` `true` if TTL fast settle used

**`dac_ttl`** `Bool` `true` if dac ttl is on

**`dac_hpf`** `Bool` `true` if dac hpf is on

**`dsp_offset`** `Bool` `true` if headstage DSP offset removal is used

**`dsp_cutoff`** `Float64` of DSP high pass filter cutoff

**`channels`** `Vector{OEChannel{T}}` list of [`OEChannel`](@ref) in Rhythm processor
"""
immutable OERhythmProcessor{T<:AbstractString} <: OEProcessor{T}
    id::Int
    lowcut::Float64
    highcut::Float64
    adcs_on::Bool
    noiseslicer::Bool
    ttl_fastsettle::Bool
    dac_ttl::Bool
    dac_hpf::Bool
    dsp_offset::Bool
    dsp_cutoff::Float64
    channels::Vector{OEChannel{T}}
end
function OERhythmProcessor(proc_e::LightXML.XMLElement)
    id_attr = attribute(proc_e, "NodeId", required = true)
    id = parse(Int, id_attr)

    channels = channel_arr(proc_e)

    # Editor
    editor_e = required_find_element(proc_e, "EDITOR")
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
        lowcut,
        highcut,
        adcs_on,
        noiseslicer,
        ttl_fastsettle,
        dac_ttl,
        dac_hpf,
        dsp_offset,
        dsp_cutoff,
        channels
    )
end

"""
    TreeNode{T}
Abstract node type for tree structure, with type `T` content.

Subtypes must have the following fields:

# Required Fields

**`content`** `T` content of node.

**`parent`** `Int` ID of parent node

**`children`** `Vector{Int}` IDs of children node
"""
abstract TreeNode{T}

"""
    SignalNode{T<:OEProcessor}
Node type for OEProcessor signal chain, subtype of [`TreeNode`](@ref).

See [`TreeNode`](@ref) for information on fields.
"""
type SignalNode{T<:OEProcessor} <: TreeNode{T}
    content::T
    parent::Int
    children::Vector{Int}
end

"""
    Tree{T}
Abstract type for tree structure, with type `T` content.

Contains a group of [`TreeNode`](@ref) in the single required field:

# Required Fields

**`nodes`** Indexable list of [`TreeNode`](@ref) elements.
"""
abstract Tree{T}

"""
    OESignalTree{T<:OEProcessor}(chain_e::LightXML.XMLElement, [recording_anmes::Set])

Signal tree for recording processors. Since [`OpenEphysLoader`](@ref) currently on works on `.continuous` file types, this will search for the first [`OERhythmProcessor`](@src) and make a signal tree up to that point.

Construct with a XML signalchain element, and a set of processor names that are valid recording nodes.

See [`Tree`](@ref) for field information.
"""
immutable OESignalTree{T<:OEProcessor} <: Tree{T}
    nodes::Vector{SignalNode{T}}
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
                    proc = OERhythmProcessor(ch_e)
                    signode = SignalNode(proc, 0, Vector{Int}())
                    return OESignalTree([signode])
                end
            end
        end
    end
end

"""
    OEInfo{T<:AbstractString}(info_e::LigthXML.XMLElement)

Type to represent the info element in `settings.xml` made by Open Ephys.

Construct with the XML info element.

# Fields

**`gui_version`** `VersionNumber` GUI version

**`plugin_api_version`** `VersionNumber` plugin API version. If `gui_version` is less than `0.4.0` then this will be `0`

**`datetime`** `DateTime` date and time that `settings.xml` was made

**`os`** `T` Operating system of computer running GUI

**`machine`** `T` hostname of computer running GUI
"""
immutable OEInfo{T<:AbstractString}
    gui_version::VersionNumber
    plugin_api_version::VersionNumber
    datetime::DateTime
    os::T
    machine::T
end
function OEInfo(info_e::LightXML.XMLElement)
    ver_e = required_find_element(info_e, "VERSION")
    gui_version = VersionNumber(content(ver_e))
    if gui_version > v"0.4.0"
        plugin_e = required_find_element(info_e, "PLUGIN_API_VERSION")
        plugin_api = VersionNumber(content(plugin_e))
    else
        plugin_api = v"0"
    end
    date_e = required_find_element(info_e, "DATE")
    datetime = DateTime(content(date_e), DATEFORMATSTR)
    os_e = required_find_element(info_e, "OS")
    os = content(os_e)
    machine_e = required_find_element(info_e, "MACHINE")
    machine = content(machine_e)
    return OEInfo(gui_version,
                  plugin_api,
                  datetime,
                  os,
                  machine)
end

"""
    OESettings{S<:AbstractString, T<:OEProcessor}(xdoc::LightXML.XMLDocument)
Type to represent information in the `settings.xml` file made by the Open Ephys GUI.

Construct with the XML document for `settings.xml`

# Fields

**`info`** [`OEInfo`](@ref) GUI info.

**`recording_chain`** [`OESignalTree`](@ref) Signal tree that leads to recording processors.
"""
immutable OESettings{S<:AbstractString, T<:OEProcessor}
    info::OEInfo{S}
    # only processors that lead to recording nodes
    recording_chain::OESignalTree{T}
end
function OESettings(xdoc::LightXML.XMLDocument)
    settings_e = root(xdoc)
    @assert name(settings_e) == "SETTINGS" "Not a settings xml"
    info_e = required_find_element(settings_e, "INFO")
    oe_info = OEInfo(info_e)
    chain_e = required_find_element(settings_e, "SIGNALCHAIN")
    signaltree = OESignalTree(chain_e)
    return OESettings(oe_info, signaltree)
end

"""
    OERecordingMeta{T<:OEProcessor}(settings::OESettings, rec_e::LightXML.XMLElement)
Type that represents recording metadata in `Continuous_Data.openephys` file made by the Open Ephys GUI.

Construct with a [`OESettings`](@ref) from the `settings.xml` file, and the XML recording element of the `Continuous_Data.openephys` file.

# Fields

**`number`** `Int` Recording number

**`samplerate`** `Float64` Sampling rate

**`recording_processors`** `Vector{T}` list of recording processors
"""
immutable OERecordingMeta{T<:OEProcessor}
    number::Int
    samplerate::Float64
    recording_processors::Vector{T}
end
function OERecordingMeta{S, T}(
    settings::OESettings{S, T},
    rec_e::LightXML.XMLElement
)
    no_attr = attribute(rec_e, "number", required=true)
    number = parse(Int, no_attr)
    samprate_attr = attribute(rec_e, "samplerate", required=true)
    samplerate = parse(Float64, samprate_attr)

    proc_es = get_elements_by_tagname(rec_e, "PROCESSOR")
    isempty(proc_es) && error("Could not find PROCESSOR elements")
    nproc = length(proc_es)
    rec_procs = Vector{T}(nproc)

    for (i, proc_e) in enumerate(proc_es)
        maybe_id = find_matching_proc(settings.recording_chain, proc_e)
        isempty(maybe_id) && error("Could not find matching processor")
        id = maybe_id[1]
        rec_procs[i] = settings.recording_chain.nodes[id].content
    end
    return OERecordingMeta(number, samplerate, rec_procs)
end

"""
    OEExperMeta{S<:AbstractString, T<:OEProcessor}(s::OESettings, exper::LightXML.XMLElement)
Type to represent the Experiment metadata in `Continuous_Data.openephys`.

Construct with the [`OESettings`](@ref) from `settings.xml` and XML experiment element.

# Fields

**`file_version`** `VersionNumber` continuous file format version

**`experiment_number`** `Int` experiment number

**`separate_files`** `Bool` `true` if files are separate

**`recordings`** `Vector{OERecordingMeta{T}}` `Vector` of each [`OERecordingMeta`](@ref) within the experiment

**`settings`** [`OESettings`](@ref) of the `settings.xml` file
"""
immutable OEExperMeta{S<:AbstractString, T<:OEProcessor}
    file_version::VersionNumber
    experiment_number::Int
    separate_files::Bool
    recordings::Vector{OERecordingMeta{T}}
    settings::OESettings{S, T}
end
function OEExperMeta{S, T}(
    settings::OESettings{S, T},
    exper_e::LightXML.XMLElement
)
    # Get version
    ver_attr = attribute(exper_e, "version", required=true)
    ## Version numbers in OE files are floats, often see 0.400000000000002
    ## Need to extract the "meaningful" part
    ver_reg = r"^(\d+)\.([1-9]\d*?)0*?\d?$"
    m = match(ver_reg, ver_attr)
    ver_str = string(m.captures[1], '.', m.captures[2])
    ver = VersionNumber(ver_str)

    # Get number
    no_attr = attribute(exper_e, "number", required=true)
    exper_no = parse(Int, no_attr)

    # Get separatefiles
    separate_attr = attribute(exper_e, "separatefiles", required=true)
    separate_files = parse(Int, separate_attr) == 1

    # get recordings
    rec_es = get_elements_by_tagname(exper_e, "RECORDING")
    isempty(rec_es) && error("Could not find RECORDING elements")
    nrec = length(rec_es)
    recordings = Vector{OERecordingMeta{T}}(nrec)
    for (i, rec_e) in enumerate(rec_es)
        recordings[i] = OERecordingMeta(settings, rec_e)
    end

    return OEExperMeta(ver,
                       exper_no,
                       separate_files,
                       recordings,
                       settings)
end

### Top level functions ###
"""
    dir_settings([dirpath::AbstractString = pwd()]; settingsfile = "settings.xml", continuousmeta="Continuous_Data.openephys")

Top-level function to read a directory and parse the `settings.xml` and `Continuous_data.openeephys` files.

returns a OEExperMeta.
"""
function dir_settings(dirpath::AbstractString = pwd();
                      settingsfile::AbstractString = "settings.xml",
                      continuousmeta::AbstractString = "Continuous_Data.openephys")
    settingspath = joinpath(dirpath, settingsfile)
    isfile(settingspath) || error("$settingspath does not exist")
    continuouspath = joinpath(dirpath, continuousmeta)
    isfile(continuouspath) || error("$continuouspath does not exist")
    local exper_meta, settings
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

### Open Ephys XML parsing functions ###
"""
Parse XML Element PROCESSOR and recover channel metadata.
"""
function channel_arr{T<:AbstractString}(proc_e::LightXML.XMLElement, ::Type{T} = String)
    # Assumes that channels are sorted!
    # Channels
    channel_vec = get_elements_by_tagname(proc_e, "CHANNEL")
    isempty(channel_vec) && error("Could not find CHANNEL elements")
    nchan = length(channel_vec)
    chan_rec = fill(false, nchan)
    chnos = Array{Int}(nchan)
    for (i, chan_e) in enumerate(channel_vec)
        sel_e = required_find_element(chan_e, "SELECTIONSTATE")
        record_attr = attribute(sel_e, "record", required=true)
        record = parse(Int, record_attr)
        if record == 1
            chan_rec[i] = true
            chno_attr = attribute(chan_e, "number", required=true)
            chno = parse(Int, chno_attr)
            chnos[i] = chno
        end
    end
    nrec = sum(chan_rec)

    # Channel info
    ch_info_e = required_find_element(proc_e, "CHANNEL_INFO")
    chinfo_children = collect(child_elements(ch_info_e))
    channels = Array{OEChannel{T}}(nrec)
    recno = 1
    for (i, chan_e) in enumerate(chinfo_children)
        if chan_rec[i]
            info_chno_attr = attribute(chan_e, "number", required = true)
            info_chno = parse(Int, info_chno_attr)
            @assert info_chno == chnos[i] "Channels not in same order"
            chname = attribute(chan_e, "name", required = true)
            bitvolt_attr = attribute(chan_e, "gain", required = true)
            bitvolts = parse(Float64, bitvolt_attr)
            channels[recno] = OEChannel{String}(chname,
                                                info_chno,
                                                bitvolts,
                                                0,
                                                "")
            recno += 1
        end
    end

    return channels
end

"""
Add data from `Continuous_Data.openephys` to [`OESettings`](@ref) from `settings.xml`
"""
function add_continuous_meta!(
    settings::OESettings,
    exper_e::LightXML.XMLElement
)
    rec_es = get_elements_by_tagname(exper_e, "RECORDING")
    length(rec_es) != 1 && error("Need to change this logic...")
    rec_e = rec_es[1]
    proc_es = get_elements_by_tagname(rec_e, "PROCESSOR")
    isempty(proc_es) && error("Could not find PROCESSOR elements")
    for (i, proc_e) in enumerate(proc_es)
        maybe_id = find_matching_proc(settings.recording_chain, proc_e)
        isempty(maybe_id) && error("Could not find matching processor")
        id = maybe_id[1]
        add_continuous_meta!(settings.recording_chain.nodes[id].content,
                             proc_e)
    end
end
function add_continuous_meta!(
    proc::OERhythmProcessor,
    proc_e::LightXML.XMLElement
)
    chan_es = get_elements_by_tagname(proc_e, "CHANNEL")
    isempty(chan_es) && error("Could not find CHANNEL elements")
    for (i, chan_e) in enumerate(chan_es)
        name = attribute(chan_e, "name", required=true)
        name == proc.channels[i].name || error("Channel names don't match!")
        filename = attribute(chan_e, "filename", required=true)
        position_attr = attribute(chan_e, "position", required=true)
        file_position = parse(Int, position_attr)
        proc.channels[i] = OEChannel(
            proc.channels[i].name,
            proc.channels[i].number,
            proc.channels[i].bitvolts,
            file_position,
            filename
        )
    end
end

"""
Find id of processor in [`OESignalTree`](@ref) that matches id of XML processor element
"""
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

### Tree functions ###
# Taken from Scott Jones' StackOverflow answer on 4/13/2016
function addchild(tree::OESignalTree, id::Int, processor::OEProcessor)
    1 <= id <= length(tree.nodes) || throw(BoundsError(tree, id))
    push!(tree.nodes, SignalNode(processor, id, Vector{Int}()))
    child_id = length(tree.nodes)
    push!(tree.nodes[id].children, child_id)
    return child_id
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

### Helper Functions ###
function required_find_element(e::LightXML.XMLElement, name::AbstractString)
    maybe_e = find_element(e, name)
    isa(maybe_e, Void) && error("Could not find $name element")
    return maybe_e
end

function parse_file(f::Function, args...)
    xdoc = parse_file(args...)
    try
        f(xdoc)
    finally
        free(xdoc)
    end
end

### Display methods ###
show(io::IO, a::OESettings) = showfields(io, a)
show(io::IO, a::OEInfo) = showfields(io, a)
show(io::IO, a::OEExperMeta) = showfields(io, a)
function show(io::IO, a::OERecordingMeta)
    compact = get(io, :compact, false)
    compact ? print(io, "recording $(a.number)") : showfields(io, a)
end
show(io::IO, a::OEProcessor) = showfields(io, a)
function show(io::IO, a::OEChannel)
    compact = get(io, :compact, false)
    compact ? print(io, a.name) : showfields(io, a)
end
show(io::IO, a::SignalNode) = show(io, a.content)

showfields(io::IO, a::Any) = showfields(IOContext(io, :depth => 0), a)
function showfields(io::IOContext, a::Any)
    depth = get(io, :depth, 0)
    pad = string(("  " for n = 1:depth)...)
    fields = fieldnames(a)
    depth > 0 && print(io, '\n')
    next_io = IOContext(io, :depth => depth + 1)
    for field in fields
        print(io, pad, "$field: ")
        show(next_io, getfield(a, field))
        print(io, '\n')
    end
end
