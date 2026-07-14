#!/usr/bin/env node

const assert = require('assert');
const {
  normalizeMessage,
  normalizeToolArguments,
} = require('../scripts/github-mcp-compat-proxy');

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
  const removed = normalizeToolArguments('add_issue_comment', args);
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
  normalizeToolArguments('add_issue_comment', args);
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
  normalizeToolArguments('add_reply_to_pull_request_comment', args);
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
  normalizeToolArguments('pull_request_review_write', args);
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
  normalizeToolArguments('pull_request_review_write', args);
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
  normalizeToolArguments('add_comment_to_pending_review', args);
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
  const message = toolCall('add_issue_comment', {
    owner: 'owner',
    repo: 'repo',
    issue_number: 24,
    body: 'body',
    comment_id: 1,
    reaction: '-1',
  });
  const changes = [];
  normalizeMessage(message, (name, removed) => changes.push({ name, removed }));
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
