#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_RUN=0

fail() {
  echo "not ok - $1" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

run_test() {
  local name="$1"
  shift

  "$@"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "ok ${TESTS_RUN} - ${name}"
}

create_fake_docker() {
  local bin_dir="$1"

  mkdir -p "${bin_dir}"
  cat > "${bin_dir}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'token=%s args=%s\n' "${GITHUB_PERSONAL_ACCESS_TOKEN:-missing}" "$*" >> "${FAKE_DOCKER_LOG}"
if [[ "${FAKE_DOCKER_REQUIRE_CONFIG:-false}" == "true" \
  && ! -f "${HOME}/.docker/config.json" ]]; then
  exit 43
fi
if [[ "${1:-}" == "${FAKE_DOCKER_FAIL_COMMAND:-}" ]]; then
  exit 42
fi
if [[ "${1:-}" == "pull" && -n "${FAKE_DOCKER_STARTED:-}" ]]; then
  lifecycle_pid="$(ps -o ppid= -p "${PPID}" | tr -d '[:space:]')"
  printf '%s %s\n' "${lifecycle_pid}" "${PPID}" > "${FAKE_DOCKER_STARTED}"
  if [[ -n "${FAKE_DOCKER_RELEASE:-}" ]]; then
    while [[ ! -e "${FAKE_DOCKER_RELEASE}" ]]; do
      sleep 0.05
    done
  fi
fi
exit "${FAKE_DOCKER_EXIT:-0}"
EOF
  chmod +x "${bin_dir}/docker"
}

create_fake_flock() {
  local bin_dir="$1"

  cat > "${bin_dir}/flock" <<'EOF'
#!/usr/bin/env python3
import fcntl
import sys

if len(sys.argv) != 2 or not sys.argv[1].isdigit():
    raise SystemExit("fake flock expects one file descriptor")

fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX)
EOF
  chmod +x "${bin_dir}/flock"
}

create_fake_node() {
  local bin_dir="$1"

  cat > "${bin_dir}/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

actual_github_command="$(jq -r '.mcpServers.github.command // "missing"' "${HOME}/.qoder.json")"
if [[ "${actual_github_command}" != "${FAKE_EXPECTED_GITHUB_COMMAND}" ]]; then
  exit 46
fi
if jq -e '(.mcpServers // {}) | has("qoder_github")' "${HOME}/.qoder.json" >/dev/null; then
  exit 47
fi
if [[ "${HOME}" != "${FAKE_EXPECTED_HOME}" || ! -x "${HOME}/bin/user-mcp-server" ]]; then
  exit 44
fi
if [[ ! -e /dev/fd/9 ]]; then
  exit 45
fi
lifecycle_pid="$(ps -o ppid= -p "${PPID}" | tr -d '[:space:]')"
printf '%s\n' "${lifecycle_pid}" > "${FAKE_NODE_STARTED}"

if [[ -n "${FAKE_NODE_RELEASE:-}" ]]; then
  while [[ ! -e "${FAKE_NODE_RELEASE}" ]]; do
    sleep 0.05
  done
fi

exit "${FAKE_NODE_EXIT:-0}"
EOF
  chmod +x "${bin_dir}/node"
}

create_mcp_fixture() {
  local destination="$1"
  local fixture_dir

  fixture_dir="$(mktemp -d)"
  create_fake_docker "${fixture_dir}/bin"
  create_fake_flock "${fixture_dir}/bin"
  mkdir -p "${fixture_dir}/home" "${fixture_dir}/runner-temp"
  printf -v "${destination}" '%s' "${fixture_dir}"
}

run_setup_script() {
  local test_dir="$1"
  local script_path="$2"
  shift 2

  env \
    PATH="${test_dir}/bin:${PATH}" \
    HOME="${test_dir}/home" \
    RUNNER_TEMP="${test_dir}/runner-temp" \
    GITHUB_OUTPUT="${test_dir}/github-output" \
    FAKE_DOCKER_LOG="${test_dir}/docker.log" \
    "$@" \
    bash "${script_path}"
}

run_official_setup() {
  local test_dir="$1"
  shift

  run_setup_script "${test_dir}" "${ROOT_DIR}/scripts/setup-github-mcp.sh" "$@"
}

run_legacy_setup() {
  local test_dir="$1"
  shift

  run_setup_script "${test_dir}" "${ROOT_DIR}/scripts/setup-qoder-github-mcp.sh" "$@"
}

test_mcp_defaults_to_enabled() {
  local test_dir
  local output_file
  local enabled

  test_dir="$(mktemp -d)"
  output_file="${test_dir}/github-output"

  GITHUB_OUTPUT="${output_file}" \
    bash "${ROOT_DIR}/scripts/resolve-github-mcp-enabled.sh"

  enabled="$(sed -n 's/^enabled=//p' "${output_file}")"
  assert_equals "true" "${enabled}" "MCP default"

  rm -rf "${test_dir}"
}

