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
resolve = steps.find { |step| step["id"] == "resolve_github_mcp" }
setup = steps.find { |step| step["id"] == "setup_github_mcp" }
run_cli = steps.find { |step| step["id"] == "run_cli" }
cleanup = steps.find { |step| step["id"] == "cleanup_github_mcp" }

assert_equal(false, migrate_legacy.nil?, "legacy migration step")
assert_equal(false, migrate_legacy&.key?("if"), "unconditional legacy migration")
assert_equal(
  true,
  steps.index(migrate_legacy) < steps.index(setup),
  "legacy migration precedes conditional setup"
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
  "${{ always() && steps.setup_github_mcp.outcome == 'success' }}",
  cleanup&.fetch("if"),
  "cleanup condition"
)

puts "ok - composite action GitHub MCP wiring"
