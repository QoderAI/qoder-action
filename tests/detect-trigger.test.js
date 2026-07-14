const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const script = path.join(root, 'scripts', 'detect-trigger.js');

function runTrigger({ eventName, payload, triggerPhrase = '@qoder' }) {
  const fixtureDir = mkdtempSync(path.join(tmpdir(), 'qoder-trigger-'));
  const eventPath = path.join(fixtureDir, 'event.json');
  const outputPath = path.join(fixtureDir, 'github-output');

  try {
    writeFileSync(eventPath, JSON.stringify(payload));
    execFileSync(process.execPath, [script], {
      env: {
        ...process.env,
        GITHUB_EVENT_NAME: eventName,
        GITHUB_EVENT_PATH: eventPath,
        GITHUB_OUTPUT: outputPath,
        INPUT_TRIGGER_PHRASE: triggerPhrase,
      },
      stdio: 'pipe',
    });

    return Object.fromEntries(
      readFileSync(outputPath, 'utf8')
        .trim()
        .split('\n')
        .map((line) => line.split('=')),
    );
  } finally {
    rmSync(fixtureDir, { recursive: true, force: true });
  }
}

test('detects @qoder in an Issue conversation comment', () => {
  const output = runTrigger({
    eventName: 'issue_comment',
    payload: {
      issue: { number: 7 },
      comment: { body: 'please @qoder help with this issue' },
    },
  });

  assert.equal(output.triggered, 'true');
});

test('detects @qoder in a PR conversation comment', () => {
  const output = runTrigger({
    eventName: 'issue_comment',
    payload: {
      issue: { number: 11, pull_request: { url: 'https://example.test/pr/11' } },
      comment: { body: '@qoder please review this PR' },
    },
  });

  assert.equal(output.triggered, 'true');
});

test('detects @qoder in a PR inline review comment', () => {
  const output = runTrigger({
    eventName: 'pull_request_review_comment',
    payload: {
      pull_request: { number: 11 },
      comment: { body: '@qoder please explain this line' },
    },
  });

  assert.equal(output.triggered, 'true');
});

test('leaves trigger detection disabled when trigger_phrase is empty', () => {
  const output = runTrigger({
    eventName: 'issue_comment',
    triggerPhrase: '',
    payload: {
      issue: { number: 7 },
      comment: { body: 'ordinary comment without a command' },
    },
  });

  assert.equal(output.triggered, 'true');
});

test('does not gate non-comment automation events', () => {
  const output = runTrigger({
    eventName: 'pull_request',
    payload: { pull_request: { number: 11 } },
  });

  assert.equal(output.triggered, 'true');
});

test('requires @qoder to be a complete phrase', () => {
  const rejectedBodies = [
    'please ask @qoderai instead',
    'please ask @qoder-helper instead',
    'please ask @qoder[bot] instead',
    'email@qoder.com',
    'ordinary comment without a command',
  ];

  for (const body of rejectedBodies) {
    const output = runTrigger({
      eventName: 'issue_comment',
      payload: { issue: { number: 7 }, comment: { body } },
    });
    assert.equal(output.triggered, 'false', body);
  }
});

test('matches the configured phrase case-insensitively with punctuation', () => {
  const output = runTrigger({
    eventName: 'issue_comment',
    triggerPhrase: '/qoder',
    payload: {
      issue: { number: 7 },
      comment: { body: 'Could you help, /QODER?' },
    },
  });

  assert.equal(output.triggered, 'true');
});

test('accepts punctuation on both sides of @qoder', () => {
  const acceptedBodies = [
    'please,@qoder help',
    '（@qoder）',
    '你好，@qoder。',
  ];

  for (const body of acceptedBodies) {
    const output = runTrigger({
      eventName: 'issue_comment',
      payload: { issue: { number: 7 }, comment: { body } },
    });
    assert.equal(output.triggered, 'true', body);
  }
});
