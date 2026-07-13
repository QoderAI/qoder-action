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
if [[ "${1:-}" == "${FAKE_DOCKER_FAIL_COMMAND:-}" ]]; then
  exit 42
fi
exit "${FAKE_DOCKER_EXIT:-0}"
EOF
  chmod +x "${bin_dir}/docker"
}

create_mcp_fixture() {
  local destination="$1"
  local fixture_dir

  fixture_dir="$(mktemp -d)"
  create_fake_docker "${fixture_dir}/bin"
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

test_legacy_token_is_bridged_at_runtime() {
  local test_dir
  local runtime_command
  local runtime_log
  local runtime_args=()

  create_mcp_fixture test_dir

  run_legacy_setup "${test_dir}" GITHUB_TOKEN="legacy-token" >/dev/null

  runtime_command="$(jq -r '.mcpServers.github.command' "${test_dir}/home/.qoder.json")"
  while IFS= read -r argument; do
    runtime_args+=("${argument}")
  done < <(jq -r '.mcpServers.github.args[]' "${test_dir}/home/.qoder.json")

  : > "${test_dir}/docker.log"
  env -u GITHUB_PERSONAL_ACCESS_TOKEN \
    PATH="${test_dir}/bin:${PATH}" \
    GITHUB_TOKEN="legacy-token" \
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

test_concurrent_runs_use_isolated_qoder_homes() {
  local test_dir
  local qoder_home_a
  local qoder_home_b
  local original_before
  local original_after

  create_mcp_fixture test_dir

  cat > "${test_dir}/home/.qoder.json" <<'JSON'
{
  "mcpServers": {
    "github": { "command": "user-github-server" },
    "other": { "command": "other-server" }
  }
}
JSON
  original_before="$(jq -S . "${test_dir}/home/.qoder.json")"

  HOME="${test_dir}/home" \
    RUNNER_TEMP="${test_dir}/runner-temp" \
    GITHUB_OUTPUT="${test_dir}/prepare-a-output" \
    bash "${ROOT_DIR}/scripts/prepare-qoder-home.sh"
  HOME="${test_dir}/home" \
    RUNNER_TEMP="${test_dir}/runner-temp" \
    GITHUB_OUTPUT="${test_dir}/prepare-b-output" \
    bash "${ROOT_DIR}/scripts/prepare-qoder-home.sh"

  qoder_home_a="$(sed -n 's/^qoder_home=//p' "${test_dir}/prepare-a-output")"
  qoder_home_b="$(sed -n 's/^qoder_home=//p' "${test_dir}/prepare-b-output")"
  if [[ -z "${qoder_home_a}" || -z "${qoder_home_b}" || "${qoder_home_a}" == "${qoder_home_b}" ]]; then
    fail "concurrent runs should receive distinct Qoder homes"
  fi

  run_official_setup "${test_dir}" \
    HOME="${qoder_home_a}" \
    GITHUB_OUTPUT="${test_dir}/setup-a-output"
  run_official_setup "${test_dir}" \
    HOME="${qoder_home_b}" \
    GITHUB_OUTPUT="${test_dir}/setup-b-output"

  original_after="$(jq -S . "${test_dir}/home/.qoder.json")"
  assert_equals "${original_before}" "${original_after}" "shared HOME after concurrent setup"

  RUNNER_TEMP="${test_dir}/runner-temp" \
    QODER_ACTION_HOME="${qoder_home_a}" \
    bash "${ROOT_DIR}/scripts/cleanup-qoder-home.sh"
  RUNNER_TEMP="${test_dir}/runner-temp" \
    QODER_ACTION_HOME="${qoder_home_b}" \
    bash "${ROOT_DIR}/scripts/cleanup-qoder-home.sh"

  if [[ -e "${qoder_home_a}" || -e "${qoder_home_b}" ]]; then
    fail "run-scoped Qoder homes should be removed independently"
  fi

  rm -rf "${test_dir}"
}

run_test "GitHub MCP defaults to enabled" test_mcp_defaults_to_enabled
run_test "canonical input wins conflicts" test_new_input_overrides_legacy_input
run_test "invalid enable input fails" test_invalid_input_fails
run_test "setup replaces legacy server with official server" test_setup_replaces_legacy_with_official_server
run_test "Docker pull failure only leaves permanent legacy migration" test_docker_pull_failure_is_atomic
run_test "legacy setup script delegates to official setup" test_legacy_script_delegates_to_official_setup
run_test "legacy token is bridged only at runtime" test_legacy_token_is_bridged_at_runtime
run_test "legacy config is removed even without official setup" test_legacy_config_is_removed_without_official_setup
run_test "concurrent runs use isolated Qoder homes" test_concurrent_runs_use_isolated_qoder_homes

echo "1..${TESTS_RUN}"
