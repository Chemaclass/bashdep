---
name: add-command
description: Add a new bashdep:: lifecycle command with TDD
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# Add Command Skill

Add a new public `bashdep::` lifecycle command (sibling of `install`,
`uninstall`, `clean`, `doctor`, `list`, `self_update`) following strict TDD.

## Prerequisites

1. **Task file** — create `.tasks/YYYY-MM-DD-add-<command>.md`
2. **Read the existing commands** — `bashdep` is a single file; scan how
    `bashdep::clean`, `bashdep::doctor`, `bashdep::uninstall` are
    structured to match style
3. **Read the API doc** — `docs/api.md` defines the public contract; the
    new command's signature must fit the same shape

## Workflow

### 1. Plan

Decide with the user:
- Command name (`bashdep::<verb>`)
- Arguments (positional vs `key=value` like `bashdep::setup`)
- Mutating? If yes, must honor `BASHDEP_DRY_RUN`, `BASHDEP_SILENT`,
  `BASHDEP_VERBOSE`, `BASHDEP_FORCE`
- Lockfile interaction (read / write / both / none)
- Exit codes (0 success, 1 validation/IO failure)
- Logging surface (`bashdep::_log` / `bashdep::_vlog`)

Document acceptance criteria + test inventory in the task file.

### 2. Study Existing Patterns

Read the closest sibling command in `bashdep` and its tests in
`tests/unit/bashdep_test.sh`. Reuse helpers: `bashdep::_classify_dep`,
`bashdep::_lock_get`, `bashdep::_lock_remove`, `bashdep::is_dry_run`.

### 3. TDD Cycles

For each test in the inventory, follow RED → GREEN → REFACTOR:

1. **Happy path** — pure-logic test if possible (no filesystem)
2. **Filesystem path** — use `$TEST_DIR` + `_seed_*` helpers
3. **Mode coverage** — one test each for `dry-run`, `silent`, `verbose`,
    `force` if the command is mutating
4. **Failure modes** — bad arguments, missing lockfile, IO error
5. **Snapshot test** for any new user-visible output

### 4. Integration

- Add the public function near the bottom of `bashdep` (after the
  existing public commands, before any trailing CLI dispatch)
- Add a CLI dispatch case if `bashdep` is invoked as an executable for
  this command
- Run full suite: `make test`
- Quality gate: `make pre_commit/run`

### 5. Documentation

- Add the function to `docs/api.md` with usage, arguments, return codes,
  and a worked example
- Update `docs/behavior.md` if the command introduces new lockfile or
  filesystem semantics
- Update `CHANGELOG.md` `## Unreleased` under `### Added`
- Update the public-API table in `.claude/CLAUDE.md`
- Update `README.md` Quick Start if the command is part of the typical
  workflow

## Final Checklist

- [ ] All tests passing (happy path, failure modes, mode flags, snapshot)
- [ ] Function namespaced `bashdep::` and documented in `docs/api.md`
- [ ] Mutating? Modes honored (`dry-run` / `silent` / `verbose` / `force`)
- [ ] Quality gate passes (`make pre_commit/run`)
- [ ] Bash 3.2+ compatible
- [ ] `CHANGELOG.md` updated
- [ ] Task file completed
