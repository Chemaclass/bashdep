#!/bin/bash
set -euo pipefail

# Dogfood: bashdep installs its own dev dependencies, pinned and checksummed in .bashdep.
cd "$(dirname "$0")"
source ./bashdep
bashdep::install_from
