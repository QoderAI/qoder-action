#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # Resolved relative to this script at runtime.
source "${SCRIPT_DIR}/github-mcp-common.sh"

CONFIG_FILE="${HOME}/.qoder.json"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required to migrate the legacy GitHub MCP configuration." >&2
  exit 1
fi

if ! jq -e 'type == "object" and ((.mcpServers // {}) | type == "object")' \
  "${CONFIG_FILE}" >/dev/null; then
  echo "::error::${CONFIG_FILE} must contain a JSON object with an optional object-valued mcpServers field." >&2
  exit 1
fi

if ! jq -e '(.mcpServers // {}) | has("qoder_github")' \
  "${CONFIG_FILE}" >/dev/null; then
  exit 0
fi

CONFIG_WRITE_TARGET="$(qoder_config_write_target "${CONFIG_FILE}")"
TMP_CONFIG="$(qoder_config_temp_file "${CONFIG_WRITE_TARGET}")"
trap 'rm -f "${TMP_CONFIG}"' EXIT

jq 'del(.mcpServers.qoder_github)' "${CONFIG_FILE}" > "${TMP_CONFIG}"
mv "${TMP_CONFIG}" "${CONFIG_WRITE_TARGET}"
echo "✓ Legacy qoder_github MCP configuration removed"
