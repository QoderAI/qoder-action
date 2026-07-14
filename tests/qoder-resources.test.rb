#!/usr/bin/env ruby

ROOT = File.expand_path("..", __dir__)
RESOURCE_PATHS = Dir.glob(File.join(ROOT, ".qoder", "{commands,agents}", "**", "*.md")).sort
RESOURCE_CONTENT = RESOURCE_PATHS.to_h { |path| [path, File.read(path)] }

def fail_test(message)
  warn "not ok - #{message}"
  exit 1
end

legacy_references = RESOURCE_CONTENT.each_with_object([]) do |(path, content), matches|
  matches << path if content.include?("mcp__qoder_github__")
end
fail_test("legacy GitHub MCP namespace remains in #{legacy_references.join(', ')}") unless legacy_references.empty?

assistant = RESOURCE_CONTENT.fetch(File.join(ROOT, ".qoder", "commands", "assistant.md"))
%w[
  mcp__github__add_issue_comment
  mcp__github__add_reply_to_pull_request_comment
  mcp__github__create_branch
  mcp__github__push_files
  mcp__github__delete_file
  mcp__github__create_pull_request
].each do |tool|
  fail_test("assistant command does not reference #{tool}") unless assistant.include?(tool)
end
fail_test("assistant command mixes single-file and batch commit tools") if assistant.include?("mcp__github__create_or_update_file")
unless assistant.include?("Never represent a deletion as an empty file")
  fail_test("assistant command does not preserve delete semantics")
end
unless assistant.include?("ISSUE_OR_PR_NUMBER` as `pullNumber")
  fail_test("assistant command does not map the PR number for review-comment replies")
end
if assistant.include?("update the comment")
  fail_test("assistant command still asks to update an already-published comment")
end

review = RESOURCE_CONTENT.fetch(File.join(ROOT, ".qoder", "commands", "review-pr.md"))
%w[
  mcp__github__pull_request_read
  mcp__github__pull_request_review_write
  mcp__github__add_comment_to_pending_review
].each do |tool|
  fail_test("review command does not reference #{tool}") unless review.include?(tool)
end
unless review.include?("reuse the existing pending review")
  fail_test("review command does not recover an existing pending review")
end
unless review.include?("omit `event`, `body`, and `commitID`")
  fail_test("review command does not prevent create from submitting the pending review")
end
unless review.include?("only review call that may include `event`")
  fail_test("review command does not reserve event for pending review submission")
end

%w[code-analyzer.md test-analyzer.md].each do |agent_name|
  agent = RESOURCE_CONTENT.fetch(File.join(ROOT, ".qoder", "agents", agent_name))
  fail_test("#{agent_name} does not allow official pull_request_read") unless agent.include?("mcp__github__pull_request_read")
end

puts "ok - bundled Qoder resources use official GitHub MCP tools"
