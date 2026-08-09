#!/bin/bash

function current_dir() {
  dirname "${BASH_SOURCE[1]}"
}

function temp_dir() {
  mkdir -p /tmp/bashunit-tmp && chmod -R 777 /tmp/bashunit-tmp
  mktemp -d --tmpdir="/tmp/bashunit-tmp" "XXXXXXX"
}

# Replace $1 with a function whose body is the remaining arguments.
#
# bashunit >= 0.40 moved its doubles under `bashunit::mock` and made the
# multi-argument form append `"$@"` to the body, so a mock body that reads
# positional arguments (`touch "$3"`) can no longer be expressed. The suite
# leans on that shape heavily, so it keeps its own helper. Each bashunit
# test runs in its own subshell, so mocks cannot leak between tests and
# need no registry.
#
# With no body, the function echoes stdin instead:
#   mock curl <<< "payload"
function mock() {
  local command=$1
  shift
  if [[ $# -gt 0 ]]; then
    eval "function $command() { $* ; }"
  else
    eval "function $command() { echo \"$(cat)\" ; }"
  fi
  export -f "${command?}"
}

# Restore $1 to its real implementation.
function unmock() {
  unset -f "$1"
}
