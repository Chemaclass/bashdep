#!/bin/bash
# shellcheck disable=SC2155,SC2034,SC2153

TEST_DIR=""

function set_up() {
  # shellcheck disable=SC1091
  source "$(current_dir)/../../bashdep"
  BASHDEP_FORCE=false
  BASHDEP_SILENT=false
  TEST_DIR=$(mktemp -d)
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
