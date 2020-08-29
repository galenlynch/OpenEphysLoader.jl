# OpenEphysLoader.jl

*A set of tools to load data written by the [Open Ephys GUI](http://www.open-ephys.org/gui/)*

| **Documentation**                                                                 | **Build Status**                                                                                  |
| :-------------------------------------------------------------------------------: | :-----------------------------------------------------------------------------------------------: |
| [![][docs-stable-img]][docs-stable-url] [![][docs-latest-img]][docs-latest-url]   | [![][travis-img]][travis-url] [![][appveyor-img]][appveyor-url] [![][codecov-img]][codecov-url]   |

## Requirements
Julia 1.0 or higher

## Installation

```julia
julia> Pkg.add("OpenEphysLoader")
```

## Documentation
- [**STABLE**][docs-stable-url] &mdash; **most recently tagged version of the documentation.**
- [**LATEST**][docs-latest-url] &mdash; *in-development version of the documentation.*

## Project Status
This package is tested against Julia `1.0`, `1`, and nightlies on Linux, OS X, and Windows.

This package only supports reading from continuous files.

[docs-latest-img]: https://img.shields.io/badge/docs-latest-blue.svg
[docs-latest-url]: https://galenlynch.github.io/OpenEphysLoader.jl/latest

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://galenlynch.github.io/OpenEphysLoader.jl/stable

[travis-img]: https://travis-ci.org/galenlynch/OpenEphysLoader.jl.svg?branch=master
[travis-url]: https://travis-ci.org/galenlynch/OpenEphysLoader.jl

[appveyor-img]: https://ci.appveyor.com/api/projects/status/pc9sjllvn2tdlpom?svg=true
[appveyor-url]: https://ci.appveyor.com/project/galenlynch/openephysloader-jl

[codecov-img]: https://codecov.io/gh/galenlynch/OpenEphysLoader.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/galenlynch/OpenEphysLoader.jl