test_new_input_overrides_legacy_input() {
  local test_dir
  local output_file
  local log_file
  local enabled

  test_dir="$(mktemp -d)"
  output_file="${test_dir}/github-output"
  log_file="${test_dir}/log"

  INPUT_ENABLE_GITHUB_MCP="false" \
    INPUT_ENABLE_QODER_GITHUB_MCP="true" \
    GITHUB_OUTPUT="${output_file}" \
    bash "${ROOT_DIR}/scripts/resolve-github-mcp-enabled.sh" > "${log_file}"

  enabled="$(sed -n 's/^enabled=//p' "${output_file}")"
  assert_equals "false" "${enabled}" "canonical input precedence"

  if ! grep -q "::warning::.*conflict" "${log_file}"; then
    fail "conflicting inputs should emit a warning"
  fi

  rm -rf "${test_dir}"
}

test_invalid_input_fails() {
  local test_dir
  local output_file
  local log_file

  test_dir="$(mktemp -d)"
  output_file="${test_dir}/github-output"
  log_file="${test_dir}/log"

  if INPUT_ENABLE_GITHUB_MCP="sometimes" \
    GITHUB_OUTPUT="${output_file}" \
    bash "${ROOT_DIR}/scripts/resolve-github-mcp-enabled.sh" > "${log_file}" 2>&1; then
    fail "invalid canonical input should fail"
  fi

  if ! grep -q "::error::.*true.*false" "${log_file}"; then
    fail "invalid canonical input should explain valid values"
  fi

  rm -rf "${test_dir}"
}

test_setup_replaces_legacy_with_official_server() {
  local test_dir
  local actual
  local expected

  create_mcp_fixture test_dir

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "theme": "dark",
  "mcpServers": {
    "qoder_github": { "command": "qoder-github-mcp-server" },
    "other": { "command": "other-server" }
  }
}
JSON

  run_official_setup "${test_dir}" \
    GITHUB_PERSONAL_ACCESS_TOKEN="must-not-be-written"

  actual="$(jq -S . "${test_dir}/home/.qoder.json")"
  expected="$(jq -S --arg launcher "${ROOT_DIR}/scripts/run-github-mcp-server.sh" \
    '.mcpServers.github.args[0] = $launcher' <<'JSON'
{
  "theme": "dark",
  "mcpServers": {
    "other": { "command": "other-server" },
    "github": {
      "command": "bash",
      "args": [
        "",
        "ghcr.io/github/github-mcp-server:v1.5.0@sha256:e25564dccc9110a70a77b9df560cbde11aa392fcb5f08b9abe5c4ebc6d146ea4"
      ],
      "type": "stdio"
    }
  }
}
JSON
)"

  assert_equals "${expected}" "${actual}" "official GitHub MCP configuration"

  rm -rf "${test_dir}"
}

test_setup_rejects_non_regular_config() {
  local test_dir
  local log_file

  create_mcp_fixture test_dir
  mkdir "${test_dir}/home/.qoder.json"
  log_file="${test_dir}/non-regular-config.log"

  if run_official_setup "${test_dir}" > "${log_file}" 2>&1; then
    fail "setup should reject a non-regular Qoder configuration path"
  fi

  if [[ ! -d "${test_dir}/home/.qoder.json" ]]; then
    fail "setup should preserve the non-regular Qoder configuration path"
  fi
  if ! grep -q "::error::.*regular file" "${log_file}"; then
    fail "setup should explain the non-regular Qoder configuration path"
  fi
  if [[ -s "${test_dir}/docker.log" ]]; then
    fail "setup should reject a non-regular Qoder configuration before using Docker"
  fi

  rm -rf "${test_dir}"
}

test_docker_pull_failure_is_atomic() {
  local test_dir
  local after
  local expected

  create_mcp_fixture test_dir

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "qoder_github": { "command": "legacy-server" }
  }
}
JSON

  if run_official_setup "${test_dir}" \
    QODER_ACTION_ALLOW_GITHUB_MCP_REPLACE="true" \
    FAKE_DOCKER_FAIL_COMMAND="pull" >/dev/null 2>&1; then
    fail "Docker pull failure should fail setup"
  fi

  after="$(jq -S . "${test_dir}/home/.qoder.json")"
  expected="$(jq -S . <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" }
  }
}
JSON
)"
  assert_equals "${expected}" "${after}" "configuration after failed Docker pull"

  rm -rf "${test_dir}"
}

test_legacy_script_delegates_to_official_setup() {
  local test_dir
  local log_file
  local command

  create_mcp_fixture test_dir
  log_file="${test_dir}/log"

  run_legacy_setup "${test_dir}" > "${log_file}"

  if ! grep -q "::warning::.*deprecated" "${log_file}"; then
    fail "legacy setup path should emit a deprecation warning"
  fi

  command="$(jq -r '.mcpServers.github.command' "${test_dir}/home/.qoder.json")"
  assert_equals "bash" "${command}" "legacy setup delegation"

  rm -rf "${test_dir}"
}

