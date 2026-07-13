#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${ENABLE_GITHUB_MCP:?ENABLE_GITHUB_MCP is required}"
: "${HOME:?HOME is required}"

case "${ENABLE_GITHUB_MCP}" in
  false)
    ;;
  true)
    ;;
  *)
    echo "::error::ENABLE_GITHUB_MCP must be 'true' or 'false'." >&2
    exit 1
    ;;
esac

if ! command -v flock >/dev/null 2>&1; then
  echo "::error::flock is required to serialize qodercli on a shared runner HOME." >&2
  exit 1
fi

if [[ "${ENABLE_GITHUB_MCP}" == "true" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq is required to preserve the GitHub MCP configuration." >&2
    exit 1
  fi
fi

LOCK_FILE="${HOME}/.qoder-action-github-mcp.lock"
if [[ -L "${LOCK_FILE}" ]]; then
  echo "::error::Refusing to use a symlink as the GitHub MCP lock file: ${LOCK_FILE}" >&2
  exit 1
fi

exec 9>> "${LOCK_FILE}"
chmod 600 "${LOCK_FILE}"

BACKUP_FILE="${HOME}/.qoder-action-github-mcp-backup.json"
BACKUP_TEMP_FILE=""
BACKUP_READY="false"

restore_configuration() {
  local command_status="$1"
  local cleanup_status=0

  trap - EXIT INT TERM
  set +e

  if [[ "${BACKUP_READY}" == "true" ]]; then
    GITHUB_MCP_BACKUP_FILE="${BACKUP_FILE}" \
      bash "${SCRIPT_DIR}/cleanup-github-mcp.sh" 9>&-
    cleanup_status=$?
  fi

  if [[ -n "${BACKUP_TEMP_FILE}" && -f "${BACKUP_TEMP_FILE}" ]]; then
    rm -f "${BACKUP_TEMP_FILE}"
  fi

  if [[ "${command_status}" -eq 0 && "${cleanup_status}" -ne 0 ]]; then
    command_status="${cleanup_status}"
  fi

  exit "${command_status}"
}

trap 'restore_configuration $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Waiting for exclusive access to ${HOME}/.qoder.json..."
flock 9
echo "✓ Exclusive Qoder configuration lock acquired"

if [[ -L "${BACKUP_FILE}" ]]; then
  echo "::error::Refusing to use a symlink as the GitHub MCP backup journal: ${BACKUP_FILE}" >&2
  exit 1
fi
if [[ -e "${BACKUP_FILE}" && ! -f "${BACKUP_FILE}" ]]; then
  echo "::error::GitHub MCP backup journal is not a regular file: ${BACKUP_FILE}" >&2
  exit 1
fi
if [[ -f "${BACKUP_FILE}" ]]; then
  echo "::warning::Recovering GitHub MCP configuration from an interrupted previous run."
  GITHUB_MCP_BACKUP_FILE="${BACKUP_FILE}" \
    bash "${SCRIPT_DIR}/cleanup-github-mcp.sh" 9>&-
  echo "✓ Interrupted GitHub MCP configuration restored"
fi

bash "${SCRIPT_DIR}/remove-legacy-github-mcp.sh" 9>&-

if [[ "${ENABLE_GITHUB_MCP}" == "false" ]]; then
  bash "${SCRIPT_DIR}/run-qodercli.sh" 9>&-
  exit 0
fi

CONFIG_FILE="${HOME}/.qoder.json"
BACKUP_TEMP_FILE="$(mktemp "${HOME}/.qoder-action-github-mcp-backup.tmp.XXXXXX")"
chmod 600 "${BACKUP_TEMP_FILE}"

if [[ -f "${CONFIG_FILE}" ]]; then
  if ! jq -e 'type == "object" and ((.mcpServers // {}) | type == "object")' \
    "${CONFIG_FILE}" >/dev/null; then
    echo "::error::${CONFIG_FILE} must contain a JSON object with an optional object-valued mcpServers field." >&2
    exit 1
  fi

  jq '{
    "had_config": true,
    "had_mcp_servers": has("mcpServers"),
    "mcp_servers_was_null": (has("mcpServers") and (.mcpServers == null)),
    "had_github": ((.mcpServers // {}) | has("github")),
    "github": (.mcpServers.github // null)
  }' "${CONFIG_FILE}" > "${BACKUP_TEMP_FILE}"
else
  jq -n '{
    "had_config": false,
    "had_mcp_servers": false,
    "mcp_servers_was_null": false,
    "had_github": false,
    "github": null
  }' > "${BACKUP_TEMP_FILE}"
fi
mv "${BACKUP_TEMP_FILE}" "${BACKUP_FILE}"
BACKUP_TEMP_FILE=""
BACKUP_READY="true"

bash "${SCRIPT_DIR}/setup-github-mcp.sh" 9>&-
bash "${SCRIPT_DIR}/run-qodercli.sh" 9>&-
