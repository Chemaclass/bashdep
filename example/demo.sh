#!/bin/bash

BASHDEP_ROOT_DIR="$(dirname "${BASH_SOURCE[0]}")/.."
source "$BASHDEP_ROOT_DIR"/bashdep.sh

DEPENDENCIES=(
  "https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  "https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr"
  "https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh:lib/dev"
)

bashdep::install "${DEPENDENCIES[@]}"
