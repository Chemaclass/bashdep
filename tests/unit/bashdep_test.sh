#!/bin/bash
# shellcheck disable=SC2155,SC2034

function set_up() {
  # shellcheck disable=SC1091
  source "$(current_dir)/../../bashdep"
  BASHDEP_FORCE=false
  BASHDEP_SILENT=false
}

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

function test_bashdep_setup_directory() {
  local dir=$(temp_dir)

  assert_empty "$(bashdep::setup_directory "$dir")"
}

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
  local file="$dir/bashunit"

  mkdir -p "$dir"
  touch "$file"
  printf 'bashunit\t%s\n' "$url" > "$dir/.bashdep.lock"
  mock curl "echo mocked curl"

  assert_match_snapshot "$(bashdep::download_url "$url" "$dir")"
  rm -rf "$dir"
}

function test_bashdep_download_url_redownloads_when_url_changes() {
  local old_url="https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  local new_url="https://github.com/TypedDevs/bashunit/releases/download/0.18.0/bashunit"
  local dir="/tmp/test_bashdep_download_url_redownloads_when_url_changes"
  local file="$dir/bashunit"

  mkdir -p "$dir"
  touch "$file"
  printf 'bashunit\t%s\n' "$old_url" > "$dir/.bashdep.lock"
  mock curl "echo mocked curl"

  assert_match_snapshot "$(bashdep::download_url "$new_url" "$dir")"

  local recorded
  recorded=$(awk -F '\t' '$1 == "bashunit" { print $2 }' "$dir/.bashdep.lock")
  assert_equals "$new_url" "$recorded"

  rm -rf "$dir"
}

function test_bashdep_download_url_redownloads_when_lock_missing() {
  local url="https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  local dir="/tmp/test_bashdep_download_url_redownloads_when_lock_missing"
  local file="$dir/bashunit"

  mkdir -p "$dir"
  touch "$file"
  mock curl "echo mocked curl"

  assert_match_snapshot "$(bashdep::download_url "$url" "$dir")"
  assert_file_exists "$dir/.bashdep.lock"
  rm -rf "$dir"
}

function test_bashdep_download_url_force_redownload() {
  local url="https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  local dir="/tmp/test_bashdep_download_url_force_redownload"
  local file="$dir/bashunit"

  mkdir -p "$dir"
  touch "$file"
  printf 'bashunit\t%s\n' "$url" > "$dir/.bashdep.lock"
  mock curl "echo mocked curl"
  bashdep::setup force=true

  assert_match_snapshot "$(bashdep::download_url "$url" "$dir")"
  rm -rf "$dir"
}

function test_bashdep_setup_rejects_invalid_bool() {
  bashdep::setup silent=maybe 2>/dev/null
  assert_general_error
}

function test_bashdep_setup_rejects_unknown_param() {
  bashdep::setup unknown=value 2>/dev/null
  assert_general_error
}

function test_bashdep_download_url_requires_url() {
  bashdep::download_url "" "/tmp" 2>/dev/null
  assert_general_error
}

function test_bashdep_install_returns_failure_count() {
  mock bashdep::setup_directory "return 0"
  mock bashdep::download_url "return 1"

  bashdep::install "https://example.com/a" "https://example.com/b"
  local rc=$?

  assert_equals 2 "$rc"
}

function test_bashdep_version_is_set() {
  assert_not_empty "$(bashdep::version)"
}

function test_bashdep_lock_get_returns_url_for_filename() {
  local lock_file
  lock_file=$(mktemp)
  {
    printf 'bashunit\thttps://example.com/bashunit\n'
    printf 'create-pr\thttps://example.com/create-pr\n'
  } > "$lock_file"

  assert_equals "https://example.com/bashunit" "$(bashdep::_lock_get "$lock_file" bashunit)"
  assert_equals "https://example.com/create-pr" "$(bashdep::_lock_get "$lock_file" create-pr)"
  assert_empty "$(bashdep::_lock_get "$lock_file" missing)"

  rm -f "$lock_file"
}

function test_bashdep_lock_set_upserts_entry() {
  local lock_file
  lock_file=$(mktemp)

  bashdep::_lock_set "$lock_file" bashunit https://example.com/0.17.0
  bashdep::_lock_set "$lock_file" bashunit https://example.com/0.18.0
  bashdep::_lock_set "$lock_file" create-pr https://example.com/cpr

  assert_equals "https://example.com/0.18.0" "$(bashdep::_lock_get "$lock_file" bashunit)"
  assert_equals "https://example.com/cpr"     "$(bashdep::_lock_get "$lock_file" create-pr)"

  rm -f "$lock_file"
}

