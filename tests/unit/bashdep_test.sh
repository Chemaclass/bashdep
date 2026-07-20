#!/bin/bash
# shellcheck disable=SC2155,SC2034,SC2153

TEST_DIR=""

function set_up() {
  # shellcheck disable=SC1091
  source "$(current_dir)/../../bashdep"
  BASHDEP_FORCE=false
  BASHDEP_SILENT=false
  BASHDEP_DRY_RUN=false
  BASHDEP_VERBOSE=false
  TEST_DIR=$(mktemp -d)
  BASHDEP_BIN="$(cd "$(current_dir)/../.." && pwd)/bashdep"
}

function tear_down() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# Test fixture: create a "previously installed" dependency at $1 with file
# $2 and lockfile entry pointing to $3. Returns the destination dir path.
function _seed_installed() {
  local dir=$1 file_name=$2 url=$3
  touch "$dir/$file_name"
  printf '%s\t%s\n' "$file_name" "$url" > "$dir/.bashdep.lock"
}

# Test fixture: write a lockfile entry mapping $2 -> $3 in dir $1.
function _seed_lock() {
  local dir=$1 file_name=$2 url=$3
  printf '%s\t%s\n' "$file_name" "$url" > "$dir/.bashdep.lock"
}

# Pure tests — no filesystem, no network.

function test_bashdep_classify_dep_routes_normal_url_to_dir() {
  BASHDEP_DIR=lib BASHDEP_DEV_DIR=lib/dev BASHDEP_DEV_SUFFIX=@dev
  bashdep::_classify_dep "https://example.com/foo"
  assert_equals "https://example.com/foo" "$BASHDEP_DEP_URL"
  assert_equals "lib"                     "$BASHDEP_DEP_DIR"
}

function test_bashdep_classify_dep_routes_dev_suffix_to_dev_dir() {
  BASHDEP_DIR=lib BASHDEP_DEV_DIR=lib/dev BASHDEP_DEV_SUFFIX=@dev
  bashdep::_classify_dep "https://example.com/foo@dev"
  assert_equals "https://example.com/foo" "$BASHDEP_DEP_URL"
  assert_equals "lib/dev"                 "$BASHDEP_DEP_DIR"
}

function test_bashdep_classify_dep_strips_only_trailing_suffix() {
  BASHDEP_DIR=lib BASHDEP_DEV_DIR=lib/dev BASHDEP_DEV_SUFFIX=@dev
  bashdep::_classify_dep "https://example.com/@dev/foo"
  assert_equals "https://example.com/@dev/foo" "$BASHDEP_DEP_URL"
  assert_equals "lib"                          "$BASHDEP_DEP_DIR"
}

function test_bashdep_classify_dep_honors_overridden_dirs() {
  BASHDEP_DIR=vendor BASHDEP_DEV_DIR=src/dev BASHDEP_DEV_SUFFIX=@dev
  bashdep::_classify_dep "https://example.com/foo@dev"
  assert_equals "https://example.com/foo" "$BASHDEP_DEP_URL"
  assert_equals "src/dev"                 "$BASHDEP_DEP_DIR"
}

function test_bashdep_is_silent_true_when_var_true() {
  BASHDEP_SILENT=true
  bashdep::is_silent
  assert_successful_code "$?"
}

function test_bashdep_is_silent_false_when_var_false() {
  BASHDEP_SILENT=false
  bashdep::is_silent
  assert_general_error
}

function test_bashdep_is_force_true_when_var_true() {
  BASHDEP_FORCE=true
  bashdep::is_force
  assert_successful_code "$?"
}

function test_bashdep_is_force_false_when_var_false() {
  BASHDEP_FORCE=false
  bashdep::is_force
  assert_general_error
}

function test_bashdep_is_dry_run_true_when_var_true() {
  BASHDEP_DRY_RUN=true
  bashdep::is_dry_run
  assert_successful_code "$?"
}

function test_bashdep_is_dry_run_false_when_var_false() {
  BASHDEP_DRY_RUN=false
  bashdep::is_dry_run
  assert_general_error
}

function test_bashdep_setup_dry_run_true_makes_is_dry_run_truthy() {
  bashdep::setup dry-run=true
  bashdep::is_dry_run
  assert_successful_code "$?"
}

function test_bashdep_download_url_dry_run_skips_curl_and_lockfile() {
  mock curl "echo SHOULD_NOT_RUN"
  bashdep::setup dry-run=true

  local output
  output=$(bashdep::download_url "https://example.com/tool" "$TEST_DIR")

  assert_not_contains "SHOULD_NOT_RUN" "$output"
  assert_contains     "[dry-run]"      "$output"
  assert_file_not_exists "$TEST_DIR/tool"
  assert_file_not_exists "$TEST_DIR/.bashdep.lock"
}

function test_bashdep_is_verbose_true_when_var_true() {
  BASHDEP_VERBOSE=true
  bashdep::is_verbose
  assert_successful_code "$?"
}

function test_bashdep_is_verbose_false_when_var_false() {
  BASHDEP_VERBOSE=false
  bashdep::is_verbose
  assert_general_error
}

function test_bashdep_setup_verbose_true_makes_is_verbose_truthy() {
  bashdep::setup verbose=true
  bashdep::is_verbose
  assert_successful_code "$?"
}

function test_bashdep_download_url_verbose_logs_url_on_skip() {
  local url="https://example.com/tool"
  _seed_installed "$TEST_DIR" tool "$url"
  bashdep::setup verbose=true

  local output
  output=$(bashdep::download_url "$url" "$TEST_DIR")
  assert_contains "skipping"     "$output"
  assert_contains "url: $url"    "$output"
}

function test_bashdep_download_url_verbose_logs_lockfile_after_install() {
  # shellcheck disable=SC2016
  mock curl 'touch "$4"'
  bashdep::setup verbose=true

  local output
  output=$(bashdep::download_url "https://example.com/tool" "$TEST_DIR")
  assert_contains "lockfile: $TEST_DIR/.bashdep.lock" "$output"
}

function test_bashdep_download_url_silent_overrides_verbose() {
  local url="https://example.com/tool"
  _seed_installed "$TEST_DIR" tool "$url"
  bashdep::setup verbose=true silent=true

  local output
  output=$(bashdep::download_url "$url" "$TEST_DIR")
  assert_empty "$output"
}

function test_bashdep_download_url_dry_run_still_skips_when_lock_matches() {
  local url="https://example.com/tool"
  _seed_installed "$TEST_DIR" tool "$url"
  mock curl "echo SHOULD_NOT_RUN"
  bashdep::setup dry-run=true

  local output
  output=$(bashdep::download_url "$url" "$TEST_DIR")

  assert_not_contains "SHOULD_NOT_RUN" "$output"
  assert_not_contains "[dry-run]"       "$output"
  assert_contains     "skipping"        "$output"
}

