#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "::error::run-github-mcp-server.sh requires exactly one container image argument." >&2
  exit 1
fi

token="${QODER_ACTION_GITHUB_MCP_TOKEN:-${GITHUB_PERSONAL_ACCESS_TOKEN:-${GITHUB_TOKEN:-}}}"
if [[ -z "${token}" ]]; then
  echo "::error::GITHUB_PERSONAL_ACCESS_TOKEN or GITHUB_TOKEN is required to run the GitHub MCP Server." >&2
  exit 1
fi

export GITHUB_PERSONAL_ACCESS_TOKEN="${token}"
if [[ -z "${GITHUB_TOOLSETS:-}" && -z "${GITHUB_TOOLS:-}" ]]; then
  export GITHUB_TOOLSETS="context,repos,issues,pull_requests,users"
fi

exec docker run -i --rm \
  -e GITHUB_PERSONAL_ACCESS_TOKEN \
  -e GITHUB_HOST \
  -e GITHUB_TOOLSETS \
  -e GITHUB_TOOLS \
  -e GITHUB_READ_ONLY \
  -e GITHUB_LOCKDOWN_MODE \
  "$1"