test_legacy_setup_preserves_existing_github() {
  local test_dir
  local actual
  local expected
  local log_file

  create_mcp_fixture test_dir
  log_file="${test_dir}/legacy-existing-github.log"
  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON
  expected="$(jq -S . "${test_dir}/home/.qoder.json")"

  if run_legacy_setup "${test_dir}" > "${log_file}" 2>&1; then
    fail "legacy setup should refuse to replace an existing GitHub MCP server"
  fi

  actual="$(jq -S . "${test_dir}/home/.qoder.json")"
  assert_equals "${expected}" "${actual}" "existing GitHub MCP after legacy setup"
  if ! grep -q "::error::.*already configured" "${log_file}"; then
    fail "legacy setup should explain the existing GitHub MCP conflict"
  fi
  if [[ -s "${test_dir}/docker.log" ]]; then
    fail "legacy setup should reject an existing GitHub MCP server before using Docker"
  fi

  rm -rf "${test_dir}"
}

test_legacy_token_is_bridged_at_runtime() {
  local test_dir
  local github_env
  local runtime_command
  local runtime_log
  local runtime_token
  local runtime_args=()

  create_mcp_fixture test_dir
  github_env="${test_dir}/github-env"

  run_legacy_setup "${test_dir}" \
    GITHUB_ENV="${github_env}" \
    GITHUB_TOKEN="legacy-token" >/dev/null

  runtime_command="$(jq -r '.mcpServers.github.command' "${test_dir}/home/.qoder.json")"
  while IFS= read -r argument; do
    runtime_args+=("${argument}")
  done < <(jq -r '.mcpServers.github.args[]' "${test_dir}/home/.qoder.json")
  runtime_token="$(sed -n 's/^GITHUB_PERSONAL_ACCESS_TOKEN=//p' "${github_env}")"
  assert_equals "legacy-token" "${runtime_token}" "legacy token propagation across steps"

  : > "${test_dir}/docker.log"
  env -u GITHUB_TOKEN \
    PATH="${test_dir}/bin:${PATH}" \
    GITHUB_PERSONAL_ACCESS_TOKEN="${runtime_token}" \
    FAKE_DOCKER_LOG="${test_dir}/docker.log" \
    "${runtime_command}" "${runtime_args[@]}"

  runtime_log="$(cat "${test_dir}/docker.log")"
  assert_equals \
    "token=legacy-token args=run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN -e GITHUB_HOST -e GITHUB_TOOLSETS -e GITHUB_TOOLS -e GITHUB_READ_ONLY -e GITHUB_LOCKDOWN_MODE ghcr.io/github/github-mcp-server:v1.5.0@sha256:e25564dccc9110a70a77b9df560cbde11aa392fcb5f08b9abe5c4ebc6d146ea4" \
    "${runtime_log}" \
    "legacy token runtime bridge"

  if grep -q "legacy-token" "${test_dir}/home/.qoder.json"; then
    fail "legacy token must not be written to the MCP configuration"
  fi

  rm -rf "${test_dir}"
}

test_legacy_config_is_removed_without_official_setup() {
  local test_dir
  local actual
  local expected

  test_dir="$(mktemp -d)"
  mkdir -p "${test_dir}/home"

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "qoder_github": {
      "command": "legacy-server",
      "env": { "GITHUB_TOKEN": "legacy-token-on-disk" }
    },
    "other": { "command": "other-server" }
  }
}
JSON

  HOME="${test_dir}/home" \
    bash "${ROOT_DIR}/scripts/remove-legacy-github-mcp.sh"

  actual="$(jq -S . "${test_dir}/home/.qoder.json")"
  expected="$(jq -S . <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON
)"

  assert_equals "${expected}" "${actual}" "disabled-path legacy migration"

  rm -rf "${test_dir}"
}

test_lifecycle_preserves_symlinked_config() {
  local test_dir
  local actual
  local expected
  local config_target
  local release_file

  create_mcp_fixture test_dir
  create_fake_node "${test_dir}/bin"
  mkdir -p "${test_dir}/home/.docker" "${test_dir}/home/bin" "${test_dir}/home/dotfiles"
  printf '{}\n' > "${test_dir}/home/.docker/config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${test_dir}/home/bin/user-mcp-server"
  chmod +x "${test_dir}/home/bin/user-mcp-server"

  config_target="${test_dir}/home/dotfiles/qoder.json"
  cat > "${config_target}" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "qoder_github": { "command": "legacy-server" },
    "other": { "command": "other-server" }
  }
}
JSON
  ln -s "dotfiles/qoder.json" "${test_dir}/home/.qoder.json"
  release_file="${test_dir}/release-symlink"
  touch "${release_file}"

  run_locked_lifecycle \
    "${test_dir}" "symlink" "${test_dir}/started-symlink" "${release_file}" \
    > "${test_dir}/run-symlink.log" 2>&1

  if [[ ! -L "${test_dir}/home/.qoder.json" ]]; then
    fail "lifecycle should preserve a symlinked Qoder configuration"
  fi
  assert_equals \
    "dotfiles/qoder.json" \
    "$(readlink "${test_dir}/home/.qoder.json")" \
    "Qoder configuration symlink target"

  actual="$(jq -S . "${config_target}")"
  expected="$(jq -S . <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON
)"
  assert_equals "${expected}" "${actual}" "symlink target after GitHub MCP lifecycle"

  rm -rf "${test_dir}"
}

