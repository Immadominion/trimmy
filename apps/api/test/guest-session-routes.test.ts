import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildApp } from '../src/app.js';
import {
  GUEST_CLAIM_ROUTE, GUEST_REFRESH_ROUTE, GUEST_SESSION_ROUTE, createGuestPaperAuthenticator,
  deriveGuestCreation, hashGuestCreationRequest, hashGuestCredential, hashGuestReplaySecret,
} from '../src/guest-session-routes.js';
import { GuestSessionError } from '../src/guest-session-repository.js';
import type {
  GuestAuthorization, GuestClaimResult, GuestPaperScope, GuestSessionRecord, GuestSessionRepository,
} from '../src/guest-session-repository.js';
import type { PracticeIdentity, PracticeIdentityVerifier } from '../src/practice-identity.js';
import {GuestSourceError} from '../src/guest-creation-source.js';
import type {GuestCreationSource} from '../src/guest-creation-source.js';

const guestId = '71000000-0000-4000-8000-000000000001';
const userId = '72000000-0000-4000-8000-000000000001';
const claimId = '73000000-0000-4000-8000-000000000001';
const creationRequestId = '70000000-0000-4000-8000-000000000001';
const replaySecret = `gr1_${Buffer.alloc(32, 17).toString('base64url')}`;
const guestToken = `tg1_${'A'.repeat(43)}`;
const privyToken = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJkaWQ6cHJpdnk6dGVzdCJ9.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const identity: PracticeIdentity = {provider: 'privy', appId: 'test-app', subject: 'did:privy:guestclaim'};
const expiresAt = '2026-10-20T12:00:00.000Z';
const hardExpiresAt = '2026-12-19T12:00:00.000Z';
const claimedAt = '2026-09-20T12:00:00.000Z';
const sourceHash = 'f'.repeat(64);
const browserOrigin = 'https://trimmy.example';
const source: GuestCreationSource = {hash: () => sourceHash};

class MemoryGuests implements GuestSessionRepository {
  attempts: string[] = [];
  creates: {sourceHash: string; attemptId: string; requestHash: string; replayHash: string; guestId: string; credentialHash: string}[] = [];
  authorizations: {credentialHash: string; scope: GuestPaperScope}[] = [];
  claims: {credentialHash: string; identity: PracticeIdentity; idempotencyKey: string}[] = [];
  fail?: GuestSessionError;
  async takeCreationAttempt(selectedSourceHash: string) {
    if (this.fail) throw this.fail;
    this.attempts.push(selectedSourceHash);
    return {sourceHash: selectedSourceHash, attemptId: String(this.attempts.length)};
  }
  async create(command: {readonly sourceHash: string; readonly attemptId: string; readonly requestHash: string;
    readonly replayHash: string; readonly guestId: string;
    readonly credentialHash: string}): Promise<GuestSessionRecord> {
    if (this.fail) throw this.fail;
    this.creates.push(command);
    return {guestId: command.guestId, expiresAt, hardExpiresAt};
  }
  async authorize(credentialHash: string, scope: GuestPaperScope): Promise<GuestAuthorization> {
    if (this.fail) throw this.fail;
    this.authorizations.push({credentialHash, scope});
    return {userId, guestId, expiresAt};
  }
  async refresh(credentialHash: string): Promise<GuestSessionRecord> {
    if (this.fail) throw this.fail;
    this.authorizations.push({credentialHash, scope: 'paper_read'});
    return {guestId, expiresAt, hardExpiresAt};
  }
  async claim(command: {readonly credentialHash: string; readonly identity: PracticeIdentity;
    readonly idempotencyKey: string}): Promise<GuestClaimResult> {
    if (this.fail) throw this.fail;
    this.claims.push(command);
    return {guestId, claimedAt};
  }
}

const verifier: PracticeIdentityVerifier = {verify: async token => token === privyToken ? identity : null};
const guestAdapters = (repository: MemoryGuests, selectedSource: GuestCreationSource = source) =>
  ({repository, verifier, source: selectedSource});

