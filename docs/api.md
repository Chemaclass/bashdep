# API reference

Public functions exposed by `source lib/bashdep`. For lockfile rules,
dev-dependency routing, and error semantics see [Behavior](behavior.md).

- [CLI](#cli)
- [`bashdep::install`](#bashdepinstall)
- [`bashdep::install_from`](#bashdepinstall_from)
- [`bashdep::uninstall`](#bashdepuninstall)
- [`bashdep::clean`](#bashdepclean)
- [`bashdep::doctor`](#bashdepdoctor)
- [`bashdep::self_update`](#bashdepself_update)
- [`bashdep::setup`](#bashdepsetup)
- [`bashdep::list`](#bashdeplist)
- [`bashdep::version`](#bashdepversion)

## CLI

Every command is also available by executing the script directly —
no `source` needed:

```bash
./lib/bashdep install                      # install from ./.bashdep
./lib/bashdep install https://example.com/tool.sh
./lib/bashdep list
./lib/bashdep uninstall tool.sh
./lib/bashdep clean --dry-run
./lib/bashdep doctor
./lib/bashdep self-update
./lib/bashdep --help
```

Options map 1:1 to [`bashdep::setup`](#bashdepsetup) parameters:
`--dir=DIR`, `--dev-dir=DIR`, `--force`, `--dry-run`, `--silent`,
`--verbose`. `install` also accepts `--file=FILE` to point at a
dependency file other than `.bashdep`.

Exit codes match the underlying function's return value (e.g. `doctor`
exits with the issue count), so the CLI drops into CI pipelines as-is.
Sourcing the script never triggers the CLI.

## `bashdep::install`

Download each dependency in the list into the configured directories.

```bash
DEPENDENCIES=(
  "https://example.com/runtime.sh"
  "https://example.com/dev-tool.sh@dev"
)
bashdep::install "${DEPENDENCIES[@]}"
```

Returns the number of failed downloads (0 on success, capped at 255).

## `bashdep::install_from`

Read a dependency list from a file and install every entry. One URL per
line; blank lines and `#` comments are ignored; leading/trailing
whitespace is stripped. Defaults to `.bashdep` in the current directory
when called without arguments.

```bash
bashdep::install_from            # reads ./.bashdep
bashdep::install_from deps.txt   # reads a custom file
```

Example `.bashdep`:

```
# Runtime
https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr

# Dev tools
https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh@dev
```

Returns `1` if the file is missing or unreadable; otherwise propagates
the failure count from `bashdep::install`.

## `bashdep::uninstall`

Remove one or more installed dependencies. Searches `dir` and `dev-dir`,
deletes the file, and drops the matching `.bashdep.lock` entry. The
lockfile is removed once it has no entries left.

```bash
bashdep::uninstall create-pr dumper.sh
```

Returns the number of names not found (0 on full success). In dry-run
mode, prints intended actions without touching disk.

## `bashdep::clean`

Remove orphan files in each managed directory: anything not recorded in
`.bashdep.lock` (and not the lockfile itself). Directories without a
lockfile are left alone — bashdep treats a missing lockfile as "this
dir is unmanaged".

```bash
bashdep::clean
```

Always returns 0. Honors dry-run mode.

## `bashdep::doctor`

Check each managed directory for inconsistencies. Reports two kinds of
issues:

- Lockfile entries whose file is missing on disk.
- Files on disk with no lockfile entry.

```bash
bashdep::doctor
# checking 'lib'...
#   missing file for 'create-pr' (url: https://...)
#   orphan file 'lib/leftover.sh' (no lockfile entry)
# doctor: 2 issue(s) found
```

Returns the issue count (capped at 255). Useful in CI to catch lockfile
drift after manual edits or merge conflicts.

## `bashdep::self_update`

Re-download the bashdep script itself from upstream and replace the
local copy via an atomic `mv`. Defaults to the `main` branch.

```bash
bashdep::self_update            # main branch
bashdep::self_update 0.4.0      # specific tag/branch
```

The download URL is built from `BASHDEP_SELF_URL_TEMPLATE` (a printf
format string with one `%s` slot for the ref). After updating, re-source
the script to load the new version. Honors dry-run mode.

## `bashdep::setup`

Configure defaults before calling `install`. All parameters are optional.

| Param     | Type   | Default   | Purpose                                                |
| --------- | ------ | --------- | ------------------------------------------------------ |
| `dir`     | string | `lib`     | Destination for normal dependencies.                   |
| `dev-dir` | string | `lib/dev` | Destination for dev dependencies (URLs ending `@dev`). |
| `silent`  | bool   | `false`   | Suppress progress output.                              |
| `force`   | bool   | `false`   | Re-download even when the file already exists.         |
| `dry-run` | bool   | `false`   | Preview actions without writing to disk.               |
| `verbose` | bool   | `false`   | Emit extra context (URLs on skip, lockfile path).      |

```bash
bashdep::setup dir="vendor" dev-dir="src/dev" silent=true force=false
```

Invalid values (unknown param, non-boolean for `silent`/`force`) cause
`setup` to print an error to stderr and return `1`.

## `bashdep::list`

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

## `bashdep::version`

Print the bashdep version.

```bash
bashdep::version  # e.g. 0.4.2
```
