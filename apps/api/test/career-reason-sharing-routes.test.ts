import assert from 'node:assert/strict';
import {Buffer} from 'node:buffer';
import {describe, test} from 'node:test';
import Fastify from 'fastify';
import {buildApp} from '../src/app.js';
import {
  CAREER_REASON_LIST_ROUTE,
  CAREER_REASON_PRIVACY_ROUTE,
  createCareerReasonSharingAuthenticator,
  registerCareerReasonSharingRoutes,
} from '../src/career-reason-sharing-routes.js';
import type {CareerReasonSharingAdapters} from
  '../src/career-reason-sharing-routes.js';
import {
  CareerReasonSharingError,
  parseCareerReasonListQuery,
  parseCareerReasonPrivacyWrite,
} from '../src/career-reason-sharing.js';
import type {
  CareerReasonListPage,
  CareerReasonListQuery,
  CareerReasonPrivacy,
  CareerReasonPrivacyWrite,
  CareerReasonSharingRepository,
} from '../src/career-reason-sharing.js';
import {hashGuestCredential} from '../src/guest-session-routes.js';
import {GuestSessionError} from '../src/guest-session-repository.js';
import type {GuestPaperScope, GuestSessionRepository} from
  '../src/guest-session-repository.js';

const userId = '74000000-0000-4000-8000-000000000001';
const mutationId = '74000000-0000-4000-8000-000000000002';
const orderId = '74000000-0000-4000-8000-000000000003';
const reasonId = '75000000-0000-4000-8000-000000000003';
const socialId = '76000000-0000-4000-8000-000000000003';
const variantMint = '11111111111111111111111111111111';

const privacy: CareerReasonPrivacy = Object.freeze({
  revision: 2,
  visibility: 'everyone',
  configured: true,
  friendsSharing: 'unavailable',
  createdAt: '2026-09-20T12:00:00.000Z',
  updatedAt: '2026-09-20T12:00:00.001Z',
});

const firstReason = Object.freeze({
  reasonId,
  orderId,
  author: Object.freeze({
    handle: 'ada_trade',
    rank: Object.freeze({id: 'analyst' as const, label: 'Analyst'}),
    isViewer: false,
  }),
  stock: Object.freeze({assetId: 'apple', variantMint, symbol: 'AAPLx'}),
  note: 'Margins improved for a second quarter.',
  deskCycle: 'current' as const,
  savedAt: '2026-09-20T12:00:00.000Z',
});

const friendReason = Object.freeze({
  reasonId,
  author: Object.freeze({
    socialId,
    handle: 'ada_trade',
    persona: 'oracle' as const,
    rank: Object.freeze({id: 'analyst' as const, label: 'Analyst'}),
    isViewer: false as const,
  }),
  stock: firstReason.stock,
  note: firstReason.note,
  savedAt: firstReason.savedAt,
});

const selfReason = Object.freeze({
  ...firstReason,
  author: Object.freeze({...firstReason.author, isViewer: true}),
  deskCycle: 'historical' as const,
});

class MemoryReasonSharingRepository implements CareerReasonSharingRepository {
  readonly reads: string[] = [];
  readonly writes: Array<{userId: string; command: CareerReasonPrivacyWrite}> = [];
  readonly lists: Array<{userId: string; query: CareerReasonListQuery}> = [];
  failure?: CareerReasonSharingError;
  page: CareerReasonListPage = Object.freeze({
    reasons: Object.freeze([firstReason]),
    hasMore: true,
  });

  async getPrivacy(selectedUser: string): Promise<CareerReasonPrivacy> {
    if (this.failure) throw this.failure;
    this.reads.push(selectedUser);
    return privacy;
  }

  async savePrivacy(
    selectedUser: string,
    input: CareerReasonPrivacyWrite,
  ): Promise<CareerReasonPrivacy> {
    if (this.failure) throw this.failure;
    this.writes.push({userId: selectedUser, command: parseCareerReasonPrivacyWrite(input)});
    return privacy;
  }

