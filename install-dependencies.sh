#!/bin/bash
set -euo pipefail

echo "Installing test dependencies via bashunit installer..."
curl -fsSL https://bashunit.typeddevs.com/install.sh | bash
