# bashdep

[![Tests](https://github.com/Chemaclass/bashdep/actions/workflows/tests.yml/badge.svg)](https://github.com/Chemaclass/bashdep/actions/workflows/tests.yml)
[![Static Analysis](https://github.com/Chemaclass/bashdep/actions/workflows/static_analysis.yml/badge.svg)](https://github.com/Chemaclass/bashdep/actions/workflows/static_analysis.yml)
[![Lint](https://github.com/Chemaclass/bashdep/actions/workflows/linter.yml/badge.svg)](https://github.com/Chemaclass/bashdep/actions/workflows/linter.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Minimal, zero-dependency **bash dependency manager**. Declare URLs;
bashdep downloads them into `lib/` and keeps installs idempotent via a
per-directory `.bashdep.lock`. No registry, no runtime — just `curl`.

```bash
mkdir -p lib
curl -fsSLo lib/bashdep https://raw.githubusercontent.com/Chemaclass/bashdep/main/bashdep
chmod +x lib/bashdep
```

## Quick start

`.bashdep`:

```
https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr
https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh@dev
```

`install-dependencies.sh`:

```bash
#!/bin/bash
set -euo pipefail

source lib/bashdep
bashdep::install_from .bashdep
```

First run downloads everything and writes `.bashdep.lock`. Re-runs skip
already-installed deps; bumping a URL version re-downloads only that
entry. Commit `.bashdep.lock` to lock versions across collaborators.

Prefer an inline array? Pass it to `bashdep::install` directly.

## Why bashdep?

- **Idempotent installs** via per-directory `.bashdep.lock`.
- **Dev/prod separation** via the `@dev` URL suffix (`lib/` vs `lib/dev/`).
- **File-driven or array-driven** — `install_from` or `install`.
- **Lifecycle commands** — `list`, `uninstall`, `clean`, `doctor`,
  `self_update`.
- **Modes** — `force`, `dry-run`, `silent`, `verbose`.

## Documentation

- [**API reference**](docs/api.md) — `install`, `install_from`, `setup`,
  `list`, `version`.
- [**Behavior**](docs/behavior.md) — lockfile rules, dev dependencies,
  error handling.
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