function test_bashdep_log_prints_when_not_silent() {
  BASHDEP_SILENT=false
  assert_equals "hello world" "$(bashdep::_log hello world)"
}

function test_bashdep_log_silent_when_silent_enabled() {
  BASHDEP_SILENT=true
  assert_empty "$(bashdep::_log hello world)"
}

function test_bashdep_setup_persists_dir() {
  bashdep::setup dir=custom_lib
  assert_equals "custom_lib" "$BASHDEP_DIR"
}

function test_bashdep_setup_persists_dev_dir() {
  bashdep::setup dev-dir=custom_dev
  assert_equals "custom_dev" "$BASHDEP_DEV_DIR"
}

function test_bashdep_setup_silent_true_makes_is_silent_truthy() {
  bashdep::setup silent=true
  bashdep::is_silent
  assert_successful_code "$?"
}

function test_bashdep_setup_force_true_makes_is_force_truthy() {
  bashdep::setup force=true
  bashdep::is_force
  assert_successful_code "$?"
}

function test_bashdep_setup_rejects_invalid_bool() {
  bashdep::setup silent=maybe 2>/dev/null
  assert_general_error
}

function test_bashdep_setup_rejects_unknown_param() {
  bashdep::setup unknown=value 2>/dev/null
  assert_general_error
}

function test_bashdep_setup_unknown_param_error_message() {
  local err
  err=$(bashdep::setup unknown=value 2>&1)
  assert_contains "unknown=value" "$err"
}

function test_bashdep_setup_invalid_bool_error_message() {
  local err
  err=$(bashdep::setup silent=maybe 2>&1)
  assert_contains "silent" "$err"
  assert_contains "maybe"  "$err"
}

function test_bashdep_version_is_set() {
  assert_not_empty "$(bashdep::version)"
}

function test_bashdep_version_returns_semver() {
  assert_matches "^[0-9]+\.[0-9]+\.[0-9]+$" "$(bashdep::version)"
}

function test_bashdep_set_bool_accepts_true() {
  local var=initial
  bashdep::_set_bool var true label
  assert_equals "true" "$var"
}

function test_bashdep_set_bool_accepts_false() {
  local var=initial
  bashdep::_set_bool var false label
  assert_equals "false" "$var"
}

function test_bashdep_set_bool_rejects_other_values() {
  local var=initial
  bashdep::_set_bool var maybe label 2>/dev/null
  assert_general_error
}

function test_bashdep_set_bool_error_includes_label_and_value() {
  local err
  err=$(bashdep::_set_bool var bogus mylabel 2>&1)
  assert_contains "mylabel" "$err"
  assert_contains "bogus"   "$err"
}

function test_bashdep_setup_does_not_leak_loop_variable() {
  unset param
  bashdep::setup dir="lib"
  assert_empty "${param:-}"
}

function test_bashdep_install_does_not_leak_loop_variable() {
  unset dep
  BASHDEP_DRY_RUN=true
  bashdep::install "https://example.com/foo.sh" >/dev/null
  assert_empty "${dep:-}"
}

function test_bashdep_install_caps_failure_count_at_255() {
  mock bashdep::setup_directory "return 0"
  mock bashdep::download_url "return 1"

  local deps=()
  local i
  for ((i = 0; i < 300; i++)); do
    deps+=("https://example.com/$i")
  done

  bashdep::install "${deps[@]}"
  assert_equals 255 "$?"
}

function test_bashdep_download_url_requires_url() {
  bashdep::download_url "" "/tmp" 2>/dev/null
  assert_general_error
}

# Lockfile tests — use an isolated mktemp lockfile (TEST_DIR-scoped).

function test_bashdep_lock_get_returns_url_for_filename() {
  local lock_file="$TEST_DIR/lock"
  {
    printf 'bashunit\thttps://example.com/bashunit\n'
    printf 'create-pr\thttps://example.com/create-pr\n'
  } > "$lock_file"

  assert_equals "https://example.com/bashunit"  "$(bashdep::_lock_get "$lock_file" bashunit)"
  assert_equals "https://example.com/create-pr" "$(bashdep::_lock_get "$lock_file" create-pr)"
  assert_empty                                  "$(bashdep::_lock_get "$lock_file" missing)"
}

function test_bashdep_lock_get_returns_empty_when_lockfile_missing() {
  assert_empty "$(bashdep::_lock_get "$TEST_DIR/nonexistent" foo)"
}

function test_bashdep_lock_get_returns_empty_when_entry_missing() {
  local lock_file="$TEST_DIR/lock"
  printf 'other\thttps://example.com/other\n' > "$lock_file"
  assert_empty "$(bashdep::_lock_get "$lock_file" missing)"
}

function test_bashdep_lock_set_upserts_entry() {
  local lock_file="$TEST_DIR/lock"

  bashdep::_lock_set "$lock_file" bashunit  https://example.com/0.17.0
  bashdep::_lock_set "$lock_file" bashunit  https://example.com/0.18.0
  bashdep::_lock_set "$lock_file" create-pr https://example.com/cpr

  assert_equals "https://example.com/0.18.0" "$(bashdep::_lock_get "$lock_file" bashunit)"
  assert_equals "https://example.com/cpr"    "$(bashdep::_lock_get "$lock_file" create-pr)"
}

function test_bashdep_lock_set_keeps_entries_sorted() {
  local lock_file="$TEST_DIR/lock"

  bashdep::_lock_set "$lock_file" zeta  https://example.com/zeta
  bashdep::_lock_set "$lock_file" alpha https://example.com/alpha
  bashdep::_lock_set "$lock_file" mu    https://example.com/mu

  local first second third
  first=$(awk -F '\t' 'NR==1 { print $1 }' "$lock_file")
  second=$(awk -F '\t' 'NR==2 { print $1 }' "$lock_file")
  third=$(awk -F '\t' 'NR==3 { print $1 }' "$lock_file")
  assert_equals "alpha" "$first"
  assert_equals "mu"    "$second"
  assert_equals "zeta"  "$third"
}

# Skip-decision tests — pure logic over a tiny seeded fixture.

function test_bashdep_should_skip_download_yes_when_lock_matches() {
  _seed_installed "$TEST_DIR" foo https://example.com/foo
  bashdep::_should_skip_download "$TEST_DIR/foo" "$TEST_DIR/.bashdep.lock" foo https://example.com/foo
  assert_successful_code "$?"
}

function test_bashdep_should_skip_download_no_when_url_differs() {
  _seed_installed "$TEST_DIR" foo https://example.com/foo-old
  bashdep::_should_skip_download "$TEST_DIR/foo" "$TEST_DIR/.bashdep.lock" foo https://example.com/foo-new
  assert_general_error
}

