#!/bin/bash
# shellcheck disable=SC2155

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
