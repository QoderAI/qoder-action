#!/usr/bin/env ruby

require "json"
require "open3"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)
WORKFLOW_PATH = File.join(ROOT, "examples", "assistant.yml")
WORKFLOW = File.read(WORKFLOW_PATH)
PUBLIC_GUIDANCE = %w[
  README.md
  docs/recipes.md
  examples/assistant.yml
  .qoder/commands/assistant.md
].to_h { |path| [path, File.read(File.join(ROOT, path))] }

def fail_test(message)
  warn "not ok - #{message}"
  exit 1
end

unless WORKFLOW.include?("issue_comment:") && WORKFLOW.include?("pull_request_review_comment:")
  fail_test("Assistant workflow does not subscribe to both Issue/PR conversation and PR inline comments")
end

unless WORKFLOW.include?("trigger_phrase: '@qoder'")
  fail_test("Assistant workflow does not configure the @qoder trigger phrase")
end

if WORKFLOW.match?(/(?:contains|startsWith)\(github\.event\.comment\.body/)
  fail_test("Assistant workflow still duplicates trigger detection in the job condition")
end

if WORKFLOW.include?("${{ github.event.comment.body }}")
  fail_test("Assistant workflow interpolates untrusted comment text into shell source")
end
unless WORKFLOW.include?('jq -r') &&
       WORKFLOW.include?('"$GITHUB_EVENT_PATH"') &&
       WORKFLOW.include?('delimiter="QODER_ARGS_$(uuidgen)"')
  fail_test("Assistant workflow does not build arguments safely from the event payload")
end

stale_mentions = PUBLIC_GUIDANCE.each_with_object([]) do |(path, content), matches|
  matches << path if content.include?("@qoderai")
end
unless stale_mentions.empty?
  fail_test("stale @qoderai guidance remains in #{stale_mentions.join(', ')}")
end

readme = PUBLIC_GUIDANCE.fetch("README.md")
unless readme.include?("Issue and PR conversation comments") &&
       readme.include?("PR inline review comments")
  fail_test("README does not document Assistant coverage across Issue and PR comment surfaces")
end

recipe = PUBLIC_GUIDANCE.fetch("docs/recipes.md")
unless recipe.include?("pull_request_review_comment:")
  fail_test("Chinese Assistant recipe does not subscribe to PR inline review comments")
end

Dir.mktmpdir("qoder-assistant-args-") do |dir|
  event_path = File.join(dir, "event.json")
  output_path = File.join(dir, "github-output")
  marker_path = File.join(dir, "injected")
  comment_body = "@qoder $(touch #{marker_path}) `touch #{marker_path}`"
  File.write(event_path, JSON.generate({
    issue: { number: 7 },
    comment: {
      node_id: "IC_kwDOExample",
      id: 42,
      user: { login: "contributor" },
      body: comment_body,
      html_url: "https://example.test/issues/7#issuecomment-42"
    }
  }))

  parsed_workflow = YAML.safe_load(WORKFLOW, aliases: true)
  build_step = parsed_workflow
    .fetch("jobs")
    .fetch("qoder-assistant")
    .fetch("steps")
    .find { |step| step["id"] == "build_args" }
  stdout, stderr, status = Open3.capture3(
    {
      "GITHUB_EVENT_NAME" => "issue_comment",
      "GITHUB_EVENT_PATH" => event_path,
      "GITHUB_OUTPUT" => output_path,
      "GITHUB_REPOSITORY" => "owner/repo"
    },
    "bash",
    "-c",
    build_step.fetch("run")
  )
  fail_test("Assistant argument builder failed: #{stdout}#{stderr}") unless status.success?
  fail_test("Assistant argument builder executed comment text") if File.exist?(marker_path)
  unless File.read(output_path).include?(comment_body)
    fail_test("Assistant argument builder did not preserve comment text as data")
  end
end

puts "ok - Assistant delegates the @qoder trigger to the action for Issue and PR comments"