function test_bashdep_should_skip_download_no_when_file_missing() {
  _seed_lock "$TEST_DIR" foo https://example.com/foo
  bashdep::_should_skip_download "$TEST_DIR/foo" "$TEST_DIR/.bashdep.lock" foo https://example.com/foo
  assert_general_error
}

function test_bashdep_should_skip_download_no_when_force_enabled() {
  _seed_installed "$TEST_DIR" foo https://example.com/foo
  BASHDEP_FORCE=true
  bashdep::_should_skip_download "$TEST_DIR/foo" "$TEST_DIR/.bashdep.lock" foo https://example.com/foo
  assert_general_error
}

function test_bashdep_should_skip_download_no_when_lockfile_missing() {
  touch "$TEST_DIR/foo"
  bashdep::_should_skip_download "$TEST_DIR/foo" "$TEST_DIR/.bashdep.lock" foo https://example.com/foo
  assert_general_error
}

# _is_orphan predicate tests — shared by clean and doctor.

function test_bashdep_is_orphan_true_when_file_has_no_lock_entry() {
  _seed_lock "$TEST_DIR" tracked https://example.com/tracked
  touch "$TEST_DIR/orphan"
  bashdep::_is_orphan "$TEST_DIR/orphan" bashdep "$TEST_DIR/.bashdep.lock"
  assert_successful_code "$?"
}

function test_bashdep_is_orphan_false_when_file_has_lock_entry() {
  _seed_installed "$TEST_DIR" tracked https://example.com/tracked
  bashdep::_is_orphan "$TEST_DIR/tracked" bashdep "$TEST_DIR/.bashdep.lock"
  assert_general_error
}

function test_bashdep_is_orphan_false_for_lockfile_itself() {
  _seed_installed "$TEST_DIR" tracked https://example.com/tracked
  bashdep::_is_orphan "$TEST_DIR/.bashdep.lock" bashdep "$TEST_DIR/.bashdep.lock"
  assert_general_error
}

function test_bashdep_is_orphan_false_for_self_name() {
  _seed_lock "$TEST_DIR" tracked https://example.com/tracked
  touch "$TEST_DIR/bashdep"
  bashdep::_is_orphan "$TEST_DIR/bashdep" bashdep "$TEST_DIR/.bashdep.lock"
  assert_general_error
}

# setup_directory tests.

function test_bashdep_setup_directory() {
  local dir=$(temp_dir)
  assert_empty "$(bashdep::setup_directory "$dir")"
}

function test_bashdep_setup_directory_requires_arg() {
  bashdep::setup_directory "" 2>/dev/null
  assert_general_error
}

function test_bashdep_setup_directory_creates_missing_dir() {
  local dir="$TEST_DIR/created"
  bashdep::setup_directory "$dir"
  assert_directory_exists "$dir"
}

# install behavior — mocks setup_directory + download_url, no I/O.

function test_bashdep_install_custom_setup() {
  mock bashdep::setup_directory "return 0"
  mock bashdep::download_url "echo mocked download_url"
  bashdep::setup dir="vendor" dev-dir="src/dev" silent=true

  local DEPENDENCIES=(
    "https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
    "https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr"
    "https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh:lib/dev"
  )

  assert_match_snapshot "$(bashdep::install "${DEPENDENCIES[@]}")"
}

function test_bashdep_install_default_setup() {
  mock bashdep::setup_directory "return 0"
  mock bashdep::download_url "echo mocked download_url"

  local DEPENDENCIES=(
    "https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
    "https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr"
    "https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh:lib/dev"
  )

  assert_match_snapshot "$(bashdep::install "${DEPENDENCIES[@]}")"
}

function test_bashdep_install_returns_zero_when_all_succeed() {
  mock bashdep::setup_directory "return 0"
  mock bashdep::download_url "return 0"

  bashdep::install "https://example.com/a" "https://example.com/b"
  assert_successful_code "$?"
}

function test_bashdep_install_returns_failure_count() {
  mock bashdep::setup_directory "return 0"
  mock bashdep::download_url "return 1"

  bashdep::install "https://example.com/a" "https://example.com/b"
  assert_equals 2 "$?"
}

function test_bashdep_install_counts_setup_directory_failures() {
  mock bashdep::setup_directory "return 1"
  mock bashdep::download_url "return 0"

  bashdep::install "https://example.com/a" 2>/dev/null
  assert_equals 1 "$?"
}

function test_bashdep_install_routes_dev_suffix_to_dev_dir() {
  mock bashdep::setup_directory "return 0"
  # shellcheck disable=SC2016 # Single quotes intentional: $1/$2 expand inside mock body, not here.
  mock bashdep::download_url 'printf "%s -> %s\n" "$1" "$2"'
  bashdep::setup dir=lib_x dev-dir=dev_y

  local output
  output=$(bashdep::install \
    "https://example.com/runtime" \
    "https://example.com/devtool@dev")

  assert_contains "https://example.com/runtime -> lib_x" "$output"
  assert_contains "https://example.com/devtool -> dev_y" "$output"
}

# download_url snapshot tests — keep hardcoded /tmp paths since snapshots
# embed them. Each test cleans up explicitly.

function test_bashdep_download_url_default_dir() {
  local dir="/tmp/test_bashdep_download_url_default_dir"
  local url="fake.url"

  mkdir -p "$dir"
  BASHDEP_DIR="$dir"
  mock curl "echo mocked curl"

  assert_match_snapshot "$(bashdep::download_url "$url")"
  rm -rf "$dir"
}

function test_bashdep_download_url_custom_dir() {
  local url="https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  local dir="/tmp/test_bashdep_download_url_custom_dir"

  mkdir -p "$dir"
  mock curl "echo mocked curl"

  assert_match_snapshot "$(bashdep::download_url "$url" "$dir")"
  rm -rf "$dir"
}

function test_bashdep_download_url_skip_when_lock_matches() {
  local url="https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  local dir="/tmp/test_bashdep_download_url_skip_when_lock_matches"

  mkdir -p "$dir"
  _seed_installed "$dir" bashunit "$url"
  mock curl "echo mocked curl"

  assert_match_snapshot "$(bashdep::download_url "$url" "$dir")"
  rm -rf "$dir"
}

function test_bashdep_download_url_redownloads_when_url_changes() {
  local old_url="https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  local new_url="https://github.com/TypedDevs/bashunit/releases/download/0.18.0/bashunit"
  local dir="/tmp/test_bashdep_download_url_redownloads_when_url_changes"

  mkdir -p "$dir"
  _seed_installed "$dir" bashunit "$old_url"
  mock curl "echo mocked curl"

  assert_match_snapshot "$(bashdep::download_url "$new_url" "$dir")"
  assert_equals "$new_url" "$(bashdep::_lock_get "$dir/.bashdep.lock" bashunit)"

  rm -rf "$dir"
}

