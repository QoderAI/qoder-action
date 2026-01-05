const { spawn } = require('child_process');
const fs = require('fs');
const readline = require('readline');
const path = require('path');

// ANSI colors
const COLORS = {
  CYAN: '\x1b[36m',
  DIM: '\x1b[2m',
  RESET: '\x1b[0m',
  BOLD: '\x1b[1m'
};

// Helper functions for GitHub Actions logging
function printGroupStart(title) {
  process.stdout.write(`::group::${title}\n`);
}

function printGroupEnd() {
  process.stdout.write(`::endgroup::\n`);
}

function maskSensitiveData(obj) {
  if (!obj || typeof obj !== 'object') return obj;
  
  const sensitiveKeys = ['token', 'password', 'secret', 'key', 'authorization', 'auth', 'credential', 'private', 'cert', 'access_key'];
  const maskedObj = Array.isArray(obj) ? [...obj] : { ...obj };

  for (const key in maskedObj) {
    if (Object.prototype.hasOwnProperty.call(maskedObj, key)) {
      const lowerKey = key.toLowerCase();
      // Check if key contains sensitive words
      if (sensitiveKeys.some(s => lowerKey.includes(s))) {
        maskedObj[key] = '******';
      } else if (typeof maskedObj[key] === 'object') {
        maskedObj[key] = maskSensitiveData(maskedObj[key]);
      }
    }
  }
  return maskedObj;
}

// --- 1. Environment & Arguments Preparation ---

const workspace = process.env.GITHUB_WORKSPACE || process.cwd();
const prompt = process.env.INPUT_PROMPT || '';
const flagsInput = process.env.INPUT_FLAGS || '';
const githubOutput = process.env.GITHUB_OUTPUT;

// Generate unique file paths
const timestamp = Math.floor(Date.now() / 1000);
const outputFile = `/tmp/qoder-output-${timestamp}.log`;
const errorFile = `/tmp/qoder-error-${timestamp}.log`;

const outputStream = fs.createWriteStream(outputFile, { flags: 'a' });
const errorStream = fs.createWriteStream(errorFile, { flags: 'a' });

// Parse flags using regex logic (migrated from shell script)
const args = ['-w', workspace];

// Add prompt if exists
if (prompt) {
  args.push('-p', prompt);
}

// Parse additional flags
if (flagsInput) {
  const lines = flagsInput.split('\n');
  // Match non-whitespace OR double-quoted content OR single-quoted content
  const regex = /[^\s"']+|"([^"]*)"|'([^']*)'/g;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;
    
    let match;
    while ((match = regex.exec(line)) !== null) {
      if (match[1] !== undefined) {
        args.push(match[1]);
      } else if (match[2] !== undefined) {
        args.push(match[2]);
      } else {
        args.push(match[0]);
      }
    }
  }
}

// Force output format to be stream-json, overriding user input if necessary
const formatIndex = args.findIndex(arg => arg === '-f' || arg === '--output-format');
if (formatIndex !== -1) {
  // Remove existing format flag and its value
  args.splice(formatIndex, 2);
}
args.push('-f', 'stream-json');

// Print Arguments Group
printGroupStart('Arguments for qodercli');
for (let i = 0; i < args.length; i++) {
  console.log(`  ${args[i]}`);
}
printGroupEnd();


// --- 2. Execution & Stream Processing ---

const child = spawn('qodercli', args, {
  stdio: ['inherit', 'pipe', 'pipe'], // Capture stdout and stderr
  shell: false,
  env: process.env
});

// Handle stdout (Main output stream)
const rlOut = readline.createInterface({
  input: child.stdout,
  terminal: false
});

let lastThinking = '';
const processedToolIds = new Set();
let sessionIdPrinted = false;
let capturedSessionId = null;

