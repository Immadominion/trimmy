import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {inspectPrivyApp, parsePrivyPublicSettings, readPrivyKeychain, settingsFetch} from './privy-app-settings.mjs';

const appId = 'testAppId123';
const secret = 'test-only-private-app-secret';
const {publicKey, privateKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const pem = publicKey.export({type: 'spki', format: 'pem'}).toString();
const settings = () => ({id: appId, name: 'Test application', data_classification: 'public', verification_key: pem,
  twitter_oauth: true, twitter_oauth_on_mobile_enabled: true, email_auth: false, google_oauth: true, allowlist_enabled: true,
  allowed_domains: ['https://example.com'], allowed_native_app_ids: ['com.trimmy.trimmy'],
  allowed_native_app_url_schemes: ['com.trimmy.trimmy.privy'], app_secret: secret,
  nested: {client_secret: secret}, twitter_consumer_secret: secret, app_clients: [{id: 'not-a-native-client-contract'}]});

test('projection keeps only public allowlisted fields and requires exact selected app identity', () => {
  const parsed = parsePrivyPublicSettings(settings(), appId);
  assert.equal(parsed.publicSettings.nativeSchemeAllowed, true);
  assert.equal(parsed.publicSettings.googleOAuthEnabled, true);
  assert.equal(parsed.publicSettings.emailAuthEnabled, false);
  assert.equal(parsed.publicSettings.nativeAppClientId, null);
  assert.equal(parsed.publicSettings.xOAuthVersion, 'not_exposed_by_settings');
  assert.equal(parsed.verificationKey, pem);
  assert.equal(JSON.stringify(parsed).includes(secret), false);
  assert.equal('app_clients' in parsed.publicSettings, false);
  assert.ok(Object.isFrozen(parsed.publicSettings));
  for (const value of [{...settings(), id: 'otherApp'}, {...settings(), id: appId + '\n'}, null]) {
    assert.throws(() => parsePrivyPublicSettings(value, appId), {code: 'PRIVY_APP_ID_MISMATCH'});
  }
});
test('private, malformed, wrong-algorithm or unclassified settings cannot become public configuration', () => {
  const rsa = generateKeyPairSync('rsa', {modulusLength: 2048}).publicKey.export({type: 'spki', format: 'pem'}).toString();
  for (const value of [{...settings(), data_classification: 'private'}, {...settings(), twitter_oauth: 'true'},
    {...settings(), google_oauth: 'true'}, {...settings(), google_oauth: undefined},
    {...settings(), allowed_native_app_url_schemes: ['unsafe\n']}, {...settings(), allowed_domains: null}]) {
    assert.throws(() => parsePrivyPublicSettings(value, appId));
  }
  for (const verification_key of [secret, rsa, privateKey.export({type: 'pkcs8', format: 'pem'}).toString(), pem + 'unexpected']) {
    assert.throws(() => parsePrivyPublicSettings({...settings(), verification_key}, appId), {code: 'PRIVY_VERIFICATION_KEY_INVALID'});
  }
});
test('single-line public PEM normalizes to the same exact P-256 SPKI without admitting trailing material', () => {
  for (const compact of [pem.replace(/\n/g, ''), pem.replace(/\n/g, ' ')]) {
    const result = parsePrivyPublicSettings({...settings(), verification_key: compact}, appId);
    assert.equal(result.verificationKey, pem);
    assert.equal(result.publicSettings.verificationKeySha256, parsePrivyPublicSettings(settings(), appId).publicSettings.verificationKeySha256);
  }
  assert.throws(() => parsePrivyPublicSettings({...settings(), verification_key: pem + pem}, appId), {code: 'PRIVY_VERIFICATION_KEY_INVALID'});
  const trailing = Buffer.concat([publicKey.export({type: 'spki', format: 'der'}), Buffer.from([0])]).toString('base64');
  assert.throws(() => parsePrivyPublicSettings({...settings(), verification_key: `-----BEGIN PUBLIC KEY-----${trailing}-----END PUBLIC KEY-----`}, appId), {code: 'PRIVY_VERIFICATION_KEY_INVALID'});
});
test('Keychain helper requests only the exact account and two services and sanitizes errors', async () => {
  const calls = [];
  const credentials = await readPrivyKeychain({execute: async (command, args) => {
    calls.push([command, args]); return {stdout: (args[4] === 'trimmy-privy-app-id' ? appId : secret) + '\n'};
  }});
  assert.deepEqual(credentials, {appId, appSecret: secret});
  assert.deepEqual(calls, [['/usr/bin/security', ['find-generic-password', '-a', 'trimmy', '-s', 'trimmy-privy-app-id', '-w']],
    ['/usr/bin/security', ['find-generic-password', '-a', 'trimmy', '-s', 'trimmy-privy-app-secret', '-w']]]);
  await assert.rejects(readPrivyKeychain({execute: async () => { throw new Error(secret); }}),
    {code: 'PRIVY_KEYCHAIN_UNAVAILABLE', message: 'PRIVY_KEYCHAIN_UNAVAILABLE'});
});
test('official SDK issues exactly one settings GET and evidence cannot claim a user login', async () => {
  let calls = 0;
  const result = await inspectPrivyApp({appId, appSecret: secret, fetchImpl: async (url, init) => {
    calls++;
    assert.equal(url, `https://api.privy.io/v1/apps/${appId}`);
    assert.equal(init.method, 'GET'); assert.equal(init.redirect, 'error');
    assert.ok(new Headers(init.headers).get('authorization').startsWith('Basic '));
    return Response.json(settings());
  }});
  assert.equal(calls, 1); assert.equal(result.evidence.loginVerified, false);
  assert.equal(result.publicConfig.PRIVY_APP_ID, appId);
  assert.equal(result.publicConfig.PRIVY_VERIFICATION_KEY, pem);
  assert.equal(JSON.stringify(result).includes(secret), false);
});
test('SDK does not retry a failure or expose private provider errors', async () => {
  let calls = 0;
  await assert.rejects(inspectPrivyApp({appId, appSecret: secret, fetchImpl: async () => {
    calls++; return new Response(secret, {status: 401});
  }}), {code: 'PRIVY_SETTINGS_READ_FAILED', message: 'PRIVY_SETTINGS_READ_FAILED'});
  assert.equal(calls, 1);
});
test('transport refuses methods/paths outside exact read before fetch and bounds body bytes', async () => {
  let calls = 0;
  const read = settingsFetch(appId, {fetchImpl: async () => { calls++; return Response.json(settings()); }});
  for (const [url, method] of [['https://api.privy.io/v1/users', 'GET'], [`https://api.privy.io/v1/apps/${appId}`, 'POST'],
    [`https://other.example/v1/apps/${appId}`, 'GET']]) await assert.rejects(read(url, {method}), {code: 'PRIVY_READ_NOT_ALLOWED'});
  assert.equal(calls, 0);
  await assert.rejects(settingsFetch(appId, {fetchImpl: async () => new Response('a'.repeat(262_145),
    {headers: {'content-type': 'application/json'}})})(`https://api.privy.io/v1/apps/${appId}`, {method: 'GET'}), {code: 'PRIVY_SETTINGS_TOO_LARGE'});
});
test('deadline includes ignored abort and stalled body without waiting for cancellation', async () => {
  const url = `https://api.privy.io/v1/apps/${appId}`;
  await assert.rejects(settingsFetch(appId, {timeoutMs: 5, fetchImpl: async () => new Promise(() => {})})(url, {method: 'GET'}), {code: 'PRIVY_SETTINGS_TIMEOUT'});
  let cancelled = false;
  const stream = new ReadableStream({cancel() { cancelled = true; return new Promise(() => {}); }});
  await assert.rejects(settingsFetch(appId, {timeoutMs: 5, fetchImpl: async () => new Response(stream,
    {headers: {'content-type': 'application/json'}})})(url, {method: 'GET'}), {code: 'PRIVY_SETTINGS_TIMEOUT'});
  assert.equal(cancelled, true);
});
