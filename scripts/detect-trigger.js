#!/usr/bin/env node

const { appendFileSync, readFileSync } = require('node:fs');

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function containsTrigger(body, triggerPhrase) {
  if (!triggerPhrase) {
    return true;
  }

  const pattern = new RegExp(
    `(^|\\s)${escapeRegExp(triggerPhrase)}([\\s.,!?;:]|$)`,
    'i',
  );
  return pattern.test(body);
}

function main() {
  const eventName = process.env.GITHUB_EVENT_NAME || '';
  const eventPath = process.env.GITHUB_EVENT_PATH;
  const outputPath = process.env.GITHUB_OUTPUT;
  const triggerPhrase = process.env.INPUT_TRIGGER_PHRASE || '';

  if (!eventPath || !outputPath) {
    throw new Error('GITHUB_EVENT_PATH and GITHUB_OUTPUT are required');
  }

  const payload = JSON.parse(readFileSync(eventPath, 'utf8'));
  const isCommentEvent =
    eventName === 'issue_comment' || eventName === 'pull_request_review_comment';
  const body = isCommentEvent ? payload.comment?.body || '' : '';
  const triggered = !isCommentEvent || containsTrigger(body, triggerPhrase);

  appendFileSync(outputPath, `triggered=${triggered}\n`);
}

if (require.main === module) {
  main();
}

module.exports = { containsTrigger };