test_qoder_wrapper_forwards_lock_lease() {
  local test_dir
  local output_file
  local error_file

  test_dir="$(mktemp -d)"
  mkdir -p "${test_dir}/bin"
  cat > "${test_dir}/bin/qodercli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${QODER_ACTION_LOCK_FD:-}" != "9" || ! -e /dev/fd/9 ]]; then
  exit 55
fi
EOF
  chmod +x "${test_dir}/bin/qodercli"

  (
    exec 9>> "${test_dir}/lock"
    PATH="${test_dir}/bin:${PATH}" \
      QODER_ACTION_LOCK_FD="9" \
      GITHUB_WORKSPACE="${ROOT_DIR}" \
      GITHUB_OUTPUT="${test_dir}/github-output" \
      INPUT_PROMPT="" \
      INPUT_FLAGS="" \
      node "${ROOT_DIR}/scripts/qoder-wrapper.js" \
      > "${test_dir}/wrapper.log" 2>&1
  )

  output_file="$(sed -n 's/^output_file=//p' "${test_dir}/github-output")"
  error_file="${output_file/qoder-output-/qoder-error-}"
  rm -f "${output_file}" "${error_file}"
  rm -rf "${test_dir}"
}

run_locked_lifecycle() {
  local test_dir="$1"
  local run_id="$2"
  local started_file="$3"
  local release_file="$4"
  local node_exit="${5:-0}"
  local enabled="${6:-true}"
  local expected_github_command="${7:-bash}"
  local personal_access_token=""

  if [[ "${enabled}" == "true" ]]; then
    personal_access_token="runtime-token"
  fi

  env \
    PATH="${test_dir}/bin:${PATH}" \
    HOME="${test_dir}/home" \
    RUNNER_TEMP="${test_dir}/runner-temp" \
    GITHUB_WORKSPACE="${ROOT_DIR}" \
    GITHUB_ACTION_PATH="${ROOT_DIR}" \
    GITHUB_OUTPUT="${test_dir}/run-${run_id}-output" \
    ENABLE_GITHUB_MCP="${enabled}" \
    GITHUB_TOKEN="runtime-token" \
    GITHUB_PERSONAL_ACCESS_TOKEN="${personal_access_token}" \
    FAKE_DOCKER_LOG="${test_dir}/docker.log" \
    FAKE_DOCKER_FAIL_COMMAND="${FAKE_DOCKER_FAIL_COMMAND:-}" \
    FAKE_DOCKER_REQUIRE_CONFIG="true" \
    FAKE_DOCKER_STARTED="${FAKE_DOCKER_STARTED:-}" \
    FAKE_DOCKER_RELEASE="${FAKE_DOCKER_RELEASE:-}" \
    FAKE_EXPECTED_HOME="${test_dir}/home" \
    FAKE_EXPECTED_GITHUB_COMMAND="${expected_github_command}" \
    FAKE_NODE_STARTED="${started_file}" \
    FAKE_NODE_RELEASE="${release_file}" \
    FAKE_NODE_EXIT="${node_exit}" \
    bash "${ROOT_DIR}/scripts/run-qodercli-with-github-mcp.sh"
}

wait_for_file() {
  local file="$1"
  local attempts=0

  while [[ ! -e "${file}" && "${attempts}" -lt 200 ]]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done

  [[ -e "${file}" ]]
}

wait_for_process_exit() {
  local pid="$1"
  local attempts=0

  while kill -0 "${pid}" 2>/dev/null && [[ "${attempts}" -lt 200 ]]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done

  ! kill -0 "${pid}" 2>/dev/null
}

