#!/bin/bash
# shellcheck disable=SC2155,SC2034
#
# Unit tests for release.sh. The script is sourced (guarded by its
# BASH_SOURCE check) to exercise individual functions — main() never runs
# and no release is ever cut. Functions that call `exit` on failure are
# invoked inside a subshell so the exit does not kill the test runner.

TEST_DIR=""

function set_up() {
  # Source once; release.sh declares readonly globals, so re-sourcing in the
  # same process would error. The guard makes it idempotent.
  if ! declare -f build_asset >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source "$(current_dir)/../../release.sh"
  fi
  # release.sh enables `set -euo pipefail` at source time; drop it so tests
  # can assert on non-zero return codes normally.
  set +e +u +o pipefail
  DRY_RUN=false
  REPO_ROOT="$(cd "$(current_dir)/../.." && pwd)"
  TEST_DIR=$(mktemp -d)
}

function tear_down() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# --- bump_version_string -----------------------------------------------------

function test_release_bump_version_major() {
  assert_equals "1.0.0" "$(bump_version_string 0.4.2 major)"
}

function test_release_bump_version_minor() {
  assert_equals "0.5.0" "$(bump_version_string 0.4.2 minor)"
}

function test_release_bump_version_patch() {
  assert_equals "0.4.3" "$(bump_version_string 0.4.2 patch)"
}

function test_release_bump_version_minor_resets_patch() {
  assert_equals "1.3.0" "$(bump_version_string 1.2.9 minor)"
}

# --- sha256_of ---------------------------------------------------------------

function test_release_sha256_of_records_basename_not_path() {
  printf 'payload\n' > "$TEST_DIR/asset"
  local line
  line=$(sha256_of "$TEST_DIR/asset")
  assert_matches "^[0-9a-f]{64}[[:space:]]+asset$" "$line"
}

# --- unreleased_has_content --------------------------------------------------

function test_release_unreleased_has_content_true_with_entry() {
  printf '## [Unreleased]\n\n### Added\n- a thing\n\n## [0.1]\n' \
    > "$TEST_DIR/CHANGELOG.md"
  ( cd "$TEST_DIR" && unreleased_has_content )
  assert_successful_code "$?"
}

function test_release_unreleased_has_content_false_when_only_headings() {
  printf '## [Unreleased]\n\n### Added\n\n### Changed\n\n## [0.1]\n' \
    > "$TEST_DIR/CHANGELOG.md"
  ( cd "$TEST_DIR" && unreleased_has_content )
  assert_general_error
}

# --- build_asset -------------------------------------------------------------

function test_release_build_asset_produces_binary_and_checksum() {
  cp "$REPO_ROOT/bashdep" "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && build_asset ) >/dev/null 2>&1

  assert_file_exists "$TEST_DIR/dist/bashdep"
  assert_file_exists "$TEST_DIR/dist/checksum"
}

function test_release_build_asset_binary_is_executable() {
  cp "$REPO_ROOT/bashdep" "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && build_asset ) >/dev/null 2>&1
  [[ -x "$TEST_DIR/dist/bashdep" ]]
  assert_successful_code "$?"
}

function test_release_build_asset_checksum_matches_binary() {
  cp "$REPO_ROOT/bashdep" "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && build_asset ) >/dev/null 2>&1

  local stored expected
  stored=$(cat "$TEST_DIR/dist/checksum")
  expected=$(cd "$TEST_DIR" && sha256_of dist/bashdep)
  assert_equals "$expected" "$stored"
}

function test_release_build_asset_fails_on_invalid_syntax() {
  printf 'if [ ( broken\n' > "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && build_asset ) >/dev/null 2>&1
  assert_general_error
}

function test_release_build_asset_dry_run_writes_nothing() {
  cp "$REPO_ROOT/bashdep" "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && DRY_RUN=true && build_asset ) >/dev/null 2>&1

  assert_file_not_exists "$TEST_DIR/dist/bashdep"
  assert_file_not_exists "$TEST_DIR/dist/checksum"
}
