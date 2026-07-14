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

qoder_config_write_target() {
  local path="$1"
  local link_target
  local parent_dir
  local depth=0

  while [[ -L "${path}" ]]; do
    if [[ "${depth}" -ge 40 ]]; then
      echo "::error::Refusing to resolve a Qoder configuration symlink chain deeper than 40 links: $1" >&2
      return 1
    fi

    link_target="$(readlink "${path}")"
    if [[ "${link_target}" == /* ]]; then
      path="${link_target}"
    else
      parent_dir="$(cd -P "$(dirname "${path}")" && pwd)"
      path="${parent_dir}/${link_target}"
    fi
    depth=$((depth + 1))
  done

  if [[ -e "${path}" && ! -f "${path}" ]]; then
    echo "::error::Qoder configuration must be a regular file or a symlink to one: $1" >&2
    return 1
  fi
  if ! parent_dir="$(cd -P "$(dirname "${path}")" && pwd)"; then
    echo "::error::Qoder configuration target directory does not exist: $(dirname "${path}")" >&2
    return 1
  fi
  printf '%s/%s\n' "${parent_dir}" "$(basename "${path}")"
}

qoder_config_temp_file() {
  local write_target="$1"

  mktemp "$(dirname "${write_target}")/.$(basename "${write_target}").tmp.XXXXXX"
}
