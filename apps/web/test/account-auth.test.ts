import assert from 'node:assert/strict';
import test from 'node:test';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { parsePracticeWebConfig, readPracticeWebConfig } from '../src/account/config.js';
import { IdentityBoundTokenReader } from '../src/account/token-binding.js';
import { PracticeAccountProvider, usePracticeAccountAuth } from '../src/account/privy-provider.js';

const appId = 'testApp';
const subject = 'did:privy:accountA';
const otherSubject = 'did:privy:accountB';
const now = Date.parse('2026-09-14T12:00:00Z');
function token(overrides: Record<string, unknown> = {}): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'ES256', typ: 'JWT' })}.${encode({
    sub: subject, aud: appId, iss: 'privy.io', sid: 'testSession',
    iat: now / 1000 - 5, exp: now / 1000 + 300, ...overrides,
  })}.c3ludGhldGlj`;
}

test('no public configuration is local guest, partial configuration is a safe error', () => {
  assert.equal(readPracticeWebConfig({}).kind, 'disabled');
  assert.equal(readPracticeWebConfig({ VITE_PRIVY_APP_ID: appId }).kind, 'invalid');
  assert.equal(parsePracticeWebConfig({ appId: '', clientId: '', apiOrigin: '' }).kind, 'disabled');
  assert.deepEqual(readPracticeWebConfig({
    VITE_PRIVY_APP_ID: appId, VITE_PRIVY_APP_CLIENT_ID: 'testClient',
    VITE_TRIMMY_API_URL: 'https://api.example.test/',
  }), { kind: 'enabled', appId, clientId: 'testClient', apiOrigin: 'https://api.example.test' });
});

test('configuration rejects unsafe origins and whitespace or invalid public IDs', () => {
  const config = { appId, clientId: 'testClient', apiOrigin: 'https://api.example.test' };
  for (const apiOrigin of [
    'http://example.test', 'http://localhost:3000', 'https://name:secret@example.test',
    'https://example.test/path', 'https://example.test?token=secret',
    'https://example.test#fragment', 'https://example.test:0', 'https://example.test:65536',
    'https://example.test\n', '//example.test', 'file:///tmp/local', 'https://example.test?',
    'https://example.test#', 'https:\\example.test',
  ]) assert.equal(parsePracticeWebConfig({ ...config, apiOrigin }).kind, 'invalid');
  for (const invalidId of [null, 3, '', 'test\n', 'has space', 'x'.repeat(129)]) {
    assert.equal(parsePracticeWebConfig({ ...config, appId: invalidId }).kind, 'invalid');
  }
  assert.equal(parsePracticeWebConfig({ ...config, apiOrigin: 'http://127.0.0.1:3000' },
    { allowLoopbackForTests: true }).kind, 'enabled');
  assert.equal(parsePracticeWebConfig({ ...config, apiOrigin: 'http://external.test' },
    { allowLoopbackForTests: true }).kind, 'invalid');
});

test('token reader accepts only current DID and obtains fresh SDK token each time', async () => {
  const reader = new IdentityBoundTokenReader(appId, () => now);
  let requests = 0;
  const sdk = async () => { requests++; return token(); };
  assert.equal(await reader.read(subject, sdk), null);
  reader.observe(subject);
  assert.equal(await reader.read(otherSubject, sdk), null);
  assert.equal(await reader.read(subject, sdk), token());
  assert.equal(await reader.read(subject, sdk), token());
  assert.equal(requests, 2);
});

test('logout, DID switch, same-DID return and unmount all deny in-flight tokens', async () => {
  for (const change of ['logout', 'switch', 'return', 'close']) {
    const reader = new IdentityBoundTokenReader(appId, () => now);
    reader.observe(subject);
    let release!: (token: string) => void;
    const pending = reader.read(subject, () => new Promise<string>((resolve) => { release = resolve; }));
    if (change === 'logout') reader.invalidate();
    if (change === 'switch' || change === 'return') reader.observe(otherSubject);
    if (change === 'return') reader.observe(subject);
    if (change === 'close') reader.close();
    release(token());
    assert.equal(await pending, null, change);
  }
});

test('malformed, expired or differently bound tokens are denied', async () => {
  const reader = new IdentityBoundTokenReader(appId, () => now);
  reader.observe(subject);
  for (const invalid of [
    null, '', 'opaque', `${token()}\n`, token({ sub: otherSubject }), token({ aud: 'otherApp' }),
    token({ iss: 'otherIssuer' }), token({ exp: now / 1000 }), token({ iat: now / 1000 + 1 }),
    token({ sid: null }), token({ iat: null }), token({ exp: 1e30 }),
  ]) assert.equal(await reader.read(subject, async () => invalid), null);
  assert.equal(await reader.read(subject, async () => { throw new Error('private SDK error'); }), null);
});

test('an invalid subject and a closed reader cannot be revived', async () => {
  const reader = new IdentityBoundTokenReader(appId, () => now);
  reader.observe('did:privy:invalid\n');
  assert.equal(await reader.read('did:privy:invalid\n', async () => token()), null);
  reader.close();
  reader.observe(subject);
  assert.equal(await reader.read(subject, async () => token()), null);
});

test('unconfigured and invalid provider render local children without SDK initialization', () => {
  function Probe() {
    const auth = usePracticeAccountAuth();
    return createElement('p', null, `${auth.enabled}:${auth.ready}:${auth.subject}:${auth.errorCode}`);
  }
  for (const [config, expected] of [
    [parsePracticeWebConfig({}), '<p>false:true:null:null</p>'],
    [parsePracticeWebConfig({ appId }), '<p>false:true:null:PRACTICE_CONFIGURATION_INVALID</p>'],
  ] as const) {
    assert.equal(renderToStaticMarkup(createElement(PracticeAccountProvider,
      { config, children: createElement(Probe) })), expected);
  }
});
