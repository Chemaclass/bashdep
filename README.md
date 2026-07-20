# bashdep

[![Release](https://img.shields.io/github/v/release/Chemaclass/bashdep?sort=semver)](https://github.com/Chemaclass/bashdep/releases/latest)
[![Tests](https://github.com/Chemaclass/bashdep/actions/workflows/tests.yml/badge.svg)](https://github.com/Chemaclass/bashdep/actions/workflows/tests.yml)
[![Static Analysis](https://github.com/Chemaclass/bashdep/actions/workflows/static_analysis.yml/badge.svg)](https://github.com/Chemaclass/bashdep/actions/workflows/static_analysis.yml)
[![Lint](https://github.com/Chemaclass/bashdep/actions/workflows/linter.yml/badge.svg)](https://github.com/Chemaclass/bashdep/actions/workflows/linter.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Minimal, zero-dependency **bash dependency manager**. Declare URLs;
bashdep downloads them into `lib/` and keeps installs idempotent via a
per-directory `.bashdep.lock`. No registry, no runtime — just `curl`.

## Quick start

**1. Vendor bashdep into your repo:**

```bash
mkdir -p lib
curl -fsSLo lib/bashdep https://raw.githubusercontent.com/Chemaclass/bashdep/main/bashdep
chmod +x lib/bashdep
```

Prefer a pinned, verifiable version? Grab a tagged release and check it
against the published `checksum`:

```bash
curl -fsSLo lib/bashdep https://github.com/Chemaclass/bashdep/releases/latest/download/bashdep
curl -fsSLo checksum     https://github.com/Chemaclass/bashdep/releases/latest/download/checksum
( cd lib && shasum -a 256 -c ../checksum ) && chmod +x lib/bashdep
```

**2. Declare your dependencies in a `.bashdep` file** (one URL per
line; `#` comments allowed; `@dev` suffix routes to `lib/dev/`):

```
https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr
https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh@dev
```

**3. Install:**

```bash
./lib/bashdep install
```

That's it. The first run downloads everything and writes
`.bashdep.lock`. Re-runs skip already-installed deps; bumping a URL
version re-downloads only that entry. Commit `.bashdep.lock` to lock
versions across collaborators.

Everyday commands:

```bash
./lib/bashdep list             # what's installed (path + source URL)
./lib/bashdep doctor           # detect lockfile drift
./lib/bashdep clean --dry-run  # preview orphan removal
./lib/bashdep --help           # all commands and flags
```

### Or source it from a script

Prefer a programmatic setup (custom dirs, inline arrays)? Source
bashdep and call the same functions:

```bash
#!/bin/bash
set -euo pipefail

source lib/bashdep
bashdep::install_from   # reads ./.bashdep
```

See the [API reference](docs/api.md) for `bashdep::setup`,
`bashdep::install`, and friends.

## Why bashdep?

- **Idempotent installs** via per-directory `.bashdep.lock`.
- **Dev/prod separation** via the `@dev` URL suffix (`lib/` vs `lib/dev/`).
- **File-driven, array-driven, or CLI** — `install_from`, `install`, or
  `./lib/bashdep <command>`.
- **Lifecycle commands** — `list`, `uninstall`, `clean`, `doctor`,
  `self_update`.
- **Modes** — `force`, `dry-run`, `silent`, `verbose`.

## Documentation

- [**API reference**](docs/api.md) — `install`, `install_from`, `setup`,
  `list`, `uninstall`, `clean`, `doctor`, `self_update`, `version`.
- [**Behavior**](docs/behavior.md) — lockfile rules, dev dependencies,
  error handling.
- [**Releasing**](docs/releasing.md) — how maintainers cut a new tagged
  release with `release.sh`.
- [**Contributing**](.github/CONTRIBUTING.md) — project layout, test
  conventions, coding guidelines.

## Development

```bash
make deps              # Install bashunit (test runner)
make test              # Run the suite
make sa                # ShellCheck
make lint              # editorconfig-checker
make pre_commit/install
```

See [CONTRIBUTING](.github/CONTRIBUTING.md) for the full guide.
