#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # Resolved relative to this script at runtime.
source "${SCRIPT_DIR}/github-mcp-common.sh"

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
  if [[ "${ENABLE_GITHUB_MCP}" == "false" ]]; then
    echo "::warning::flock is unavailable; running qodercli without GitHub MCP configuration migration or shared-HOME serialization."
    bash "${SCRIPT_DIR}/run-qodercli.sh"
    exit 0
  fi
  echo "::error::flock is required to serialize qodercli on a shared runner HOME." >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "::error::node is required to validate the shared GitHub MCP lock file." >&2
  exit 1
fi

if [[ "${ENABLE_GITHUB_MCP}" == "true" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq is required to preserve the GitHub MCP configuration." >&2
    exit 1
  fi
fi

LOCK_FILE="${HOME}/.qoder-action-github-mcp.lock"
LOCK_VALIDATOR="${SCRIPT_DIR}/validate-lock-file.js"
if [[ -L "${LOCK_FILE}" || ( -e "${LOCK_FILE}" && ! -f "${LOCK_FILE}" ) ]]; then
  echo "::error::GitHub MCP lock path must be a regular file and not a symlink: ${LOCK_FILE}" >&2
  exit 1
fi

ORIGINAL_UMASK="$(umask)"
umask 077
exec 9>> "${LOCK_FILE}"
umask "${ORIGINAL_UMASK}"
if ! node "${LOCK_VALIDATOR}" "${LOCK_FILE}" 9 chmod-600; then
  exec 9>&-
  echo "::error::GitHub MCP lock path changed while it was opened: ${LOCK_FILE}" >&2
  exit 1
fi

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
      bash "${SCRIPT_DIR}/cleanup-github-mcp.sh"
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

run_qodercli_holding_lock() {
  # Keep fd 9 open in the qodercli process tree. If this lifecycle shell is
  # killed, the surviving work retains the lock until it actually finishes.
  QODER_ACTION_LOCK_FD="9" bash "${SCRIPT_DIR}/run-qodercli.sh"
}

trap 'restore_configuration $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Waiting for exclusive access to ${HOME}/.qoder.json..."
flock 9
if ! node "${LOCK_VALIDATOR}" "${LOCK_FILE}" 9; then
  echo "::error::GitHub MCP lock path changed while waiting for exclusive access: ${LOCK_FILE}" >&2
  exit 1
fi
echo "✓ Exclusive Qoder configuration lock acquired"

CONFIG_FILE="${HOME}/.qoder.json"
CONFIG_WRITE_TARGET="$(qoder_config_write_target "${CONFIG_FILE}")"

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
    bash "${SCRIPT_DIR}/cleanup-github-mcp.sh"
  echo "✓ Interrupted GitHub MCP configuration restored"
fi

bash "${SCRIPT_DIR}/remove-legacy-github-mcp.sh"

if [[ "${ENABLE_GITHUB_MCP}" == "false" ]]; then
  run_qodercli_holding_lock
  exit 0
fi

TEMPORARY_GITHUB_ENTRY="$(
  github_mcp_server_entry \
    "${SCRIPT_DIR}/run-github-mcp-server.sh" \
    "$(github_mcp_server_image)"
)"
BACKUP_TEMP_FILE="$(mktemp "${HOME}/.qoder-action-github-mcp-backup.tmp.XXXXXX")"
chmod 600 "${BACKUP_TEMP_FILE}"

if [[ -f "${CONFIG_FILE}" ]]; then
  if ! jq -e 'type == "object" and ((.mcpServers // {}) | type == "object")' \
    "${CONFIG_FILE}" >/dev/null; then
    echo "::error::${CONFIG_FILE} must contain a JSON object with an optional object-valued mcpServers field." >&2
    exit 1
  fi

  jq \
    --arg config_write_target "${CONFIG_WRITE_TARGET}" \
    --argjson temporary_github "${TEMPORARY_GITHUB_ENTRY}" '{
    "had_config": true,
    "had_mcp_servers": has("mcpServers"),
    "mcp_servers_was_null": (has("mcpServers") and (.mcpServers == null)),
    "had_github": ((.mcpServers // {}) | has("github")),
    "github": .mcpServers.github,
    "config_write_target": $config_write_target,
    "temporary_github": $temporary_github
  }' "${CONFIG_FILE}" > "${BACKUP_TEMP_FILE}"
else
  jq -n \
    --arg config_write_target "${CONFIG_WRITE_TARGET}" \
    --argjson temporary_github "${TEMPORARY_GITHUB_ENTRY}" '{
    "had_config": false,
    "had_mcp_servers": false,
    "mcp_servers_was_null": false,
    "had_github": false,
    "github": null,
    "config_write_target": $config_write_target,
    "temporary_github": $temporary_github
  }' > "${BACKUP_TEMP_FILE}"
fi
mv "${BACKUP_TEMP_FILE}" "${BACKUP_FILE}"
BACKUP_TEMP_FILE=""
BACKUP_READY="true"

QODER_ACTION_ALLOW_GITHUB_MCP_REPLACE="true" \
  bash "${SCRIPT_DIR}/setup-github-mcp.sh"
run_qodercli_holding_lock