function test_bashdep_lock_set_keeps_entries_sorted() {
  local lock_file
  lock_file=$(mktemp)

  bashdep::_lock_set "$lock_file" zeta https://example.com/zeta
  bashdep::_lock_set "$lock_file" alpha https://example.com/alpha
  bashdep::_lock_set "$lock_file" mu https://example.com/mu

  local first second third
  first=$(awk -F '\t' 'NR==1 { print $1 }' "$lock_file")
  second=$(awk -F '\t' 'NR==2 { print $1 }' "$lock_file")
  third=$(awk -F '\t' 'NR==3 { print $1 }' "$lock_file")
  assert_equals "alpha" "$first"
  assert_equals "mu"    "$second"
  assert_equals "zeta"  "$third"

  rm -f "$lock_file"
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

function test_bashdep_should_skip_download_yes_when_lock_matches() {
  local dir="/tmp/test_should_skip_match"
  mkdir -p "$dir"
  touch "$dir/foo"
  printf 'foo\thttps://example.com/foo\n' > "$dir/.bashdep.lock"

  bashdep::_should_skip_download "$dir/foo" "$dir/.bashdep.lock" foo https://example.com/foo
  assert_successful_code "$?"
  rm -rf "$dir"
}

function test_bashdep_should_skip_download_no_when_url_differs() {
  local dir="/tmp/test_should_skip_url_diff"
  mkdir -p "$dir"
  touch "$dir/foo"
  printf 'foo\thttps://example.com/foo-old\n' > "$dir/.bashdep.lock"

  bashdep::_should_skip_download "$dir/foo" "$dir/.bashdep.lock" foo https://example.com/foo-new
  assert_general_error
  rm -rf "$dir"
}

function test_bashdep_should_skip_download_no_when_file_missing() {
  local dir="/tmp/test_should_skip_no_file"
  mkdir -p "$dir"
  printf 'foo\thttps://example.com/foo\n' > "$dir/.bashdep.lock"

  bashdep::_should_skip_download "$dir/foo" "$dir/.bashdep.lock" foo https://example.com/foo
  assert_general_error
  rm -rf "$dir"
}

function test_bashdep_should_skip_download_no_when_force_enabled() {
  local dir="/tmp/test_should_skip_force"
  mkdir -p "$dir"
  touch "$dir/foo"
  printf 'foo\thttps://example.com/foo\n' > "$dir/.bashdep.lock"
  BASHDEP_FORCE=true

  bashdep::_should_skip_download "$dir/foo" "$dir/.bashdep.lock" foo https://example.com/foo
  assert_general_error
  rm -rf "$dir"
}

function test_bashdep_should_skip_download_no_when_lockfile_missing() {
  local dir="/tmp/test_should_skip_no_lock"
  mkdir -p "$dir"
  touch "$dir/foo"

  bashdep::_should_skip_download "$dir/foo" "$dir/.bashdep.lock" foo https://example.com/foo
  assert_general_error
  rm -rf "$dir"
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

function test_bashdep_setup_unknown_param_error_message() {
  local err
  err=$(bashdep::setup unknown=value 2>&1)
  assert_contains "unknown=value" "$err"
}

function test_bashdep_setup_invalid_bool_error_message() {
  local err
  err=$(bashdep::setup silent=maybe 2>&1)
  assert_contains "silent" "$err"
  assert_contains "maybe" "$err"
}

function test_bashdep_setup_directory_requires_arg() {
  bashdep::setup_directory "" 2>/dev/null
  assert_general_error
}

function test_bashdep_setup_directory_creates_missing_dir() {
  local dir="/tmp/test_setup_dir_create_$$"
  rm -rf "$dir"

  bashdep::setup_directory "$dir"
  assert_directory_exists "$dir"
  rm -rf "$dir"
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

function test_bashdep_install_returns_zero_when_all_succeed() {
  mock bashdep::setup_directory "return 0"
  mock bashdep::download_url "return 0"

  bashdep::install "https://example.com/a" "https://example.com/b"
  assert_successful_code "$?"
}

function test_bashdep_install_counts_setup_directory_failures() {
  mock bashdep::setup_directory "return 1"
  mock bashdep::download_url "return 0"

  bashdep::install "https://example.com/a" 2>/dev/null
  assert_equals 1 "$?"
}

function test_bashdep_download_url_silent_mode_no_progress_output() {
  local dir="/tmp/test_silent_install"
  mkdir -p "$dir"
  mock curl "true"
  bashdep::setup silent=true

  local output
  output=$(bashdep::download_url "https://example.com/foo" "$dir")
  assert_empty "$output"
  rm -rf "$dir"
}

function test_bashdep_download_url_silent_mode_skip_no_output() {
  local url="https://example.com/foo"
  local dir="/tmp/test_silent_skip"
  mkdir -p "$dir"
  touch "$dir/foo"
  printf 'foo\t%s\n' "$url" > "$dir/.bashdep.lock"
  bashdep::setup silent=true

  local output
  output=$(bashdep::download_url "$url" "$dir")
  assert_empty "$output"
  rm -rf "$dir"
}

function test_bashdep_download_url_curl_failure_message_includes_exit_code() {
  local dir="/tmp/test_curl_fail_msg"
  mkdir -p "$dir"
  mock curl "return 22"

  local err
  err=$(bashdep::download_url "https://example.com/dead" "$dir" 2>&1 >/dev/null)
  assert_contains "exit 22" "$err"
  rm -rf "$dir"
}

function test_bashdep_download_url_curl_failure_returns_non_zero() {
  local dir="/tmp/test_curl_fail_rc"
  mkdir -p "$dir"
  mock curl "return 7"

  bashdep::download_url "https://example.com/x" "$dir" 2>/dev/null
  assert_general_error
  rm -rf "$dir"
}

function test_bashdep_download_url_writes_lockfile_entry() {
  local dir="/tmp/test_writes_lock"
  local url="https://example.com/tool"
  mkdir -p "$dir"
  mock curl "true"

  bashdep::download_url "$url" "$dir" >/dev/null

  assert_file_exists "$dir/.bashdep.lock"
  local recorded
  recorded=$(awk -F '\t' '$1 == "tool" { print $2 }' "$dir/.bashdep.lock")
  assert_equals "$url" "$recorded"
  rm -rf "$dir"
}

function test_bashdep_download_url_chmod_makes_file_executable() {
  local dir="/tmp/test_chmod"
  mkdir -p "$dir"
  mock curl "true"

  bashdep::download_url "https://example.com/tool" "$dir" >/dev/null

  assert_successful_code "$([[ -x "$dir/tool" ]]; echo $?)"
  rm -rf "$dir"
}

function test_bashdep_download_url_url_change_updates_lock() {
  local dir="/tmp/test_url_change_updates"
  local old_url="https://example.com/v1/tool"
  local new_url="https://example.com/v2/tool"
  mkdir -p "$dir"
  touch "$dir/tool"
  printf 'tool\t%s\n' "$old_url" > "$dir/.bashdep.lock"
  mock curl "true"

  bashdep::download_url "$new_url" "$dir" >/dev/null

  local recorded
  recorded=$(awk -F '\t' '$1 == "tool" { print $2 }' "$dir/.bashdep.lock")
  assert_equals "$new_url" "$recorded"
  rm -rf "$dir"
}

function test_bashdep_install_lockfile_contains_all_deps() {
  local dir="/tmp/test_install_lock_all"
  mkdir -p "$dir"
  mock curl "true"
  BASHDEP_DIR="$dir"

  bashdep::install \
    "https://example.com/aaa" \
    "https://example.com/bbb" >/dev/null

  assert_file_contains "$dir/.bashdep.lock" "aaa"
  assert_file_contains "$dir/.bashdep.lock" "bbb"
  rm -rf "$dir"
}

function test_bashdep_install_dev_lockfile_separated_from_main() {
  local dir="/tmp/test_install_dev_split_main"
  local dev_dir="/tmp/test_install_dev_split_dev"
  mkdir -p "$dir" "$dev_dir"
  mock curl "true"
  BASHDEP_DIR="$dir"
  BASHDEP_DEV_DIR="$dev_dir"

  bashdep::install \
    "https://example.com/runtime" \
    "https://example.com/devtool@dev" >/dev/null

  assert_file_contains "$dir/.bashdep.lock" "runtime"
  assert_file_not_contains "$dir/.bashdep.lock" "devtool"
  assert_file_contains "$dev_dir/.bashdep.lock" "devtool"
  assert_file_not_contains "$dev_dir/.bashdep.lock" "runtime"

  rm -rf "$dir" "$dev_dir"
}

function test_bashdep_lock_get_returns_empty_when_lockfile_missing() {
  assert_empty "$(bashdep::_lock_get /nonexistent/path/lockfile foo)"
}

function test_bashdep_lock_get_returns_empty_when_entry_missing() {
  local lock_file
  lock_file=$(mktemp)
  printf 'other\thttps://example.com/other\n' > "$lock_file"

  assert_empty "$(bashdep::_lock_get "$lock_file" missing)"
  rm -f "$lock_file"
}