test_concurrent_runs_serialize_shared_home() {
  local test_dir
  local pid_a
  local pid_b
  local original_before
  local original_after
  local started_a
  local started_b
  local release_a
  local release_b

  create_mcp_fixture test_dir
  create_fake_node "${test_dir}/bin"
  mkdir -p "${test_dir}/home/.docker" "${test_dir}/home/bin"
  printf '{"auths":{"registry.example.com":{}}}\n' > "${test_dir}/home/.docker/config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${test_dir}/home/bin/user-mcp-server"
  chmod +x "${test_dir}/home/bin/user-mcp-server"

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON
  original_before="$(jq -S . "${test_dir}/home/.qoder.json")"

  started_a="${test_dir}/started-a"
  started_b="${test_dir}/started-b"
  release_a="${test_dir}/release-a"
  release_b="${test_dir}/release-b"
  touch "${release_b}"

  run_locked_lifecycle "${test_dir}" "a" "${started_a}" "${release_a}" \
    > "${test_dir}/run-a.log" 2>&1 &
  pid_a=$!
  if ! wait_for_file "${started_a}"; then
    wait "${pid_a}" || true
    fail "first locked lifecycle did not start"
  fi

  run_locked_lifecycle "${test_dir}" "b" "${started_b}" "${release_b}" \
    > "${test_dir}/run-b.log" 2>&1 &
  pid_b=$!
  sleep 0.5
  if [[ -e "${started_b}" ]]; then
    kill "${pid_a}" "${pid_b}" 2>/dev/null || true
    fail "second lifecycle entered qodercli before the first released the lock"
  fi

  touch "${release_a}"
  wait "${pid_a}"
  wait "${pid_b}"

  if [[ ! -e "${started_b}" ]]; then
    fail "second lifecycle did not start after the first released the lock"
  fi

  original_after="$(jq -S . "${test_dir}/home/.qoder.json")"
  assert_equals "${original_before}" "${original_after}" "shared HOME after serialized lifecycles"

  rm -rf "${test_dir}"
}

test_disabled_run_waits_for_enabled_restore() {
  local test_dir
  local docker_calls
  local pid_enabled
  local pid_disabled
  local release_disabled
  local release_enabled
  local started_disabled
  local started_enabled

  create_mcp_fixture test_dir
  create_fake_node "${test_dir}/bin"
  mkdir -p "${test_dir}/home/.docker" "${test_dir}/home/bin"
  printf '{}\n' > "${test_dir}/home/.docker/config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${test_dir}/home/bin/user-mcp-server"
  chmod +x "${test_dir}/home/bin/user-mcp-server"

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON

  started_enabled="${test_dir}/started-enabled"
  started_disabled="${test_dir}/started-disabled"
  release_enabled="${test_dir}/release-enabled"
  release_disabled="${test_dir}/release-disabled"
  touch "${release_disabled}"

  run_locked_lifecycle \
    "${test_dir}" "enabled" "${started_enabled}" "${release_enabled}" \
    > "${test_dir}/run-enabled.log" 2>&1 &
  pid_enabled=$!
  if ! wait_for_file "${started_enabled}"; then
    wait "${pid_enabled}" || true
    fail "enabled lifecycle did not start"
  fi

  run_locked_lifecycle \
    "${test_dir}" "disabled" "${started_disabled}" "${release_disabled}" \
    "0" "false" "user-github-server" \
    > "${test_dir}/run-disabled.log" 2>&1 &
  pid_disabled=$!
  sleep 0.5
  if [[ -e "${started_disabled}" ]]; then
    kill "${pid_enabled}" "${pid_disabled}" 2>/dev/null || true
    fail "disabled lifecycle read the temporary GitHub MCP configuration"
  fi

  touch "${release_enabled}"
  wait "${pid_enabled}"
  wait "${pid_disabled}"

  docker_calls="$(wc -l < "${test_dir}/docker.log" | tr -d ' ')"
  assert_equals "2" "${docker_calls}" "disabled lifecycle Docker calls"

  rm -rf "${test_dir}"
}

test_disabled_run_migrates_legacy_before_qodercli() {
  local test_dir
  local actual
  local expected
  local release_file

  create_mcp_fixture test_dir
  create_fake_node "${test_dir}/bin"
  mkdir -p "${test_dir}/home/.docker" "${test_dir}/home/bin"
  printf '{}\n' > "${test_dir}/home/.docker/config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${test_dir}/home/bin/user-mcp-server"
  chmod +x "${test_dir}/home/bin/user-mcp-server"

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "qoder_github": { "command": "legacy-server" },
    "other": { "command": "other-server" }
  }
}
JSON
  release_file="${test_dir}/release"
  touch "${release_file}"

  run_locked_lifecycle \
    "${test_dir}" "disabled-migration" "${test_dir}/started-disabled-migration" "${release_file}" \
    "0" "false" "user-github-server" \
    > "${test_dir}/run-disabled-migration.log" 2>&1

  actual="$(jq -S . "${test_dir}/home/.qoder.json")"
  expected="$(jq -S . <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON
)"
  assert_equals "${expected}" "${actual}" "disabled lifecycle legacy migration"

  rm -rf "${test_dir}"
}

