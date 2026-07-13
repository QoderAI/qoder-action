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
assert_equal("", inputs.fetch("enable_github_mcp").fetch("default"), "canonical input default")
assert_equal("", inputs.fetch("enable_qoder_github_mcp").fetch("default"), "legacy input default")

steps = ACTION.fetch("runs").fetch("steps")
migrate_legacy = steps.find { |step| step["id"] == "remove_legacy_github_mcp" }
prepare_home = steps.find { |step| step["id"] == "prepare_qoder_home" }
resolve = steps.find { |step| step["id"] == "resolve_github_mcp" }
setup = steps.find { |step| step["id"] == "setup_github_mcp" }
run_cli = steps.find { |step| step["id"] == "run_cli" }
cleanup_home = steps.find { |step| step["id"] == "cleanup_qoder_home" }

assert_equal(false, migrate_legacy.nil?, "legacy migration step")
assert_equal(false, migrate_legacy&.key?("if"), "unconditional legacy migration")
assert_equal(false, prepare_home.nil?, "run-scoped Qoder home preparation")
assert_equal(false, prepare_home&.key?("if"), "unconditional Qoder home preparation")
assert_equal(
  true,
  steps.index(migrate_legacy) < steps.index(prepare_home),
  "legacy migration precedes Qoder home copy"
)
assert_equal(
  "${{ inputs.enable_github_mcp }}",
  resolve&.dig("env", "INPUT_ENABLE_GITHUB_MCP"),
  "canonical input wiring"
)
assert_equal(
  "steps.resolve_github_mcp.outputs.enabled == 'true'",
  setup&.fetch("if"),
  "official setup condition"
)
assert_equal(
  "${{ steps.prepare_qoder_home.outputs.qoder_home }}",
  setup&.dig("env", "HOME"),
  "isolated setup HOME"
)
assert_equal(
  "${{ steps.prepare_qoder_home.outputs.qoder_home }}",
  run_cli&.dig("env", "HOME"),
  "isolated qodercli HOME"
)
assert_equal(
  "${{ steps.resolve_github_mcp.outputs.enabled == 'true' && steps.auth.outputs.github_token || '' }}",
  run_cli&.dig("env", "GITHUB_PERSONAL_ACCESS_TOKEN"),
  "runtime-only GitHub MCP token"
)
assert_equal(
  "${{ github.server_url }}",
  run_cli&.dig("env", "GITHUB_HOST"),
  "GitHub host wiring"
)
assert_equal(
  "${{ always() && steps.prepare_qoder_home.outcome == 'success' }}",
  cleanup_home&.fetch("if"),
  "isolated HOME cleanup condition"
)
assert_equal(
  "${{ steps.prepare_qoder_home.outputs.qoder_home }}",
  cleanup_home&.dig("env", "QODER_ACTION_HOME"),
  "isolated HOME cleanup target"
)

puts "ok - composite action GitHub MCP wiring"
