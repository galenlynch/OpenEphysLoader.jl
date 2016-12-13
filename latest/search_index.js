var documenterSearchIndex = {"docs": [

{
    "location": "index.html#",
    "page": "Home",
    "title": "Home",
    "category": "page",
    "text": ""
},

{
    "location": "index.html#OpenEphysLoader.jl-Documentation-1",
    "page": "Home",
    "title": "OpenEphysLoader.jl Documentation",
    "category": "section",
    "text": "A set of tools to load data files made by the OpenEphys GUInote: Note\nThis module is experimental, and may damage your data. No module functions intentionally modify the contents of data files, but use this module at your own risk."
},

{
    "location": "index.html#Package-Features-1",
    "page": "Home",
    "title": "Package Features",
    "category": "section",
    "text": "Read contents of continuous data files without loading the entire file into memory\nArray interface to sample values, time stamps, and recording numbers\nFlexibly typed output provides access to raw sample values or converted voltage values"
},

{
    "location": "index.html#Example-Usage-1",
    "page": "Home",
    "title": "Example Usage",
    "category": "section",
    "text": "OpenEphysLoader.jl provides array types to access file contents. Values accessed through these subtypes of OEArray have an array interface backed by file contents, instead of memory.docpath = @__FILE__()\ndocdir = dirname(docpath)\nrelloadpath = joinpath(docdir, \"../test/data\")\nabsloadpath = realpath(relloadpath)\nabsloadfile = joinpath(absloadpath, \"100_AUX1.continuous\")\nopen(absloadfile, \"r\") do dataio\n    global databytes = read(dataio, 3094)\nend\npath, tmpio = mktemp()\ntry\n    write(tmpio, databytes)\nfinally\n    close(tmpio)\nendusing OpenEphysLoader\nopen(path, \"r\") do io\n    A = SampleArray(io)\n    A[1:3]\nendrm(path)To pull the entire file contents into memory, use copy(OEArray)."
},

{
    "location": "index.html#Library-Outline-1",
    "page": "Home",
    "title": "Library Outline",
    "category": "section",
    "text": "Pages = [\"lib/public.md\", \"lib/internals.md\"]"
},

{
    "location": "lib/public.html#",
    "page": "Public",
    "title": "Public",
    "category": "page",
    "text": ""
},

{
    "location": "lib/public.html#OpenEphysLoader",
    "page": "Public",
    "title": "OpenEphysLoader",
    "category": "Module",
    "text": "Module to read the binary data files created by the OpenEphys GUI\n\nProvides array interfaces to file contents, without loading the entire file into memory\n\n\n\n"
},

{
    "location": "lib/public.html#Public-Documentation-1",
    "page": "Public",
    "title": "Public Documentation",
    "category": "section",
    "text": "Documentation for exported functions and types for OpenEphysLoader.jlOpenEphysLoader"
},

{
    "location": "lib/public.html#OpenEphysLoader.OEArray",
    "page": "Public",
    "title": "OpenEphysLoader.OEArray",
    "category": "Type",
    "text": "Abstract array for file-backed OpenEphys data.\n\nAll subtypes support a ready-only array interface and should be constructable with a single IOStream argument.\n\n\n\n"
},

{
    "location": "lib/public.html#OpenEphysLoader.OEContArray",
    "page": "Public",
    "title": "OpenEphysLoader.OEContArray",
    "category": "Type",
    "text": "Abstract array for file-backed continuous OpenEphys data.\n\nWill throw CorruptedException if the data file has a corrupt OriginalHeader, is not the correct size for an .continuous file, or contains corrupt data blocks.\n\nSubtype of abstract type OEArray are read only, and have with the following fields:\n\nFields\n\ncontfile ContinuousFile for the current file.\n\nblock buffer object for the data blocks in the file.\n\nblockno the current block being access in the file.\n\ncheck Bool to check each data block's validity.\n\n\n\n"
},

{
    "location": "lib/public.html#OpenEphysLoader.SampleArray",
    "page": "Public",
    "title": "OpenEphysLoader.SampleArray",
    "category": "Type",
    "text": "SampleArray(type::Type{T}, io::IOStream, [check::Bool])\n\nSubtype of OEContArray to provide file backed access to OpenEphys sample values. If type is a floating point type, then the sample value will be converted to voltage (in uV). Otherwise, the sample values will remain the raw ADC integer readings.\n\n\n\n"
},

{
    "location": "lib/public.html#OpenEphysLoader.TimeArray",
    "page": "Public",
    "title": "OpenEphysLoader.TimeArray",
    "category": "Type",
    "text": "TimeArray(type::Type{T}, io::IOStream, [check::Bool])\n\nSubtype of OEContArray to provide file backed access to OpenEphys time stamps. If type is a floating point type, then the time stamps will be converted to seconds. Otherwise, the time stamp will be the sample number.\n\n\n\n"
},

{
    "location": "lib/public.html#OpenEphysLoader.RecNoArray",
    "page": "Public",
    "title": "OpenEphysLoader.RecNoArray",
    "category": "Type",
    "text": "RecNoArray(type::Type{T}, io::IOStream, [check::Bool])\n\nSubtype of OEContArray to provide file backed access to OpenEphys numbers.\n\n\n\n"
},

{
    "location": "lib/public.html#OpenEphysLoader.JointArray",
    "page": "Public",
    "title": "OpenEphysLoader.JointArray",
    "category": "Type",
    "text": "JointArray(type::Type{T}, io::IOStream, [check::Bool])\n\nSubtype of OEContArray to provide file backed access to OpenEphys data. Returns a tuple of type type, whose values represent (samplevalue, timestamp, recordingnumber). For a description of each, see SampleArray, TimeArray, and RecNoArray, respectively.\n\n\n\n"
},

{
    "location": "lib/public.html#Array-types-1",
    "page": "Public",
    "title": "Array types",
    "category": "section",
    "text": "All array types are subtypes of the abstract type OEArray, and data from continuous files are subtypes of the abstract type OEContArray.OEArray\nOEContArrayThe following array types can be used to access different aspects of the data:SampleArray\nTimeArray\nRecNoArrayAlternatively, all three aspects can be accessed simultaneously:JointArray"
},

{
    "location": "lib/public.html#OpenEphysLoader.OriginalHeader",
    "page": "Public",
    "title": "OpenEphysLoader.OriginalHeader",
    "category": "Type",
    "text": "OriginalHeader(io::IOStream)\n\nData in the header of binary OpenEphys files.\n\nWill throw CorruptedException if header is corrupt, not an \"OpenEphys\" data format, or not version 0.4 of the data format.\n\nFields\n\nformat is the name of the data format.\n\nversion is the version number of the data format.\n\nheaderbytes is the number of bytes in the header.\n\ndescription is a description of the header.\n\ncreated is the date and time the file was created.\n\nchannel is the name of the channel used to acquire this data.\n\nchanneltype is the type of channel used to acquire this data.\n\nsamplerate is the sampling rate in Hz.\n\nblocklength is the length in bytes of each block of data within the file.\n\nbuffersize is the size of the buffer used during acquisition, in bytes.\n\nbitvolts are the Volts per ADC bit.\n\n\n\n"
},

{
    "location": "lib/public.html#OpenEphysLoader.ContinuousFile",
    "page": "Public",
    "title": "OpenEphysLoader.ContinuousFile",
    "category": "Type",
    "text": "ContinuousFile(io::IOStream)\n\nType for an open continuous file.\n\nFields\n\nio IOStream object.\n\nnsample number of samples in a file.\n\nnblock number of data blocks in a file.\n\nheader OriginalHeader of the current file.\n\n\n\n"
},

{
    "location": "lib/public.html#Information-types-1",
    "page": "Public",
    "title": "Information types",
    "category": "section",
    "text": "The following types provide information about OpenEphys filesOriginalHeader\nContinuousFile"
},

{
    "location": "lib/public.html#OpenEphysLoader.CorruptedException",
    "page": "Public",
    "title": "OpenEphysLoader.CorruptedException",
    "category": "Type",
    "text": "Exception type to indicate a malformed data file\n\n\n\n"
},

{
    "location": "lib/public.html#Exceptions-1",
    "page": "Public",
    "title": "Exceptions",
    "category": "section",
    "text": "CorruptedException"
},

{
    "location": "lib/internals.html#",
    "page": "Internals",
    "title": "Internals",
    "category": "page",
    "text": ""
},

{
    "location": "lib/internals.html#OpenEphysLoader.BlockBuffer",
    "page": "Internals",
    "title": "OpenEphysLoader.BlockBuffer",
    "category": "Type",
    "text": "Type to buffer continuous file contents\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.BlockHeader",
    "page": "Internals",
    "title": "OpenEphysLoader.BlockHeader",
    "category": "Type",
    "text": "Represents the header of each data block\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.DataBlock",
    "page": "Internals",
    "title": "OpenEphysLoader.DataBlock",
    "category": "Type",
    "text": "Represents the entirety of a data block\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.MATLABdata",
    "page": "Internals",
    "title": "OpenEphysLoader.MATLABdata",
    "category": "Type",
    "text": "Abstract class for representing matlab code fragments\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.MATfloat",
    "page": "Internals",
    "title": "OpenEphysLoader.MATfloat",
    "category": "Type",
    "text": "type for representing Matlab floatingpoint numbers\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.MATint",
    "page": "Internals",
    "title": "OpenEphysLoader.MATint",
    "category": "Type",
    "text": "Type for representing Matlab integers\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.MATstr",
    "page": "Internals",
    "title": "OpenEphysLoader.MATstr",
    "category": "Type",
    "text": "Type for representing Matlab strings\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.check_filesize-Tuple{IOStream}",
    "page": "Internals",
    "title": "OpenEphysLoader.check_filesize",
    "category": "Method",
    "text": "Check that file could be comprised of header and complete data blocks\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.convert_block!-Tuple{OpenEphysLoader.DataBlock}",
    "page": "Internals",
    "title": "OpenEphysLoader.convert_block!",
    "category": "Method",
    "text": "Convert the wacky data format in OpenEphys continuous files\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.matread-Tuple{Type{T<:OpenEphysLoader.MATLABdata},S<:AbstractString}",
    "page": "Internals",
    "title": "OpenEphysLoader.matread",
    "category": "Method",
    "text": "read a Matlab source line\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.parseline",
    "page": "Internals",
    "title": "OpenEphysLoader.parseline",
    "category": "Function",
    "text": "Parse a line of Matlab source code\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.parseto",
    "page": "Internals",
    "title": "OpenEphysLoader.parseto",
    "category": "Function",
    "text": "Convert a string to the desired type\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.prepare_block!-Tuple{OpenEphysLoader.OEContArray,Integer}",
    "page": "Internals",
    "title": "OpenEphysLoader.prepare_block!",
    "category": "Method",
    "text": "Load data block if necessary\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.read_into!",
    "page": "Internals",
    "title": "OpenEphysLoader.read_into!",
    "category": "Function",
    "text": "Read file data block into data block buffer\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.read_into!-Tuple{IOStream,OpenEphysLoader.BlockHeader}",
    "page": "Internals",
    "title": "OpenEphysLoader.read_into!",
    "category": "Method",
    "text": "Read block header into header buffer\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.seek_to_block-Tuple{IOStream,Integer}",
    "page": "Internals",
    "title": "OpenEphysLoader.seek_to_block",
    "category": "Method",
    "text": "Move io to data block\n\n\n\n"
},

{
    "location": "lib/internals.html#OpenEphysLoader.verify_tail!-Tuple{IOStream,Array{UInt8,1}}",
    "page": "Internals",
    "title": "OpenEphysLoader.verify_tail!",
    "category": "Method",
    "text": "Verify end of block marker\n\n\n\n"
},

{
    "location": "lib/internals.html#Package-Internals-1",
    "page": "Internals",
    "title": "Package Internals",
    "category": "section",
    "text": "Documentation of the OpenEphysLoader.jl internals.Modules = [OpenEphysLoader]\nPublic = false"
},

]}
