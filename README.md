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
  - [Skip vs. force re-download](#skip-vs-force-re-download)
  - [Dev dependencies](#dev-dependencies)
  - [Error handling](#error-handling)
- [Development](#development)

## Why bashdep?

Most bash projects vendor scripts by hand: `curl`, `chmod +x`, repeat. bashdep
turns that into one declarative list with sensible defaults: idempotent
installs, dev/prod separation via the `@dev` suffix, and a single `force` flag
to force a refresh. No package registry, no lockfile, no runtime — just `curl`.

## Install

Drop the `bashdep` script into your repo (typically under `lib/`):

```bash
mkdir -p lib
curl -fsSLo lib/bashdep https://raw.githubusercontent.com/Chemaclass/bashdep/main/bashdep
chmod +x lib/bashdep
```

Then `source lib/bashdep` from your install script.

## Quick start

```bash
#!/bin/bash
set -euo pipefail

source lib/bashdep

DEPENDENCIES=(
  "https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  "https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr"
  "https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh@dev"
)

bashdep::install "${DEPENDENCIES[@]}"
```

Run it, and bashdep prints:

```
Downloading 'bashunit' to 'lib'...
> bashunit installed successfully in 'lib'
Downloading 'create-pr' to 'lib'...
> create-pr installed successfully in 'lib'
Downloading 'dumper.sh' to 'lib/dev'...
> dumper.sh installed successfully in 'lib/dev'
```

Re-run it and previously-installed files are skipped:

```
> bashunit already exists in 'lib', skipping.
```

## API

### `bashdep::install`

Download every dependency in the list into the configured directories.

```bash
bashdep::install "${DEPENDENCIES[@]}"
```

Returns the number of failed downloads (0 on success, capped at 255).
Pair with `set -e` or check `$?` to gate the rest of your script.

### `bashdep::install_from`

Read a dependency list from a file and install every entry. Blank lines
and lines starting with `#` are ignored; leading/trailing whitespace per
line is stripped.

```bash
bashdep::install_from .bashdep
```

Example `.bashdep`:

```
# Runtime
https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr

# Dev tools
https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh@dev
```

Returns `1` if the file argument is missing or unreadable; otherwise
returns the same failure count as `bashdep::install`.

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

Print every dependency recorded in the lockfiles under `dir` and `dev-dir`.
One entry per line, tab-separated: `<path>\t<source URL>`. Pass extra
directories as positional arguments to include their lockfiles too.

```bash
bashdep::list
# lib/bashunit	https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
# lib/create-pr	https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr
# lib/dev/dumper.sh	https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh
```

### `bashdep::version`

Print the bashdep version.

```bash
bashdep::version  # 0.3.0
```

## Behavior

### Skip vs. force re-download

`bashdep::install` is idempotent **per source URL**, not per filename. The
first install writes a `.bashdep.lock` file in each destination directory
recording every dependency's source URL:

```
# lib/.bashdep.lock
bashunit	https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
create-pr	https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr
```

On subsequent runs, a dependency is skipped only when the file is present
**and** the lockfile records the same URL. Bumping a release in the URL
(e.g. `0.17.0` → `0.18.0`) triggers a re-download even though the basename
is unchanged.

Pass `force=true` to refresh regardless of the lockfile:

```bash
bashdep::setup force=true
bashdep::install "${DEPENDENCIES[@]}"
```

Commit `.bashdep.lock` alongside your install script so collaborators get the
same versions you do.

### Dev dependencies

A URL ending in `@dev` is treated as a development-only dependency and
installed into `dev-dir` instead of `dir`:

```bash
DEPENDENCIES=(
  "https://example.com/runtime.sh"          # → lib/
  "https://example.com/dev-tool.sh@dev"     # → lib/dev/
)
```

### Error handling

- `download_url` returns `1` and prints to stderr on `curl` failure or missing URL.
- `install` keeps going through the list and returns the number of failures.
- `setup_directory` returns `1` if it cannot create the destination dir.

Use `set -e` plus `bashdep::install ... || exit $?` to fail fast in scripts.

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
