#!/usr/bin/env node

const fs = require("node:fs");

const [lockPath, fdInput, operation = "validate"] = process.argv.slice(2);
const fd = Number(fdInput);

if (!lockPath || !Number.isSafeInteger(fd) || fd < 3) {
  console.error("validate-lock-file.js requires a lock path and an open file descriptor.");
  process.exit(2);
}

if (operation !== "validate" && operation !== "chmod-600") {
  console.error(`Unsupported lock validation operation: ${operation}`);
  process.exit(2);
}

try {
  const pathStat = fs.lstatSync(lockPath, { bigint: true });
  const fdStat = fs.fstatSync(fd, { bigint: true });
  const matchesOpenFile =
    !pathStat.isSymbolicLink() &&
    pathStat.isFile() &&
    fdStat.isFile() &&
    pathStat.dev === fdStat.dev &&
    pathStat.ino === fdStat.ino;

  if (!matchesOpenFile) {
    console.error(`Lock pathname no longer identifies file descriptor ${fd}: ${lockPath}`);
    process.exit(1);
  }

  if (operation === "chmod-600") {
    fs.fchmodSync(fd, 0o600);
  }
} catch (error) {
  console.error(`Unable to validate lock file ${lockPath}: ${error.message}`);
  process.exit(1);
}
