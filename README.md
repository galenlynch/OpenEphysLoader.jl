# OpenEphysLoader.jl

*A set of tools to load data written by the [Open Ephys GUI](http://www.open-ephys.org/gui/)*

| **Documentation**                                                                 | **PackageEvaluator**                                            | **Build Status**                                                                                  |
| :-------------------------------------------------------------------------------: | :-------------------------------------------------------------: | :-----------------------------------------------------------------------------------------------: |
| [![][docs-stable-img]][docs-stable-url] [![][docs-latest-img]][docs-latest-url]   |  [![][pkg-0.6-img]][pkg-0.6-url] | [![][travis-img]][travis-url] [![][appveyor-img]][appveyor-url] [![][codecov-img]][codecov-url]   |

## Requirements
Julia 0.5 or higher

## Installation
This package is registered, so simply install it with the package manager:

```julia
julia> Pkg.add("OpenEphysLoader")
```

## Documentation
For documentation on the use of `metadata`, please see the latest docs below.

- [**STABLE**][docs-stable-url] &mdash; **most recently tagged version of the documentation.**
- [**LATEST**][docs-latest-url] &mdash; *in-development version of the documentation.*

## Project Status
This package is tested against Julia `0.6` and nightlies on Linux, OS X, and Windows.

This package only supports reading from continuous files at the moment, with no immediate
plans to support spike data.

## Contributing
Contributions are welcome, as are feature requests and suggestions.

Pull requests should be against the develop branch, as per the [Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow) work flow.

Please open an issue if you encounter any problems.

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

[pkg-0.6-img]: http://pkg.julialang.org/badges/OpenEphysLoader_0.6.svg
[pkg-0.6-url]: http://pkg.julialang.org/?pkg=OpenEphysLoader
