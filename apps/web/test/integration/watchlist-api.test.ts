import assert from 'node:assert/strict';
import { generateKeyPairSync, randomUUID, sign } from 'node:crypto';
import { test } from 'node:test';
import { Pool } from 'pg';
import { PRACTICE_ASSET_IDS } from '@trimmy/domain';
import { buildApp } from '../../../api/src/app.js';
import { PostgresPracticeAccounts } from '../../../api/src/postgres-practice-accounts.js';
import { PrivyPracticeIdentityVerifier } from '../../../api/src/privy-practice-auth.js';
import { PostgresWatchlistRepository } from '../../../api/src/postgres-watchlist-repository.js';
import { createPracticeAuthenticator } from '../../../api/src/practice-session-routes.js';
import { WatchlistSession } from '../../src/account/watchlist-sync';
import type { WatchlistStorage } from '../../src/account/watchlist-sync';

test('web client recovers an uncertain write through real HTTP, verified identity and PostgreSQL', async () => {
  const host = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
  assert.ok(host?.endsWith('/infra/.practice-runtime/socket'));
  assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
  const {privateKey, publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
  const appId = 'trimmy-web-client-test';
  function token(subject: string): string {
    const now = Math.floor(Date.now() / 1000);
    const unsigned = [{alg: 'ES256', typ: 'JWT'}, {iss: 'privy.io', aud: appId, sub: subject, iat: now, exp: now + 600, sid: 'local-test'}]
      .map(part => Buffer.from(JSON.stringify(part)).toString('base64url')).join('.');
    return `${unsigned}.${sign('sha256', Buffer.from(unsigned), {key: privateKey, dsaEncoding: 'ieee-p1363'}).toString('base64url')}`;
  }
  const pool = new Pool({host, port: 65438, user: 'trimmy_practice_test_app', database: 'postgres', max: 3, connectionTimeoutMillis: 3000});
  const sessions = {verifier: new PrivyPracticeIdentityVerifier({appId, verificationKey: publicKey.export({type: 'spki', format: 'pem'}).toString()}), accounts: new PostgresPracticeAccounts(pool)};
  const allowedAssetIds = new Set(PRACTICE_ASSET_IDS);
  const origin = 'https://web.trimmy.test';
  const app = buildApp({logger: false, browserOrigins: [origin], practiceSessions: sessions,
    watchlist: {repository: new PostgresWatchlistRepository(pool, {allowedAssetIds}), allowedAssetIds, authenticate: createPracticeAuthenticator(sessions)}});
  const opened: WatchlistSession[] = [];
  try {
    const apiBaseUrl = await app.listen({host: '127.0.0.1', port: 0});
    const preflight = await fetch(`${apiBaseUrl}/v1/watchlist`, {method: 'OPTIONS', headers: {origin, 'access-control-request-method': 'PUT', 'access-control-request-headers': 'authorization,content-type'}});
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('access-control-allow-origin'), origin);
    const values = new Map<string, string>();
    const storage: WatchlistStorage = {getItem: key => values.get(key) ?? null, setItem: (key, value) => {values.set(key, value);}};
    const freshStorage = (): WatchlistStorage => {
      const records = new Map<string, string>();
      return {getItem: key => records.get(key) ?? null, setItem: (key, value) => {records.set(key, value);}};
    };
    const subject = 'did:privy:webclientfirst';
    let dropNextPut = true;
    const writes: string[] = [];
    const transport: typeof fetch = async (input, init) => {
      const headers = new Headers(init?.headers); headers.set('origin', origin);
      const response = await fetch(input, {...init, headers});
      assert.equal(response.headers.get('access-control-allow-origin'), origin);
      if (init?.method === 'PUT') {
        writes.push(String(init.body));
        if (dropNextPut) {
          dropNextPut = false;
          assert.equal(response.status, 200, 'The real server committed before the simulated disconnect.');
          await response.body?.cancel();
          throw new TypeError('Simulated lost response');
        }
      }
      return response;
    };
    const open = async (store: WatchlistStorage, identity = subject) => {
      const session = await WatchlistSession.open({subject: identity, currentSubject: () => identity, accessToken: async expected => expected === identity ? token(identity) : null,
        apiBaseUrl, storage: store, fetch: transport, mutationId: randomUUID, allowLoopbackForTests: true});
      opened.push(session); return session;
    };
    let client = await open(storage);
    await client.synchronize();
    client.setAssetIds(['forma', 'pollen']);
    await assert.rejects(client.synchronize());
    assert.equal(client.getSnapshot().pending, true);
    assert.equal(client.getSnapshot().status, 'offline');
    const uncertain = values.get(WatchlistSession.storageKey(client.accountId));
    client.close();
    client = await open(storage);
    assert.equal(values.get(WatchlistSession.storageKey(client.accountId)), uncertain);
    await client.synchronize();
    assert.equal(writes.length, 2);
    assert.equal(writes[0], writes[1], 'Restart retries the exact saved request.');
    assert.equal(client.getSnapshot().status, 'saved');
    const other = await open(freshStorage(), 'did:privy:webclientsecond');
    await other.synchronize();
    assert.notEqual(other.accountId, client.accountId);
    assert.deepEqual(other.getSnapshot().assetIds, []);
    const secondDevice = await open(freshStorage());
    await secondDevice.synchronize();
    assert.deepEqual(secondDevice.getSnapshot().assetIds, ['forma', 'pollen']);
    secondDevice.setAssetIds(['grove']); await secondDevice.synchronize();
    client.setAssetIds(['nori']);
    await assert.rejects(client.synchronize(), {code: 'WATCHLIST_REVISION_CONFLICT'});
    assert.deepEqual(client.getSnapshot().assetIds, ['nori']);
    assert.deepEqual(client.getSnapshot().conflictAssetIds, ['grove']);
    client.useRemote();
    client.setAssetIds([]); await client.synchronize();
    await secondDevice.synchronize();
    assert.deepEqual(secondDevice.getSnapshot().assetIds, [], 'An explicitly empty list remains empty on another device.');
  } finally {
    for (const session of opened) session.close();
    await app.close(); await pool.end();
  }
});