function test_bashdep_download_url_redownloads_when_lock_missing() {
  local url="https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  local dir="/tmp/test_bashdep_download_url_redownloads_when_lock_missing"

  mkdir -p "$dir"
  touch "$dir/bashunit"
  mock curl "echo mocked curl"

  assert_match_snapshot "$(bashdep::download_url "$url" "$dir")"
  assert_file_exists "$dir/.bashdep.lock"
  rm -rf "$dir"
}

function test_bashdep_download_url_force_redownload() {
  local url="https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  local dir="/tmp/test_bashdep_download_url_force_redownload"

  mkdir -p "$dir"
  _seed_installed "$dir" bashunit "$url"
  mock curl "echo mocked curl"
  bashdep::setup force=true

  assert_match_snapshot "$(bashdep::download_url "$url" "$dir")"
  rm -rf "$dir"
}

# download_url behavior tests — TEST_DIR-isolated.

function test_bashdep_download_url_silent_mode_no_progress_output() {
  mock curl "true"
  bashdep::setup silent=true

  local output
  output=$(bashdep::download_url "https://example.com/foo" "$TEST_DIR")
  assert_empty "$output"
}

function test_bashdep_download_url_silent_mode_skip_no_output() {
  local url="https://example.com/foo"
  _seed_installed "$TEST_DIR" foo "$url"
  bashdep::setup silent=true

  local output
  output=$(bashdep::download_url "$url" "$TEST_DIR")
  assert_empty "$output"
}

function test_bashdep_download_url_curl_failure_message_includes_exit_code() {
  mock curl "return 22"

  local err
  err=$(bashdep::download_url "https://example.com/dead" "$TEST_DIR" 2>&1 >/dev/null)
  assert_contains "exit 22" "$err"
}

function test_bashdep_download_url_curl_failure_returns_non_zero() {
  mock curl "return 7"
  bashdep::download_url "https://example.com/x" "$TEST_DIR" 2>/dev/null
  assert_general_error
}

function test_bashdep_download_url_returns_zero_on_success() {
  # shellcheck disable=SC2016
  mock curl 'touch "$4"'
  bashdep::download_url "https://example.com/tool" "$TEST_DIR" >/dev/null
  assert_successful_code "$?"
}

function test_bashdep_download_url_returns_zero_when_verbose_off() {
  # shellcheck disable=SC2016
  mock curl 'touch "$4"'
  BASHDEP_VERBOSE=false
  bashdep::download_url "https://example.com/tool" "$TEST_DIR" >/dev/null
  assert_successful_code "$?"
}

function test_bashdep_download_url_returns_zero_when_verbose_on() {
  # shellcheck disable=SC2016
  mock curl 'touch "$4"'
  BASHDEP_VERBOSE=true
  bashdep::download_url "https://example.com/tool" "$TEST_DIR" >/dev/null
  assert_successful_code "$?"
}

function test_bashdep_install_returns_zero_after_real_download() {
  # shellcheck disable=SC2016
  mock curl 'touch "$4"'
  BASHDEP_DIR="$TEST_DIR"
  bashdep::install "https://example.com/a" >/dev/null
  assert_successful_code "$?"
}

function test_bashdep_install_from_returns_zero_after_real_download() {
  local file="$TEST_DIR/.bashdep"
  printf 'https://example.com/a\n' > "$file"
  # shellcheck disable=SC2016
  mock curl 'touch "$4"'
  BASHDEP_DIR="$TEST_DIR"
  bashdep::install_from "$file" >/dev/null
  assert_successful_code "$?"
}

function test_bashdep_vlog_returns_zero_when_verbose_off() {
  BASHDEP_VERBOSE=false
  bashdep::_vlog hi
  assert_successful_code "$?"
}

function test_bashdep_vlog_returns_zero_when_verbose_on() {
  BASHDEP_VERBOSE=true
  bashdep::_vlog hi >/dev/null
  assert_successful_code "$?"
}

function test_bashdep_download_url_writes_lockfile_entry() {
  local url="https://example.com/tool"
  mock curl "true"

  bashdep::download_url "$url" "$TEST_DIR" >/dev/null

  assert_file_exists "$TEST_DIR/.bashdep.lock"
  assert_equals "$url" "$(bashdep::_lock_get "$TEST_DIR/.bashdep.lock" tool)"
}

function test_bashdep_download_url_chmod_makes_file_executable() {
  # download_url calls: curl -fsSL "$url" -o "$destination_file" — so $4 is the dest path.
  # shellcheck disable=SC2016 # Single quotes intentional: $4 expands inside mock body, not here.
  mock curl 'touch "$4"'
  bashdep::download_url "https://example.com/tool" "$TEST_DIR" >/dev/null
  [[ -x "$TEST_DIR/tool" ]]
  assert_successful_code "$?"
}

function test_bashdep_download_url_url_change_updates_lock() {
  local old_url="https://example.com/v1/tool"
  local new_url="https://example.com/v2/tool"
  _seed_installed "$TEST_DIR" tool "$old_url"
  mock curl "true"

  bashdep::download_url "$new_url" "$TEST_DIR" >/dev/null

  assert_equals "$new_url" "$(bashdep::_lock_get "$TEST_DIR/.bashdep.lock" tool)"
}

function test_bashdep_install_lockfile_contains_all_deps() {
  # shellcheck disable=SC2016 # Single quotes intentional: $4 expands inside mock body, not here.
  mock curl 'touch "$4"'
  BASHDEP_DIR="$TEST_DIR"

  bashdep::install \
    "https://example.com/aaa" \
    "https://example.com/bbb" >/dev/null

  local lock
  lock=$(cat "$TEST_DIR/.bashdep.lock")
  assert_contains "aaa" "$lock"
  assert_contains "bbb" "$lock"
}

function test_bashdep_install_from_defaults_to_bashdep_file() {
  printf 'https://example.com/default-tool\n' > "$TEST_DIR/.bashdep"
  BASHDEP_DRY_RUN=true

  local output
  output=$(cd "$TEST_DIR" && bashdep::install_from)
  assert_contains "default-tool" "$output"
}

function test_bashdep_install_from_errors_on_missing_file() {
  bashdep::install_from "$TEST_DIR/does_not_exist" 2>/dev/null
  assert_general_error
}

function test_bashdep_install_from_passes_each_url_to_install() {
  local file="$TEST_DIR/.bashdep"
  cat > "$file" <<'EOF'
https://example.com/aaa
https://example.com/bbb
EOF
  mock bashdep::install "echo install \"\$@\""

  local output
  output=$(bashdep::install_from "$file")
  assert_contains "https://example.com/aaa" "$output"
  assert_contains "https://example.com/bbb" "$output"
}

