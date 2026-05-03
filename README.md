# bashdep

[![Tests](https://github.com/Chemaclass/bashdep/actions/workflows/tests.yml/badge.svg)](https://github.com/Chemaclass/bashdep/actions/workflows/tests.yml)
[![Static Analysis](https://github.com/Chemaclass/bashdep/actions/workflows/static_analysis.yml/badge.svg)](https://github.com/Chemaclass/bashdep/actions/workflows/static_analysis.yml)
[![Lint](https://github.com/Chemaclass/bashdep/actions/workflows/linter.yml/badge.svg)](https://github.com/Chemaclass/bashdep/actions/workflows/linter.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A minimalistic, zero-dependency **bash dependency manager**. Declare a list of
URLs and bashdep will download them into a `lib/` directory you can `source`
from your scripts.

## Contents

- [Why bashdep?](#why-bashdep)
- [Install](#install)
- [Quick start](#quick-start)
- [API](#api)
  - [`bashdep::install`](#bashdepinstall)
  - [`bashdep::install_from`](#bashdepinstall_from)
  - [`bashdep::setup`](#bashdepsetup)
  - [`bashdep::list`](#bashdeplist)
  - [`bashdep::version`](#bashdepversion)
- [Behavior](#behavior)
  - [Lockfile and idempotency](#lockfile-and-idempotency)
  - [Dev dependencies](#dev-dependencies)
  - [Error handling](#error-handling)
- [Development](#development)

## Why bashdep?

Most bash projects vendor scripts by hand: `curl`, `chmod +x`, repeat.
bashdep turns that into one declarative list with sensible defaults:

- Idempotent installs via a per-directory `.bashdep.lock`. Bumping a
  release URL re-downloads automatically; same URL is skipped.
- Dev/prod separation via the `@dev` URL suffix (`lib/` vs `lib/dev/`).
- One `force=true` flag for full refreshes.
- Read deps from a file (`bashdep::install_from .bashdep`) or pass an
  array directly.

No package registry, no runtime — just `curl`.

## Install

Drop the `bashdep` script into your repo (typically under `lib/`):

```bash
mkdir -p lib
curl -fsSLo lib/bashdep https://raw.githubusercontent.com/Chemaclass/bashdep/main/bashdep
chmod +x lib/bashdep
```

Then `source lib/bashdep` from your install script.

## Quick start

Declare your deps in a `.bashdep` file:

```
# .bashdep
https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr
https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh@dev
```

Then in your install script:

```bash
#!/bin/bash
set -euo pipefail

source lib/bashdep
bashdep::install_from .bashdep
```

First run downloads everything and writes `.bashdep.lock` in each
destination directory:

```
Downloading 'bashunit' to 'lib'...
> bashunit installed successfully in 'lib'
Downloading 'create-pr' to 'lib'...
> create-pr installed successfully in 'lib'
Downloading 'dumper.sh' to 'lib/dev'...
> dumper.sh installed successfully in 'lib/dev'
```

Re-runs skip already-installed deps; bumping a URL version re-downloads
the affected entry only:

```
> bashunit already exists in 'lib', skipping.
> create-pr already exists in 'lib', skipping.
> dumper.sh already exists in 'lib/dev', skipping.
```

Prefer an inline array? Pass it to `bashdep::install` directly — see
[`bashdep::install`](#bashdepinstall).

## API

### `bashdep::install`

Download each dependency in the list into the configured directories.

```bash
DEPENDENCIES=(
  "https://example.com/runtime.sh"
  "https://example.com/dev-tool.sh@dev"
)
bashdep::install "${DEPENDENCIES[@]}"
```

Returns the number of failed downloads (0 on success, capped at 255).

### `bashdep::install_from`

Read a dependency list from a file and install every entry. One URL per
line; blank lines and `#` comments are ignored; leading/trailing
whitespace is stripped.

```bash
bashdep::install_from .bashdep
```

Returns `1` if the file is missing or unreadable; otherwise propagates
the failure count from `bashdep::install`.

### `bashdep::setup`

Configure defaults before calling `install`. All parameters are optional.

| Param     | Type   | Default   | Purpose                                                |
| --------- | ------ | --------- | ------------------------------------------------------ |
| `dir`     | string | `lib`     | Destination for normal dependencies.                   |
| `dev-dir` | string | `lib/dev` | Destination for dev dependencies (URLs ending `@dev`). |
| `silent`  | bool   | `false`   | Suppress progress output.                              |
| `force`   | bool   | `false`   | Re-download even when the file already exists.         |

```bash
bashdep::setup dir="vendor" dev-dir="src/dev" silent=true force=false
```

Invalid values (unknown param, non-boolean for `silent`/`force`) cause
`setup` to print an error to stderr and return `1`.

### `bashdep::list`

Print every installed dependency recorded in the lockfiles under `dir`
and `dev-dir`. One entry per line, tab-separated: `<path>\t<source URL>`.
Pass extra directories as positional arguments to include them too.

```bash
$ bashdep::list
lib/bashunit	https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
lib/create-pr	https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr
lib/dev/dumper.sh	https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh
```

Pipe into `awk` / `cut` for audit and diff tooling.

### `bashdep::version`

Print the bashdep version.

```bash
bashdep::version  # 0.3.0
```

## Behavior

### Lockfile and idempotency

`bashdep::install` is idempotent **per source URL**, not per filename.
Each destination directory gets a `.bashdep.lock` recording the URL of
every dependency installed there:

```
# lib/.bashdep.lock
bashunit	https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
create-pr	https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr
```

Skip rules on subsequent runs:

| File present | Lock URL matches | `force` | Action      |
| :----------: | :--------------: | :-----: | ----------- |
|     yes      |       yes        |   no    | skip        |
|     yes      |        no        |   no    | re-download |
|      no      |        —         |    —    | re-download |
|     yes      |       yes        |   yes   | re-download |

Bumping a release in the URL (`0.17.0` → `0.18.0`) re-downloads the
affected entry only; nothing else is touched.

Commit `.bashdep.lock` alongside your install script so collaborators
get the same versions you do.

### Dev dependencies

A URL ending in `@dev` routes to `dev-dir` instead of `dir`:

```bash
DEPENDENCIES=(
  "https://example.com/runtime.sh"        # → lib/
  "https://example.com/dev-tool.sh@dev"   # → lib/dev/
)
```

Each directory keeps its own `.bashdep.lock`.

### Error handling

- `bashdep::install` continues past failed downloads and returns the
  failure count (capped at 255).
- `bashdep::install_from` returns `1` if the file is missing or
  unreadable.
- `bashdep::setup` returns `1` on unknown params or non-boolean values
  for `silent` / `force`.
- `curl` failures print the exit code to stderr (e.g. `22` = HTTP error,
  `6` = DNS, `7` = connect refused).

Pair with `set -euo pipefail` and `|| exit $?` to fail fast.

## Development

Install test dependencies (bashunit) and run the suite:

```bash
make deps
make test
```

Other targets:

```bash
make sa                # ShellCheck static analysis
make lint              # editorconfig-checker
make pre_commit/install
```

See [CONTRIBUTING](.github/CONTRIBUTING.md) for the full contributor guide.
