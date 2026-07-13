#!/usr/bin/env bash

set -euo pipefail

: "${GITHUB_MCP_BACKUP_FILE:?GITHUB_MCP_BACKUP_FILE is required}"

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required to restore the GitHub MCP configuration." >&2
  exit 1
fi

CONFIG_FILE="${HOME}/.qoder.json"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "::error::Cannot restore GitHub MCP configuration because ${CONFIG_FILE} is missing." >&2
  exit 1
fi

if [[ ! -f "${GITHUB_MCP_BACKUP_FILE}" ]]; then
  echo "::error::GitHub MCP configuration backup is missing: ${GITHUB_MCP_BACKUP_FILE}" >&2
  exit 1
fi

TMP_CONFIG="$(mktemp "${HOME}/.qoder.json.tmp.XXXXXX")"
trap 'rm -f "${TMP_CONFIG}"' EXIT

jq --slurpfile backup "${GITHUB_MCP_BACKUP_FILE}" '
  ($backup[0]) as $saved
  | if $saved.had_github then
      if .mcpServers == null then .mcpServers = {} else . end
      | .mcpServers.github = $saved.github
    else
      del(.mcpServers.github)
    end
  | if ($saved.had_mcp_servers | not)
      and (.mcpServers != null)
      and ((.mcpServers | length) == 0)
    then del(.mcpServers)
    else .
    end
' "${CONFIG_FILE}" > "${TMP_CONFIG}"

mv "${TMP_CONFIG}" "${CONFIG_FILE}"
rm -f "${GITHUB_MCP_BACKUP_FILE}"
echo "✓ Previous GitHub MCP configuration restored"
