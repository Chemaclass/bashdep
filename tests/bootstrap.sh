#!/bin/bash

function current_dir() {
  dirname "${BASH_SOURCE[1]}"
}

function temp_dir() {
  mkdir -p /tmp/bashunit-tmp && chmod -R 777 /tmp/bashunit-tmp
  mktemp -d --tmpdir="/tmp/bashunit-tmp" "XXXXXXX"
}