test_next_run_recovers_after_sigkill() {
  local test_dir
  local killed_pid
  local lifecycle_job_pid
  local original_before
  local original_after
  local release_killed
  local release_retry
  local retry_pid
  local started_killed
  local started_retry

  create_mcp_fixture test_dir
  create_fake_node "${test_dir}/bin"
  mkdir -p "${test_dir}/home/.docker" "${test_dir}/home/bin"
  printf '{}\n' > "${test_dir}/home/.docker/config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${test_dir}/home/bin/user-mcp-server"
  chmod +x "${test_dir}/home/bin/user-mcp-server"

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON
  original_before="$(jq -S . "${test_dir}/home/.qoder.json")"
  started_killed="${test_dir}/started-killed"
  release_killed="${test_dir}/release-killed"
  release_retry="${test_dir}/release-retry"
  started_retry="${test_dir}/started-recover"
  touch "${release_retry}"

  run_locked_lifecycle \
    "${test_dir}" "killed" "${started_killed}" "${release_killed}" \
    > "${test_dir}/run-killed.log" 2>&1 &
  lifecycle_job_pid=$!
  if ! wait_for_file "${started_killed}"; then
    wait "${lifecycle_job_pid}" || true
    fail "lifecycle selected for SIGKILL did not start"
  fi

  killed_pid="$(cat "${started_killed}")"
  if [[ ! "${killed_pid}" =~ ^[0-9]+$ ]]; then
    fail "fake node did not report the lifecycle PID"
  fi
  kill -KILL "${killed_pid}"
  if wait "${lifecycle_job_pid}" 2>/dev/null; then
    fail "SIGKILL should terminate the lifecycle"
  fi

  run_locked_lifecycle \
    "${test_dir}" "recover" "${started_retry}" "${release_retry}" \
    "0" "false" "user-github-server" \
    > "${test_dir}/run-recover.log" 2>&1 &
  retry_pid=$!
  sleep 0.5
  if [[ -e "${started_retry}" ]]; then
    touch "${release_killed}"
    wait "${retry_pid}" || true
    fail "recovery started while the killed lifecycle's qodercli was still running"
  fi

  touch "${release_killed}"
  wait "${retry_pid}"
  if [[ ! -e "${started_retry}" ]]; then
    fail "recovery did not start after the orphaned qodercli released the lock"
  fi

  original_after="$(jq -S . "${test_dir}/home/.qoder.json")"
  assert_equals "${original_before}" "${original_after}" "shared HOME after SIGKILL recovery"
  if [[ -e "${test_dir}/home/.qoder-action-github-mcp-backup.json" ]]; then
    fail "SIGKILL recovery should consume the persistent backup journal"
  fi

  rm -rf "${test_dir}"
}

test_next_run_waits_for_orphaned_setup() {
  local test_dir
  local lifecycle_job_pid
  local lifecycle_pid
  local release_retry
  local release_setup
  local retry_pid
  local setup_pid
  local started_retry
  local started_setup

  create_mcp_fixture test_dir
  create_fake_node "${test_dir}/bin"
  mkdir -p "${test_dir}/home/.docker" "${test_dir}/home/bin"
  printf '{}\n' > "${test_dir}/home/.docker/config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${test_dir}/home/bin/user-mcp-server"
  chmod +x "${test_dir}/home/bin/user-mcp-server"
  printf '{"mcpServers":{"github":{"command":"user-github-server"}}}\n' \
    > "${test_dir}/home/.qoder.json"

  started_setup="${test_dir}/started-setup"
  release_setup="${test_dir}/release-setup"
  started_retry="${test_dir}/started-after-setup"
  release_retry="${test_dir}/release-retry-after-setup"
  touch "${release_retry}"

  FAKE_DOCKER_STARTED="${started_setup}" \
    FAKE_DOCKER_RELEASE="${release_setup}" \
    run_locked_lifecycle \
      "${test_dir}" "orphaned-setup" "${test_dir}/unused-node-start" "${test_dir}/unused-node-release" \
      > "${test_dir}/run-orphaned-setup.log" 2>&1 &
  lifecycle_job_pid=$!
  if ! wait_for_file "${started_setup}"; then
    wait "${lifecycle_job_pid}" || true
    fail "GitHub MCP setup did not reach the blocking Docker pull"
  fi

  read -r lifecycle_pid setup_pid < "${started_setup}"
  kill -KILL "${lifecycle_pid}"
  wait "${lifecycle_job_pid}" 2>/dev/null || true

  run_locked_lifecycle \
    "${test_dir}" "after-orphaned-setup" "${started_retry}" "${release_retry}" \
    "0" "false" "user-github-server" \
    > "${test_dir}/run-after-orphaned-setup.log" 2>&1 &
  retry_pid=$!
  sleep 0.5
  if [[ -e "${started_retry}" ]]; then
    touch "${release_setup}"
    wait "${retry_pid}" || true
    wait_for_process_exit "${setup_pid}" || true
    fail "a new lifecycle started while an orphaned setup still owned configuration work"
  fi

  touch "${release_setup}"
  wait "${retry_pid}"
  if [[ ! -e "${started_retry}" ]]; then
    fail "the waiting lifecycle did not start after orphaned setup released the lock"
  fi

  rm -rf "${test_dir}"
}