function test_bashdep_install_from_skips_comments_and_blanks() {
  local file="$TEST_DIR/.bashdep"
  cat > "$file" <<'EOF'
# top comment

https://example.com/aaa
  # indented comment

https://example.com/bbb
EOF
  mock bashdep::install "echo install \"\$@\""

  local output
  output=$(bashdep::install_from "$file")
  assert_not_contains "comment" "$output"
  assert_contains     "https://example.com/aaa" "$output"
  assert_contains     "https://example.com/bbb" "$output"
}

function test_bashdep_install_from_strips_whitespace() {
  local file="$TEST_DIR/.bashdep"
  printf '  https://example.com/aaa  \n\thttps://example.com/bbb\t\n' > "$file"
  # shellcheck disable=SC2016
  mock bashdep::install 'for d in "$@"; do printf "[%s]\n" "$d"; done'

  local output
  output=$(bashdep::install_from "$file")
  assert_contains "[https://example.com/aaa]" "$output"
  assert_contains "[https://example.com/bbb]" "$output"
}

function test_bashdep_install_from_empty_file_returns_zero() {
  local file="$TEST_DIR/.bashdep"
  : > "$file"
  mock bashdep::install "echo SHOULD_NOT_RUN"

  local output
  output=$(bashdep::install_from "$file")
  bashdep::install_from "$file"
  assert_successful_code "$?"
  assert_not_contains "SHOULD_NOT_RUN" "$output"
}

function test_bashdep_install_from_propagates_failure_count() {
  local file="$TEST_DIR/.bashdep"
  cat > "$file" <<'EOF'
https://example.com/a
https://example.com/b
EOF
  mock bashdep::setup_directory "return 0"
  mock bashdep::download_url "return 1"

  bashdep::install_from "$file"
  assert_equals 2 "$?"
}

function test_bashdep_uninstall_removes_file_and_lock_entry() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tool https://example.com/tool

  bashdep::uninstall tool >/dev/null
  assert_file_not_exists "$TEST_DIR/tool"
  assert_empty "$(bashdep::_lock_get "$TEST_DIR/.bashdep.lock" tool)"
}

function test_bashdep_uninstall_drops_lockfile_when_empty() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tool https://example.com/tool

  bashdep::uninstall tool >/dev/null
  assert_file_not_exists "$TEST_DIR/.bashdep.lock"
}

function test_bashdep_uninstall_keeps_lockfile_with_remaining_entries() {
  BASHDEP_DIR="$TEST_DIR"
  touch "$TEST_DIR/aaa" "$TEST_DIR/bbb"
  printf 'aaa\thttps://example.com/aaa\nbbb\thttps://example.com/bbb\n' > "$TEST_DIR/.bashdep.lock"

  bashdep::uninstall aaa >/dev/null
  assert_file_exists "$TEST_DIR/.bashdep.lock"
  assert_equals "https://example.com/bbb" "$(bashdep::_lock_get "$TEST_DIR/.bashdep.lock" bbb)"
  assert_empty  "$(bashdep::_lock_get "$TEST_DIR/.bashdep.lock" aaa)"
}

function test_bashdep_uninstall_searches_dev_dir() {
  BASHDEP_DIR="$TEST_DIR/main"
  BASHDEP_DEV_DIR="$TEST_DIR/dev"
  mkdir -p "$BASHDEP_DIR" "$BASHDEP_DEV_DIR"
  _seed_installed "$BASHDEP_DEV_DIR" tool https://example.com/tool

  bashdep::uninstall tool >/dev/null
  assert_successful_code "$?"
  assert_file_not_exists "$BASHDEP_DEV_DIR/tool"
}

function test_bashdep_uninstall_returns_nonzero_when_not_found() {
  BASHDEP_DIR="$TEST_DIR"
  bashdep::uninstall ghost 2>/dev/null
  assert_general_error
}

function test_bashdep_uninstall_dry_run_skips_actual_removal() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tool https://example.com/tool
  bashdep::setup dry-run=true

  local output
  output=$(bashdep::uninstall tool)
  assert_contains  "[dry-run]" "$output"
  assert_file_exists "$TEST_DIR/tool"
  assert_file_exists "$TEST_DIR/.bashdep.lock"
}

function test_bashdep_self_update_writes_target_from_curl() {
  local target="$TEST_DIR/bashdep_copy"
  # shellcheck disable=SC2016
  mock curl 'printf "NEW_BASHDEP_CONTENT\n" > "$4"'

  bashdep::self_update main "$target" >/dev/null
  assert_file_exists "$target"
  assert_contains "NEW_BASHDEP_CONTENT" "$(cat "$target")"
}

function test_bashdep_self_update_dry_run_skips_write() {
  local target="$TEST_DIR/bashdep_copy"
  mock curl "echo SHOULD_NOT_RUN"
  bashdep::setup dry-run=true

  local output
  output=$(bashdep::self_update main "$target")
  assert_contains       "[dry-run]" "$output"
  assert_file_not_exists "$target"
}

function test_bashdep_self_update_curl_failure_returns_nonzero() {
  local target="$TEST_DIR/bashdep_copy"
  mock curl "return 22"

  bashdep::self_update main "$target" 2>/dev/null >/dev/null
  assert_general_error
  assert_file_not_exists "$target"
}

function test_bashdep_self_update_uses_url_template() {
  local target="$TEST_DIR/bashdep_copy"
  BASHDEP_SELF_URL_TEMPLATE="https://example.test/bashdep/%s"
  # download_url contract: curl -fsSL <url> -o <dest> -> $2=url, $4=dest.
  # shellcheck disable=SC2016
  mock curl 'printf "from=%s\n" "$2" > "$4"'

  bashdep::self_update v1.2.3 "$target" >/dev/null
  assert_contains "from=https://example.test/bashdep/v1.2.3" "$(cat "$target")"
}

function test_bashdep_doctor_reports_orphan_files() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tracked https://example.com/tracked
  touch "$TEST_DIR/orphan"

  local output
  output=$(bashdep::doctor)
  local rc=$?
  assert_contains "orphan file" "$output"
  assert_equals 1 "$rc"
}

function test_bashdep_doctor_reports_missing_files() {
  BASHDEP_DIR="$TEST_DIR"
  printf 'gone\thttps://example.com/gone\n' > "$TEST_DIR/.bashdep.lock"

  local output
  output=$(bashdep::doctor)
  local rc=$?
  assert_contains "missing file" "$output"
  assert_equals 1 "$rc"
}

function test_bashdep_doctor_ok_when_consistent() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tracked https://example.com/tracked

  local output
  output=$(bashdep::doctor)
  assert_successful_code "$?"
  assert_contains "OK" "$output"
}

