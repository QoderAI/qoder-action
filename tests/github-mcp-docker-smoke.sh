#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091 # Resolved relative to the repository at runtime.
source "${ROOT_DIR}/scripts/github-mcp-common.sh"

IMAGE="$(github_mcp_server_image)"
EXPECTED_VERSION="$(github_mcp_server_version)"

docker pull "${IMAGE}"
version_output="$(docker run --rm "${IMAGE}" --version 2>&1)"

if [[ "${version_output}" != *"${EXPECTED_VERSION}"* ]]; then
  echo "Expected GitHub MCP Server ${EXPECTED_VERSION}, got: ${version_output}" >&2
  exit 1
fi

echo "✓ Official GitHub MCP Server ${EXPECTED_VERSION} container started successfully"
