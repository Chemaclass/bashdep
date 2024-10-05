#!/bin/bash

DM_ROOT_DIR="$(dirname "${BASH_SOURCE[0]}")/.."
source "$DM_ROOT_DIR"/dependency-manager.sh

DEPENDENCIES=(
  "https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  "https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr"
  "https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh:lib/dev"
)

# Main execution
process_dependencies "${DEPENDENCIES[@]}"
