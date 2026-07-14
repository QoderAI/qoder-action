#!/usr/bin/env bash

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

canonical_value="${INPUT_ENABLE_GITHUB_MCP:-}"
legacy_value="${INPUT_ENABLE_QODER_GITHUB_MCP:-}"

validate_boolean_input() {
  local name="$1"
  local value="$2"

  if [[ -n "${value}" && "${value}" != "true" && "${value}" != "false" ]]; then
    echo "::error::'${name}' must be 'true' or 'false'." >&2
    exit 1
  fi
}

validate_boolean_input "enable_github_mcp" "${canonical_value}"
validate_boolean_input "enable_qoder_github_mcp" "${legacy_value}"

if [[ -n "${legacy_value}" ]]; then
  echo "::warning::'enable_qoder_github_mcp' is deprecated; use 'enable_github_mcp' instead."
fi

if [[ -n "${canonical_value}" ]]; then
  enabled="${canonical_value}"
  if [[ -n "${legacy_value}" && "${legacy_value}" != "${canonical_value}" ]]; then
    echo "::warning::GitHub MCP enable inputs conflict; 'enable_github_mcp' takes precedence."
  fi
elif [[ -n "${legacy_value}" ]]; then
  enabled="${legacy_value}"
else
  enabled="true"
fi

echo "enabled=${enabled}" >> "${GITHUB_OUTPUT}"
