#!/usr/bin/env bash

readonly DEFAULT_GITHUB_MCP_SERVER_IMAGE="ghcr.io/github/github-mcp-server:v1.5.0@sha256:e25564dccc9110a70a77b9df560cbde11aa392fcb5f08b9abe5c4ebc6d146ea4"

github_mcp_server_version() {
  printf '%s\n' "1.5.0"
}

github_mcp_server_image() {
  printf '%s\n' "${GITHUB_MCP_SERVER_IMAGE:-${DEFAULT_GITHUB_MCP_SERVER_IMAGE}}"
}

github_mcp_server_entry() {
  local launcher="$1"
  local image="$2"

  jq -n --arg launcher "${launcher}" --arg image "${image}" '{
    "command": "bash",
    "args": [$launcher, $image],
    "type": "stdio"
  }'
}
