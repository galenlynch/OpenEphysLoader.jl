module TestUtilities
using OpenEphysLoader, Base.ImmutableDict, Base.Test
export filecontext, test_fields

function filecontext(file_reader::Function, args...; kwargs...)
    wrapped_reader(::AbstractString, io::IOStream) = file_reader(io)
    pathiocontext(wrapped_reader, args...; kwargs...)
end

function pathiocontext(
    file_reader::Function,
    file_writer::Function,
    args...;
    kwargs...
)
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

@generated function test_fields(a::Any, args...; kwargs...)
    fields = fieldnames(a)
    nfield = length(fields)
    testarr = Vector{Expr}(nfield)
    for (i, field) in enumerate(fields)
        check_ex = :(get(kwarg_dict, $(QuoteNode(field)), true))
        fldtype = fieldtype(a, field)
        moddefined = Base.datatype_module(fldtype) == OpenEphysLoader
        if moddefined
            test_ex = :(test_fields(a.$(field), args[j]...))
        else
            test_ex = :(@test a.$(field) == args[j])
        end
        testarr[i] = quote
            if $(check_ex)
                $(test_ex)
                j += 1
            end
        end
    end
    return quote
        @assert $(nfield) == length(args) + length(kwargs) "Args and kwargs must match number of fields"
        j = 1
        kwarg_dict = Dict(kwargs)
        $(testarr...)
    end
end

end
