import assert from 'node:assert/strict';
import {describe, test} from 'node:test';
import {buildApp} from '../src/app.js';
import {
  CAREER_ACTIVITY_WEEK_ROUTE,
  CAREER_DAY_CONTEXT_ROUTE,
  CAREER_MISSIONS_ROUTE,
  CAREER_PROMOTION_ROUTE,
  CAREER_REASON_ROUTE,
  CAREER_SUMMARY_ROUTE,
  createCareerAuthenticator,
} from '../src/career-routes.js';
import {
  CareerRepositoryError,
  parseCareerDayContextWrite,
  parseCareerPromotionWrite,
  parseCareerTradeReasonWrite,
} from '../src/career-repository.js';
import {hashGuestCredential} from '../src/guest-session-routes.js';
import {GuestSessionError} from '../src/guest-session-repository.js';
import type {
  GuestPaperScope,
  GuestSessionRepository,
} from '../src/guest-session-repository.js';
import {requestPracticeBearerToken} from '../src/practice-session-routes.js';
import type {
  CareerRepository,
  CareerDayContext,
  CareerDayContextWrite,
  CareerMissionBoard,
  CareerPromotionReceipt,
  CareerPromotionWrite,
  CareerSummary,
  CareerTradeReasonReceipt,
  CareerTradeReasonWrite,
} from '../src/career-repository.js';

const userId = '72000000-0000-4000-8000-000000000001';
const mutationId = '72000000-0000-4000-8000-000000000002';
const orderId = '72000000-0000-4000-8000-000000000003';
const promotionMutationId = '72000000-0000-4000-8000-000000000004';
const dayMutationId = '72000000-0000-4000-8000-000000000005';
const career: CareerSummary = Object.freeze({
  revision: 2,
  trims: Object.freeze({total: 10, today: 10, thisWeek: 10}),
  rank: Object.freeze({id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0}),
  nextRank: Object.freeze({
    id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 290, promotionRequired: false,
  }),
  streak: Object.freeze({days: 1, status: 'active', lastActiveDate: '2026-09-20'}),
  careerStarted: true,
  firstConfirmedBuy: Object.freeze({orderId, assetId: 'apple',
    variantMint: '11111111111111111111111111111111', symbol: 'AAPLx', quantityMicros: '5000',
    confirmedAt: '2026-09-20T09:00:00.000Z'}),
  serverDate: '2026-09-20',
  updatedAt: '2026-09-20T10:00:00.000Z',
});
const missions: CareerMissionBoard = Object.freeze({
  revision: 2,
  currentRank: 'rookie',
  missions: Object.freeze([
    Object.freeze({id: 'first-paper-buy', chapterRank: 'rookie', order: 1, kind: 'action',
      title: 'Buy your first stock', instruction: 'Complete one paper buy.', trimsReward: 20,
      promotesToRank: null, status: 'complete', completedAt: '2026-09-20T09:00:00.000Z'}),
    Object.freeze({id: 'write-a-reason', chapterRank: 'rookie', order: 2, kind: 'action',
      title: 'Write your reason', instruction: 'Add a reason to a paper buy you still hold.', trimsReward: 20,
      promotesToRank: null, status: 'ready', completedAt: null}),
    Object.freeze({id: 'hold-through-red-day', chapterRank: 'rookie', order: 3, kind: 'promotion',
      title: 'Hold through a red day',
      instruction: 'Hold a stock through a verified red Wall Street day.', trimsReward: 20,
      promotesToRank: 'analyst', status: 'locked', completedAt: null}),
  ]),
});
const promotion: CareerPromotionReceipt = Object.freeze({
  mutationId: promotionMutationId,
  fromRank: 'rookie',
  toRank: 'analyst',
  careerRevision: 20,
  trimsAwarded: 100,
  promotedAt: '2026-09-20T12:00:00.000Z',
});
const receipt: CareerTradeReasonReceipt = Object.freeze({
  orderId,
  assetId: 'apple',
  variantMint: '11111111111111111111111111111111',
  note: 'The services margin is improving.',
  trimsAwarded: 10,
  dailyAwardNumber: 1,
  savedAt: '2026-09-20T10:00:00.000Z',
});
const dayContext: CareerDayContext = Object.freeze({
  revision: 2,
  timeZone: 'Africa/Lagos',
  configured: true,
  serverDate: '2026-09-20',
  nextDayAt: '2026-09-20T23:00:00.000Z',
  createdAt: '2026-09-20T08:00:00.000Z',
  updatedAt: '2026-09-20T09:00:00.000Z',
});

