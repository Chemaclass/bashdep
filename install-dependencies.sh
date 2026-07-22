#!/bin/bash
set -euo pipefail

# Pin to the same bashunit version used in CI (.github/workflows/ci.yml).
BASHUNIT_VERSION="${BASHUNIT_VERSION:-0.17.0}"

echo "Installing bashunit ${BASHUNIT_VERSION} into lib/..."
curl -fsSL https://bashunit.typeddevs.com/install.sh | bash -s lib "${BASHUNIT_VERSION}"
