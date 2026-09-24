import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';
import { buildApp } from '../src/app.js';
import {
  createProductProfileAuthenticator, PRODUCT_LAUNCH_ROUTE, PRODUCT_PROFILE_ROUTE, PRODUCT_PROFILE_V2_MEDIA_TYPE,
} from '../src/product-profile-routes.js';
import { GuestSessionError } from '../src/guest-session-repository.js';
import type { GuestPaperScope, GuestSessionRepository } from '../src/guest-session-repository.js';
import { ProductProfileRepositoryError } from '../src/product-profile-repository.js';
import type {
  ProductLaunchWrite, ProductProfilePrincipal, ProductProfileRepository, ProductProfileSnapshot,
  ProductProfileWrite,
} from '../src/product-profile-repository.js';

const accountUser = '81000000-0000-4000-8000-000000000001';
const guestUser = '81000000-0000-4000-8000-000000000002';
const guestId = '81000000-0000-4000-8000-000000000003';
const guestToken = `tg1_${'G'.repeat(43)}`;
const mutations = [
  '81000000-0000-4000-8000-000000000011',
  '81000000-0000-4000-8000-000000000012',
  '81000000-0000-4000-8000-000000000013',
] as const;
const onboarding = Object.freeze({goal: 'learn' as const, knowledge: 'basics' as const,
  persona: 'wolf' as const, dailyGoal: 'one-mission' as const, handle: 'trimrookie'});

function body(mutationId: string = mutations[0], baseRevision = 0, launchCheckpoint = 'first-trade') {
  return {schemaVersion: 1, mutationId, baseRevision, onboarding, launchCheckpoint};
}

function launchBody(
  action: ProductLaunchWrite['action'],
  mutationId: string = mutations[1],
  baseRevision = 1,
) {
  return {schemaVersion: 1, mutationId, baseRevision, action};
}

class MemoryProductProfiles implements ProductProfileRepository {
  readonly profiles = new Map<string, ProductProfileSnapshot>();
  readonly receipts = new Map<string, {hash: string; profile: ProductProfileSnapshot}>();
  readonly launchReceipts = new Map<string, {hash: string; profile: ProductProfileSnapshot}>();
  firstBuyConfirmed = false;
  careerStarted = false;
  async get(userId: string) { return this.profiles.get(userId) ?? null; }
  async put(userId: string, command: ProductProfileWrite) {
    const key = `${userId}:${command.mutationId}`;
    const hash = JSON.stringify({baseRevision: command.baseRevision, onboarding: command.onboarding,
      launchCheckpoint: command.launchCheckpoint});
    const receipt = this.receipts.get(key);
    if (receipt) {
      if (receipt.hash !== hash) throw new ProductProfileRepositoryError(
        'PRODUCT_PROFILE_IDEMPOTENCY_CONFLICT', 'rebound');
      return receipt.profile;
    }
    const current = this.profiles.get(userId) ?? null;
    if ((current?.revision ?? 0) !== command.baseRevision) throw new ProductProfileRepositoryError(
      'PRODUCT_PROFILE_REVISION_CONFLICT', 'stale', current);
    if (!current && command.launchCheckpoint !== 'first-trade') throw new ProductProfileRepositoryError(
      'PRODUCT_PROFILE_CHECKPOINT_CONFLICT', 'initial checkpoint');
    if (current && command.launchCheckpoint !== current.launchCheckpoint) throw new ProductProfileRepositoryError(
      'PRODUCT_PROFILE_CHECKPOINT_CONFLICT', 'launch actions own checkpoint advancement');
    const revision = (current?.revision ?? 0) + 1;
    const createdAt = current?.createdAt ?? '2026-09-20T10:00:00.000Z';
    const profile = Object.freeze({revision, onboarding: command.onboarding,
      launchCheckpoint: command.launchCheckpoint,
      hasConfirmedPaperTrade: this.firstBuyConfirmed,
      createdAt, updatedAt: `2026-09-20T10:00:0${revision - 1}.000Z`}) as ProductProfileSnapshot;
    this.profiles.set(userId, profile);
    this.receipts.set(key, {hash, profile});
    return profile;
  }