test_recovery_preserves_new_user_github() {
  local test_dir
  local actual
  local expected
  local killed_pid
  local lifecycle_job_pid
  local release_killed
  local started_killed
  local tmp_config

  create_mcp_fixture test_dir
  create_fake_node "${test_dir}/bin"
  mkdir -p "${test_dir}/home/.docker" "${test_dir}/home/bin"
  printf '{}\n' > "${test_dir}/home/.docker/config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${test_dir}/home/bin/user-mcp-server"
  chmod +x "${test_dir}/home/bin/user-mcp-server"
  printf '{"mcpServers":{"other":{"command":"other-server"}}}\n' \
    > "${test_dir}/home/.qoder.json"

  started_killed="${test_dir}/started-conflict"
  release_killed="${test_dir}/release-conflict"
  run_locked_lifecycle \
    "${test_dir}" "conflict" "${started_killed}" "${release_killed}" \
    > "${test_dir}/run-conflict.log" 2>&1 &
  lifecycle_job_pid=$!
  if ! wait_for_file "${started_killed}"; then
    wait "${lifecycle_job_pid}" || true
    fail "lifecycle selected for recovery conflict did not start"
  fi

  killed_pid="$(cat "${started_killed}")"
  kill -KILL "${killed_pid}"
  wait "${lifecycle_job_pid}" 2>/dev/null || true

  tmp_config="$(mktemp "${test_dir}/home/.qoder.json.user.XXXXXX")"
  jq '.mcpServers.github = {"command":"new-user-server"}' \
    "${test_dir}/home/.qoder.json" > "${tmp_config}"
  mv "${tmp_config}" "${test_dir}/home/.qoder.json"
  touch "${release_killed}"

  if run_locked_lifecycle \
    "${test_dir}" "conflict-recovery" "${test_dir}/started-conflict-recovery" "${release_killed}" \
    "0" "false" "new-user-server" \
    > "${test_dir}/run-conflict-recovery.log" 2>&1; then
    fail "recovery should stop when the user GitHub MCP entry changed"
  fi

  actual="$(jq -S . "${test_dir}/home/.qoder.json")"
  expected="$(jq -S . <<'JSON'
{
  "mcpServers": {
    "github": { "command": "new-user-server" },
    "other": { "command": "other-server" }
  }
}
JSON
)"
  assert_equals "${expected}" "${actual}" "user GitHub MCP entry after recovery conflict"
  if [[ ! -f "${test_dir}/home/.qoder-action-github-mcp-backup.json" ]]; then
    fail "recovery conflict should retain the backup journal"
  fi
  if ! grep -q "mcpServers.github changed" "${test_dir}/run-conflict-recovery.log"; then
    fail "recovery conflict should explain why automatic restoration stopped"
  fi

  rm -rf "${test_dir}"
}

test_failed_setup_consumes_prepared_journal() {
  local test_dir
  local original_before
  local original_after
  local release_file

  create_mcp_fixture test_dir
  mkdir -p "${test_dir}/home/.docker"
  printf '{}\n' > "${test_dir}/home/.docker/config.json"
  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON
  original_before="$(jq -S . "${test_dir}/home/.qoder.json")"
  release_file="${test_dir}/release-failed-setup"
  touch "${release_file}"

  if FAKE_DOCKER_FAIL_COMMAND="pull" run_locked_lifecycle \
    "${test_dir}" "failed-setup" "${test_dir}/started-failed-setup" "${release_file}" \
    > "${test_dir}/run-failed-setup.log" 2>&1; then
    fail "failed GitHub MCP setup should fail the lifecycle"
  fi

  original_after="$(jq -S . "${test_dir}/home/.qoder.json")"
  assert_equals "${original_before}" "${original_after}" "shared HOME after failed setup"
  if [[ -e "${test_dir}/home/.qoder-action-github-mcp-backup.json" ]]; then
    fail "failed setup should consume a prepared journal after confirming the original entry"
  fi

  rm -rf "${test_dir}"
}

test_invalid_recovery_journal_is_retained() {
  local test_dir
  local release_file

  create_mcp_fixture test_dir
  printf '{}\n' > "${test_dir}/home/.qoder.json"
  printf '{}\n' > "${test_dir}/home/.qoder-action-github-mcp-backup.json"
  release_file="${test_dir}/release-invalid-journal"
  touch "${release_file}"

  if run_locked_lifecycle \
    "${test_dir}" "invalid-journal" "${test_dir}/started-invalid-journal" "${release_file}" \
    "0" "false" "missing" \
    > "${test_dir}/run-invalid-journal.log" 2>&1; then
    fail "invalid recovery journal should stop the lifecycle"
  fi

  if [[ ! -f "${test_dir}/home/.qoder-action-github-mcp-backup.json" ]]; then
    fail "invalid recovery journal should be retained for manual recovery"
  fi

  rm -rf "${test_dir}"
}

