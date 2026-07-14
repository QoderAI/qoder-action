#!/usr/bin/env node

const assert = require('assert');
const {
  normalizeMessage,
  normalizeToolArguments,
  resolveCompatibilityProfile,
} = require('../scripts/github-mcp-compat-proxy');

const assistantProfile = { compatibilityProfile: 'assistant' };
const reviewProfile = { compatibilityProfile: 'review-pr' };

function toolCall(name, args) {
  return {
    jsonrpc: '2.0',
    id: 1,
    method: 'tools/call',
    params: {
      name,
      arguments: args,
    },
  };
}

{
  const args = {
    owner: 'owner',
    repo: 'repo',
    issue_number: 24,
    body: 'final response',
    comment_id: 1,
    reaction: '-1',
  };
  const removed = normalizeToolArguments('add_issue_comment', args, assistantProfile);
  assert.deepStrictEqual(args, {
    owner: 'owner',
    repo: 'repo',
    issue_number: 24,
    body: 'final response',
  });
  assert.deepStrictEqual(removed, ['comment_id', 'reaction']);
}

{
  const args = {
    owner: 'owner',
    repo: 'repo',
    issue_number: 24,
    comment_id: 100,
    reaction: 'eyes',
  };
  normalizeToolArguments('add_issue_comment', args, assistantProfile);
  assert.deepStrictEqual(args, {
    owner: 'owner',
    repo: 'repo',
    issue_number: 24,
    comment_id: 100,
    reaction: 'eyes',
  });
}

{
  const args = {
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    commentId: 123,
    body: 'reply',
    reaction: '+1',
  };
  normalizeToolArguments('add_reply_to_pull_request_comment', args, assistantProfile);
  assert.deepStrictEqual(args, {
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    commentId: 123,
    body: 'reply',
  });
}

{
  const args = {
    method: 'create',
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    body: 'placeholder',
    event: 'COMMENT',
    commitID: 'abc123',
    threadId: 'unused',
  };
  normalizeToolArguments('pull_request_review_write', args, reviewProfile);
  assert.deepStrictEqual(args, {
    method: 'create',
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
  });
}

{
  const args = {
    method: 'submit_pending',
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    body: 'summary',
    event: 'COMMENT',
  };
  normalizeToolArguments('pull_request_review_write', args, reviewProfile);
  assert.strictEqual(args.body, 'summary');
  assert.strictEqual(args.event, 'COMMENT');
}

{
  const args = {
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    path: 'README.md',
    body: 'file comment',
    subjectType: 'FILE',
    line: 1,
    side: 'LEFT',
    startLine: 1,
    startSide: 'LEFT',
  };
  normalizeToolArguments('add_comment_to_pending_review', args, reviewProfile);
  assert.deepStrictEqual(args, {
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    path: 'README.md',
    body: 'file comment',
    subjectType: 'FILE',
  });
}

{
  const args = {
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    path: 'src/index.js',
    body: 'range comment',
    subjectType: 'LINE',
    line: 12,
    side: 'RIGHT',
    startLine: 8,
    startSide: 'RIGHT',
  };
  normalizeToolArguments('add_comment_to_pending_review', args, reviewProfile);
  assert.deepStrictEqual(args, {
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    path: 'src/index.js',
    body: 'range comment',
    subjectType: 'LINE',
    line: 12,
    side: 'RIGHT',
    startLine: 8,
    startSide: 'RIGHT',
  });
}

{
  const args = {
    method: 'create',
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    body: 'ship it',
    event: 'APPROVE',
    commitID: 'abc123',
  };
  normalizeToolArguments('pull_request_review_write', args);
  assert.deepStrictEqual(args, {
    method: 'create',
    owner: 'owner',
    repo: 'repo',
    pullNumber: 24,
    body: 'ship it',
    event: 'APPROVE',
    commitID: 'abc123',
  });
}

{
  const args = {
    owner: 'owner',
    repo: 'repo',
    issue_number: 24,
    body: 'comment and react',
    comment_id: 100,
    reaction: 'heart',
  };
  normalizeToolArguments('add_issue_comment', args);
  assert.deepStrictEqual(args, {
    owner: 'owner',
    repo: 'repo',
    issue_number: 24,
    body: 'comment and react',
    comment_id: 100,
    reaction: 'heart',
  });
}

assert.strictEqual(
  resolveCompatibilityProfile({ INPUT_PROMPT: '/assistant\nREPO:owner/repo' }),
  'assistant',
);
assert.strictEqual(
  resolveCompatibilityProfile({ INPUT_PROMPT: '  /review-pr\nREPO:owner/repo' }),
  'review-pr',
);
assert.strictEqual(
  resolveCompatibilityProfile({ INPUT_PROMPT: 'Use /review-pr only if needed' }),
  '',
);

{
  const message = toolCall('add_issue_comment', {
    owner: 'owner',
    repo: 'repo',
    issue_number: 24,
    body: 'body',
    comment_id: 1,
    reaction: '-1',
  });
  const changes = [];
  normalizeMessage(
    message,
    (name, removed) => changes.push({ name, removed }),
    assistantProfile,
  );
  assert.deepStrictEqual(message.params.arguments, {
    owner: 'owner',
    repo: 'repo',
    issue_number: 24,
    body: 'body',
  });
  assert.deepStrictEqual(changes, [{
    name: 'add_issue_comment',
    removed: ['comment_id', 'reaction'],
  }]);
}

console.log('ok - GitHub MCP compatibility proxy normalizes Qoder defaults');
