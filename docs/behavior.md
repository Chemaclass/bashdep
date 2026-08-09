# Behavior

How bashdep decides what to download, where to put it, and when to skip. For function signatures and the CLI see the [API reference](api.md).

- [Lockfile and idempotency](#lockfile-and-idempotency)
- [Dev dependencies](#dev-dependencies)
- [Checksum verification](#checksum-verification-opt-in)
- [Error handling](#error-handling)
- [Gotchas](#gotchas)

## Lockfile and idempotency

`bashdep::install` is idempotent **per source URL**, not per filename. Each destination directory gets a `.bashdep.lock` recording the URL of every dependency installed there:

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

Bumping a release in the URL (`0.17.0` → `0.18.0`) re-downloads the affected entry only; nothing else is touched.

### Recommended workflow

Commit `.bashdep.lock` alongside your install script so collaborators get the same versions you do. Rotate by editing the URL in your dependency list (or `.bashdep` file) and re-running install — the lockfile updates automatically.

## Dev dependencies

A URL ending in `@dev` routes to `dev-dir` instead of `dir`:

```bash
DEPENDENCIES=(
  "https://example.com/runtime.sh"        # → lib/
  "https://example.com/dev-tool.sh@dev"   # → lib/dev/
)
```

Each directory keeps its own `.bashdep.lock`. `bashdep::list` reads both by default.

## Checksum verification (opt-in)

Append `#sha256=<hex>` to a dependency URL to have bashdep verify the download's SHA-256 before recording it:

```
https://example.com/tool.sh#sha256=e3b0c44298fc1c149afbf4c8996fb924...
https://example.com/dev-tool.sh@dev#sha256=2c26b46b68ffc68ff99b453c...
```

The annotation is stripped before download (`curl`/`wget` never see it) and can combine with the `@dev` suffix. On a mismatch — or when neither `shasum` nor `sha256sum` is available — the download fails, the file is removed, and no lockfile entry is written. A present-but-empty or non-hex annotation (e.g. `#sha256=`) is rejected before download rather than silently skipping the check. Without the annotation, nothing is verified (the default).

## Error handling

- `bashdep::install` downloads in parallel (up to `BASHDEP_JOBS`, default `4`; use `1` for sequential). `BASHDEP_JOBS` is also settable via `bashdep::setup jobs=N` or the CLI's `--jobs=N`. It must be a non-negative integer; a non-numeric or otherwise invalid value is rejected with a warning and the default of `4` is used. It continues past failed downloads and returns the failure count (capped at 255). Lockfile writes are batched into a single rewrite per directory after all downloads finish, so concurrency never corrupts the lockfile.
- `bashdep::install_from` returns `1` if the file (default: `.bashdep`) is missing or unreadable.
- `bashdep::setup` returns `1` on unknown params or non-boolean values for `silent` / `force`.
- `bashdep::clean` returns the number of orphans it could not remove (capped at 255), reporting each failed removal to stderr; `0` when all orphans were removed.
- Downloads use `curl` when available and fall back to `wget`; if neither is installed the download fails with exit `127`.
- Download failures print the downloader's exit code to stderr (e.g. curl `22` = HTTP error, `6` = DNS, `7` = connect refused).

Pair with `set -euo pipefail` and `|| exit $?` to fail fast:

```bash
#!/bin/bash
set -euo pipefail

source lib/bashdep
bashdep::install_from .bashdep || exit $?
```

## Gotchas

Known boundaries of the flat, URL-driven model — by design, not bugs:

- **A dependency's identity is its filename** — the last path segment of the URL. Two URLs ending in the same basename (`.../v1/util.sh` and `.../v2/util.sh`) resolve to the same file in the same directory: the second overwrites the first and the lockfile keeps a single entry. Disambiguate by routing one to `@dev`, pointing it at another `dir`, or renaming upstream.
- **The lockfile pins the source URL, not a checksum.** Idempotency and `doctor` drift detection compare URLs; integrity is enforced only when you add an explicit `#sha256=` annotation, which is re-checked on every download.
- **No transitive resolution.** bashdep installs exactly the URLs you list — a dependency cannot declare its own dependencies. List the full set yourself.
