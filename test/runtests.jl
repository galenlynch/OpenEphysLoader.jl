@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

@testset "OpenEphysLoader.jl" begin
    include("util.jl")
    include("original.jl")
    include("continuous.jl")
    include("test_continuous.jl")
    include("metadata.jl")
end
