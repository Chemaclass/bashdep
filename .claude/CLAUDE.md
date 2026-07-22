# bashdep - Bash Dependency Manager

## Project Overview

**bashdep** is a minimal, zero-runtime bash dependency manager. Declare URLs in
`.bashdep`; bashdep downloads them into `lib/` and keeps installs idempotent
via a per-directory `.bashdep.lock`. No registry, no daemon — just `curl` +
`awk` + `mktemp`.

**Repo:** https://github.com/Chemaclass/bashdep

## Core Principles

### TDD by Default
**RED → GREEN → REFACTOR** — every change starts from a failing test. The
`tests/unit/bashdep_test.sh` suite is the only safety net; keep it green.

### Bash 3.2+ Compatible

The library must run on **macOS default bash (3.2)** as well as Linux bash 4+.
`[[ ]]` is allowed (Bash 3.2+); avoid features that need 4.0+:

- `declare -A` (associative arrays)
- `${var,,}` / `${var^^}` (case conversion)
- `${array[-1]}` (negative indexing — needs 4.3+)
- `&>>` (append both streams)
- `mapfile` / `readarray`

See `.claude/rules/bash-style.md` (auto-loaded when editing `bashdep` or any
`*.sh`).

### Zero Runtime Dependencies

Library code may only call: `curl` (or `wget` as a fallback), `awk`,
`mktemp`, `mkdir`, `rm`, `cp`, `mv`, `printf`, `cat`, `grep`, `sort`,
`tr`, `dirname`, `basename`, plus shell builtins. **No** `jq`, `python`,
`node`, etc. at runtime.

### Quality Standards

Every change must pass:
```bash
make test    # bashunit suite
make sa      # ShellCheck
make lint    # editorconfig-checker
```

`make pre_commit/run` runs all three.

## Architecture

```
bashdep/
├── bashdep                    # Library entry point — sourced by consumers
├── release.sh                 # Release automation (see docs/releasing.md)
├── install-dependencies.sh    # Installs the test runner via bashdep itself
├── Makefile                   # test / sa / lint / deps / release
├── tests/
│   ├── bootstrap.sh          # Shared test helpers
│   └── unit/
│       ├── bashdep_test.sh   # The unit suite
│       └── snapshots/        # Captured stdout for snapshot assertions
├── docs/
│   ├── api.md                # Public function reference
│   ├── behavior.md           # Lockfile / dev-dep / error semantics
│   └── releasing.md          # Release process
├── example/                  # End-to-end demo
├── lib/                      # Vendored test runner (bashunit) — git-ignored
├── .claude/                  # Claude Code configuration
│   ├── CLAUDE.md            # This file
│   ├── rules/               # Path-scoped guidelines
│   └── skills/              # Custom workflows (invoke with /skill-name)
└── .github/workflows/        # CI: tests, ShellCheck, editorconfig
```

## Public API Surface

All public functions live in the single `bashdep` script under the
`bashdep::` namespace:

| Function | Purpose |
|----------|---------|
| `bashdep::install` | Install from an inline URL array |
| `bashdep::install_from` | Install from a `.bashdep` file |
| `bashdep::setup` | Configure dirs / modes (`force`, `dry-run`, `silent`, `verbose`) |
| `bashdep::list` | List installed deps |
| `bashdep::uninstall` | Remove specific deps |
| `bashdep::clean` | Remove orphan files (in dir, not in lockfile) |
| `bashdep::doctor` | Report missing/orphan inconsistencies |
| `bashdep::self_update` | Re-download `bashdep` from upstream |
| `bashdep::version` | Print `BASHDEP_VERSION` |
| `bashdep::main` | CLI dispatcher (runs when the script is executed, not sourced) |
| `bashdep::usage` | Print CLI usage/help text |

Private helpers use a leading `_` (`bashdep::_classify_dep`, `_lock_get`, …).

## Common Commands

```bash
make test                       # Run the suite
make pre_commit/run             # test + sa + lint
make deps                       # Install bashunit (test runner)
lib/bashunit tests              # Run bashunit directly
lib/bashunit tests --filter NAME  # Run a single test by name
./bashdep --help                # CLI usage (when invoked, not sourced)
```

## Test Patterns

`tests/unit/bashdep_test.sh` is split into two layers:

