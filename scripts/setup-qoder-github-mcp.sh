#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "::warning::scripts/setup-qoder-github-mcp.sh is deprecated; use scripts/setup-github-mcp.sh instead."
exec bash "${SCRIPT_DIR}/setup-github-mcp.sh" "$@"
