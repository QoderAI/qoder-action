#!/usr/bin/env node

const { spawn } = require('child_process');
const readline = require('readline');

function deleteKeys(object, keys) {
  for (const key of keys) {
    delete object[key];
  }
}

function normalizeToolArguments(name, args) {
  if (!args || typeof args !== 'object' || Array.isArray(args)) {
    return [];
  }

  const removed = [];
  const remove = (keys) => {
    for (const key of keys) {
      if (Object.prototype.hasOwnProperty.call(args, key)) {
        removed.push(key);
      }
    }
    deleteKeys(args, keys);
  };

  if (name === 'add_issue_comment' && typeof args.body === 'string' && args.body.length > 0) {
    remove(['comment_id', 'reaction']);
  }

  if (name === 'add_reply_to_pull_request_comment'
    && typeof args.body === 'string'
    && args.body.length > 0) {
    remove(['reaction']);
  }

  if (name === 'pull_request_review_write' && args.method === 'create') {
    remove(['body', 'event', 'commitID', 'threadId']);
  }

  if (name === 'add_comment_to_pending_review') {
    remove(['startLine', 'startSide']);
    if (args.subjectType === 'FILE') {
      remove(['line', 'side']);
    }
  }

  return removed;
}

function normalizeMessage(message, onNormalize = () => {}) {
  const messages = Array.isArray(message) ? message : [message];

  for (const item of messages) {
    if (!item || item.method !== 'tools/call' || !item.params) {
      continue;
    }

    const removed = normalizeToolArguments(item.params.name, item.params.arguments);
    if (removed.length > 0) {
      onNormalize(item.params.name, removed);
    }
  }

  return message;
}

function run() {
  const separator = process.argv.indexOf('--');
  const command = separator === -1 ? undefined : process.argv[separator + 1];
  const args = separator === -1 ? [] : process.argv.slice(separator + 2);

  if (!command) {
    console.error('github-mcp-compat-proxy.js requires a child command after --');
    process.exit(2);
  }

  const child = spawn(command, args, {
    env: process.env,
    stdio: ['pipe', 'pipe', 'inherit'],
  });

  child.stdout.pipe(process.stdout);

  const input = readline.createInterface({
    input: process.stdin,
    crlfDelay: Infinity,
    terminal: false,
  });

  input.on('line', (line) => {
    let output = line;

    try {
      const message = JSON.parse(line);
      normalizeMessage(message);
      output = JSON.stringify(message);
    } catch (_error) {
      // Forward malformed input unchanged so the official server owns protocol errors.
    }

    if (!child.stdin.write(`${output}\n`)) {
      input.pause();
      child.stdin.once('drain', () => input.resume());
    }
  });

  input.on('close', () => child.stdin.end());

  child.on('error', (error) => {
    console.error(`Failed to start official GitHub MCP Server: ${error.message}`);
    process.exit(1);
  });

  child.on('close', (code, signal) => {
    if (signal) {
      process.removeAllListeners(signal);
      process.kill(process.pid, signal);
      return;
    }
    process.exit(code === null ? 1 : code);
  });

  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => {
      if (!child.killed) {
        child.kill(signal);
      }
    });
  }
}

if (require.main === module) {
  run();
}

module.exports = {
  normalizeMessage,
  normalizeToolArguments,
};
