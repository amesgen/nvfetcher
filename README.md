# nvfetcher

[![Hackage](https://img.shields.io/hackage/v/nvfetcher.svg?logo=haskell)](https://hackage.haskell.org/package/nvfetcher)
[![MIT license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![nix](https://github.com/berberman/nvfetcher/actions/workflows/nix.yml/badge.svg)](https://github.com/berberman/nvfetcher/actions/workflows/nix.yml)

nvfetcher is a tool to automate packages updates in flakes repos. It's built on top of [shake](https://www.shakebuild.com/),
integrating [nvchecker](https://github.com/lilydjwg/nvchecker).
It's very simple -- most complicated works are done by nvchecker, nvfetcher just wires it with prefetch tools,
producing only one artifact as the result of build.
nvfetcher cli program accepts a TOML file as config, which defines a set of package sources to run.

## Overview

For example, given the following configuration file:

```toml
# nvfetcher.toml
[feeluown-core]
src.pypi = "feeluown"
fetch.pypi = "feeluown"

[qliveplayer]
src.github = "IsoaSFlus/QLivePlayer"
fetch.github = "IsoaSFlus/QLivePlayer"
git.fetchSubmodules = true
```

running `nvfetcher build` will create `sources.nix` like:

```nix
# sources.nix
{ fetchgit, fetchurl }:
{
  feeluown-core = {
    pname = "feeluown-core";
    version = "3.7.7";
    src = fetchurl {
      sha256 = "06d3j39ff9znqxkhp9ly81lcgajkhg30hyqxy2809yn23xixg3x2";
      url = "https://pypi.io/packages/source/f/feeluown/feeluown-3.7.7.tar.gz";
    };
  };
  qliveplayer = {
    pname = "qliveplayer";
    version = "3.22.1";
    src = fetchgit {
      url = "https://github.com/IsoaSFlus/QLivePlayer";
      rev = "3.22.1";
      fetchSubmodules = true;
      deepClone = false;
      leaveDotGit = false;
      sha256 = "00zqg28q5xrbgql0kclgkhd15fc02qzsrvi0qg8lg3qf8a53v263";
    };
  };
}
```

We tell nvfetcher how to get the latest version number of packages and how to fetch their sources given version numbers,
and nvfetcher will help us keep their version and prefetched SHA256 sums up-to-date, stored in `sources.nix`.
Shake will help us handle necessary rebuilds -- we check versions of packages during each run, but only prefetch them when needed.

### Live examples

How to use the generated sources file? Here are some examples:

* My [flakes repo](https://github.com/berberman/flakes)

* Nick Cao's [flakes repo](https://gitlab.com/NickCao/flakes/-/tree/master/pkgs)

## Installation

`nvfetcher` package is available in [nixpkgs](https://github.com/NixOS/nixpkgs), so you can try it with:

```
$ nix-shell -p nvfetcher
```

This repo also has flakes support:

```
$ nix run github:berberman/nvfetcher
```

To use it as a Haskell library, the package is available on [Hackage](https://hackage.haskell.org/package/nvfetcher).
If you want to use the Haskell library from flakes, there is also a shell `ghcWithNvfetcher`:

```
$ nix develop github:berberman/nvfetcher#ghcWithNvfetcher
$ runghc Main.hs
```

where you can define packages in `Main.hs`. See [Haskell library](#Haskell-library) for details.

## Usage

Basically, there are two ways to use nvfetcher, where the difference is how we provide package sources definitions to it.

### CLI

To run nvfetcher as a CLI program, you'll need to provide package sources defined in TOML.

```
Available options:
  --version                Show version
  --help                   Show this help text
  -c,--config FILE         Path to nvfetcher TOML config
                           (default: "nvfetcher.toml")
  -o,--output FILE         Path to output nix file (default: "sources.nix")
  -l,--changelog FILE      Dump version changes to a file
  -j NUM                   Number of threads (0: detected number of processors)
                           (default: 0)
  -r,--retry NUM           Times to retry of some rules (nvchecker, prefetch,
                           nix-instantiate, etc.) (default: 3)
  -t,--timing              Show build time
  -v,--verbose             Verbose mode
  TARGET                   Two targets are available: 1.build 2.clean
                           (default: "build")
```

Each *package* corresponds to a TOML table, whose name is encoded as table key;
there are two required fields and three optional fields in each table:
* a nvchecker configuration, how to track version updates
  * `src.github = owner/repo` - the latest gituhb release
  * `src.github_tag = owner/repo` - the max github tag, usually used with list options (see below)
  * `src.pypi = pypi_name` - the latest pypi release
  * `src.git = git_url` (and an optional `src.branch = git_branch`) - the latest commit of a repo
  * `src.archpkg = archlinux_pkg_name` -- the latest version of an archlinux package
  * `src.aur = aur_pkg_name` -- the latest version of an aur package
  * `src.manual = v` -- a fixed version, which never updates
  * `src.repology = project:repo` -- the latest version from repology
  * `src.webpage = web_url` and `src.regex` -- a string in webpage that matches with regex
  * `src.httpheader = request_url` and `src.regex` -- a string in http header that matches with regex
* a nix fetcher function, how to fetch the package given the version number. `$ver` is available, which will be set to the result of nvchecker.
  * `fetch.github = owner/repo`
  * `fetch.pypi = pypi_name`
  * `fetch.git = git_url`
  * `fetch.url = url`

* optional git prefetch configuration, which makes sense only when the fetcher equals to `fetch.github` or `fetch.git`.
They can exist simultanesouly.
  * `git.deepClone` - a bool value to control deep clone
  * `git.fetchSubmodules` - a bool value to control fetching submodules
  * `git.leaveDotGit` - a bool value to control leaving dot git

* optional list options configuration for some version sources. See the corresponding [documentation of nvchecker](https://nvchecker.readthedocs.io/en/latest/usage.html#list-options) for details.
  * `src.include_regex`
  * `src.exclude_regex`
  * `src.sort_version_key`
  * `src.ignored`

* optional *extract* configuration
  * `extract = [ "file_1", "file_2", ...]` - file paths are relative to the source root, which will be pulled into generated nix expr.

You can find an example of the configuration file, see [`nvfetcher_example.toml`](nvfetcher_example.toml).

### Haskell library

nvfetcher itsetlf is a Haskell library as well, whereas the CLI program is just a trivial wrapper of the library.
You can create a Haskell program depending on it directly, by using the `runNvFetcher` entry point.
In this case, we can define packages in Haskell language, getting rid of TOML constraints.

You can find an example of using nvfetcher in the library way, see [`Main_example.hs`](Main_example.hs).

## Documentation

For details of the library, documentation of released versions is available on [Hackage](https://hackage.haskell.org/package/nvfetcher),
and of master is on our [github pages](https://nvfetcher.berberman.space).

## Limitations

There is no way to check the equality over version sources and fetchers, so If you change either of them in a package,
you will need to rebuild everything, i.e. run `nvfetcher clean` to remove shake databsae, to make sure that
our build system works correctly. We could automate this process, for example,
calculate the hash of the configuration file and bump `shakeVersion` to trigger the rebuild.
However, this shouldn't happen frequently and we want to minimize the changes, so it's left for you to do manually.

> Adding or removing a package doesn't require such rebuild

## Contributing

Issues and PRs are always welcome. **\_(:з」∠)\_**

Building from source:

```
$ git clone https://github.com/berberman/nvfetcher
$ nix develop
$ cabal build
```