class MemoryCareerRepository implements CareerRepository {
  readonly writes: Array<{userId: string; command: CareerTradeReasonWrite}> = [];
  readonly promotions: Array<{userId: string; command: CareerPromotionWrite}> = [];
  readonly dayWrites: Array<{userId: string; command: CareerDayContextWrite}> = [];
  failure?: CareerRepositoryError;

  async getActivityWeek(selectedUser: string) {
    assert.equal(selectedUser, userId);
    return {serverDate: '2026-09-24', weekStart: '2026-09-21', activeDates: ['2026-09-21', '2026-09-24']};
  }

  async getSummary(selectedUser: string): Promise<CareerSummary> {
    if (this.failure) throw this.failure;
    assert.equal(selectedUser, userId);
    return career;
  }

  async getMissions(selectedUser: string): Promise<CareerMissionBoard> {
    if (this.failure) throw this.failure;
    assert.equal(selectedUser, userId);
    return missions;
  }

  async getDayContext(selectedUser: string): Promise<CareerDayContext> {
    if (this.failure) throw this.failure;
    assert.equal(selectedUser, userId);
    return dayContext;
  }

  async saveDayContext(selectedUser: string, command: CareerDayContextWrite): Promise<CareerDayContext> {
    if (this.failure) throw this.failure;
    this.dayWrites.push({userId: selectedUser, command: parseCareerDayContextWrite(command)});
    return dayContext;
  }

  async saveTradeReason(selectedUser: string, command: CareerTradeReasonWrite): Promise<CareerTradeReasonReceipt> {
    if (this.failure) throw this.failure;
    this.writes.push({userId: selectedUser, command: parseCareerTradeReasonWrite(command)});
    return receipt;
  }

  async promote(selectedUser: string, command: CareerPromotionWrite): Promise<CareerPromotionReceipt> {
    if (this.failure) throw this.failure;
    this.promotions.push({userId: selectedUser, command: parseCareerPromotionWrite(command)});
    return promotion;
  }
}

