#!/usr/bin/env bash

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${HOME:?HOME is required}"

if [[ ! -d "${RUNNER_TEMP}" ]]; then
  echo "::error::RUNNER_TEMP does not exist: ${RUNNER_TEMP}" >&2
  exit 1
fi

SOURCE_HOME="${HOME}"
QODER_HOME="$(mktemp -d "${RUNNER_TEMP%/}/qoder-action-home.XXXXXX")"
PREPARE_COMPLETE="false"

cleanup() {
  if [[ "${PREPARE_COMPLETE}" != "true" ]]; then
    rm -rf -- "${QODER_HOME}"
  fi
}
trap cleanup EXIT

chmod 700 "${QODER_HOME}"
if [[ -f "${SOURCE_HOME}/.qoder.json" ]]; then
  cp "${SOURCE_HOME}/.qoder.json" "${QODER_HOME}/.qoder.json"
  chmod 600 "${QODER_HOME}/.qoder.json"
fi

echo "qoder_home=${QODER_HOME}" >> "${GITHUB_OUTPUT}"
PREPARE_COMPLETE="true"
echo "✓ Run-scoped Qoder home prepared"
