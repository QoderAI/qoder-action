#!/usr/bin/env ruby

require "yaml"

ROOT = File.expand_path("..", __dir__)
ACTION = YAML.safe_load(File.read(File.join(ROOT, "action.yml")), aliases: true)

def assert_equal(expected, actual, message)
  return if expected == actual

  warn "not ok - #{message}: expected #{expected.inspect}, got #{actual.inspect}"
  exit 1
end

inputs = ACTION.fetch("inputs")
assert_equal("", inputs.fetch("trigger_phrase").fetch("default"), "trigger detection default")
assert_equal("", inputs.fetch("enable_github_mcp").fetch("default"), "canonical input default")
assert_equal("", inputs.fetch("enable_qoder_github_mcp").fetch("default"), "legacy input default")

steps = ACTION.fetch("runs").fetch("steps")
detect_trigger = steps.find { |step| step["id"] == "detect_trigger" }
migrate_legacy = steps.find { |step| step["id"] == "remove_legacy_github_mcp" }
resolve = steps.find { |step| step["id"] == "resolve_github_mcp" }
setup = steps.find { |step| step["id"] == "setup_github_mcp" }
run_cli = steps.find { |step| step["id"] == "run_cli" }
cleanup = steps.find { |step| step["id"] == "cleanup_github_mcp" }

assert_equal(
  "${{ inputs.trigger_phrase }}",
  detect_trigger&.dig("env", "INPUT_TRIGGER_PHRASE"),
  "trigger phrase wiring"
)
assert_equal(
  "node \"${GITHUB_ACTION_PATH}/scripts/detect-trigger.js\"",
  detect_trigger&.fetch("run")&.strip,
  "trigger detection entrypoint"
)

steps.reject { |step| step["id"] == "detect_trigger" }.each do |step|
  assert_equal(
    "steps.detect_trigger.outputs.triggered == 'true'",
    step["if"],
    "#{step.fetch('name')} trigger gate"
  )
end

assert_equal(true, migrate_legacy.nil?, "legacy migration is owned by the locked lifecycle")
assert_equal(
  "${{ inputs.enable_github_mcp }}",
  resolve&.dig("env", "INPUT_ENABLE_GITHUB_MCP"),
  "canonical input wiring"
)
assert_equal(
  true,
  setup.nil?,
  "setup is owned by the locked qodercli lifecycle"
)
assert_equal(
  true,
  cleanup.nil?,
  "cleanup is owned by the locked qodercli lifecycle"
)
assert_equal(
  nil,
  run_cli&.dig("env", "HOME"),
  "qodercli preserves the caller HOME"
)
assert_equal(
  "${{ steps.resolve_github_mcp.outputs.enabled }}",
  run_cli&.dig("env", "ENABLE_GITHUB_MCP"),
  "locked lifecycle enablement"
)
assert_equal(
  nil,
  run_cli&.dig("env", "GITHUB_PERSONAL_ACCESS_TOKEN"),
  "disabled lifecycle preserves the caller GitHub personal access token"
)
assert_equal(
  "${{ steps.resolve_github_mcp.outputs.enabled == 'true' && steps.auth.outputs.github_token || '' }}",
  run_cli&.dig("env", "QODER_ACTION_GITHUB_MCP_TOKEN"),
  "private runtime-only GitHub MCP token"
)
assert_equal(
  "${{ github.server_url }}",
  run_cli&.dig("env", "GITHUB_HOST"),
  "GitHub host wiring"
)
assert_equal(
  "bash \"${GITHUB_ACTION_PATH}/scripts/run-qodercli-with-github-mcp.sh\"",
  run_cli&.fetch("run")&.strip,
  "locked qodercli lifecycle entrypoint"
)

puts "ok - composite action GitHub MCP wiring"
