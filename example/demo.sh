#!/bin/bash
#
# End-to-end demo of bashdep:
#   - Inline DEPENDENCIES array passed to bashdep::install.
#   - Custom destination directories via bashdep::setup.
#   - Re-runs are idempotent thanks to the per-directory .bashdep.lock.
#
# Run from the repo root:  bash example/demo.sh
#
# To list what was installed afterwards:
#   source bashdep && bashdep::setup dir=vendor dev-dir=local/dev && bashdep::list
#
# For the file-driven workflow, use bashdep::install_from <path> instead.

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/../bashdep"

DEPENDENCIES=(
  "https://github.com/TypedDevs/bashunit/releases/download/0.45.0/bashunit"
  "https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr"
  "https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh@dev"
)

bashdep::setup dir="vendor" dev-dir="local/dev"
bashdep::install "${DEPENDENCIES[@]}" || exit $?