function test_bashdep_doctor_skips_dir_without_lockfile() {
  BASHDEP_DIR="$TEST_DIR"
  touch "$TEST_DIR/free_file"

  local output
  output=$(bashdep::doctor)
  assert_successful_code "$?"
  assert_contains "skip" "$output"
}

function test_bashdep_doctor_counts_issues_across_dirs() {
  BASHDEP_DIR="$TEST_DIR/main"
  BASHDEP_DEV_DIR="$TEST_DIR/dev"
  mkdir -p "$BASHDEP_DIR" "$BASHDEP_DEV_DIR"
  _seed_installed "$BASHDEP_DIR"     a https://example.com/a
  _seed_installed "$BASHDEP_DEV_DIR" b https://example.com/b
  touch "$BASHDEP_DIR/orphan_main"
  printf 'gone\thttps://example.com/gone\n' >> "$BASHDEP_DEV_DIR/.bashdep.lock"

  bashdep::doctor >/dev/null
  assert_equals 2 "$?"
}

function test_bashdep_clean_removes_orphan_files() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tracked https://example.com/tracked
  touch "$TEST_DIR/orphan"

  bashdep::clean >/dev/null
  assert_file_exists     "$TEST_DIR/tracked"
  assert_file_not_exists "$TEST_DIR/orphan"
}

function test_bashdep_clean_preserves_lockfile_itself() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tracked https://example.com/tracked
  touch "$TEST_DIR/orphan"

  bashdep::clean >/dev/null
  assert_file_exists "$TEST_DIR/.bashdep.lock"
}

function test_bashdep_clean_skips_dir_without_lockfile() {
  BASHDEP_DIR="$TEST_DIR"
  touch "$TEST_DIR/keep_me"

  bashdep::clean >/dev/null
  assert_file_exists "$TEST_DIR/keep_me"
}

function test_bashdep_clean_dry_run_preserves_files() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tracked https://example.com/tracked
  touch "$TEST_DIR/orphan"
  bashdep::setup dry-run=true

  local output
  output=$(bashdep::clean)
  assert_contains    "[dry-run]"         "$output"
  assert_file_exists "$TEST_DIR/orphan"
}

function test_bashdep_clean_does_not_remove_bashdep_script_itself() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tracked https://example.com/tracked
  cp "$(current_dir)/../../bashdep" "$TEST_DIR/bashdep"
  touch "$TEST_DIR/orphan"

  bashdep::clean >/dev/null
  assert_file_exists     "$TEST_DIR/bashdep"
  assert_file_exists     "$TEST_DIR/tracked"
  assert_file_not_exists "$TEST_DIR/orphan"
}

function test_bashdep_doctor_does_not_flag_bashdep_script_itself() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" tracked https://example.com/tracked
  cp "$(current_dir)/../../bashdep" "$TEST_DIR/bashdep"

  local output
  output=$(bashdep::doctor)
  assert_successful_code "$?"
  assert_not_contains "bashdep" "$output"
}

function test_bashdep_clean_handles_both_dirs() {
  BASHDEP_DIR="$TEST_DIR/main"
  BASHDEP_DEV_DIR="$TEST_DIR/dev"
  mkdir -p "$BASHDEP_DIR" "$BASHDEP_DEV_DIR"
  _seed_installed "$BASHDEP_DIR"     a https://example.com/a
  _seed_installed "$BASHDEP_DEV_DIR" b https://example.com/b
  touch "$BASHDEP_DIR/orphan_main" "$BASHDEP_DEV_DIR/orphan_dev"

  bashdep::clean >/dev/null
  assert_file_not_exists "$BASHDEP_DIR/orphan_main"
  assert_file_not_exists "$BASHDEP_DEV_DIR/orphan_dev"
  assert_file_exists     "$BASHDEP_DIR/a"
  assert_file_exists     "$BASHDEP_DEV_DIR/b"
}

function test_bashdep_lock_remove_drops_entry() {
  local lock_file="$TEST_DIR/lock"
  printf 'aaa\thttps://example.com/aaa\nbbb\thttps://example.com/bbb\n' > "$lock_file"

  bashdep::_lock_remove "$lock_file" aaa
  assert_empty "$(bashdep::_lock_get "$lock_file" aaa)"
  assert_equals "https://example.com/bbb" "$(bashdep::_lock_get "$lock_file" bbb)"
}

function test_bashdep_lock_remove_deletes_empty_lockfile() {
  local lock_file="$TEST_DIR/lock"
  printf 'only\thttps://example.com/only\n' > "$lock_file"

  bashdep::_lock_remove "$lock_file" only
  assert_file_not_exists "$lock_file"
}

function test_bashdep_lock_remove_no_op_when_lockfile_missing() {
  bashdep::_lock_remove "$TEST_DIR/nope" anything
  assert_successful_code "$?"
}

function test_bashdep_list_empty_when_no_lockfiles() {
  BASHDEP_DIR="$TEST_DIR/empty_main"
  BASHDEP_DEV_DIR="$TEST_DIR/empty_dev"
  mkdir -p "$BASHDEP_DIR" "$BASHDEP_DEV_DIR"
  assert_empty "$(bashdep::list)"
}

function test_bashdep_list_returns_entries_from_main_dir() {
  BASHDEP_DIR="$TEST_DIR/main"
  BASHDEP_DEV_DIR="$TEST_DIR/dev"
  mkdir -p "$BASHDEP_DIR"
  printf 'aaa\thttps://example.com/aaa\nbbb\thttps://example.com/bbb\n' \
    > "$BASHDEP_DIR/.bashdep.lock"

  local output
  output=$(bashdep::list)
  assert_contains "$BASHDEP_DIR/aaa	https://example.com/aaa" "$output"
  assert_contains "$BASHDEP_DIR/bbb	https://example.com/bbb" "$output"
}

function test_bashdep_list_combines_main_and_dev_lockfiles() {
  BASHDEP_DIR="$TEST_DIR/main"
  BASHDEP_DEV_DIR="$TEST_DIR/dev"
  mkdir -p "$BASHDEP_DIR" "$BASHDEP_DEV_DIR"
  printf 'runtime\thttps://example.com/runtime\n' > "$BASHDEP_DIR/.bashdep.lock"
  printf 'devtool\thttps://example.com/devtool\n' > "$BASHDEP_DEV_DIR/.bashdep.lock"

  local output
  output=$(bashdep::list)
  assert_contains "$BASHDEP_DIR/runtime"    "$output"
  assert_contains "$BASHDEP_DEV_DIR/devtool" "$output"
}

function test_bashdep_list_deduplicates_when_dir_equals_dev_dir() {
  BASHDEP_DIR="$TEST_DIR/shared"
  BASHDEP_DEV_DIR="$TEST_DIR/shared"
  mkdir -p "$BASHDEP_DIR"
  printf 'tool\thttps://example.com/tool\n' > "$BASHDEP_DIR/.bashdep.lock"

  local count
  count=$(bashdep::list | wc -l | tr -d ' ')
  assert_equals "1" "$count"
}

