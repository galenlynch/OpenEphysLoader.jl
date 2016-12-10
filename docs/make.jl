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
