#!/usr/bin/env bash

set -euo pipefail

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

TMP_CONFIG="$(mktemp "${HOME}/.qoder.json.tmp.XXXXXX")"
trap 'rm -f "${TMP_CONFIG}"' EXIT

jq 'del(.mcpServers.qoder_github)' "${CONFIG_FILE}" > "${TMP_CONFIG}"
mv "${TMP_CONFIG}" "${CONFIG_FILE}"
echo "✓ Legacy qoder_github MCP configuration removed"
