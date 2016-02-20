function filecontext(file_reader::Function, file_writer::Function, args::Any...; kwargs::Any...)
    path, io = mktemp()
    try
        file_writer(io, args...; kwargs...)
        close(io)
        io = open(path)
        file_reader(io)
    finally
        close(io)
        rm(path)
    end
end

function pathcontext(file_reader::Function, file_writer::Function, args::Any...; kwargs::Any...)
    path, io = mktemp()
    try
        file_writer(io, args...; kwargs...)
        close(io)
        file_reader(path)
    finally
        close(io)
        rm(path)
    end
end

function pathiocontext(file_reader::Function, file_writer::Function, args::Any...; kwargs::Any...)
    path, io = mktemp()
    try
        file_writer(io, args...; kwargs...)
        close(io)
        io = open(path)
        file_reader(path, io)
    finally
        close(io)
        rm(path)
    end
end

function dircontext(dir_reader::Function, dir_writer::Function, args::Any...; kwargs::Any...)
    dirpath = mktempdir()
    try
        files = dir_writer(dirpath, args...; kwargs...)
        dir_reader(dirpath, files)
    finally
        rm(dirpath; recursive = true)
    end
end
