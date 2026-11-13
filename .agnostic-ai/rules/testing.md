---
paths:
  - "tests/**/*_test.sh"
  - "tests/bootstrap.sh"
---

# Testing Guidelines

## Organization

bashdep currently has a single test layer:

| Directory | Purpose | Pattern |
|-----------|---------|---------|
| `tests/unit/` | Behavior tests for `bashdep::*` functions | Pure-logic on top, filesystem-using below |
| `tests/unit/snapshots/` | Captured stdout for snapshot assertions | Hardcoded `/tmp/test_<name>` paths |

**Naming:** Files end with `_test.sh`. Functions:
`test_bashdep_<thing>_<behavior_or_failure_mode>`.

Pure-logic tests live above filesystem tests in
`tests/unit/bashdep_test.sh`. Keep that ordering when adding new tests.

## Assertions

Use bashunit's `assert_equals`, `assert_not_equals`, `assert_contains`,
`assert_not_contains`, `assert_matches`, `assert_empty`, `assert_not_empty`,
`assert_successful_code`, `assert_general_error`, file/directory existence
assertions, and `assert_match_snapshot` as appropriate. One assertion per test;
name each test for its behavior.

## Lifecycle Hooks

`set_up` in `tests/unit/bashdep_test.sh` sources `bashdep`, resets all four mode
globals to `false`, and creates `$TEST_DIR` with `mktemp -d`. `tear_down` removes
that directory when it exists. Keep these resets so tests cannot leak state.

## Test Fixtures

Two helpers at the top of `tests/unit/bashdep_test.sh`:

```bash
# Lockfile entry only.
_seed_lock "$TEST_DIR" "file_name" "https://example.com/url"

# Lockfile entry + the on-disk file.
_seed_installed "$TEST_DIR" "file_name" "https://example.com/url"
```

Use these instead of writing lockfile lines by hand - they keep the
on-disk format consistent.

## Snapshot Tests

Snapshot tests assert that stdout matches `tests/unit/snapshots/<name>`.
Update with:

```bash
lib/bashunit --update-snapshots tests/
```

**Important:** snapshot tests embed the temp path into the snapshot, so
they keep hardcoded `/tmp/test_<name>` paths. Do **not** migrate them to
`$TEST_DIR`.

## Test Isolation

- Use `$TEST_DIR` (per-test `mktemp -d`) for filesystem tests
- No shared global state between tests - always reset `BASHDEP_*` in `set_up`
- **No network calls** - mock or stub `curl`. Set
  `BASHDEP_DRY_RUN=true` if you only need to assert what *would* happen
- No real `release.sh` invocations from tests
- Tests must be safe to run in any order

## The `mock` / `unmock` helpers

`mock` and `unmock` are defined by **this repo** in `tests/bootstrap.sh`,
not by bashunit. bashunit >= 0.40 moved its doubles under
`bashunit::mock` and made the multi-argument form append `"$@"` to the
body, which cannot express a mock body that reads positional arguments -
the shape this suite uses everywhere:

```bash
mock curl 'touch "$3"'          # body sees the real call's arguments
mock bashdep::download_url "return 1"
mock curl <<< "payload"         # no body: echo stdin instead
```

Each bashunit test runs in its own subshell, so mocks cannot leak between
tests and need no registry - `unmock` is only for restoring a real
command *within* a single test.

## Mocking `curl`

For installation tests, use `BASHDEP_DRY_RUN=true` and assert the log, or define
`curl` as a shell function that writes a fixture to the requested output path
and returns success. Keep real network calls out of tests.

## Reference Tests

- **Pure logic:** top of `tests/unit/bashdep_test.sh`
  (`test_bashdep_classify_dep_*`)
- **Filesystem:** `_seed_installed` / `_seed_lock`-based tests further down
- **Snapshot:** `test_bashdep_*_snapshot` tests
