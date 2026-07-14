const SENSITIVE_KEY_PARTS = [
  'token',
  'password',
  'secret',
  'key',
  'authorization',
  'auth',
  'credential',
  'private',
  'cert',
  'access_key',
];

function isSensitiveKey(key) {
  const normalizedKey = String(key).toLowerCase();
  return SENSITIVE_KEY_PARTS.some(part => normalizedKey.includes(part));
}

function isAssignmentBoundary(value, index) {
  if (index === 0) return true;
  return !isUnquotedKeyCharacter(value[index - 1]);
}

function isUnquotedKeyCharacter(character) {
  return /[A-Za-z0-9_.-]/u.test(character);
}

function skipWhitespace(value, index) {
  let cursor = index;
  while (cursor < value.length && /\s/u.test(value[cursor])) cursor += 1;
  return cursor;
}

function findClosingQuote(value, index, quote) {
  let cursor = index;
  while (cursor < value.length) {
    if (value[cursor] === '\\') {
      cursor += Math.min(2, value.length - cursor);
    } else if (value[cursor] === quote) {
      return cursor;
    } else {
      cursor += 1;
    }
  }
  return value.length;
}

function findUnquotedValueEnd(value, index) {
  let cursor = index;
  const structuralDelimiters = [',', ';', '}', '&', '"', "'", ')', ']', '|'];
  while (cursor < value.length
    && !/\s/u.test(value[cursor])
    && !structuralDelimiters.includes(value[cursor])) {
    cursor += 1;
  }
  return cursor;
}

function maskSensitiveAssignments(value) {
  const replacements = [];
  let index = 0;

  while (index < value.length) {
    if (!isAssignmentBoundary(value, index)) {
      index += 1;
      continue;
    }

    let cursor = index;
    let key;
    const keyQuote = value[cursor] === '"' || value[cursor] === "'" ? value[cursor] : '';
    if (keyQuote) {
      const keyEnd = findClosingQuote(value, cursor + 1, keyQuote);
      if (keyEnd === value.length) {
        index += 1;
        continue;
      }
      key = value.slice(cursor + 1, keyEnd);
      cursor = keyEnd + 1;
    } else {
      const keyStart = cursor;
      while (cursor < value.length && isUnquotedKeyCharacter(value[cursor])) cursor += 1;
      if (cursor === keyStart) {
        index += 1;
        continue;
      }
      key = value.slice(keyStart, cursor);
    }

    cursor = skipWhitespace(value, cursor);
    if (value[cursor] !== ':' && value[cursor] !== '=') {
      index += 1;
      continue;
    }
    cursor = skipWhitespace(value, cursor + 1);

    if (!isSensitiveKey(key)) {
      index += 1;
      continue;
    }

    const valueQuote = value[cursor] === '"' || value[cursor] === "'" ? value[cursor] : '';
    const valueStart = valueQuote ? cursor + 1 : cursor;
    const valueEnd = valueQuote
      ? findClosingQuote(value, valueStart, valueQuote)
      : findUnquotedValueEnd(value, valueStart);
    replacements.push({ start: valueStart, end: valueEnd });
    index = valueEnd < value.length ? valueEnd + 1 : valueEnd;
  }

  if (replacements.length === 0) return value;

  let output = '';
  let copiedThrough = 0;
  for (const replacement of replacements) {
    output += `${value.slice(copiedThrough, replacement.start)}******`;
    copiedThrough = replacement.end;
  }
  return output + value.slice(copiedThrough);
}

function maskSensitiveString(value) {
  const obviousCredentialsMasked = value
    .replace(/(\b(?:bearer|basic)\s+)[^\s"',;}]+/gi, '$1******')
    .replace(/\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b/g, '******')
    .replace(
      /([?&](?:signature|sig|x-amz-signature|x-amz-credential)=)[^&#\s]+/gi,
      '$1******',
    );
  return maskSensitiveAssignments(obviousCredentialsMasked);
}

function maskSensitiveData(value) {
  if (typeof value === 'string') return maskSensitiveString(value);
  if (!value || typeof value !== 'object') return value;

  const maskedValue = Array.isArray(value) ? [...value] : { ...value };
  for (const key in maskedValue) {
    if (!Object.prototype.hasOwnProperty.call(maskedValue, key)) continue;
    maskedValue[key] = isSensitiveKey(key) ? '******' : maskSensitiveData(maskedValue[key]);
  }
  return maskedValue;
}

module.exports = {
  isSensitiveKey,
  maskSensitiveAssignments,
  maskSensitiveData,
  maskSensitiveString,
};