function test_bashdep_list_includes_extra_dirs_passed_as_args() {
  BASHDEP_DIR="$TEST_DIR/main"
  BASHDEP_DEV_DIR="$TEST_DIR/dev"
  local extra="$TEST_DIR/extra"
  mkdir -p "$BASHDEP_DIR" "$extra"
  printf 'main\thttps://example.com/main\n'  > "$BASHDEP_DIR/.bashdep.lock"
  printf 'extra\thttps://example.com/extra\n' > "$extra/.bashdep.lock"

  local output
  output=$(bashdep::list "$extra")
  assert_contains "$BASHDEP_DIR/main"  "$output"
  assert_contains "$extra/extra"        "$output"
}

function test_bashdep_install_dev_lockfile_separated_from_main() {
  local main_dir="$TEST_DIR/main"
  local dev_dir="$TEST_DIR/dev"
  mkdir -p "$main_dir" "$dev_dir"
  # shellcheck disable=SC2016 # Single quotes intentional: $4 expands inside mock body, not here.
  mock curl 'touch "$4"'
  BASHDEP_DIR="$main_dir"
  BASHDEP_DEV_DIR="$dev_dir"

  bashdep::install \
    "https://example.com/runtime" \
    "https://example.com/devtool@dev" >/dev/null

  local main_lock dev_lock
  main_lock=$(cat "$main_dir/.bashdep.lock")
  dev_lock=$(cat "$dev_dir/.bashdep.lock")
  assert_contains     "runtime" "$main_lock"
  assert_not_contains "devtool" "$main_lock"
  assert_contains     "devtool" "$dev_lock"
  assert_not_contains "runtime" "$dev_lock"
}

function test_bashdep_setup_directory_mkdir_failure_returns_error() {
  mock mkdir "return 1"

  local stderr
  stderr=$(bashdep::setup_directory "$TEST_DIR/sub" 2>&1 >/dev/null)
  assert_general_error
  assert_contains "Could not create directory" "$stderr"
}

function test_bashdep_self_update_mv_failure_returns_error() {
  mock curl "true"
  mock mv "return 1"

  local stderr
  stderr=$(bashdep::self_update main "$TEST_DIR/bashdep" 2>&1 >/dev/null)
  assert_general_error
  assert_contains "failed to write" "$stderr"
}

function test_bashdep_download_url_mktemp_failure_returns_error() {
  mock curl "true"
  mock mktemp "return 1"

  bashdep::download_url "https://example.com/tool" "$TEST_DIR" >/dev/null 2>&1
  assert_general_error
}

function test_bashdep_doctor_silent_suppresses_output_keeps_exit_code() {
  BASHDEP_DIR="$TEST_DIR"
  BASHDEP_SILENT=true
  _seed_lock "$TEST_DIR" missing "https://example.com/missing"

  local output
  output=$(bashdep::doctor)
  assert_general_error
  assert_empty "$output"
}

function test_bashdep_clean_silent_suppresses_output_still_removes() {
  BASHDEP_DIR="$TEST_DIR"
  BASHDEP_SILENT=true
  _seed_installed "$TEST_DIR" kept "https://example.com/kept"
  touch "$TEST_DIR/orphan"

  local output
  output=$(bashdep::clean)
  assert_empty "$output"
  assert_file_not_exists "$TEST_DIR/orphan"
}

function test_bashdep_uninstall_silent_keeps_errors_on_stderr() {
  BASHDEP_DIR="$TEST_DIR"
  BASHDEP_SILENT=true

  local stderr
  stderr=$(bashdep::uninstall nope 2>&1 >/dev/null)
  assert_contains "not found" "$stderr"
}

function test_bashdep_list_skips_blank_dirs() {
  BASHDEP_DIR=""
  BASHDEP_DEV_DIR=""
  assert_empty "$(bashdep::list)"
}

# CLI tests — run the bashdep script as an executable ($BASHDEP_BIN).
# Never hit the network: mutating commands always pass --dry-run or
# operate on seeded fixtures in $TEST_DIR.

function test_bashdep_cli_version_prints_version() {
  local output
  output=$(bash "$BASHDEP_BIN" version)
  assert_equals "$BASHDEP_VERSION" "$output"
}

function test_bashdep_cli_help_prints_usage() {
  local output
  output=$(bash "$BASHDEP_BIN" --help)
  assert_contains "Usage:" "$output"
}

function test_bashdep_cli_help_command_prints_usage() {
  local output
  output=$(bash "$BASHDEP_BIN" help)
  assert_contains "Usage:" "$output"
}

function test_bashdep_cli_no_args_prints_usage_and_fails() {
  bash "$BASHDEP_BIN" >/dev/null 2>&1
  assert_general_error
}

function test_bashdep_cli_unknown_command_fails() {
  local stderr
  stderr=$(bash "$BASHDEP_BIN" bogus 2>&1 >/dev/null)
  assert_contains "Unknown command" "$stderr"
}

function test_bashdep_cli_unknown_option_fails() {
  local stderr
  stderr=$(bash "$BASHDEP_BIN" install --bogus 2>&1 >/dev/null)
  assert_contains "Unknown option" "$stderr"
}

function test_bashdep_cli_install_url_dry_run_downloads_nothing() {
  local output
  output=$(bash "$BASHDEP_BIN" install --dry-run --dir="$TEST_DIR" \
    "https://example.com/tool")
  assert_contains "[dry-run]" "$output"
  assert_file_not_exists "$TEST_DIR/tool"
}

function test_bashdep_cli_install_reads_default_bashdep_file() {
  printf 'https://example.com/from-file\n' > "$TEST_DIR/.bashdep"
  local output
  output=$(cd "$TEST_DIR" && bash "$BASHDEP_BIN" install --dry-run)
  assert_contains "from-file" "$output"
}

function test_bashdep_cli_install_respects_file_flag() {
  printf 'https://example.com/custom-tool\n' > "$TEST_DIR/deps.txt"
  local output
  output=$(bash "$BASHDEP_BIN" install --dry-run --file="$TEST_DIR/deps.txt")
  assert_contains "custom-tool" "$output"
}

function test_bashdep_cli_install_missing_default_file_fails() {
  local stderr
  stderr=$(cd "$TEST_DIR" && bash "$BASHDEP_BIN" install 2>&1 >/dev/null)
  assert_contains "not found" "$stderr"
}

function test_bashdep_cli_install_silent_suppresses_output() {
  local output
  output=$(bash "$BASHDEP_BIN" install --dry-run --silent --dir="$TEST_DIR" \
    "https://example.com/tool")
  assert_empty "$output"
}

