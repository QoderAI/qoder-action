#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/github-mcp-common.sh
source "${ROOT_DIR}/scripts/github-mcp-common.sh"

IMAGE="$(github_mcp_server_image)"

docker pull "${IMAGE}"
version_output="$(docker run --rm "${IMAGE}" --version 2>&1)"

if [[ "${version_output}" != *"${DEFAULT_GITHUB_MCP_SERVER_VERSION}"* ]]; then
  echo "Expected GitHub MCP Server ${DEFAULT_GITHUB_MCP_SERVER_VERSION}, got: ${version_output}" >&2
  exit 1
fi

echo "✓ Official GitHub MCP Server ${DEFAULT_GITHUB_MCP_SERVER_VERSION} container started successfully"