test('creation material is stable per request, separated across requests and stored only as digests', async () => {
  const derived = deriveGuestCreation(creationRequestId, replaySecret);
  assert.deepEqual(deriveGuestCreation(creationRequestId.toUpperCase(), replaySecret), derived);
  assert.notDeepEqual(deriveGuestCreation('70000000-0000-4000-8000-000000000002', replaySecret), derived);
  assert.notDeepEqual(deriveGuestCreation(creationRequestId,
    `gr1_${Buffer.alloc(32, 18).toString('base64url')}`), derived);
  assert.match(derived.guestId, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.match(derived.credential, /^tg1_[A-Za-z0-9_-]{43}$/);
  assert.equal(Buffer.from(derived.credential.slice(4), 'base64url').length, 32);
  assert.equal(Buffer.from(replaySecret.slice(4), 'base64url').length, 32);
  assert.throws(() => deriveGuestCreation(creationRequestId, 'not-a-secret'), /creation material is invalid/);

  const repository = new MemoryGuests();
  const app = buildApp({logger: false, guestSessions: guestAdapters(repository)});
  try {
    const payload = {schemaVersion: 1, requestId: creationRequestId.toUpperCase(), replaySecret};
    const response = await app.inject({method: 'POST', url: GUEST_SESSION_ROUTE, payload});
    assert.equal(response.statusCode, 201, response.body);
    assert.equal(response.json().token, derived.credential);
    assert.equal(response.json().guestId, derived.guestId);
    assert.equal(response.json().requestId, creationRequestId);
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.equal(repository.creates.length, 1);
    assert.deepEqual(repository.attempts, [sourceHash]);
    assert.equal(repository.creates[0]?.sourceHash, sourceHash);
    assert.equal(repository.creates[0]?.attemptId, '1');
    assert.equal(repository.creates[0]?.requestHash, hashGuestCreationRequest(creationRequestId));
    assert.equal(repository.creates[0]?.replayHash, hashGuestReplaySecret(replaySecret));
    assert.equal(repository.creates[0]?.credentialHash, hashGuestCredential(derived.credential));
    assert.equal(JSON.stringify(repository.creates).includes(derived.credential), false);
    assert.equal(JSON.stringify(repository.creates).includes(replaySecret), false);
    assert.equal(JSON.stringify(repository.creates).includes(creationRequestId), false);
    const replay = await app.inject({method: 'POST', url: GUEST_SESSION_ROUTE,
      payload: {schemaVersion: 1, requestId: creationRequestId, replaySecret}});
    assert.equal(replay.statusCode, 201, replay.body);
    assert.deepEqual(replay.json(), response.json());
    assert.deepEqual({...repository.creates[1], attemptId: '1'}, repository.creates[0]);
    assert.equal(repository.creates[1]?.attemptId, '2');
    assert.equal(response.body.includes(replaySecret), false);
    for (const bad of [
      {schemaVersion: 1, requestId: creationRequestId},
      {schemaVersion: 1, requestId: creationRequestId, replaySecret: `gr1_${'R'.repeat(43)}`},
    ]) {
      const rejected = await app.inject({method: 'POST', url: GUEST_SESSION_ROUTE, payload: bad});
      assert.equal(rejected.statusCode, 400, rejected.body);
    }
    assert.equal(repository.creates.length, 2);
    assert.equal((await app.inject('/v1/config')).json().guestSessionsEnabled, true);
  } finally { await app.close(); }
});

test('creation admission counts requests before body parsing and uses the database retry delay exactly', async () => {
  const repository = new MemoryGuests();
  const app = buildApp({logger: false, browserOrigins: [browserOrigin], guestSessions: guestAdapters(repository)});
  try {
    const schemaInvalid = await app.inject({method: 'POST', url: GUEST_SESSION_ROUTE,
      payload: {schemaVersion: 1, requestId: creationRequestId}});
    assert.equal(schemaInvalid.statusCode, 400);
    const malformed = await app.inject({method: 'POST', url: GUEST_SESSION_ROUTE,
      headers: {'content-type': 'application/json'}, payload: '{'});
    assert.equal(malformed.statusCode, 400);
    const oversized = await app.inject({method: 'POST', url: GUEST_SESSION_ROUTE,
      headers: {'content-type': 'application/json'}, payload: JSON.stringify({padding: 'x'.repeat(300)})});
    assert.equal(oversized.statusCode, 413);
    assert.deepEqual(repository.attempts, [sourceHash, sourceHash, sourceHash]);
    assert.equal(repository.creates.length, 0);

    repository.fail = new GuestSessionError('GUEST_SESSION_RATE_LIMITED', 'private limiter state', 137);
    const limited = await app.inject({method: 'POST', url: GUEST_SESSION_ROUTE,
      headers: {origin: browserOrigin},
      payload: {schemaVersion: 1, requestId: creationRequestId, replaySecret}});
    assert.equal(limited.statusCode, 429, limited.body);
    assert.equal(limited.headers['retry-after'], '137');
    assert.equal(limited.headers['access-control-allow-origin'], browserOrigin);
    assert.equal(limited.headers['access-control-expose-headers'], 'Retry-After');
    assert.equal(limited.body.includes('private'), false);
    assert.equal(repository.creates.length, 0);
  } finally { await app.close(); }
});

test('an unavailable or ambiguous network source fails closed before storage', async () => {
  const repository = new MemoryGuests();
  const unavailable: GuestCreationSource = {hash: () => { throw new GuestSourceError(); }};
  const app = buildApp({logger: false, guestSessions: guestAdapters(repository, unavailable)});
  try {
    const response = await app.inject({method: 'POST', url: GUEST_SESSION_ROUTE,
      payload: {schemaVersion: 1, requestId: creationRequestId, replaySecret}});
    assert.equal(response.statusCode, 503, response.body);
    assert.equal(response.json().error.code, 'GUEST_SESSION_UNAVAILABLE');
    assert.deepEqual(repository.attempts, []);
    assert.deepEqual(repository.creates, []);
  } finally { await app.close(); }
});

test('refresh uses only Guest authorization and never returns another credential', async () => {
  const repository = new MemoryGuests();
  const app = buildApp({logger: false, guestSessions: guestAdapters(repository)});
  try {
    const response = await app.inject({method: 'POST', url: GUEST_REFRESH_ROUTE,
      headers: {authorization: `Guest ${guestToken}`}, payload: {schemaVersion: 1}});
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(response.json(), {schemaVersion: 1, guestId, expiresAt, hardExpiresAt});
    assert.equal(response.body.includes(guestToken), false);
    assert.equal(repository.authorizations[0]?.credentialHash, hashGuestCredential(guestToken));
    const bearer = await app.inject({method: 'POST', url: GUEST_REFRESH_ROUTE,
      headers: {authorization: `Bearer ${privyToken}`}, payload: {schemaVersion: 1}});
    assert.equal(bearer.statusCode, 401);
  } finally { await app.close(); }
});

test('claim binds only the verifier output and passes the stable idempotency key', async () => {
  const repository = new MemoryGuests();
  const app = buildApp({logger: false, guestSessions: guestAdapters(repository)});
  try {
    const response = await app.inject({method: 'POST', url: GUEST_CLAIM_ROUTE,
      headers: {authorization: `Bearer ${privyToken}`, 'x-trimmy-guest': guestToken},
      payload: {schemaVersion: 1, idempotencyKey: claimId}});
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(response.json(), {schemaVersion: 1, status: 'claimed', guestId, claimedAt});
    assert.deepEqual(repository.claims, [{credentialHash: hashGuestCredential(guestToken), identity,
      idempotencyKey: claimId}]);
    for (const headers of [
      {authorization: `Bearer ${privyToken}`},
      {authorization: 'Bearer wrong.token.value', 'x-trimmy-guest': guestToken},
      {authorization: `Guest ${guestToken}`, 'x-trimmy-guest': guestToken},
    ]) {
      const denied = await app.inject({method: 'POST', url: GUEST_CLAIM_ROUTE, headers,
        payload: {schemaVersion: 1, idempotencyKey: claimId}});
      assert.equal(denied.statusCode, 401);
    }
    assert.equal(repository.claims.length, 1);
  } finally { await app.close(); }
});

test('guest paper authenticator scopes credentials by the exact paper route', async () => {
  const repository = new MemoryGuests();
  let accountCalls = 0;
  const authenticate = createGuestPaperAuthenticator(async () => { accountCalls++; return {userId};}, repository);
  const app = buildApp({logger: false});
  try {
    app.get('/test-paper', async request => authenticate(request));
    const unsupported = await app.inject({url: '/test-paper', headers: {authorization: `Guest ${guestToken}`}});
    assert.equal(unsupported.statusCode, 200);
    assert.equal(unsupported.body, 'null');
    assert.equal(repository.authorizations.length, 0);
    const bearer = await app.inject({url: '/test-paper', headers: {authorization: `Bearer ${privyToken}`}});
    assert.equal(bearer.statusCode, 200);
    assert.equal(accountCalls, 1);
  } finally { await app.close(); }
});

test('rate and claim conflicts are explicit while failures never expose secret detail', async () => {
  for (const [failure, status] of [
    [new GuestSessionError('GUEST_SESSION_RATE_LIMITED', 'secret rate row'), 429],
    [new GuestSessionError('GUEST_CLAIM_ACCOUNT_EXISTS', 'secret identity'), 409],
    [new GuestSessionError('GUEST_SESSION_UNAVAILABLE', 'secret database'), 503],
  ] as const) {
    const repository = new MemoryGuests(); repository.fail = failure;
    const app = buildApp({logger: false, guestSessions: guestAdapters(repository)});
    try {
      const response = await app.inject({method: 'POST', url: GUEST_CLAIM_ROUTE,
        headers: {authorization: `Bearer ${privyToken}`, 'x-trimmy-guest': guestToken},
        payload: {schemaVersion: 1, idempotencyKey: claimId}});
      assert.equal(response.statusCode, status, response.body);
      assert.equal(response.body.includes('secret'), false);
      if (status === 429) assert.equal(response.headers['retry-after'], '3600');
    } finally { await app.close(); }
  }
});

test('refresh rate responses use the configured one-hour database window', async () => {
  const repository = new MemoryGuests();
  repository.fail = new GuestSessionError('GUEST_SESSION_RATE_LIMITED', 'secret rate row');
  const app = buildApp({logger: false, guestSessions: guestAdapters(repository)});
  try {
    const response = await app.inject({method: 'POST', url: GUEST_REFRESH_ROUTE,
      headers: {authorization: `Guest ${guestToken}`}, payload: {schemaVersion: 1}});
    assert.equal(response.statusCode, 429, response.body);
    assert.equal(response.headers['retry-after'], '3600');
    assert.equal(response.body.includes('secret'), false);
  } finally { await app.close(); }
});

test('guest routes remain closed when the adapter is absent and aliases do not bypass the write gate', async () => {
  const app = buildApp({logger: false});
  try {
    assert.equal((await app.inject({method: 'POST', url: GUEST_SESSION_ROUTE,
      payload: {schemaVersion: 1, requestId: creationRequestId, replaySecret}})).statusCode, 503);
    assert.equal((await app.inject('/v1/config')).json().guestSessionsEnabled, false);
    for (const url of ['/v1/guest/session/', '/v1/guest/claim/extra', '/v1/guest/wallet']) {
      const response = await app.inject({method: 'POST', url, payload: {}});
      assert.equal(response.statusCode, 503);
      assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
    }
  } finally { await app.close(); }
});
