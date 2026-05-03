# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed

## [0.4.2] - 2026-05-03

### Added

### Changed

### Fixed

## [0.4.1] - 2026-05-03

### Added

### Changed

### Fixed

## [0.4.0] - 2026-05-03

### Added

- `bashdep::uninstall <file...>` removes a dep file plus its lockfile
  entry; drops the lockfile when its last entry is gone.
- `bashdep::clean` removes orphan files (in dir, not in lockfile).
  Skips directories without a lockfile.
- `bashdep::doctor` reports lockfile/filesystem inconsistencies
  (missing files, orphan files). Returns the issue count.
- `bashdep::self_update [ref] [target]` refreshes the bashdep script
  from upstream via atomic `mv`. URL configurable via
  `BASHDEP_SELF_URL_TEMPLATE`.
- `dry-run=true` setup parameter previews actions without writing.
- `verbose=true` setup parameter logs extra context (URLs on skip,
  lockfile path on install). Suppressed by `silent=true`.
- Dedicated `docs/` folder split out of README: `docs/api.md` (full API
  reference) and `docs/behavior.md` (lockfile, dev deps, error handling).
- `bashdep::install_from <file>` reads a dependency list from disk; blank
  lines and `#` comments are ignored.
- `release.sh` automates cutting a tagged release: bumps
  `BASHDEP_VERSION`, rolls `CHANGELOG.md`, runs the test/sa/lint gates,
  commits, tags, pushes, and creates a GitHub release with the `bashdep`
  script attached as an asset. With no positional arg it auto-bumps the
  minor version (`--major` / `--patch` switch the level). Also accepts
  an explicit `X.Y.Z`. Supports `--dry-run`, `--force`, `--no-gh`,
  `--remote=NAME`. Wired up via `make release` / `make release/dry-run`.
  See `docs/releasing.md`.
- `bashdep::list` prints every installed dependency from the lockfiles
  under `dir` and `dev-dir` (tab-separated `<path>\t<URL>` lines).
- `bashdep::setup` accepts `dir`, `dev-dir`, `silent`, `force` parameters.
- `bashdep::version` prints the current version.
- `@dev` URL suffix routes a dependency to `dev-dir`.
- Per-directory `.bashdep.lock` records the source URL of each installed
  dependency.

### Changed

- `bashdep::install` is idempotent **per source URL**, not per filename.
  A release bump (e.g. `0.17.0` → `0.18.0`) re-downloads even when the
  basename is unchanged. Pre-existing files without a lock entry are
  re-downloaded once after upgrade to populate the lockfile.
- `bashdep::install` returns the failure count, capped at 255.
- `download_url` surfaces the `curl` exit code in its error message.
- Strict error handling: `download_url` / `setup_directory` return
  non-zero on failure.

## [0.1]

- Initial release: declarative `bashdep::install` over a list of URLs.

[Unreleased]: https://github.com/Chemaclass/bashdep/compare/0.4.2...HEAD
[0.4.2]: https://github.com/Chemaclass/bashdep/compare/0.4.1...0.4.2
[0.4.1]: https://github.com/Chemaclass/bashdep/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/Chemaclass/bashdep/compare/0.3.0...0.4.0
[0.1]: https://github.com/Chemaclass/bashdep/releases/tag/0.1
