# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed

- `bashdep::setup` and `bashdep::install` no longer leak their loop
  variables (`param`, `dep`) into the sourcing shell's global scope.

## [0.5.0] - 2026-07-20

### Added

- **CLI**: `bashdep` now runs as an executable, not only when sourced.
  Dispatches `install`, `list`, `uninstall`, `clean`, `doctor`,
  `self-update`, `version`, and `help`. Flags mirror `bashdep::setup`
  (`--dir`, `--dev-dir`, `--force`, `--dry-run`, `--silent`,
  `--verbose`), plus `--file=FILE` for `install`. Exit codes propagate
  from the underlying functions; sourcing stays side-effect-free.
- Releases now ship a `checksum` (sha256) asset alongside the `bashdep`
  script so downloads can be verified.

### Changed

- `bashdep::install_from` defaults to `.bashdep` in the current
  directory when called with no argument (previously required a path).

## [0.4.2] - 2026-05-03

First usable 0.4 release. Supersedes the yanked 0.4.0 and 0.4.1 — see
[Yanked releases](#yanked-releases) below.

### Added

- `bashdep::install_from <file>` reads a dependency list from disk; blank
  lines and `#` comments are ignored, leading/trailing whitespace stripped.
- `bashdep::list` prints every installed dependency from the lockfiles
  under `dir` and `dev-dir` (tab-separated `<path>\t<URL>` lines).
- `bashdep::uninstall <file...>` removes a dep file plus its lockfile
  entry; drops empty lockfiles after the last entry is gone.
- `bashdep::clean` removes orphan files (in dir, not in lockfile).
  Skips directories without a lockfile and never removes the bashdep
  script itself.
- `bashdep::doctor` reports lockfile/filesystem inconsistencies
  (missing files, orphan files). Returns the issue count, capped at 255.
- `bashdep::self_update [ref] [target]` refreshes the bashdep script
  from upstream via atomic `mv`. URL configurable via
  `BASHDEP_SELF_URL_TEMPLATE`.
- `bashdep::version` prints the current version.
- `dry-run=true` setup parameter previews actions without writing.
- `verbose=true` setup parameter logs extra context (URLs on skip,
  lockfile path on install). Suppressed by `silent=true`.
- `bashdep::setup` accepts `dir`, `dev-dir`, `silent`, `force`,
  `dry-run`, `verbose` parameters.
- `@dev` URL suffix routes a dependency to `dev-dir`.
- Per-directory `.bashdep.lock` records the source URL of each installed
  dependency.
- Dedicated `docs/` folder split out of README: `docs/api.md` (full API
  reference), `docs/behavior.md` (lockfile, dev deps, error handling),
  `docs/releasing.md` (release process).
- `release.sh` automates cutting a tagged release: bumps
  `BASHDEP_VERSION`, rolls `CHANGELOG.md`, runs the test/sa/lint gates,
  commits, tags, pushes, and creates a GitHub release with the `bashdep`
  script attached as an asset. With no positional arg it auto-bumps the
  minor version (`--major` / `--patch` switch the level). Supports
  `--dry-run`, `--force`, `--no-gh`, `--remote=NAME`. Wired up via
  `make release` / `make release/dry-run`. See `docs/releasing.md`.

### Changed

- `bashdep::install` is idempotent **per source URL**, not per filename.
  A release bump (e.g. `0.17.0` → `0.18.0`) re-downloads even when the
  basename is unchanged. Pre-existing files without a lock entry are
  re-downloaded once after upgrade to populate the lockfile.
- `bashdep::install` returns the failure count, capped at 255.
- `download_url` surfaces the `curl` exit code in its error message
  (e.g. `22` HTTP error, `6` DNS, `7` connect refused).
- Strict error handling: `download_url` / `setup_directory` return
  non-zero on failure.

### Fixed

- `bashdep::clean` and `bashdep::doctor` now skip the running bashdep
  script (matched by `BASH_SOURCE` basename), so the README's
  recommended `lib/bashdep` layout no longer triggers `clean` to delete
  the tool or `doctor` to flag it as an orphan. *(was broken in 0.4.0)*
- `bashdep::_vlog` returns 0 when verbose is off — previously the
  trailing `&&` short-circuit propagated rc=1 out of `download_url`,
  causing `install` and `install_from` to return the install count as a
  "failure count" on every successful run. *(was broken in 0.4.0 and
  0.4.1)*

## Yanked releases

- **[0.4.1] - 2026-05-03 — YANKED**: ships the clean/doctor self-exclusion
  fix but still contains the `_vlog` rc bug; `install_from` returns
  non-zero on success when verbose is off. Use 0.4.2.
- **[0.4.0] - 2026-05-03 — YANKED**: ships every listed feature but
  contains both bugs above. Use 0.4.2.

GitHub release assets for 0.4.0 and 0.4.1 have been removed; their
download URLs return 404. Git tags are preserved for history.

## [0.1]

- Initial release: declarative `bashdep::install` over a list of URLs.

[Unreleased]: https://github.com/Chemaclass/bashdep/compare/0.5.0...HEAD
[0.5.0]: https://github.com/Chemaclass/bashdep/compare/0.4.2...0.5.0
[0.4.2]: https://github.com/Chemaclass/bashdep/compare/0.1...0.4.2
[0.4.1]: https://github.com/Chemaclass/bashdep/compare/0.1...0.4.1
[0.4.0]: https://github.com/Chemaclass/bashdep/compare/0.1...0.4.0
[0.1]: https://github.com/Chemaclass/bashdep/releases/tag/0.1