  async advance(principal: ProductProfilePrincipal, command: ProductLaunchWrite) {
    const key = `${principal.userId}:${command.mutationId}`;
    const hash = JSON.stringify({baseRevision: command.baseRevision, action: command.action});
    const receipt = this.launchReceipts.get(key);
    if (receipt) {
      if (receipt.hash !== hash) throw new ProductProfileRepositoryError(
        'PRODUCT_PROFILE_IDEMPOTENCY_CONFLICT', 'rebound');
      return receipt.profile;
    }
    if (this.receipts.has(key)) throw new ProductProfileRepositoryError(
      'PRODUCT_PROFILE_IDEMPOTENCY_CONFLICT', 'profile mutation rebound');
    const current = this.profiles.get(principal.userId) ?? null;
    if (!current) throw new ProductProfileRepositoryError('PRODUCT_PROFILE_MISSING', 'missing');
    if (current.revision !== command.baseRevision) throw new ProductProfileRepositoryError(
      'PRODUCT_PROFILE_REVISION_CONFLICT', 'stale', current);
    if (current.revision >= 9007199254740991) throw new ProductProfileRepositoryError(
      'PRODUCT_PROFILE_REVISION_EXHAUSTED', 'exhausted');
    const transition = {
      'paper-trade-confirmed': ['first-trade', 'first-position'],
      'first-position-collected': ['first-position', 'streak'],
      'day-one-seen': ['streak', 'save-desk'],
      'save-desk-later': ['save-desk', 'app'],
      'save-desk-saved': ['save-desk', 'app'],
      'introduction-skipped': [current.launchCheckpoint, 'app'],
      'introduction-completed': [current.launchCheckpoint, 'app'],
    } as const;
    const [from, to] = transition[command.action];
    if (current.launchCheckpoint !== from) throw new ProductProfileRepositoryError(
      'PRODUCT_PROFILE_CHECKPOINT_CONFLICT', 'checkpoint');
    if ((command.action === 'save-desk-later' && principal.kind !== 'guest') ||
        (command.action === 'save-desk-saved' && principal.kind !== 'account')) {
      throw new ProductProfileRepositoryError('PRODUCT_PROFILE_PRINCIPAL_CONFLICT', 'principal');
    }
    if ((['paper-trade-confirmed', 'first-position-collected', 'introduction-completed'].includes(command.action) &&
          !this.firstBuyConfirmed) ||
        (['first-position-collected', 'day-one-seen', 'save-desk-later', 'save-desk-saved'].includes(command.action) &&
          !this.careerStarted)) {
      throw new ProductProfileRepositoryError('PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED', 'evidence');
    }
    const revision = current.revision + 1;
    const profile = Object.freeze({...current, revision, launchCheckpoint: to,
      hasConfirmedPaperTrade: this.firstBuyConfirmed,
      updatedAt: `2026-09-20T10:00:0${revision - 1}.000Z`}) as ProductProfileSnapshot;
    this.profiles.set(principal.userId, profile);
    this.launchReceipts.set(key, {hash, profile});
    return profile;
  }
}

const accountPrincipal = Object.freeze({kind: 'account' as const, userId: accountUser});

function guests(scopes: GuestPaperScope[]): GuestSessionRepository {
  return {
    takeCreationAttempt: async sourceHash => ({sourceHash, attemptId: '1'}),
    create: async () => ({guestId, expiresAt: '2026-09-21T00:00:00.000Z', hardExpiresAt: '2026-12-20T00:00:00.000Z'}),
    authorize: async (credentialHash, scope) => {
      assert.match(credentialHash, /^[a-f0-9]{64}$/);
      assert.equal(credentialHash.includes(guestToken), false);
      scopes.push(scope);
      return {userId: guestUser, guestId, expiresAt: '2026-09-21T00:00:00.000Z'};
    },
    refresh: async () => ({guestId, expiresAt: '2026-09-21T00:00:00.000Z', hardExpiresAt: '2026-12-20T00:00:00.000Z'}),
    claim: async () => ({guestId, claimedAt: '2026-09-20T00:00:00.000Z'}),
  };
}

let repository: MemoryProductProfiles;
beforeEach(() => { repository = new MemoryProductProfiles(); });

