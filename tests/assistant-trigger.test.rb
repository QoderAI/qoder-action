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

unless WORKFLOW.include?("github.event.comment.body == '@qoderai'") &&
       WORKFLOW.include?("startsWith(github.event.comment.body, '@qoderai ')")
  fail_test("Assistant workflow does not require an @qoderai command at the start of the comment")
end

if WORKFLOW.include?("contains(github.event.comment.body, '@qoder')")
  fail_test("Assistant workflow still uses the broad @qoder substring trigger")
end

stale_mentions = PUBLIC_GUIDANCE.each_with_object([]) do |(path, content), matches|
  matches << path if content.match?(/@qoder(?!ai|-)/)
end
unless stale_mentions.empty?
  fail_test("unrelated @qoder account remains in #{stale_mentions.join(', ')}")
end

puts "ok - Assistant uses the QoderAI App mention without matching the unrelated @qoder account"
