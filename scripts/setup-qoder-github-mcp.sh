#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "::warning::scripts/setup-qoder-github-mcp.sh is deprecated; use scripts/setup-github-mcp.sh instead."

if [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" \
  && -n "${GITHUB_TOKEN:-}" \
  && -n "${GITHUB_ENV:-}" ]]; then
  echo "::add-mask::${GITHUB_TOKEN}"
  printf 'GITHUB_PERSONAL_ACCESS_TOKEN=%s\n' "${GITHUB_TOKEN}" >> "${GITHUB_ENV}"
fi

exec bash "${SCRIPT_DIR}/setup-github-mcp.sh" "$@"
