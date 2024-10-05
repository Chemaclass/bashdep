#!/bin/bash
# shellcheck disable=SC2155

function set_up() {
  # shellcheck disable=SC1091
  source "$(current_dir)/../../bashdep"
}

function test_bashdep_install_custom_setup() {
  mock bashdep::setup_directory "/dev/null"
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
  mock bashdep::setup_directory "/dev/null"
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
  mock curl "echo mocked curl"
  local url="fake.url"

  assert_match_snapshot "$(bashdep::download_url "$url")"
}

function test_bashdep_download_url_custom_dir() {
  local url="https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  local dir="/tmp/test_bashdep_download_url_custom_dir"

  mock curl "echo mocked curl"

  assert_match_snapshot "$(bashdep::download_url "$url" "$dir")"
  rmdir "$dir"
}
