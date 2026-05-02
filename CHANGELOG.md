# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-05-02

### Added

- Per-destination `.bashdep.lock` file recording the source URL of each
  installed dependency. `bashdep::install` now uses the lockfile to make the
  install idempotent **per source URL** rather than per filename.
- New internal helpers `bashdep::_lock_get` and `bashdep::_lock_set` to
  read and upsert entries in the lockfile.

### Changed

- `bashdep::download_url` re-downloads a dependency when its source URL
  changes (e.g. a release version bump), even if a file with the same
  basename already exists. Previously, a version bump was silently skipped
  because the on-disk filename had not changed.
- A pre-existing destination file with no matching lockfile entry is now
  re-downloaded once to record its source URL. This is a one-time cost on
  upgrade from 0.2.x and ensures the lockfile stays authoritative.
- Bumped `BASHDEP_VERSION` to `0.3.0`.

## [0.2.0]

### Added

- `force=true` setup parameter to refresh dependencies even when the file
  already exists.
- `@dev` URL suffix to route a dependency to the dev directory.

[Unreleased]: https://github.com/Chemaclass/bashdep/compare/0.3.0...HEAD
[0.3.0]: https://github.com/Chemaclass/bashdep/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/Chemaclass/bashdep/releases/tag/0.2.0
