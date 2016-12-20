using Base.Test
@testset "OpenEphysLoader.jl" begin
    include("util.jl")
    include("original.jl")
    include("continuous.jl")
    include("test_continuous.jl")
    include("metadata.jl")
end
