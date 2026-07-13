#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # Resolved relative to this script at runtime.
source "${SCRIPT_DIR}/github-mcp-common.sh"

bash "${SCRIPT_DIR}/remove-legacy-github-mcp.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required to configure the GitHub MCP Server." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "::error::Docker is required to run the official GitHub MCP Server." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "::error::Docker is installed but the daemon is unavailable." >&2
  exit 1
fi

IMAGE="$(github_mcp_server_image)"
LAUNCHER="${SCRIPT_DIR}/run-github-mcp-server.sh"
GITHUB_MCP_ENTRY="$(github_mcp_server_entry "${LAUNCHER}" "${IMAGE}")"
echo "::group::Pulling official GitHub MCP Server image"
if ! docker pull "${IMAGE}"; then
  echo "::endgroup::"
  echo "::error::Failed to pull ${IMAGE}. If ghcr.io has stale credentials, run 'docker logout ghcr.io' and retry." >&2
  exit 1
fi
echo "::endgroup::"

CONFIG_FILE="${HOME}/.qoder.json"
mkdir -p "${HOME}"
TMP_CONFIG="$(mktemp "${HOME}/.qoder.json.tmp.XXXXXX")"
trap 'rm -f "${TMP_CONFIG}"' EXIT
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "{}" > "${CONFIG_FILE}"
fi

jq --argjson github_mcp_entry "${GITHUB_MCP_ENTRY}" '
  if .mcpServers == null then .mcpServers = {} else . end
  | .mcpServers.github = $github_mcp_entry
' "${CONFIG_FILE}" > "${TMP_CONFIG}"

mv "${TMP_CONFIG}" "${CONFIG_FILE}"
echo "✓ Official GitHub MCP Server configured at ${CONFIG_FILE}"