rlOut.on('line', (line) => {
  outputStream.write(line + '\n');

  if (!line.trim()) return;

  try {
    const data = JSON.parse(line);
    
    if (data.type === 'system' && data.subtype === 'init' && data.session_id) {
      capturedSessionId = data.session_id;
      if (!sessionIdPrinted) {
        process.stdout.write(`${COLORS.BOLD}Session ID:${COLORS.RESET} ${data.session_id}\n`);
        sessionIdPrinted = true;
      }
    }
    
    // Stream Content
    if (data.type === 'assistant' && data.subtype === 'message') {
      if (data.message && Array.isArray(data.message.content)) {
        data.message.content.forEach(part => {
          // Text
          if (part.type === 'text' && part.text) {
            const summary = part.text.substring(0, 60).replace(/\r?\n/g, ' ') + (part.text.length > 60 ? '...' : '');
            printGroupStart(`${COLORS.CYAN}Assistant${COLORS.RESET} ${summary}`);
            process.stdout.write(part.text + '\n');
            printGroupEnd();
          }
          // Thinking
          else if (part.thinking) {
            if (part.thinking === lastThinking) return;
            lastThinking = part.thinking;
            const summary = part.thinking.substring(0, 60).replace(/\r?\n/g, ' ') + (part.thinking.length > 60 ? '...' : '');
            printGroupStart(`${COLORS.CYAN}[Thinking]${COLORS.RESET} ${summary}`);
            process.stdout.write(part.thinking + '\n');
            printGroupEnd();
          }
          // Tool Calls
          else if (part.type === 'function' && part.id && part.name) {
            if (processedToolIds.has(part.id)) return;
            processedToolIds.add(part.id);

            let displayStr = part.input;
            try {
                const inputObj = JSON.parse(part.input);
                const maskedObj = maskSensitiveData(inputObj);
                displayStr = JSON.stringify(maskedObj, null, 2);
            } catch (e) {}

            const argsSummary = displayStr.replace(/\s+/g, ' ').substring(0, 50) + (displayStr.length > 50 ? '...' : '');
            printGroupStart(`${COLORS.CYAN}[Tool Call]${COLORS.RESET} ${part.name} ${argsSummary}`);
            
            if (process.env.ACTIONS_STEP_DEBUG === 'true') {
                process.stdout.write(displayStr + '\n');
            } else {
                process.stdout.write('(Detailed arguments hidden. Enable Actions Debug logging to view)\n');
            }
            
            printGroupEnd();
          }
        });
      }
    }

  } catch (e) {
    console.log(line);
  }
});

// Handle stderr (Error logging)
child.stderr.on('data', (chunk) => {
  errorStream.write(chunk);
  process.stderr.write(chunk); // Also print to console stderr
});

// --- 3. Cleanup & Output ---

child.on('close', (code) => {
  outputStream.end();
  errorStream.end(() => {
    // After streams close, write to GITHUB_OUTPUT
    if (githubOutput) {
        try {
            fs.appendFileSync(githubOutput, `output_file=${outputFile}\n`);
            
            // Check if error file has content
            const errorStats = fs.statSync(errorFile);
            if (errorStats.size > 0) {
                const errorContent = fs.readFileSync(errorFile, 'utf8');
                fs.appendFileSync(githubOutput, `error<<QODER_ERROR_EOF\n${errorContent}\nQODER_ERROR_EOF\n`);
            } else {
                fs.appendFileSync(githubOutput, `error=\n`);
            }
        } catch (err) {
            console.error('Failed to write to GITHUB_OUTPUT:', err);
        }
    }
    
    if (code !== 0) {
        let errorMessage = `qodercli failed with exit code ${code}`;
        if (capturedSessionId) {
            errorMessage += ` (Session ID: ${capturedSessionId})`;
        }

        // Try to read the last few lines of the error file to provide more context
        try {
            if (fs.existsSync(errorFile)) {
                const errorContent = fs.readFileSync(errorFile, 'utf8').trim();
                if (errorContent) {
                    // Get the last 5 lines or 500 chars to avoid spamming
                    const lines = errorContent.split('\n');
                    const lastLines = lines.slice(-10).join('\n'); 
                    errorMessage += `\n\nError Details:\n${lastLines}`;
                }
            }
        } catch (e) {
            // Ignore file read errors
        }

        console.log(`::error::${errorMessage.replace(/\n/g, '%0A')}`); // Escape newlines for GitHub Actions
    } else {
        console.log('✓ qodercli executed successfully');
    }

    process.exit(code);
  });
});

child.on('error', (err) => {
  console.error(`Failed to start qodercli: ${err}`);
  process.exit(1);
});
