import assert from 'node:assert/strict';
import {describe, test} from 'node:test';
import {
  CareerRepositoryError,
  parseCareerDayContext,
  parseCareerDayContextWrite,
  parseCareerMissionBoard,
  parseCareerPromotionReceipt,
  parseCareerPromotionWrite,
  parseCareerSummary,
  parseCareerTradeReasonReceipt,
  parseCareerTradeReasonWrite,
} from '../src/career-repository.js';

const mutationId = '71000000-0000-4000-8000-000000000001';
const orderId = '71000000-0000-4000-8000-000000000002';

describe('career repository boundary', () => {
  test('normalizes identifiers and accepts a concise Unicode reason', () => {
    const value = parseCareerTradeReasonWrite({
      mutationId: mutationId.toUpperCase(),
      orderId: orderId.toUpperCase(),
      note: 'I expect margins to recover 📈',
    });
    assert.equal(value.mutationId, mutationId);
    assert.equal(value.orderId, orderId);
    assert.equal(value.note, 'I expect margins to recover 📈');
  });

  test('rejects padded, empty, overlong, controlled or widened reason input', () => {
    const invalid = [
      {mutationId, orderId, note: ''},
      {mutationId, orderId, note: ' padded '},
      {mutationId, orderId, note: 'a'.repeat(181)},
      {mutationId, orderId, note: 'line\u0000break'},
      {mutationId, orderId, note: 'valid', visibility: 'everyone'},
    ];
    for (const input of invalid) {
      assert.throws(() => parseCareerTradeReasonWrite(input),
        (error: unknown) => error instanceof CareerRepositoryError && error.code === 'CAREER_INVALID_INPUT');
    }
  });

  test('parses the empty server-owned career summary exactly', () => {
    assert.deepEqual(parseCareerSummary({
      revision: 0,
      trims: {total: 0, today: 0, thisWeek: 0},
      rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0},
      nextRank: {
        id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 300, promotionRequired: false,
      },
      streak: {days: 0, status: 'not-started', lastActiveDate: null},
      careerStarted: false,
      firstConfirmedBuy: null,
      serverDate: '2026-09-20',
      updatedAt: null,
    }), {
      revision: 0,
      trims: {total: 0, today: 0, thisWeek: 0},
      rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0},
      nextRank: {
        id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 300, promotionRequired: false,
      },
      streak: {days: 0, status: 'not-started', lastActiveDate: null},
      careerStarted: false,
      firstConfirmedBuy: null,
      serverDate: '2026-09-20',
      updatedAt: null,
    });
  });

  test('rejects internally impossible summary snapshots as stored corruption', () => {
    const base = {
      revision: 1,
      trims: {total: 10, today: 10, thisWeek: 10},
      rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0},
      nextRank: {
        id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 290, promotionRequired: false,
      },
      streak: {days: 1, status: 'active', lastActiveDate: '2026-09-20'},
      careerStarted: true,
      firstConfirmedBuy: {orderId, assetId: 'apple',
        variantMint: '11111111111111111111111111111111', symbol: 'AAPLx', quantityMicros: '5000',
        confirmedAt: '2026-09-20T09:00:00.000Z'},
      serverDate: '2026-09-20',
      updatedAt: '2026-09-20T10:00:00.000Z',
    };
    for (const input of [
      {...base, trims: {...base.trims, today: 11}},
      {...base, revision: 0},
      {...base, streak: {...base.streak, days: 0}},
      {...base, careerStarted: false},
      {...base, firstConfirmedBuy: {...base.firstConfirmedBuy, symbol: ' AAPLx'}},
      {...base, firstConfirmedBuy: {...base.firstConfirmedBuy, quantityMicros: '05000'}},
      {...base, firstConfirmedBuy: {...base.firstConfirmedBuy, quantityMicros: '0'}},
      {...base, firstConfirmedBuy: {...base.firstConfirmedBuy, confirmedAt: '2026-09-20T11:00:00.000Z'}},
      {...base, surprise: true},
    ]) {
      assert.throws(() => parseCareerSummary(input),
        (error: unknown) => error instanceof CareerRepositoryError && error.code === 'CAREER_STORAGE_INVALID');
    }
  });

  test('accepts only zero or ten Trims and the first three daily awards', () => {
    const base = {
      orderId,
      assetId: 'apple',
      variantMint: '11111111111111111111111111111111',
      note: 'The services margin is improving.',
      savedAt: '2026-09-20T10:00:00.000Z',
    };
    assert.equal(parseCareerTradeReasonReceipt({
      ...base, trimsAwarded: 10, dailyAwardNumber: 3,
    }).trimsAwarded, 10);
    assert.equal(parseCareerTradeReasonReceipt({
      ...base, trimsAwarded: 0, dailyAwardNumber: null,
    }).trimsAwarded, 0);
    for (const input of [
      {...base, trimsAwarded: 5, dailyAwardNumber: 1},
      {...base, trimsAwarded: 10, dailyAwardNumber: null},
      {...base, trimsAwarded: 0, dailyAwardNumber: 1},
      {...base, trimsAwarded: 10, dailyAwardNumber: 4},
    ]) {
      assert.throws(() => parseCareerTradeReasonReceipt(input),
        (error: unknown) => error instanceof CareerRepositoryError && error.code === 'CAREER_STORAGE_INVALID');
    }
  });

  test('parses the exact authored mission path and rejects client-invented missions', () => {
    const board = parseCareerMissionBoard({revision: 2, currentRank: 'rookie', missions: [
      {id: 'first-paper-buy', chapterRank: 'rookie', order: 1, kind: 'action',
        title: 'Buy your first stock', instruction: 'Complete one paper buy.', trimsReward: 20,
        promotesToRank: null, status: 'complete', completedAt: '2026-09-20T09:00:00.000Z'},
      {id: 'write-a-reason', chapterRank: 'rookie', order: 2, kind: 'action',
        title: 'Write your reason', instruction: 'Add a reason to a paper buy you still hold.',
        trimsReward: 20, promotesToRank: null, status: 'ready', completedAt: null},
      {id: 'hold-through-red-day', chapterRank: 'rookie', order: 3, kind: 'promotion',
        title: 'Hold through a red day',
        instruction: 'Hold a stock through a verified red Wall Street day.', trimsReward: 20,
        promotesToRank: 'analyst', status: 'locked', completedAt: null},
    ]});
    assert.equal(board.missions[1]?.status, 'ready');
    assert.throws(() => parseCareerMissionBoard({...board,
      missions: [...board.missions.slice(0, 2), {...board.missions[2], title: 'Trade more'}]}),
    (error: unknown) => error instanceof CareerRepositoryError && error.code === 'CAREER_STORAGE_INVALID');
  });

  test('normalizes promotion commands and validates an adjacent 100-Trim receipt', () => {
    const command = parseCareerPromotionWrite({mutationId: mutationId.toUpperCase(), targetRank: 'analyst'});
    assert.deepEqual(command, {mutationId, targetRank: 'analyst'});
    const receipt = parseCareerPromotionReceipt({mutationId, fromRank: 'rookie', toRank: 'analyst',
      careerRevision: 18, trimsAwarded: 100, promotedAt: '2026-09-20T12:00:00.000Z'});
    assert.equal(receipt.trimsAwarded, 100);
    for (const input of [
      {mutationId, targetRank: 'rookie'},
      {mutationId, targetRank: 'legend'},
    ]) {
      if (input.targetRank === 'rookie') {
        assert.throws(() => parseCareerPromotionWrite(input),
          (error: unknown) => error instanceof CareerRepositoryError && error.code === 'CAREER_INVALID_INPUT');
      } else {
        assert.throws(() => parseCareerPromotionReceipt({mutationId, fromRank: 'rookie',
          toRank: input.targetRank, careerRevision: 18, trimsAwarded: 100,
          promotedAt: '2026-09-20T12:00:00.000Z'}),
        (error: unknown) => error instanceof CareerRepositoryError && error.code === 'CAREER_STORAGE_INVALID');
      }
    }
  });

  test('accepts only strict IANA day-context commands and snapshots', () => {
    assert.deepEqual(parseCareerDayContextWrite({
      mutationId: mutationId.toUpperCase(), baseRevision: 1, timeZone: 'Africa/Lagos',
    }), {mutationId, baseRevision: 1, timeZone: 'Africa/Lagos'});
    const fallback = parseCareerDayContext({
      revision: 1, timeZone: 'UTC', configured: false, serverDate: '2026-09-20',
      nextDayAt: '2026-09-21T00:00:00.000Z',
      createdAt: '2026-09-20T10:00:00.000Z', updatedAt: '2026-09-20T10:00:00.000Z',
    });
    assert.equal(fallback.configured, false);
    assert.equal(parseCareerDayContext({
      revision: 2, timeZone: 'America/Argentina/Buenos_Aires', configured: true,
      serverDate: '2026-09-20', createdAt: '2026-09-20T10:00:00.000Z',
      nextDayAt: '2026-09-21T03:00:00.000Z',
      updatedAt: '2026-09-20T10:01:00.000Z',
    }).timeZone, 'America/Argentina/Buenos_Aires');
    for (const input of [
      {mutationId, baseRevision: 1, timeZone: '+01:00'},
      {mutationId, baseRevision: 1, timeZone: 'PST'},
      {mutationId, baseRevision: 0, timeZone: 'Africa/Lagos'},
      {mutationId, baseRevision: 1, timeZone: 'posix/Africa/Lagos'},
      {mutationId, baseRevision: 1, timeZone: 'Africa/Lagos', offset: 60},
    ]) {
      assert.throws(() => parseCareerDayContextWrite(input),
        (error: unknown) => error instanceof CareerRepositoryError && error.code === 'CAREER_INVALID_INPUT');
    }
    assert.throws(() => parseCareerDayContext({...fallback, revision: 2}),
      (error: unknown) => error instanceof CareerRepositoryError && error.code === 'CAREER_STORAGE_INVALID');
  });
});