describe('product profile routes', () => {
  test('v2 persists unanswered preferences and skips the introduction without claiming a trade', async () => {
    const app = buildApp({logger: false, productProfile: {repository,
      authenticate: async () => accountPrincipal}});
    const unanswered = {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null};
    const headers = {accept: PRODUCT_PROFILE_V2_MEDIA_TYPE};
    try {
      const legacyNull = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE,
        payload: {...body(), onboarding: unanswered}});
      assert.equal(legacyNull.statusCode, 400);
      assert.equal(repository.profiles.size, 0);
      const saved = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE,
        payload: {...body(), schemaVersion: 2, onboarding: unanswered}});
      assert.equal(saved.statusCode, 200, saved.body);
      assert.equal(saved.json().schemaVersion, 2);
      assert.deepEqual(saved.json().profile.onboarding, unanswered);
      assert.equal(saved.json().profile.hasConfirmedPaperTrade, false);
      const read = await app.inject({url: PRODUCT_PROFILE_ROUTE, headers});
      assert.deepEqual(read.json(), saved.json());
      const legacyRead = await app.inject({url: PRODUCT_PROFILE_ROUTE});
      assert.equal(legacyRead.statusCode, 409);
      assert.equal(legacyRead.json().error.code, 'PRODUCT_PROFILE_UPGRADE_REQUIRED');
      const forged = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE,
        payload: {...body(), schemaVersion: 2, onboarding: unanswered, hasConfirmedPaperTrade: true}});
      assert.equal(forged.statusCode, 400);
      const completed = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        payload: {...launchBody('introduction-completed'), schemaVersion: 2}});
      assert.equal(completed.statusCode, 409);
      assert.equal(completed.json().error.code, 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED');
      const command = {...launchBody('introduction-skipped'), schemaVersion: 2};
      const skipped = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, payload: command});
      assert.equal(skipped.statusCode, 200, skipped.body);
      assert.equal(skipped.json().profile.launchCheckpoint, 'app');
      assert.equal(skipped.json().profile.hasConfirmedPaperTrade, false);
      assert.deepEqual(skipped.json().profile.onboarding, unanswered);
      assert.equal(repository.firstBuyConfirmed, false);
      assert.equal(repository.careerStarted, false);
      const replay = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, payload: command});
      assert.deepEqual(replay.json(), skipped.json());
    } finally { await app.close(); }
  });

  test('v2 completion exposes separately verified trade truth while legacy launch actions remain versioned', async () => {
    const app = buildApp({logger: false, productProfile: {repository,
      authenticate: async () => accountPrincipal}});
    try {
      await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, payload: {...body(), schemaVersion: 2}});
      const legacy = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        payload: launchBody('introduction-completed')});
      assert.equal(legacy.statusCode, 400);
      repository.firstBuyConfirmed = true;
      const completed = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        payload: {...launchBody('introduction-completed'), schemaVersion: 2}});
      assert.equal(completed.statusCode, 200, completed.body);
      assert.equal(completed.json().profile.launchCheckpoint, 'app');
      assert.equal(completed.json().profile.hasConfirmedPaperTrade, true);
      assert.equal(repository.careerStarted, false);
      const legacyRead = await app.inject({url: PRODUCT_PROFILE_ROUTE});
      assert.equal(legacyRead.statusCode, 200);
      assert.equal(legacyRead.json().schemaVersion, 1);
      assert.equal('hasConfirmedPaperTrade' in legacyRead.json().profile, false);
    } finally { await app.close(); }
  });

  test('remain explicitly unavailable without storage and authentication adapters', async () => {
    const app = buildApp({logger: false});
    try {
      assert.equal((await app.inject('/v1/config')).json().productProfileEnabled, false);
      assert.equal((await app.inject(PRODUCT_PROFILE_ROUTE)).statusCode, 503);
      assert.equal((await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, payload: body()})).statusCode, 503);
      assert.equal((await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        payload: launchBody('paper-trade-confirmed')})).statusCode, 503);
    } finally { await app.close(); }
  });

  test('accepts a verified account, starts at first trade and returns the stored profile', async () => {
    const app = buildApp({logger: false, productProfile: {repository,
      authenticate: async request => request.headers.authorization === 'Bearer account-token'
        ? accountPrincipal : null}});
    try {
      assert.equal((await app.inject('/v1/config')).json().productProfileEnabled, true);
      const headers = {authorization: 'Bearer account-token'};
      const empty = await app.inject({url: PRODUCT_PROFILE_ROUTE, headers});
      assert.deepEqual(empty.json(), {schemaVersion: 1, profile: null});
      const saved = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, headers, payload: body()});
      assert.equal(saved.statusCode, 200, saved.body);
      assert.equal(saved.json().profile.revision, 1);
      assert.equal(saved.json().profile.launchCheckpoint, 'first-trade');
      assert.deepEqual((await app.inject({url: PRODUCT_PROFILE_ROUTE, headers})).json(), saved.json());
    } finally { await app.close(); }
  });

  test('gives a guest only the route-specific profile scopes', async () => {
    const scopes: GuestPaperScope[] = [];
    const guestRepository = guests(scopes);
    const app = buildApp({logger: false, productProfile: {repository,
      authenticate: createProductProfileAuthenticator(async () => null, guestRepository)}});
    try {
      const headers = {authorization: `Guest ${guestToken}`};
      assert.equal((await app.inject({url: PRODUCT_PROFILE_ROUTE, headers})).statusCode, 200);
      assert.equal((await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, headers,
        payload: body()})).statusCode, 200);
      const notReady = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers,
        payload: launchBody('paper-trade-confirmed')});
      assert.equal(notReady.statusCode, 409);
      assert.deepEqual(scopes, ['profile_read', 'profile_write', 'profile_write']);
      assert.equal(repository.profiles.has(guestUser), true);
      assert.equal((await app.inject({url: PRODUCT_PROFILE_ROUTE,
        headers: {authorization: `Guest tg1_${'x'.repeat(42)}`}})).statusCode, 401);
    } finally { await app.close(); }
  });

  test('preserves server-expired and server-revoked guest codes without exposing repository detail', async () => {
    for (const code of ['GUEST_SESSION_EXPIRED', 'GUEST_SESSION_REVOKED'] as const) {
      const unavailableGuest: GuestSessionRepository = {...guests([]), authorize: async () => {
        throw new GuestSessionError(code, `private ${code} database detail`);
      }};
      const app = buildApp({logger: false, productProfile: {repository,
        authenticate: createProductProfileAuthenticator(async () => null, unavailableGuest)}});
      try {
        const headers = {authorization: `Guest ${guestToken}`};
        for (const request of [
          {method: 'GET' as const, url: PRODUCT_PROFILE_ROUTE, headers},
          {method: 'PUT' as const, url: PRODUCT_PROFILE_ROUTE, headers, payload: body()},
          {method: 'POST' as const, url: PRODUCT_LAUNCH_ROUTE, headers,
            payload: launchBody('paper-trade-confirmed')},
        ]) {
          const response = await app.inject(request);
          assert.equal(response.statusCode, 401, response.body);
          assert.equal(response.json().error.code, code);
          assert.equal(response.body.includes('private'), false);
        }
      } finally { await app.close(); }
    }
    assert.equal(repository.profiles.size, 0);
  });

  test('replays an exact mutation and separates stale revisions from mutation rebinding', async () => {
    const app = buildApp({logger: false, productProfile: {repository, authenticate: async () => accountPrincipal}});
    try {
      const first = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, payload: body()});
      assert.equal(first.statusCode, 200, first.body);
      assert.deepEqual((await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, payload: body()})).json(), first.json());

      const stale = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE,
        payload: body(mutations[1], 0, 'first-trade')});
      assert.equal(stale.statusCode, 409, stale.body);
      assert.equal(stale.json().error.code, 'PRODUCT_PROFILE_REVISION_CONFLICT');
      assert.equal(stale.json().error.currentProfile.revision, 1);

      const rebound = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE,
        payload: {...body(), onboarding: {...onboarding, handle: 'different'}}});
      assert.equal(rebound.statusCode, 409, rebound.body);
      assert.equal(rebound.json().error.code, 'PRODUCT_PROFILE_IDEMPOTENCY_CONFLICT');
      assert.equal(rebound.json().error.currentProfile, undefined);
    } finally { await app.close(); }
  });

  test('rejects generic checkpoint writes and advances only ordered evidence-backed launch actions', async () => {
    const app = buildApp({logger: false, productProfile: {repository, authenticate: async () => accountPrincipal}});
    try {
      await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, payload: body()});
      const beforeTrade = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE,
        payload: body(mutations[1], 1, 'first-position')});
      assert.equal(beforeTrade.statusCode, 409);
      assert.equal(beforeTrade.json().error.code, 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT');

      const noEvidence = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        payload: launchBody('paper-trade-confirmed')});
      assert.equal(noEvidence.statusCode, 409);
      assert.equal(noEvidence.json().error.code, 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED');
      repository.firstBuyConfirmed = true;
      repository.careerStarted = true;
      const position = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        payload: launchBody('paper-trade-confirmed')});
      assert.equal(position.statusCode, 200, position.body);
      assert.equal(position.json().profile.launchCheckpoint, 'first-position');
      assert.deepEqual((await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        payload: launchBody('paper-trade-confirmed')})).json(), position.json());

      const skipped = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        payload: launchBody('day-one-seen', mutations[2], 2)});
      assert.equal(skipped.statusCode, 409);
      assert.equal(skipped.json().error.code, 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT');
    } finally { await app.close(); }
  });

  test('keeps the maximum safe revision distinct from invalid launch input', async () => {
    repository.profiles.set(accountUser, Object.freeze({
      revision: 9007199254740991,
      hasConfirmedPaperTrade: false,
      onboarding,
      launchCheckpoint: 'first-trade',
      createdAt: '2026-09-20T10:00:00.000Z',
      updatedAt: '2026-09-20T10:00:01.000Z',
    }));
    const app = buildApp({logger: false, productProfile: {repository,
      authenticate: async () => accountPrincipal}});
    try {
      const response = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        payload: launchBody('paper-trade-confirmed', mutations[1], 9007199254740991)});
      assert.equal(response.statusCode, 409, response.body);
      assert.equal(response.json().error.code, 'PRODUCT_PROFILE_REVISION_EXHAUSTED');
    } finally { await app.close(); }
  });

  test('rejects extra fields and maps guest rate limits without storing profile data', async () => {
    const limited: GuestSessionRepository = {...guests([]), authorize: async () => {
      throw new GuestSessionError('GUEST_SESSION_RATE_LIMITED', 'private database detail');
    }};
    const app = buildApp({logger: false, productProfile: {repository,
      authenticate: createProductProfileAuthenticator(async () => null, limited)}});
    try {
      const headers = {authorization: `Guest ${guestToken}`};
      const invalid = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, headers,
        payload: {...body(), wallet: 'secret'}});
      assert.equal(invalid.statusCode, 400);
      const limitedResponse = await app.inject({url: PRODUCT_PROFILE_ROUTE, headers});
      assert.equal(limitedResponse.statusCode, 429);
      assert.equal(limitedResponse.headers['retry-after'], '60');
      assert.equal(limitedResponse.body.includes('private'), false);
      const limitedWrite = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, headers,
        payload: body()});
      assert.equal(limitedWrite.statusCode, 429);
      assert.equal(limitedWrite.headers['retry-after'], '600');
      assert.equal(repository.profiles.size, 0);
      assert.equal((await app.inject({method: 'POST', url: '/v1/product/profile/wallet', payload: {}})).json().error.code,
        'FINANCIAL_OPERATIONS_DISABLED');
    } finally { await app.close(); }
  });

  test('permits only the exact profile GET/PUT and launch POST preflights', async () => {
    const app = buildApp({logger: false, browserOrigins: ['https://trimmy.xyz'],
      productProfile: {repository, authenticate: async () => accountPrincipal}});
    try {
      const allowed = await app.inject({method: 'OPTIONS', url: PRODUCT_PROFILE_ROUTE, headers: {
        origin: 'https://trimmy.xyz', 'access-control-request-method': 'PUT',
        'access-control-request-headers': 'authorization, content-type',
      }});
      assert.equal(allowed.statusCode, 204, allowed.body);
      assert.equal(allowed.headers['access-control-allow-methods'], 'GET, PUT');
      const denied = await app.inject({method: 'OPTIONS', url: PRODUCT_PROFILE_ROUTE, headers: {
        origin: 'https://trimmy.xyz', 'access-control-request-method': 'POST',
        'access-control-request-headers': 'authorization, content-type',
      }});
      assert.equal(denied.statusCode, 403);
      assert.equal(denied.json().error.code, 'BROWSER_PREFLIGHT_DENIED');
      const launch = await app.inject({method: 'OPTIONS', url: PRODUCT_LAUNCH_ROUTE, headers: {
        origin: 'https://trimmy.xyz', 'access-control-request-method': 'POST',
        'access-control-request-headers': 'authorization, content-type',
      }});
      assert.equal(launch.statusCode, 204, launch.body);
      assert.equal(launch.headers['access-control-allow-methods'], 'POST');
    } finally { await app.close(); }
  });
});
