#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # Resolved relative to this script at runtime.
source "${SCRIPT_DIR}/github-mcp-common.sh"

: "${GITHUB_MCP_BACKUP_FILE:?GITHUB_MCP_BACKUP_FILE is required}"
: "${HOME:?HOME is required}"

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required to restore the GitHub MCP configuration." >&2
  exit 1
fi

if [[ ! -f "${GITHUB_MCP_BACKUP_FILE}" ]]; then
  echo "::error::GitHub MCP configuration backup is missing: ${GITHUB_MCP_BACKUP_FILE}" >&2
  exit 1
fi

if ! jq -e '
  type == "object"
  and (.had_config | type == "boolean")
  and (.had_mcp_servers | type == "boolean")
  and (.mcp_servers_was_null | type == "boolean")
  and (.had_github | type == "boolean")
  and (.config_write_target | type == "string" and startswith("/"))
  and (.temporary_github | type == "object")
' "${GITHUB_MCP_BACKUP_FILE}" >/dev/null; then
  echo "::error::GitHub MCP configuration backup is invalid." >&2
  exit 1
fi

CONFIG_FILE="${HOME}/.qoder.json"
CONFIG_WRITE_TARGET="$(jq -r '.config_write_target' "${GITHUB_MCP_BACKUP_FILE}")"

configuration_target_matches_journal() {
  local current_target
  local saved_target

  if ! current_target="$(qoder_config_write_target "${CONFIG_FILE}")" \
    || ! saved_target="$(qoder_config_write_target "${CONFIG_WRITE_TARGET}")" \
    || [[ "${current_target}" != "${CONFIG_WRITE_TARGET}" ]] \
    || [[ "${saved_target}" != "${CONFIG_WRITE_TARGET}" ]]; then
    echo "::error::Cannot restore GitHub MCP because the Qoder configuration target changed since this action created its backup journal. Current configuration and backup journal were preserved." >&2
    return 1
  fi
}

configuration_target_matches_journal

if [[ ! -f "${CONFIG_WRITE_TARGET}" ]]; then
  if jq -e '.had_config' "${GITHUB_MCP_BACKUP_FILE}" >/dev/null; then
    echo "::error::Cannot restore GitHub MCP because ${CONFIG_FILE} was removed during the run. Backup retained at ${GITHUB_MCP_BACKUP_FILE}." >&2
    exit 1
  fi
  rm -f "${GITHUB_MCP_BACKUP_FILE}"
  echo "✓ GitHub MCP configuration already matches the backup journal"
  exit 0
fi

if ! jq -e 'type == "object" and ((.mcpServers // {}) | type == "object")' \
  "${CONFIG_WRITE_TARGET}" >/dev/null; then
  echo "::error::${CONFIG_FILE} changed to an invalid shape while GitHub MCP was running." >&2
  exit 1
fi

CURRENT_STATE="$(jq -r --slurpfile backup "${GITHUB_MCP_BACKUP_FILE}" '
  ($backup[0]) as $saved
  | def has_github: ((.mcpServers // {}) | has("github"));
  def is_temporary_github_entry:
    . == $saved.temporary_github
    or (
      type == "object"
      and ((has("InProcessMcpServer") | not) or .InProcessMcpServer == null)
      and ((has("WorkingDir") | not) or .WorkingDir == "")
      and (del(.InProcessMcpServer, .WorkingDir) == $saved.temporary_github)
    );
  if has_github and (.mcpServers.github | is_temporary_github_entry) then
    "temporary"
  elif (($saved.had_github and has_github and (.mcpServers.github == $saved.github))
    or (($saved.had_github | not) and (has_github | not))) then
    "original"
  else
    "conflict"
  end
' "${CONFIG_WRITE_TARGET}")"

case "${CURRENT_STATE}" in
  original)
    configuration_target_matches_journal
    rm -f "${GITHUB_MCP_BACKUP_FILE}"
    echo "✓ GitHub MCP configuration already matches the backup journal"
    exit 0
    ;;
  temporary)
    ;;
  conflict)
    echo "::error::Cannot restore GitHub MCP because mcpServers.github changed since this action installed its temporary entry. Current configuration and backup journal were preserved." >&2
    exit 1
    ;;
  *)
    echo "::error::Cannot classify the current GitHub MCP configuration. Backup retained at ${GITHUB_MCP_BACKUP_FILE}." >&2
    exit 1
    ;;
esac

TMP_CONFIG="$(qoder_config_temp_file "${CONFIG_WRITE_TARGET}")"
trap 'rm -f "${TMP_CONFIG}"' EXIT

jq --slurpfile backup "${GITHUB_MCP_BACKUP_FILE}" '
  ($backup[0]) as $saved
  | if $saved.had_github then
      if .mcpServers == null then .mcpServers = {} else . end
      | .mcpServers.github = $saved.github
    else
      del(.mcpServers.github)
    end
  | if $saved.mcp_servers_was_null
      and (.mcpServers != null)
      and ((.mcpServers | length) == 0)
    then .mcpServers = null
    elif ($saved.had_mcp_servers | not)
      and (.mcpServers != null)
      and ((.mcpServers | length) == 0)
    then del(.mcpServers)
    else .
    end
' "${CONFIG_WRITE_TARGET}" > "${TMP_CONFIG}"

configuration_target_matches_journal

if jq -e --slurpfile backup "${GITHUB_MCP_BACKUP_FILE}" \
  '($backup[0].had_config | not) and (length == 0)' \
  "${TMP_CONFIG}" >/dev/null; then
  rm -f "${CONFIG_WRITE_TARGET}" "${TMP_CONFIG}"
else
  mv "${TMP_CONFIG}" "${CONFIG_WRITE_TARGET}"
fi

rm -f "${GITHUB_MCP_BACKUP_FILE}"
echo "✓ Previous GitHub MCP configuration restored"
