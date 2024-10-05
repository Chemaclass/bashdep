#!/bin/bash

# shellcheck disable=SC1091
source "$(dirname "$0")/../bashdep"

DEPENDENCIES=(
  "https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  "https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr"
  "https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh@dev"
)

bashdep::setup dir="vendor" dev-dir="local/dev"
bashdep::install "${DEPENDENCIES[@]}"
