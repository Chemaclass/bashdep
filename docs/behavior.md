# Behavior

How bashdep decides what to download, where to put it, and when to
skip. For function signatures and the CLI see the
[API reference](api.md).

- [Lockfile and idempotency](#lockfile-and-idempotency)
- [Dev dependencies](#dev-dependencies)
- [Error handling](#error-handling)

## Lockfile and idempotency

`bashdep::install` is idempotent **per source URL**, not per filename.
Each destination directory gets a `.bashdep.lock` recording the URL of
every dependency installed there:

```
# lib/.bashdep.lock
bashunit	https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit
create-pr	https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr
```

### Skip rules

| File present | Lock URL matches | `force` | Action      |
| :----------: | :--------------: | :-----: | ----------- |
|     yes      |       yes        |   no    | skip        |
|     yes      |        no        |   no    | re-download |
|      no      |        —         |    —    | re-download |
|     yes      |       yes        |   yes   | re-download |

Bumping a release in the URL (`0.17.0` → `0.18.0`) re-downloads the
affected entry only; nothing else is touched.

### Recommended workflow

Commit `.bashdep.lock` alongside your install script so collaborators
get the same versions you do. Rotate by editing the URL in your
dependency list (or `.bashdep` file) and re-running install — the
lockfile updates automatically.

## Dev dependencies

A URL ending in `@dev` routes to `dev-dir` instead of `dir`:

```bash
DEPENDENCIES=(
  "https://example.com/runtime.sh"        # → lib/
  "https://example.com/dev-tool.sh@dev"   # → lib/dev/
)
```

Each directory keeps its own `.bashdep.lock`. `bashdep::list` reads
both by default.

## Error handling

- `bashdep::install` continues past failed downloads and returns the
  failure count (capped at 255).
- `bashdep::install_from` returns `1` if the file (default: `.bashdep`)
  is missing or unreadable.
- `bashdep::setup` returns `1` on unknown params or non-boolean values
  for `silent` / `force`.
- `bashdep::clean` returns the number of orphans it could not remove
  (capped at 255), reporting each failed removal to stderr; `0` when all
  orphans were removed.
- Downloads use `curl` when available and fall back to `wget`; if neither
  is installed the download fails with exit `127`.
- Download failures print the downloader's exit code to stderr (e.g. curl
  `22` = HTTP error, `6` = DNS, `7` = connect refused).

Pair with `set -euo pipefail` and `|| exit $?` to fail fast:

```bash
#!/bin/bash
set -euo pipefail

source lib/bashdep
bashdep::install_from .bashdep || exit $?
```