describe('career routes', () => {
  test('are closed when the server-owned career adapter is absent', async () => {
    const app = buildApp({logger: false});
    try {
      assert.equal((await app.inject({url: CAREER_SUMMARY_ROUTE})).statusCode, 503);
      assert.equal((await app.inject({url: CAREER_MISSIONS_ROUTE})).statusCode, 503);
      assert.equal((await app.inject({url: CAREER_DAY_CONTEXT_ROUTE})).statusCode, 503);
      const write = await app.inject({method: 'POST', url: CAREER_REASON_ROUTE, payload: {
        schemaVersion: 1, mutationId, orderId, note: 'A reason',
      }});
      assert.equal(write.statusCode, 503);
      assert.equal(write.json().error.code, 'CAREER_UNAVAILABLE');
      const promotion = await app.inject({method: 'POST', url: CAREER_PROMOTION_ROUTE, payload: {
        schemaVersion: 1, mutationId: promotionMutationId, targetRank: 'analyst',
      }});
      assert.equal(promotion.statusCode, 503);
      assert.equal(promotion.json().error.code, 'CAREER_UNAVAILABLE');
      assert.equal((await app.inject({method: 'PUT', url: CAREER_DAY_CONTEXT_ROUTE, payload: {
        schemaVersion: 1, mutationId: dayMutationId, baseRevision: 1, timeZone: 'Africa/Lagos',
      }})).statusCode, 503);
    } finally { await app.close(); }
  });

  test('returns a summary and saves one authenticated paper reason', async () => {
    const repository = new MemoryCareerRepository();
    const app = buildApp({logger: false, career: {
      repository, authenticate: async () => ({userId}),
    }});
    try {
      const week = await app.inject({url: CAREER_ACTIVITY_WEEK_ROUTE});
      assert.equal(week.statusCode, 200, week.body);
      assert.deepEqual(week.json().activityWeek.activeDates, ['2026-09-21', '2026-09-24']);
      assert.equal((await app.inject({url: `${CAREER_ACTIVITY_WEEK_ROUTE}?userId=someone-else`})).statusCode, 400);
      const summary = await app.inject({url: CAREER_SUMMARY_ROUTE});
      assert.equal(summary.statusCode, 200, summary.body);
      assert.deepEqual(summary.json(), {schemaVersion: 1, career});

      const write = await app.inject({method: 'POST', url: CAREER_REASON_ROUTE, payload: {
        schemaVersion: 1,
        mutationId: mutationId.toUpperCase(),
        orderId: orderId.toUpperCase(),
        note: receipt.note,
      }});
      assert.equal(write.statusCode, 201, write.body);
      assert.deepEqual(write.json(), {schemaVersion: 1, reason: receipt});
      assert.deepEqual(repository.writes, [{userId, command: {
        mutationId, orderId, note: receipt.note,
      }}]);

      const missionResponse = await app.inject({url: CAREER_MISSIONS_ROUTE});
      assert.equal(missionResponse.statusCode, 200, missionResponse.body);
      assert.deepEqual(missionResponse.json(), {schemaVersion: 1,
        career: {revision: missions.revision, currentRank: missions.currentRank},
        missions: missions.missions});

      const promoted = await app.inject({method: 'POST', url: CAREER_PROMOTION_ROUTE, payload: {
        schemaVersion: 1, mutationId: promotionMutationId.toUpperCase(), targetRank: 'analyst',
      }});
      assert.equal(promoted.statusCode, 201, promoted.body);
      assert.deepEqual(promoted.json(), {schemaVersion: 1, promotion});
      assert.deepEqual(repository.promotions, [{userId, command: {
        mutationId: promotionMutationId, targetRank: 'analyst',
      }}]);

      const dayRead = await app.inject({url: CAREER_DAY_CONTEXT_ROUTE});
      assert.equal(dayRead.statusCode, 200, dayRead.body);
      assert.deepEqual(dayRead.json(), {schemaVersion: 1, dayContext});
      const dayWrite = await app.inject({method: 'PUT', url: CAREER_DAY_CONTEXT_ROUTE, payload: {
        schemaVersion: 1, mutationId: dayMutationId.toUpperCase(),
        baseRevision: 1, timeZone: 'Africa/Lagos',
      }});
      assert.equal(dayWrite.statusCode, 200, dayWrite.body);
      assert.deepEqual(dayWrite.json(), {schemaVersion: 1, dayContext});
      assert.deepEqual(repository.dayWrites, [{userId, command: {
        mutationId: dayMutationId, baseRevision: 1, timeZone: 'Africa/Lagos',
      }}]);
      const rawOffset = await app.inject({method: 'PUT', url: CAREER_DAY_CONTEXT_ROUTE, payload: {
        schemaVersion: 1, mutationId: dayMutationId, baseRevision: 1, timeZone: '+01:00',
      }});
      assert.equal(rawOffset.statusCode, 400, rawOffset.body);
      assert.equal(rawOffset.json().error.code, 'CAREER_INVALID_INPUT');
      assert.equal(repository.dayWrites.length, 1);
    } finally { await app.close(); }
  });

  test('authenticates before reading or writing and rejects widened payloads', async () => {
    const repository = new MemoryCareerRepository();
    const app = buildApp({logger: false, career: {
      repository, authenticate: async () => null,
    }});
    try {
      assert.equal((await app.inject({url: CAREER_SUMMARY_ROUTE})).statusCode, 401);
      assert.equal((await app.inject({method: 'POST', url: CAREER_REASON_ROUTE, payload: {
        schemaVersion: 1, mutationId, orderId, note: 'A reason', wallet: 'secret',
      }})).statusCode, 400);
      assert.equal((await app.inject({method: 'POST', url: CAREER_REASON_ROUTE, payload: {
        schemaVersion: 1, mutationId, orderId, note: 'A reason',
      }})).statusCode, 401);
      assert.equal((await app.inject({method: 'POST', url: CAREER_PROMOTION_ROUTE, payload: {
        schemaVersion: 1, mutationId: promotionMutationId, targetRank: 'analyst', paperLimit: '25000',
      }})).statusCode, 400);
      assert.equal((await app.inject({method: 'PUT', url: CAREER_DAY_CONTEXT_ROUTE, payload: {
        schemaVersion: 1, mutationId: dayMutationId, baseRevision: 1,
        timeZone: 'Africa/Lagos', offsetMinutes: 60,
      }})).statusCode, 400);
      assert.equal(repository.writes.length, 0);
      assert.equal(repository.promotions.length, 0);
    } finally { await app.close(); }
  });

  test('maps domain conflicts without leaking private details', async () => {
    const repository = new MemoryCareerRepository();
    repository.failure = new CareerRepositoryError('CAREER_POSITION_REQUIRED', 'private database detail');
    const app = buildApp({logger: false, career: {
      repository, authenticate: async () => ({userId}),
    }});
    try {
      const response = await app.inject({method: 'POST', url: CAREER_REASON_ROUTE, payload: {
        schemaVersion: 1, mutationId, orderId, note: 'A reason',
      }});
      assert.equal(response.statusCode, 409);
      assert.equal(response.json().error.code, 'CAREER_POSITION_REQUIRED');
      assert.equal(response.body.includes('private'), false);
    } finally { await app.close(); }
  });

  test('maps account and guest authorization to the exact Career scope', async () => {
    const repository = new MemoryCareerRepository();
    const guestToken = `tg1_${'C'.repeat(43)}`;
    const scopes: GuestPaperScope[] = [];
    const guests: GuestSessionRepository = {
      takeCreationAttempt: async () => { throw new Error('not used'); },
      create: async () => { throw new Error('not used'); },
      refresh: async () => { throw new Error('not used'); },
      claim: async () => { throw new Error('not used'); },
      authorize: async (credentialHash, scope) => {
        assert.equal(credentialHash, hashGuestCredential(guestToken));
        scopes.push(scope);
        return {userId, guestId: '72000000-0000-4000-8000-000000000009',
          expiresAt: '2026-09-21T00:00:00.000Z'};
      },
    };
    let accountCalls = 0;
    const authenticate = createCareerAuthenticator(async request => {
      accountCalls++;
      return requestPracticeBearerToken(request) ? {userId} : null;
    }, guests);
    const app = buildApp({logger: false, career: {repository, authenticate}});
    try {
      const guestRead = await app.inject({url: CAREER_SUMMARY_ROUTE,
        headers: {authorization: `Guest ${guestToken}`}});
      assert.equal(guestRead.statusCode, 200, guestRead.body);
      const guestWrite = await app.inject({method: 'POST', url: CAREER_REASON_ROUTE,
        headers: {authorization: `Guest ${guestToken}`}, payload: {
          schemaVersion: 1, mutationId, orderId, note: receipt.note,
        }});
      assert.equal(guestWrite.statusCode, 201, guestWrite.body);
      const guestMissions = await app.inject({url: CAREER_MISSIONS_ROUTE,
        headers: {authorization: `Guest ${guestToken}`}});
      assert.equal(guestMissions.statusCode, 200, guestMissions.body);
      const guestPromotion = await app.inject({method: 'POST', url: CAREER_PROMOTION_ROUTE,
        headers: {authorization: `Guest ${guestToken}`}, payload: {
          schemaVersion: 1, mutationId: promotionMutationId, targetRank: 'analyst',
        }});
      assert.equal(guestPromotion.statusCode, 201, guestPromotion.body);
      const guestDayRead = await app.inject({url: CAREER_DAY_CONTEXT_ROUTE,
        headers: {authorization: `Guest ${guestToken}`}});
      assert.equal(guestDayRead.statusCode, 200, guestDayRead.body);
      const guestDayWrite = await app.inject({method: 'PUT', url: CAREER_DAY_CONTEXT_ROUTE,
        headers: {authorization: `Guest ${guestToken}`}, payload: {
          schemaVersion: 1, mutationId: dayMutationId, baseRevision: 1, timeZone: 'Africa/Lagos',
        }});
      assert.equal(guestDayWrite.statusCode, 200, guestDayWrite.body);
      assert.deepEqual(scopes, [
        'career_read', 'career_write', 'career_read', 'career_write', 'career_read', 'career_write',
      ]);
      assert.equal(accountCalls, 0);

      const accountRead = await app.inject({url: CAREER_SUMMARY_ROUTE,
        headers: {authorization: 'Bearer header.payload.signature'}});
      assert.equal(accountRead.statusCode, 200, accountRead.body);
      assert.equal(accountCalls, 1);
      assert.deepEqual(scopes, [
        'career_read', 'career_write', 'career_read', 'career_write', 'career_read', 'career_write',
      ]);
    } finally { await app.close(); }
  });

  test('preserves terminal guest codes on Career reads and writes without leaking storage detail', async () => {
    const guestToken = `tg1_${'T'.repeat(43)}`;
    for (const code of ['GUEST_SESSION_EXPIRED', 'GUEST_SESSION_REVOKED'] as const) {
      const guests: GuestSessionRepository = {
        takeCreationAttempt: async () => { throw new Error('not used'); },
        create: async () => { throw new Error('not used'); },
        refresh: async () => { throw new Error('not used'); },
        claim: async () => { throw new Error('not used'); },
        authorize: async () => {
          throw new GuestSessionError(code, `private ${code} database detail`);
        },
      };
      const repository = new MemoryCareerRepository();
      const app = buildApp({logger: false, career: {repository,
        authenticate: createCareerAuthenticator(async () => null, guests)}});
      try {
        const headers = {authorization: `Guest ${guestToken}`};
        for (const request of [
          {method: 'GET' as const, url: CAREER_SUMMARY_ROUTE, headers},
          {method: 'POST' as const, url: CAREER_REASON_ROUTE, headers, payload: {
            schemaVersion: 1, mutationId, orderId, note: receipt.note,
          }},
        ]) {
          const response = await app.inject(request);
          assert.equal(response.statusCode, 401, response.body);
          assert.equal(response.json().error.code, code);
          assert.equal(response.body.includes('private'), false);
        }
        assert.equal(repository.writes.length, 0);
      } finally { await app.close(); }
    }
  });
});