1. **Pure-logic tests** (top of file) — no filesystem, no network. Set
    `BASHDEP_*` globals directly and call `bashdep::_*` helpers.
2. **Filesystem tests** — use `$TEST_DIR` (a `mktemp -d` set up in
    `set_up`, cleaned in `tear_down`). Use the `_seed_lock` /
    `_seed_installed` helpers to scaffold lockfile fixtures.

**Snapshot tests** keep hardcoded `/tmp/test_<name>` paths because the
snapshot embeds the path. Don't migrate those to `$TEST_DIR`.

Test fixtures must never reach the network — mock or stub `curl`.

## Skills

Invoke with `/skill-name`:

| Skill | Purpose |
|-------|---------|
| `/tdd-cycle` | RED → GREEN → REFACTOR for a single test |
| `/fix-test` | Debug and fix failing tests |
| `/add-command` | Add a new `bashdep::` lifecycle command with TDD |
| `/doctor-check` | Coverage gap analysis + `bashdep::doctor` audit |
| `/pre-release` | Pre-release validation checklist |
| `/release` | Run pre-release checks then execute `release.sh` |
| `/commit` | Stage and commit with conventional commits |
| `/gh-issue <N>` | GitHub issue → branch → implement → PR |
| `/pr [#N]` | Push branch and open a PR |

## Path-Scoped Guidelines

Rules auto-load based on file paths being edited (via `paths:` frontmatter
in each rule file).

### `bashdep` and `**/*.sh`
- Bash 3.2+ compatible (no associative arrays, no `${var,,}`)
- Public functions in `bashdep::` namespace, private with leading `_`
- 2-space indent, quote variables, `$()` not backticks
- Pass `make sa` (ShellCheck)

### `tests/**/*_test.sh`
- One assertion per test; name describes behavior
- Pure-logic tests above filesystem tests
- Use `$TEST_DIR` from `set_up`, never `/tmp/...` (except snapshot tests)
- Mock `curl` — no real network calls
- Snapshot updates: `lib/bashunit --update-snapshots tests/`

### `docs/**/*.md`
- Reflect the actual public API in `bashdep` — no inventing flags
- Cross-link `api.md` ↔ `behavior.md` ↔ `releasing.md` where relevant
- Keep examples copy-pasteable and runnable

## Guardrails

### Never:
- Add a runtime dependency beyond `curl` / `wget` / `awk` / `mktemp` / POSIX builtins
- Break Bash 3.2+ compatibility (test on macOS default bash mentally)
- Change public function signatures without updating `docs/api.md` and `CHANGELOG.md`
- Skip `make pre_commit/run` before pushing
- Network in tests
- Commit `lib/`, `local/`, or `tmp/` artifacts
- Commit without a corresponding test for behavior changes

### Always:
- Write a failing test first
- Use existing patterns in `tests/unit/bashdep_test.sh`
- Update `CHANGELOG.md` `## Unreleased` section for any user-visible change
- Update `docs/api.md` when adding/changing a public `bashdep::` function
- Update `docs/behavior.md` when changing lockfile / dev-dep / error semantics
- Honor `BASHDEP_DRY_RUN`, `BASHDEP_SILENT`, `BASHDEP_VERBOSE`, `BASHDEP_FORCE` in any new mutating command

## Definition of Done

- All tests green for the **right reason**
- `make sa` passes (ShellCheck)
- `make lint` passes (editorconfig-checker)
- Bash 3.2+ compatible
- `CHANGELOG.md` updated (if user-facing)
- `docs/api.md` / `docs/behavior.md` updated (if API or semantics changed)
- Modes (`dry-run`, `silent`, `verbose`, `force`) honored in any new mutating path

## Commit Message Format

[Conventional Commits](https://conventionalcommits.org/): `<type>(<scope>): <description>`

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`
**Scopes:** `install`, `lock`, `doctor`, `clean`, `uninstall`, `setup`, `cli`, `docs`, `ci`, `release`

Never mention AI / Claude / automation in commit messages.

## Prohibited Actions

**Never without explicit user request:**
- Commit secrets or `.env` contents
- Force push to `main`
- Skip git hooks (`--no-verify`)
- Amend published commits
- Use destructive git commands (`reset --hard`, `clean -f`, `branch -D`)
- Push to remote without confirmation
- Cut a release (only via `/release` after explicit user confirmation)
