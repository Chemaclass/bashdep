# templates

Reusable, zero-runtime release tooling for GitHub-hosted bash projects,
extracted from bashdep's own release flow. bashdep **dogfoods** these —
`./release.sh` at the repo root is a thin wrapper around
[`release.sh`](release.sh) driven by [`../release.conf`](../release.conf),
so what you copy is exactly what ships bashdep.

| File | Purpose |
| --- | --- |
| [`release.sh`](release.sh) | Generic release engine — validate → bump → roll CHANGELOG → gate → build → commit + tag → push → GitHub release. Project-agnostic; never edit it. |
| [`release.conf.example`](release.conf.example) | Documented config template. Copy to your repo root as `release.conf`. |
| [`build.sh`](build.sh) | Amalgamator — inline `source`d files into one executable script (a release asset). |

## Use it in your project

```bash
# From your repo root:
mkdir -p templates
curl -fsSLo templates/release.sh \
  https://raw.githubusercontent.com/Chemaclass/bashdep/main/templates/release.sh
curl -fsSLo templates/build.sh \
  https://raw.githubusercontent.com/Chemaclass/bashdep/main/templates/build.sh
curl -fsSLo release.conf \
  https://raw.githubusercontent.com/Chemaclass/bashdep/main/templates/release.conf.example
chmod +x templates/release.sh templates/build.sh
```

Edit `release.conf` (see below), then run from the repo root:

```bash
bash templates/release.sh --dry-run     # preview
bash templates/release.sh               # auto-bump minor, cut the release
bash templates/release.sh 1.4.0         # explicit version
```

Optionally add a one-line `./release.sh` wrapper like bashdep's so
`./release.sh` and `make release` just work — see the repo root
[`release.sh`](../release.sh).

## Configuration

`release.conf` is sourced by the engine. Two hooks and one list are
required; everything else defaults.

| Setting | Required | Default | Purpose |
| --- | :---: | --- | --- |
| `release_version_read()` | ✅ | — | Echo the current version. |
| `release_version_write()` | ✅ | — | Write `$1` as the new version. |
| `RELEASE_COMMIT_PATHS=(…)` | ✅ | — | Files the release commit stages (version file + CHANGELOG). |
| `RELEASE_REPO` | | `git remote` | `owner/repo` on GitHub. |
| `RELEASE_GATE` | | `make test` | Pre-release gate command (`""` skips). |
| `RELEASE_CHANGELOG` | | `CHANGELOG.md` | Keep-a-Changelog file (`""` skips rolling). |
| `RELEASE_ASSETS=(…)` | | none | Files uploaded to the release. |
| `release_build()` | | no-op | Produce `RELEASE_ASSETS`. `sha256_of <file>` is provided. |
| `release_notes()` | | generic | GitHub release body (`$VERSION` available). |

## Flags

Same as bashdep's release: `--major` / `--minor` / `--patch`, `--dry-run`,
`--force`, `--no-gh`, `--trust-ci`, `--remote=NAME`, `--config=FILE`.

## Requirements

`git` and `awk` always; `gh` for the GitHub release step (skip with
`--no-gh`); `shasum` or `sha256sum` only if your `release_build` checksums
assets. Run from the repo root — the engine uses paths relative to the
current directory.

## Amalgamating a multi-file project — `build.sh`

`build.sh` turns an entry script that `source`s helpers into one
self-contained executable, suitable as a `RELEASE_ASSETS` entry:

```bash
templates/build.sh src/main.sh > dist/mytool
```

It inlines **static, top-level** `source ./path` / `. ./path` directives
(recursively, each file once). It deliberately does **not** follow dynamic
includes — `source "$var"`, command substitution in the path, or `source`
inside a function/conditional — those lines are left as-is. Keep includes
static and top-level for a clean bundle.