  async listReasons(
    selectedUser: string,
    input: CareerReasonListQuery,
  ): Promise<CareerReasonListPage> {
    if (this.failure) throw this.failure;
    this.lists.push({userId: selectedUser, query: parseCareerReasonListQuery(input)});
    return this.page;
  }
}

function appWith(repository?: MemoryReasonSharingRepository,
  authenticate: CareerReasonSharingAdapters['authenticate'] = async () => ({userId}),
  relationshipSafetyEnabled = false) {
  const app = Fastify({logger: false, ajv: {customOptions: {
    removeAdditional: false, coerceTypes: false, useDefaults: false,
  }}});
  registerCareerReasonSharingRoutes(app, repository ? {repository, authenticate} : undefined,
    relationshipSafetyEnabled,
    relationshipSafetyEnabled ? async () => true : undefined);
  return app;
}

describe('Career reason sharing routes', () => {
  test('is composed behind the shared write gate and advertised only when complete', async () => {
    const repository = new MemoryReasonSharingRepository();
    const app = buildApp({logger: false, careerReasonSharing: {
      repository,
      authenticate: async () => ({userId}),
    }});
    try {
      const config = (await app.inject('/v1/config')).json();
      assert.equal(config.careerReasonSharingEnabled, true);
      const write = await app.inject({
        method: 'PUT',
        url: CAREER_REASON_PRIVACY_ROUTE,
        payload: {schemaVersion: 1, mutationId, baseRevision: 1, visibility: 'nobody'},
      });
      assert.equal(write.statusCode, 200, write.body);
      assert.equal(repository.writes.length, 1);

      const unsupported = await app.inject({
        method: 'PATCH',
        url: CAREER_REASON_PRIVACY_ROUTE,
        payload: {visibility: 'everyone'},
      });
      assert.equal(unsupported.statusCode, 503, unsupported.body);
      assert.equal(unsupported.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
    } finally { await app.close(); }

    const disabled = buildApp({logger: false});
    try {
      assert.equal((await disabled.inject('/v1/config')).json()
        .careerReasonSharingEnabled, false);
      const unavailable = await disabled.inject({
        method: 'PUT',
        url: CAREER_REASON_PRIVACY_ROUTE,
        payload: {schemaVersion: 1, mutationId, baseRevision: 1, visibility: 'nobody'},
      });
      assert.equal(unavailable.statusCode, 503, unavailable.body);
      assert.equal(unavailable.json().error.code, 'CAREER_REASON_SHARING_UNAVAILABLE');
    } finally { await disabled.close(); }
  });

  test('stay closed until all server adapters are present', async () => {
    const app = appWith();
    try {
      for (const request of [
        {method: 'GET' as const, url: `${CAREER_REASON_LIST_ROUTE}?scope=self`},
        {method: 'GET' as const, url: CAREER_REASON_PRIVACY_ROUTE},
        {method: 'PUT' as const, url: CAREER_REASON_PRIVACY_ROUTE, payload: {
          schemaVersion: 1, mutationId, baseRevision: 1, visibility: 'nobody',
        }},
      ]) {
        const response = await app.inject(request);
        assert.equal(response.statusCode, 503, response.body);
        assert.equal(response.json().error.code, 'CAREER_REASON_SHARING_UNAVAILABLE');
      }
    } finally { await app.close(); }
  });

  test('returns a strict stock page and a scope-bound continuation cursor', async () => {
    const repository = new MemoryReasonSharingRepository();
    const app = appWith(repository);
    try {
      const response = await app.inject({
        url: `${CAREER_REASON_LIST_ROUTE}?scope=everyone&limit=1&assetId=apple&variantMint=${variantMint}`,
      });
      assert.equal(response.statusCode, 200, response.body);
      assert.equal(response.headers['cache-control'], 'no-store');
      const body = response.json();
      assert.equal(body.schemaVersion, 1);
      assert.equal(body.scope, 'everyone');
      assert.deepEqual(body.filter, {assetId: 'apple', variantMint});
      assert.deepEqual(body.reasons, [{
        reasonId,
        author: firstReason.author,
        stock: firstReason.stock,
        note: firstReason.note,
        savedAt: firstReason.savedAt,
      }]);
      assert.equal('orderId' in body.reasons[0], false);
      assert.equal('deskCycle' in body.reasons[0], false);
      assert.equal(body.page.limit, 1);
      assert.match(body.page.nextCursor, /^[A-Za-z0-9_-]+$/u);
      const cursorPayload = JSON.parse(
        Buffer.from(body.page.nextCursor, 'base64url').toString('utf8'),
      ) as unknown;
      assert.ok(Array.isArray(cursorPayload));
      assert.equal(cursorPayload.at(-1), reasonId);
      assert.equal(JSON.stringify(cursorPayload).includes(orderId), false);
      assert.deepEqual(repository.lists[0], {userId, query: {
        scope: 'everyone', limit: 1, assetId: 'apple', variantMint, cursor: null,
      }});

      repository.page = Object.freeze({reasons: Object.freeze([]), hasMore: false});
      const next = await app.inject({
        url: `${CAREER_REASON_LIST_ROUTE}?scope=everyone&limit=1&assetId=apple&variantMint=${variantMint}&cursor=${body.page.nextCursor}`,
      });
      assert.equal(next.statusCode, 200, next.body);
      assert.deepEqual(repository.lists[1]?.query.cursor, {
        savedAt: firstReason.savedAt, reasonId,
      });
      assert.equal(next.json().page.nextCursor, null);

      const rebound = await app.inject({
        url: `${CAREER_REASON_LIST_ROUTE}?scope=self&limit=1&cursor=${body.page.nextCursor}`,
      });
      assert.equal(rebound.statusCode, 400, rebound.body);
      assert.equal(repository.lists.length, 2);
    } finally { await app.close(); }
  });

  test('preserves the complete own-row contract only for self history', async () => {
    const repository = new MemoryReasonSharingRepository();
    repository.page = Object.freeze({reasons: Object.freeze([selfReason]), hasMore: false});
    const app = appWith(repository);
    try {
      const response = await app.inject(`${CAREER_REASON_LIST_ROUTE}?scope=self`);
      assert.equal(response.statusCode, 200, response.body);
      assert.deepEqual(response.json().reasons, [selfReason]);
      assert.equal(response.json().reasons[0].orderId, orderId);
      assert.equal(response.json().reasons[0].deskCycle, 'historical');
      assert.equal('socialId' in response.json().reasons[0].author, false);
      assert.equal('persona' in response.json().reasons[0].author, false);
    } finally { await app.close(); }
  });

  test('reads and writes privacy without implying friendship support', async () => {
    const repository = new MemoryReasonSharingRepository();
    const app = appWith(repository);
    try {
      const read = await app.inject({url: CAREER_REASON_PRIVACY_ROUTE});
      assert.equal(read.statusCode, 200, read.body);
      assert.equal(read.headers['cache-control'], 'no-store');
      assert.deepEqual(read.json(), {schemaVersion: 1, reasonPrivacy: privacy});

      const write = await app.inject({method: 'PUT', url: CAREER_REASON_PRIVACY_ROUTE,
        payload: {schemaVersion: 1, mutationId: mutationId.toUpperCase(),
          baseRevision: 1, visibility: 'friends'}});
      assert.equal(write.statusCode, 200, write.body);
      assert.equal(write.json().reasonPrivacy.friendsSharing, 'unavailable');
      assert.deepEqual(repository.writes, [{userId, command: {
        mutationId, baseRevision: 1, visibility: 'friends',
      }}]);

      const widened = await app.inject({method: 'PUT', url: CAREER_REASON_PRIVACY_ROUTE,
        payload: {schemaVersion: 1, mutationId, baseRevision: 1,
          visibility: 'everyone', followers: true}});
      assert.equal(widened.statusCode, 400, widened.body);
      assert.equal(repository.writes.length, 1);
    } finally { await app.close(); }
  });

  test('gates friends reads and capability, then returns only the public friends projection', async () => {
    const disabledRepository = new MemoryReasonSharingRepository();
    disabledRepository.page = Object.freeze({reasons: Object.freeze([friendReason]), hasMore: false,
      principalSocialId: socialId});
    const disabled = appWith(disabledRepository);
    const url = `${CAREER_REASON_LIST_ROUTE}?scope=friends&limit=1&assetId=apple&variantMint=${variantMint}`;
    try {
      const response = await disabled.inject(url);
      assert.equal(response.statusCode, 503, response.body);
      assert.equal(response.json().error.code, 'CAREER_REASON_SHARING_UNAVAILABLE');
      assert.equal(disabledRepository.lists.length, 0);
      assert.equal((await disabled.inject(CAREER_REASON_PRIVACY_ROUTE)).json()
        .reasonPrivacy.friendsSharing, 'unavailable');
    } finally { await disabled.close(); }

    const repository = new MemoryReasonSharingRepository();
    repository.page = Object.freeze({reasons: Object.freeze([friendReason]), hasMore: true,
      principalSocialId: socialId});
    const enabled = appWith(repository, async () => ({userId}), true);
    try {
      const response = await enabled.inject(url);
      assert.equal(response.statusCode, 200, response.body);
      assert.deepEqual(response.json().reasons, [friendReason]);
      assert.equal(response.body.includes(orderId), false);
      assert.equal('deskCycle' in response.json().reasons[0], false);
      assert.equal(response.json().reasons[0].author.socialId, socialId);
      assert.equal(response.json().reasons[0].author.persona, 'oracle');
      const cursor = response.json().page.nextCursor as string;
      assert.deepEqual(JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')), [
        2, 'career-reasons', socialId, 'friends', 'apple', variantMint,
        friendReason.savedAt, reasonId,
      ]);
      repository.page = Object.freeze({reasons: Object.freeze([]), hasMore: false,
        principalSocialId: '76000000-0000-4000-8000-000000000099'});
      const crossed = await enabled.inject(`${url}&cursor=${cursor}`);
      assert.equal(crossed.statusCode, 503, crossed.body);
      assert.equal((await enabled.inject(CAREER_REASON_PRIVACY_ROUTE)).json()
        .reasonPrivacy.friendsSharing, 'available');
    } finally { await enabled.close(); }
  });

  test('returns current privacy when an older completed mutation is replayed', async () => {
    const repository = new MemoryReasonSharingRepository();
    const current = Object.freeze({
      ...privacy,
      revision: 4,
      visibility: 'nobody' as const,
      updatedAt: '2026-09-20T12:00:00.003Z',
    });
    repository.savePrivacy = async (selectedUser, command) => {
      repository.writes.push({userId: selectedUser,
        command: parseCareerReasonPrivacyWrite(command)});
      return current;
    };
    const app = appWith(repository);
    try {
      const replay = await app.inject({method: 'PUT', url: CAREER_REASON_PRIVACY_ROUTE,
        payload: {schemaVersion: 1, mutationId, baseRevision: 1,
          visibility: 'friends'}});
      assert.equal(replay.statusCode, 200, replay.body);
      assert.deepEqual(replay.json(), {schemaVersion: 1, reasonPrivacy: current});
    } finally { await app.close(); }
  });

  test('authenticates before every operation and exposes only supported scopes', async () => {
    const repository = new MemoryReasonSharingRepository();
    const app = appWith(repository, async () => null);
    try {
      for (const request of [
        {method: 'GET' as const, url: `${CAREER_REASON_LIST_ROUTE}?scope=self`},
        {method: 'GET' as const, url: CAREER_REASON_PRIVACY_ROUTE},
        {method: 'PUT' as const, url: CAREER_REASON_PRIVACY_ROUTE, payload: {
          schemaVersion: 1, mutationId, baseRevision: 1, visibility: 'nobody',
        }},
      ]) assert.equal((await app.inject(request)).statusCode, 401);
      assert.equal(repository.lists.length, 0);
      assert.equal(repository.reads.length, 0);
      assert.equal(repository.writes.length, 0);

    } finally { await app.close(); }

    const authenticated = appWith(new MemoryReasonSharingRepository());
    try {
      assert.equal((await authenticated.inject({
        url: `${CAREER_REASON_LIST_ROUTE}?scope=friends`,
      })).statusCode, 400);
      assert.equal((await authenticated.inject({
        url: `${CAREER_REASON_LIST_ROUTE}?scope=everyone`,
      })).statusCode, 400);
      assert.equal((await authenticated.inject({
        url: `${CAREER_REASON_LIST_ROUTE}?scope=everyone&assetId=apple`,
      })).statusCode, 400);
    } finally { await authenticated.close(); }
  });

  test('maps privacy conflicts without exposing repository messages', async () => {
    const repository = new MemoryReasonSharingRepository();
    repository.failure = new CareerReasonSharingError(
      'CAREER_REASON_PRIVACY_REVISION_CONFLICT',
      'private database detail',
    );
    const app = appWith(repository);
    try {
      const response = await app.inject({method: 'PUT', url: CAREER_REASON_PRIVACY_ROUTE,
        payload: {schemaVersion: 1, mutationId, baseRevision: 1,
          visibility: 'everyone'}});
      assert.equal(response.statusCode, 409, response.body);
      assert.equal(response.json().error.code, 'CAREER_REASON_PRIVACY_REVISION_CONFLICT');
      assert.equal(response.body.includes('private'), false);
    } finally { await app.close(); }
  });

  test('maps account-only friends reads to the stable 403 error', async () => {
    const repository = new MemoryReasonSharingRepository();
    repository.failure = new CareerReasonSharingError(
      'CAREER_REASON_FRIENDS_ACCOUNT_REQUIRED',
      'private account linkage detail',
    );
    const guestToken = `tg1_${'H'.repeat(43)}`;
    const guests: GuestSessionRepository = {
      takeCreationAttempt: async () => { throw new Error('not used'); },
      create: async () => { throw new Error('not used'); },
      refresh: async () => { throw new Error('not used'); },
      claim: async () => { throw new Error('not used'); },
      authorize: async () => ({userId,
        guestId: '74000000-0000-4000-8000-000000000009',
        expiresAt: '2026-09-21T00:00:00.000Z'}),
    };
    const app = appWith(repository,
      createCareerReasonSharingAuthenticator(async () => null, guests), true);
    try {
      const response = await app.inject({
        url: `${CAREER_REASON_LIST_ROUTE}?scope=friends&assetId=apple&variantMint=${variantMint}`,
        headers: {authorization: `Guest ${guestToken}`},
      });
      assert.equal(response.statusCode, 403, response.body);
      assert.equal(response.json().error.code, 'CAREER_REASON_FRIENDS_ACCOUNT_REQUIRED');
      assert.equal(response.body.includes('private'), false);
    } finally { await app.close(); }
  });

  test('does not present a closed account receipt as an active privacy setting', async () => {
    const repository = new MemoryReasonSharingRepository();
    repository.failure = new CareerReasonSharingError(
      'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND',
      'closed account still has a private receipt',
    );
    const app = appWith(repository);
    try {
      const replay = await app.inject({method: 'PUT', url: CAREER_REASON_PRIVACY_ROUTE,
        payload: {schemaVersion: 1, mutationId, baseRevision: 1,
          visibility: 'everyone'}});
      assert.equal(replay.statusCode, 404, replay.body);
      assert.equal(replay.json().error.code, 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND');
      assert.equal('reasonPrivacy' in replay.json(), false);
      assert.equal(replay.body.includes('private receipt'), false);
    } finally { await app.close(); }
  });

  test('rejects widened adapter output before it reaches a response', async () => {
    const repository = new MemoryReasonSharingRepository();
    repository.page = {
      reasons: [{...firstReason, secret: 'private adapter detail'}],
      hasMore: false,
    } as unknown as CareerReasonListPage;
    const originalGet = repository.getPrivacy.bind(repository);
    repository.getPrivacy = async selectedUser => ({
      ...await originalGet(selectedUser),
      secret: 'private adapter detail',
    } as unknown as CareerReasonPrivacy);
    const app = appWith(repository);
    try {
      const list = await app.inject({
        url: `${CAREER_REASON_LIST_ROUTE}?scope=everyone&assetId=apple&variantMint=${variantMint}`,
      });
      assert.equal(list.statusCode, 503, list.body);
      assert.equal(list.body.includes('private adapter detail'), false);
      const read = await app.inject({url: CAREER_REASON_PRIVACY_ROUTE});
      assert.equal(read.statusCode, 503, read.body);
      assert.equal(read.body.includes('private adapter detail'), false);
    } finally { await app.close(); }
  });

  test('uses existing Career guest read and write budgets', async () => {
    const guestToken = `tg1_${'G'.repeat(43)}`;
    const scopes: GuestPaperScope[] = [];
    const guests: GuestSessionRepository = {
      takeCreationAttempt: async () => { throw new Error('not used'); },
      create: async () => { throw new Error('not used'); },
      refresh: async () => { throw new Error('not used'); },
      claim: async () => { throw new Error('not used'); },
      authorize: async (credentialHash, scope) => {
        assert.equal(credentialHash, hashGuestCredential(guestToken));
        scopes.push(scope);
        return {userId, guestId: '74000000-0000-4000-8000-000000000009',
          expiresAt: '2026-09-21T00:00:00.000Z'};
      },
    };
    const repository = new MemoryReasonSharingRepository();
    repository.page = Object.freeze({reasons: Object.freeze([]), hasMore: false});
    const app = appWith(repository,
      createCareerReasonSharingAuthenticator(async () => null, guests));
    try {
      const headers = {authorization: `Guest ${guestToken}`};
      assert.equal((await app.inject({url: `${CAREER_REASON_LIST_ROUTE}?scope=self`,
        headers})).statusCode, 200);
      assert.equal((await app.inject({url: CAREER_REASON_PRIVACY_ROUTE,
        headers})).statusCode, 200);
      assert.equal((await app.inject({method: 'PUT', url: CAREER_REASON_PRIVACY_ROUTE,
        headers, payload: {schemaVersion: 1, mutationId,
          baseRevision: 1, visibility: 'nobody'}})).statusCode, 200);
      assert.deepEqual(scopes, ['career_read', 'career_read', 'career_write']);
    } finally { await app.close(); }

    const limitedGuests = {...guests, authorize: async () => {
      throw new GuestSessionError(
        'GUEST_SESSION_RATE_LIMITED',
        'private rate state',
        17,
      );
    }};
    const limited = appWith(new MemoryReasonSharingRepository(),
      createCareerReasonSharingAuthenticator(async () => null, limitedGuests));
    try {
      const response = await limited.inject({url: `${CAREER_REASON_LIST_ROUTE}?scope=self`,
        headers: {authorization: `Guest ${guestToken}`}});
      assert.equal(response.statusCode, 429, response.body);
      assert.equal(response.headers['retry-after'], '17');
      assert.equal(response.body.includes('private'), false);
    } finally { await limited.close(); }
  });
});
