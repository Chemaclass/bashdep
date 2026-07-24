#!/bin/bash
# shellcheck disable=SC2155,SC2034
#
# Unit tests for the release engine (templates/release.sh) and bashdep's
# own config (release.conf). Both are sourced — the engine is guarded by
# its BASH_SOURCE check so main() never runs and no release is ever cut.
# Functions that call `exit` on failure are invoked inside a subshell so
# the exit does not kill the test runner.

TEST_DIR=""

function set_up() {
  # Source once; re-sourcing in the same process is harmless but avoided.
  # The engine + bashdep's release.conf (release_build, release_version_*).
  if ! declare -f bump_version_string >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source "$(current_dir)/../../templates/release.sh"
    # shellcheck disable=SC1091
    source "$(current_dir)/../../release.conf"
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

# --- derive_repo -------------------------------------------------------------

function test_release_derive_repo_from_ssh_remote() {
  mock git "echo git@github.com:owner/repo.git"
  assert_equals "owner/repo" "$(derive_repo)"
}

function test_release_derive_repo_from_https_remote() {
  mock git "echo https://github.com/owner/repo.git"
  assert_equals "owner/repo" "$(derive_repo)"
}

function test_release_derive_repo_from_https_remote_without_dot_git() {
  mock git "echo https://github.com/owner/repo"
  assert_equals "owner/repo" "$(derive_repo)"
}

# --- --trust-ci gate-skip decision -------------------------------------------

function test_release_should_skip_gates_false_without_trust_ci() {
  TRUST_CI=false
  should_skip_gates
  assert_general_error
}

function test_release_should_skip_gates_true_when_ci_green() {
  TRUST_CI=true
  mock ci_head_conclusion "echo success"
  should_skip_gates
  assert_successful_code "$?"
}

function test_release_should_skip_gates_false_when_ci_failed() {
  TRUST_CI=true
  mock ci_head_conclusion "echo failure"
  should_skip_gates
  assert_general_error
}

function test_release_should_skip_gates_false_when_ci_pending() {
  TRUST_CI=true
  mock ci_head_conclusion "echo pending"
  should_skip_gates
  assert_general_error
}

# Fail-safe: a CI lookup that could not determine a green run (yields "none")
# must NOT skip the gates, even under --trust-ci. Guards against the gate
# ever failing open.
function test_release_should_skip_gates_false_when_ci_lookup_fails() {
  TRUST_CI=true
  mock ci_head_conclusion "echo none"
  should_skip_gates
  assert_general_error
}

function test_release_ci_head_conclusion_returns_gh_output() {
  mock git "echo deadsha"
  mock gh "echo success"
  assert_equals "success" "$(ci_head_conclusion)"
}

# Fail-safe: when the gh lookup itself fails (network/auth/rate-limit), the
# conclusion must fall back to "none" — the conservative value that makes
# should_skip_gates run the gates. It must never surface as "success".
function test_release_ci_head_conclusion_returns_none_when_gh_fails() {
  mock git "echo deadsha"
  mock gh "return 1"
  assert_equals "none" "$(ci_head_conclusion)"
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

# --- config: version read/write (bashdep's release.conf) ---------------------

function test_release_version_read_reads_from_bashdep_file() {
  printf 'BASHDEP_VERSION="1.2.3"\n#!/bin/bash\n' > "$TEST_DIR/bashdep"
  assert_equals "1.2.3" "$(cd "$TEST_DIR" && release_version_read)"
}

function test_release_version_write_updates_bashdep_file() {
  printf 'BASHDEP_VERSION="1.2.3"\nother="x"\n' > "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && release_version_write 2.0.0 )
  assert_equals "2.0.0" "$(cd "$TEST_DIR" && release_version_read)"
}

function test_release_version_write_leaves_no_backup_file() {
  printf 'BASHDEP_VERSION="1.2.3"\n' > "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && release_version_write 2.0.0 )
  assert_file_not_exists "$TEST_DIR/bashdep.bak"
}

# --- config: release_build (bashdep's release.conf) --------------------------

function test_release_build_produces_binary_and_checksum() {
  cp "$REPO_ROOT/bashdep" "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && release_build ) >/dev/null 2>&1

  assert_file_exists "$TEST_DIR/dist/bashdep"
  assert_file_exists "$TEST_DIR/dist/checksum"
}

function test_release_build_binary_is_executable() {
  cp "$REPO_ROOT/bashdep" "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && release_build ) >/dev/null 2>&1
  [[ -x "$TEST_DIR/dist/bashdep" ]]
  assert_successful_code "$?"
}

function test_release_build_checksum_matches_binary() {
  cp "$REPO_ROOT/bashdep" "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && release_build ) >/dev/null 2>&1

  local stored expected
  stored=$(cat "$TEST_DIR/dist/checksum")
  expected=$(cd "$TEST_DIR" && sha256_of dist/bashdep)
  assert_equals "$expected" "$stored"
}

function test_release_build_fails_on_invalid_syntax() {
  printf 'if [ ( broken\n' > "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && release_build ) >/dev/null 2>&1
  assert_general_error
}

# --- engine: build_step dry-run ----------------------------------------------

function test_release_build_step_dry_run_writes_nothing() {
  cp "$REPO_ROOT/bashdep" "$TEST_DIR/bashdep"
  ( cd "$TEST_DIR" && DRY_RUN=true && ASSETS=() && build_step ) >/dev/null 2>&1
  [[ ! -d "$TEST_DIR/dist" ]]
  assert_successful_code "$?"
}
