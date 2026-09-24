import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import { buildApp } from '../../src/app.js';
import { PostgresPracticeRepository } from '../../src/postgres-practice-repository.js';
import { PostgresPracticeAccounts } from '../../src/postgres-practice-accounts.js';
import { PrivyPracticeIdentityVerifier } from '../../src/privy-practice-auth.js';
import { createPracticeAuthenticator } from '../../src/practice-session-routes.js';

const host = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.practice-runtime/socket'));
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const {privateKey, publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const appId = 'trimmy-mobile-sync-test';
function token(subject: string): string {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = [
    {alg: 'ES256', typ: 'JWT'},
    {iss: 'privy.io', aud: appId, sub: `did:privy:${subject}`, iat: now, exp: now + 600, sid: 'fixture-session'},
  ].map(value => Buffer.from(JSON.stringify(value)).toString('base64url')).join('.');
  return `${unsigned}.${sign('sha256', Buffer.from(unsigned), {key: privateKey, dsaEncoding: 'ieee-p1363'}).toString('base64url')}`;
}
const pool = new Pool({host, port: 65438, user: 'trimmy_practice_test_app', database: 'postgres', max: 3, connectionTimeoutMillis: 3000});
const sessions = {
  verifier: new PrivyPracticeIdentityVerifier({appId, verificationKey: publicKey.export({type: 'spki', format: 'pem'}).toString()}),
  accounts: new PostgresPracticeAccounts(pool),
};
const app = buildApp({logger: false, practiceSessions: sessions, practice: {
  repository: new PostgresPracticeRepository(pool), authenticate: createPracticeAuthenticator(sessions),
}});
try {
  const address = await app.listen({host: '127.0.0.1', port: 0});
  // Fixtures exist only in this private test process. No real Privy login or
  // external provider is called; the real SDK verifies locally signed JWTs.
  const child = spawn('flutter', ['test', '--no-pub', 'tool/practice_sync_live_api_test.dart'], {
    cwd: fileURLToPath(new URL('../../../mobile/', import.meta.url)),
    stdio: ['ignore', 'inherit', 'inherit'],
    env: {...process.env, TRIMMY_SYNC_TEST_API: address, TRIMMY_SYNC_TEST_TOKEN: token('mobilefirst'), TRIMMY_SYNC_TEST_OTHER_TOKEN: token('mobilesecond')},
  });
  const timeout = setTimeout(() => child.kill('SIGTERM'), 180_000);
  try {
    const code = await new Promise<number | null>((resolve, reject) => {child.once('error', reject); child.once('exit', resolve);});
    assert.equal(code, 0, 'Native headless sync/API/database checks failed.');
  } finally { clearTimeout(timeout); }
} finally { await app.close(); await pool.end(); }
