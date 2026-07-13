#!/usr/bin/env bash

set -euo pipefail

: "${QODER_ACTION_HOME:?QODER_ACTION_HOME is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

if [[ ! -e "${QODER_ACTION_HOME}" ]]; then
  exit 0
fi

if [[ -L "${QODER_ACTION_HOME}" || ! -d "${QODER_ACTION_HOME}" ]]; then
  echo "::error::Refusing to remove an invalid run-scoped Qoder home: ${QODER_ACTION_HOME}" >&2
  exit 1
fi

RUNNER_TEMP_REAL="$(cd "${RUNNER_TEMP}" && pwd -P)"
QODER_HOME_PARENT_REAL="$(cd "$(dirname "${QODER_ACTION_HOME}")" && pwd -P)"
QODER_HOME_BASENAME="$(basename "${QODER_ACTION_HOME}")"

if [[ "${QODER_HOME_PARENT_REAL}" != "${RUNNER_TEMP_REAL}" \
  || "${QODER_HOME_BASENAME}" != qoder-action-home.* ]]; then
  echo "::error::Refusing to remove Qoder home outside RUNNER_TEMP: ${QODER_ACTION_HOME}" >&2
  exit 1
fi

rm -rf -- "${QODER_ACTION_HOME}"
echo "✓ Run-scoped Qoder home removed"
