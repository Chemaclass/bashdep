# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `<dest>/.bashdep.lock` records the source URL of each installed dependency.
- Internal helpers `bashdep::_lock_get` / `bashdep::_lock_set`.
- `bashdep::setup` with `dir`, `dev-dir`, `silent`, `force` parameters.
- `@dev` URL suffix routes a dependency to `dev-dir`.
- `bashdep::version` prints the current version.

### Changed

- `bashdep::install` is now idempotent **per source URL**, not per filename.
  A release bump (e.g. `0.17.0` → `0.18.0`) re-downloads even when the
  basename is unchanged.
- Pre-existing files without a lock entry are re-downloaded once on first
  run after upgrade to populate the lockfile.
- Strict error handling: `download_url` / `setup_directory` return non-zero
  on failure; `install` returns the failure count.
- `BASHDEP_VERSION` set to `0.3.0` (in-tree; not yet released).

## [0.1]

- Initial release: declarative `bashdep::install` over a list of URLs.

[Unreleased]: https://github.com/Chemaclass/bashdep/compare/0.1...HEAD
[0.1]: https://github.com/Chemaclass/bashdep/releases/tag/0.1
