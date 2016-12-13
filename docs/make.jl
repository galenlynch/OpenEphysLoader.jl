using Documenter, OpenEphysLoader

makedocs(
    modules = [OpenEphysLoader],
    format = :html,
    sitename = "OpenEphysLoader.jl",
    pages = Any[
        "Home" => "index.md"
        "Library" => Any[
            "Public" => "lib/public.md"
            "Internals" => "lib/internals.md"
        ]
    ]
)

deploydocs(
    repo = "https://github.com/galenlynch/OpenEphysLoader.jl",
    target = "build",
    julia = "0.5",
    deps = nothing,
    make = nothing
)
