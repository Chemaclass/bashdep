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

## Common bashunit Assertions

```bash
assert_equals "expected" "$actual"
assert_not_equals "not_this" "$actual"
assert_contains "substring" "$haystack"
assert_not_contains "substring" "$haystack"
assert_matches "regex" "$string"
assert_empty "$var"
assert_not_empty "$var"
assert_successful_code "$?"
assert_general_error "$?"
assert_file_exists "$path"
assert_file_not_exists "$path"
assert_directory_exists "$path"
assert_match_snapshot "$output"
```

## Lifecycle Hooks (already wired in `tests/unit/bashdep_test.sh`)

```bash
function set_up() {
  source "$(current_dir)/../../bashdep"
  BASHDEP_FORCE=false
  BASHDEP_SILENT=false
  BASHDEP_DRY_RUN=false
  BASHDEP_VERBOSE=false
  TEST_DIR=$(mktemp -d)
}

function tear_down() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
```

Always reset `BASHDEP_*` globals in `set_up` so tests don't leak state.

## Test Fixtures

Two helpers at the top of `tests/unit/bashdep_test.sh`:

```bash
# Lockfile entry only.
_seed_lock "$TEST_DIR" "file_name" "https://example.com/url"

# Lockfile entry + the on-disk file.
_seed_installed "$TEST_DIR" "file_name" "https://example.com/url"
```

Use these instead of writing lockfile lines by hand — they keep the
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
- No shared global state between tests — always reset `BASHDEP_*` in `set_up`
- **No network calls** — mock or stub `curl`. Set
  `BASHDEP_DRY_RUN=true` if you only need to assert what *would* happen
- No real `release.sh` invocations from tests
- Tests must be safe to run in any order

## Mocking `curl`

bashdep's only network surface is `curl`. To test install paths without
hitting the network, either:

1. Set `BASHDEP_DRY_RUN=true` and assert on the `[dry-run] Would …` log, or
2. Define a `curl` shell function in the test that writes a fixture file
    and returns 0:

```bash
function curl() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o) printf 'fixture\n' > "$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  return 0
}
```

## Reference Tests

- **Pure logic:** top of `tests/unit/bashdep_test.sh`
  (`test_bashdep_classify_dep_*`)
- **Filesystem:** `_seed_installed` / `_seed_lock`-based tests further down
- **Snapshot:** `test_bashdep_*_snapshot` tests