function test_bashdep_cli_list_prints_lock_entries() {
  _seed_installed "$TEST_DIR" tool "https://example.com/tool"
  local output
  output=$(bash "$BASHDEP_BIN" list --dir="$TEST_DIR")
  assert_contains "$TEST_DIR/tool	https://example.com/tool" "$output"
}

function test_bashdep_cli_uninstall_removes_dep() {
  _seed_installed "$TEST_DIR" tool "https://example.com/tool"
  bash "$BASHDEP_BIN" uninstall --dir="$TEST_DIR" tool >/dev/null
  assert_file_not_exists "$TEST_DIR/tool"
}

function test_bashdep_cli_uninstall_requires_name() {
  bash "$BASHDEP_BIN" uninstall --dir="$TEST_DIR" >/dev/null 2>&1
  assert_general_error
}

function test_bashdep_cli_clean_removes_orphans() {
  _seed_installed "$TEST_DIR" kept "https://example.com/kept"
  touch "$TEST_DIR/orphan"
  bash "$BASHDEP_BIN" clean --dir="$TEST_DIR" >/dev/null
  assert_file_not_exists "$TEST_DIR/orphan"
  assert_file_exists "$TEST_DIR/kept"
}

function test_bashdep_cli_doctor_exit_code_is_issue_count() {
  _seed_lock "$TEST_DIR" missing "https://example.com/missing"
  bash "$BASHDEP_BIN" doctor --dir="$TEST_DIR" >/dev/null
  assert_general_error
}

function test_bashdep_cli_self_update_dry_run_prints_intent() {
  local output
  output=$(bash "$BASHDEP_BIN" self-update --dry-run)
  assert_contains "[dry-run] Would update" "$output"
}

function test_bashdep_sourcing_does_not_invoke_cli() {
  local output
  output=$(bash -c "source '$BASHDEP_BIN' && echo SOURCED_OK")
  assert_equals "SOURCED_OK" "$output"
}

function test_bashdep_cli_short_help_flag_prints_usage() {
  local output
  output=$(bash "$BASHDEP_BIN" -h)
  assert_contains "Usage:" "$output"
}

function test_bashdep_cli_force_flag_bypasses_skip() {
  local url="https://example.com/tool"
  _seed_installed "$TEST_DIR" tool "$url"

  local output
  output=$(bash "$BASHDEP_BIN" install --force --dry-run --dir="$TEST_DIR" "$url")
  assert_contains "[dry-run] Would download" "$output"
}

function test_bashdep_cli_verbose_flag_logs_url_on_skip() {
  local url="https://example.com/tool"
  _seed_installed "$TEST_DIR" tool "$url"

  local output
  output=$(bash "$BASHDEP_BIN" install --verbose --dir="$TEST_DIR" "$url")
  assert_contains "url: $url" "$output"
}

function test_bashdep_cli_dev_dir_flag_routes_dev_suffix() {
  local output
  output=$(bash "$BASHDEP_BIN" install --dry-run --dev-dir="$TEST_DIR/devx" \
    "https://example.com/tool@dev")
  assert_contains "$TEST_DIR/devx" "$output"
}

function test_bashdep_cli_self_update_passes_ref() {
  local output
  output=$(bash "$BASHDEP_BIN" self-update --dry-run 1.2.3)
  assert_contains "/1.2.3/" "$output"
}

# Stub curl on PATH so the CLI subprocess performs a full install
# without touching the network.
function _stub_curl_on_path() {
  mkdir -p "$TEST_DIR/bin"
  # shellcheck disable=SC2016 # Single quotes intentional: $1/$2 must expand in the stub, not here.
  printf '%s\n' '#!/bin/sh' 'while [ $# -gt 0 ]; do' \
    '  if [ "$1" = "-o" ]; then : > "$2"; shift 2; else shift; fi' \
    'done' 'exit 0' > "$TEST_DIR/bin/curl"
  chmod +x "$TEST_DIR/bin/curl"
}

function test_bashdep_cli_install_downloads_and_writes_lockfile() {
  _stub_curl_on_path
  PATH="$TEST_DIR/bin:$PATH" bash "$BASHDEP_BIN" install --dir="$TEST_DIR" \
    "https://example.com/tool" >/dev/null

  assert_file_exists "$TEST_DIR/tool"
  assert_file_exists "$TEST_DIR/.bashdep.lock"
}

function test_bashdep_cli_install_curl_failure_exits_nonzero() {
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/sh\nexit 7\n' > "$TEST_DIR/bin/curl"
  chmod +x "$TEST_DIR/bin/curl"

  local stderr
  stderr=$(PATH="$TEST_DIR/bin:$PATH" bash "$BASHDEP_BIN" install \
    --dir="$TEST_DIR" "https://example.com/tool" 2>&1 >/dev/null)
  assert_general_error
  assert_contains "curl exit 7" "$stderr"
}

# Positional-argument accumulation: the first non-flag token is the
# command, every later one lands in args[] and is forwarded intact.

function test_bashdep_cli_install_accumulates_multiple_urls() {
  local output
  output=$(bash "$BASHDEP_BIN" install --dry-run --dir="$TEST_DIR" \
    "https://example.com/aaa" "https://example.com/bbb")
  assert_contains "aaa" "$output"
  assert_contains "bbb" "$output"
}

function test_bashdep_cli_uninstall_removes_multiple_names() {
  BASHDEP_DIR="$TEST_DIR"
  _seed_installed "$TEST_DIR" aaa "https://example.com/aaa"
  printf 'bbb\thttps://example.com/bbb\n' >> "$TEST_DIR/.bashdep.lock"
  touch "$TEST_DIR/bbb"

  bash "$BASHDEP_BIN" uninstall --dir="$TEST_DIR" aaa bbb >/dev/null
  assert_file_not_exists "$TEST_DIR/aaa"
  assert_file_not_exists "$TEST_DIR/bbb"
}

function test_bashdep_cli_list_forwards_extra_dir_arg() {
  _seed_lock "$TEST_DIR" main "https://example.com/main"
  local extra="$TEST_DIR/extra"
  mkdir -p "$extra"
  printf 'ex\thttps://example.com/ex\n' > "$extra/.bashdep.lock"

  local output
  output=$(bash "$BASHDEP_BIN" list --dir="$TEST_DIR" "$extra")
  assert_contains "$TEST_DIR/main" "$output"
  assert_contains "$extra/ex" "$output"
}

function test_bashdep_cli_flag_after_command_still_parsed() {
  local output
  output=$(bash "$BASHDEP_BIN" install "https://example.com/tool" \
    --dry-run --dir="$TEST_DIR")
  assert_contains "[dry-run]" "$output"
  assert_contains "$TEST_DIR" "$output"
}
