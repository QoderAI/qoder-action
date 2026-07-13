#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./github-mcp-common.sh
source "${SCRIPT_DIR}/github-mcp-common.sh"

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

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
echo "::group::Pulling official GitHub MCP Server image"
if ! docker pull "${IMAGE}"; then
  echo "::endgroup::"
  echo "::error::Failed to pull ${IMAGE}. If ghcr.io has stale credentials, run 'docker logout ghcr.io' and retry." >&2
  exit 1
fi
echo "::endgroup::"

CONFIG_FILE="${HOME}/.qoder.json"
TMP_CONFIG=""
BACKUP_FILE=""
SETUP_COMPLETE="false"

cleanup() {
  if [[ -n "${TMP_CONFIG}" ]]; then
    rm -f "${TMP_CONFIG}"
  fi
  if [[ "${SETUP_COMPLETE}" != "true" && -n "${BACKUP_FILE}" && -f "${BACKUP_FILE}" ]]; then
    GITHUB_MCP_BACKUP_FILE="${BACKUP_FILE}" \
      bash "${SCRIPT_DIR}/cleanup-github-mcp.sh" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p "${HOME}"
TMP_CONFIG="$(mktemp "${HOME}/.qoder.json.tmp.XXXXXX")"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "{}" > "${CONFIG_FILE}"
fi

if ! jq -e 'type == "object" and ((.mcpServers // {}) | type == "object")' \
  "${CONFIG_FILE}" >/dev/null; then
  echo "::error::${CONFIG_FILE} must contain a JSON object with an optional object-valued mcpServers field." >&2
  exit 1
fi

BACKUP_FILE="$(mktemp "${RUNNER_TEMP}/qoder-github-mcp-backup.XXXXXX.json")"

jq '{
  "had_mcp_servers": has("mcpServers"),
  "had_github": ((.mcpServers // {}) | has("github")),
  "github": (.mcpServers.github // null)
}' "${CONFIG_FILE}" > "${BACKUP_FILE}"
chmod 600 "${BACKUP_FILE}"

jq --arg image "${IMAGE}" '
  if .mcpServers == null then .mcpServers = {} else . end
  | del(.mcpServers.qoder_github)
  | .mcpServers.github = {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
        "-e", "GITHUB_HOST",
        "-e", "GITHUB_TOOLSETS",
        "-e", "GITHUB_TOOLS",
        "-e", "GITHUB_READ_ONLY",
        "-e", "GITHUB_LOCKDOWN_MODE",
        $image
      ],
      "type": "stdio"
    }
' "${CONFIG_FILE}" > "${TMP_CONFIG}"

mv "${TMP_CONFIG}" "${CONFIG_FILE}"
echo "backup_file=${BACKUP_FILE}" >> "${GITHUB_OUTPUT}"
SETUP_COMPLETE="true"
echo "✓ Official GitHub MCP Server configured at ${CONFIG_FILE}"
