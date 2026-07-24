#!/bin/bash
#
# Thin wrapper: bashdep dogfoods the generic release engine in
# templates/release.sh, configured by ./release.conf. Other projects copy
# templates/release.sh + release.conf into their repo and run it the same
# way. See docs/releasing.md and templates/README.md.
#
# Usage:  ./release.sh [version] [flags]   (same as templates/release.sh)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Only exec when run directly; sourcing (e.g. from tests) is a no-op.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cd "$here"
  exec bash "$here/templates/release.sh" --config="$here/release.conf" "$@"
fi
