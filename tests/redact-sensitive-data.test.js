#!/usr/bin/env node

const assert = require('assert');
const {
  maskSensitiveData,
  maskSensitiveString,
} = require('../scripts/redact-sensitive-data');

const secrets = [
  'raw-bearer-token',
  'opaque-authorization-token',
  'jwt.payload.signature',
  'quoted-api-key',
  'oauth-client-secret',
  'oauth-refresh-token',
  'pem-private-key',
  'VISIBLE_SECRET',
  'UNQUOTED_CLIENT_SECRET',
  'UNQUOTED_REFRESH_TOKEN',
  'UNQUOTED_PRIVATE_KEY',
  'WRAPPED_CLIENT_SECRET',
  'PIPE_REFRESH_TOKEN',
  'SHELL_HEADER_KEY',
  'OPAQUE_VALUE',
  'SPACED_TOKEN',
  'query-signature',
];
const input = [
  'Authorization: Bearer raw-bearer-token;',
  'Authorization: Token opaque-authorization-token;',
  'headers={"Authorization":"Bearer jwt.payload.signature","api_key":"quoted-api-key",',
  '"client_secret":"oauth-client-secret","refresh_token":"oauth-refresh-token",',
  '"privateKey":"pem-private-key","password":"abc\\"VISIBLE_SECRET"};',
  'client_secret=UNQUOTED_CLIENT_SECRET;',
  'refresh_token: UNQUOTED_REFRESH_TOKEN;',
  'privateKey=UNQUOTED_PRIVATE_KEY;',
  'OAuthError(client_secret=WRAPPED_CLIENT_SECRET)',
  'details|refresh_token=PIPE_REFRESH_TOKEN;',
  "curl -H 'X-API-Key: SHELL_HEADER_KEY'",
  'token=OPAQUE_VALUE|status=denied',
  'Error: token=SPACED_TOKEN Resource not accessible by integration',
  'https://example.test/file?x-amz-signature=query-signature&status=denied',
].join(' ');

const redacted = maskSensitiveString(input);
for (const secret of secrets) {
  assert.ok(!redacted.includes(secret), `redacted output still contains ${secret}`);
}
assert.ok(redacted.includes('status=denied'));
assert.ok(redacted.includes("curl -H 'X-API-Key: ******'"));
assert.ok(redacted.includes('OAuthError(client_secret=******)'));
assert.ok(redacted.includes('token=******|status=denied'));
assert.ok(redacted.includes('Resource not accessible by integration'));
assert.ok(redacted.includes('******'));

assert.deepStrictEqual(
  maskSensitiveData({
    nested: {
      client_secret: 'object-client-secret',
      safe: 'visible context',
    },
  }),
  {
    nested: {
      client_secret: '******',
      safe: 'visible context',
    },
  },
);

const malformed = `Error: {"password":"${'\\'.repeat(10_000)}`;
const startedAt = process.hrtime.bigint();
const malformedRedacted = maskSensitiveString(malformed);
const elapsedMilliseconds = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
assert.ok(elapsedMilliseconds < 100, `malformed input took ${elapsedMilliseconds}ms`);
assert.ok(!malformedRedacted.includes('\\'));

console.log('ok - sensitive debug data is redacted in linear time');