test_failed_run_restores_config_and_releases_lock() {
  local test_dir
  local original_before
  local original_after
  local release_file

  create_mcp_fixture test_dir
  create_fake_node "${test_dir}/bin"
  mkdir -p "${test_dir}/home/.docker" "${test_dir}/home/bin"
  printf '{}\n' > "${test_dir}/home/.docker/config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${test_dir}/home/bin/user-mcp-server"
  chmod +x "${test_dir}/home/bin/user-mcp-server"

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON
  original_before="$(jq -S . "${test_dir}/home/.qoder.json")"
  release_file="${test_dir}/release"
  touch "${release_file}"

  if run_locked_lifecycle \
    "${test_dir}" "failed" "${test_dir}/started-failed" "${release_file}" "42" \
    > "${test_dir}/run-failed.log" 2>&1; then
    fail "failed qodercli run should propagate its exit status"
  fi

  run_locked_lifecycle \
    "${test_dir}" "retry" "${test_dir}/started-retry" "${release_file}" \
    > "${test_dir}/run-retry.log" 2>&1

  original_after="$(jq -S . "${test_dir}/home/.qoder.json")"
  assert_equals "${original_before}" "${original_after}" "shared HOME after failed run and retry"

  rm -rf "${test_dir}"
}

test_null_mcp_servers_shape_is_restored() {
  local test_dir
  local original_before
  local original_after
  local release_file

  create_mcp_fixture test_dir
  create_fake_node "${test_dir}/bin"
  mkdir -p "${test_dir}/home/.docker" "${test_dir}/home/bin"
  printf '{}\n' > "${test_dir}/home/.docker/config.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${test_dir}/home/bin/user-mcp-server"
  chmod +x "${test_dir}/home/bin/user-mcp-server"

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "theme": "dark",
  "mcpServers": null
}
JSON
  original_before="$(jq -S . "${test_dir}/home/.qoder.json")"
  release_file="${test_dir}/release"
  touch "${release_file}"

  run_locked_lifecycle \
    "${test_dir}" "null-shape" "${test_dir}/started-null" "${release_file}" \
    > "${test_dir}/run-null.log" 2>&1

  original_after="$(jq -S . "${test_dir}/home/.qoder.json")"
  assert_equals "${original_before}" "${original_after}" "null mcpServers restoration"

  rm -rf "${test_dir}"
}

run_test "GitHub MCP defaults to enabled" test_mcp_defaults_to_enabled
run_test "canonical input wins conflicts" test_new_input_overrides_legacy_input
run_test "invalid enable input fails" test_invalid_input_fails
run_test "setup replaces legacy server with official server" test_setup_replaces_legacy_with_official_server
run_test "setup rejects a non-regular Qoder configuration" test_setup_rejects_non_regular_config
run_test "Docker pull failure only leaves permanent legacy migration" test_docker_pull_failure_is_atomic
run_test "legacy setup script delegates to official setup" test_legacy_script_delegates_to_official_setup
run_test "legacy setup preserves an existing GitHub MCP server" test_legacy_setup_preserves_existing_github
run_test "legacy token crosses steps without entering Qoder config" test_legacy_token_is_bridged_at_runtime
run_test "legacy config is removed even without official setup" test_legacy_config_is_removed_without_official_setup
run_test "lifecycle preserves a symlinked Qoder configuration" test_lifecycle_preserves_symlinked_config
run_test "qoder wrapper forwards the lock lease" test_qoder_wrapper_forwards_lock_lease
run_test "concurrent runs serialize the shared Qoder configuration" test_concurrent_runs_serialize_shared_home
run_test "disabled runs wait for enabled configuration restore" test_disabled_run_waits_for_enabled_restore
run_test "disabled runs migrate legacy config before qodercli" test_disabled_run_migrates_legacy_before_qodercli
run_test "next run recovers configuration after SIGKILL" test_next_run_recovers_after_sigkill
run_test "next run waits for orphaned setup" test_next_run_waits_for_orphaned_setup
run_test "recovery preserves a new user GitHub MCP entry" test_recovery_preserves_new_user_github
run_test "failed setup consumes a prepared journal" test_failed_setup_consumes_prepared_journal
run_test "invalid recovery journal is retained" test_invalid_recovery_journal_is_retained
run_test "failed runs restore configuration and release the lock" test_failed_run_restores_config_and_releases_lock
run_test "null mcpServers shape is restored" test_null_mcp_servers_shape_is_restored

echo "1..${TESTS_RUN}"
