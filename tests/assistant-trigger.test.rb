#!/usr/bin/env ruby

ROOT = File.expand_path("..", __dir__)
WORKFLOW = File.read(File.join(ROOT, "examples", "assistant.yml"))
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

puts "ok - Assistant delegates the @qoder trigger to the action for Issue and PR comments"
