import assert from 'node:assert/strict';
import {Buffer} from 'node:buffer';
import {describe, test} from 'node:test';
import {
  CareerReasonSharingError,
  careerReasonRankLabel,
  decodeCareerReasonCursor,
  encodeCareerReasonCursor,
  parseCareerReasonListHttpQuery,
  parseCareerReasonListItem,
  parseCareerReasonListPage,
  parseCareerReasonListQuery,
  parseCareerReasonPrivacy,
  parseCareerReasonPrivacyWrite,
} from '../src/career-reason-sharing.js';

const mutationId = '74000000-0000-4000-8000-000000000001';
const orderId = '74000000-0000-4000-8000-000000000002';
const reasonId = '75000000-0000-4000-8000-000000000002';
const socialId = '76000000-0000-4000-8000-000000000002';
const variantMint = '11111111111111111111111111111111';
const savedAt = '2026-09-20T12:00:00.000Z';

function isInvalid(error: unknown): boolean {
  return error instanceof CareerReasonSharingError &&
    error.code === 'CAREER_REASON_SHARING_INVALID_INPUT';
}

function isStorageInvalid(error: unknown): boolean {
  return error instanceof CareerReasonSharingError &&
    error.code === 'CAREER_REASON_SHARING_STORAGE_INVALID';
}

describe('Career reason sharing boundary', () => {
  test('accepts only the conservative default and revisioned configured snapshots', () => {
    const initial = parseCareerReasonPrivacy({
      revision: 1,
      visibility: 'nobody',
      configured: false,
      friendsSharing: 'unavailable',
      createdAt: savedAt,
      updatedAt: savedAt,
    });
    assert.deepEqual(initial, {
      revision: 1,
      visibility: 'nobody',
      configured: false,
      friendsSharing: 'unavailable',
      createdAt: savedAt,
      updatedAt: savedAt,
    });
    assert.equal(parseCareerReasonPrivacy({
      ...initial,
      revision: 2,
      visibility: 'friends',
      configured: true,
      updatedAt: '2026-09-20T12:00:00.001Z',
    }).visibility, 'friends');

    for (const input of [
      {...initial, visibility: 'everyone'},
      {...initial, configured: true},
      {...initial, revision: 2},
      {...initial, extra: true},
    ]) assert.throws(() => parseCareerReasonPrivacy(input), isStorageInvalid);
    assert.equal(parseCareerReasonPrivacy({...initial, friendsSharing: 'available'}).friendsSharing,
      'available');
  });

  test('normalizes strict revisioned privacy writes', () => {
    assert.deepEqual(parseCareerReasonPrivacyWrite({
      mutationId: mutationId.toUpperCase(),
      baseRevision: 1,
      visibility: 'everyone',
    }), {mutationId, baseRevision: 1, visibility: 'everyone'});
    for (const input of [
      {mutationId, baseRevision: 0, visibility: 'nobody'},
      {mutationId, baseRevision: 1, visibility: 'self'},
      {mutationId, baseRevision: 1, visibility: 'friends', configured: true},
    ]) assert.throws(() => parseCareerReasonPrivacyWrite(input), isInvalid);
  });

  test('requires exact asset and mint pairs and applies bounded HTTP limits', () => {
    const defaults = parseCareerReasonListHttpQuery({scope: 'self'});
    assert.deepEqual(defaults, {
      scope: 'self', limit: 20, assetId: null, variantMint: null, cursor: null,
    });
    assert.deepEqual(parseCareerReasonListHttpQuery({
      scope: 'everyone', limit: '50', assetId: 'apple', variantMint,
    }), {
      scope: 'everyone', limit: 50, assetId: 'apple', variantMint, cursor: null,
    });
    assert.equal(parseCareerReasonListHttpQuery({
      scope: 'friends', assetId: 'apple', variantMint,
    }).scope, 'friends');
    for (const input of [
      {scope: 'friends'},
      {scope: 'everyone'},
      {scope: 'everyone', limit: '0'},
      {scope: 'everyone', limit: '01'},
      {scope: 'everyone', limit: 20},
      {scope: 'everyone', assetId: 'apple'},
      {scope: 'everyone', variantMint},
      {scope: 'everyone', assetId: 'Apple', variantMint},
      {scope: 'everyone', extra: 'value'},
    ]) assert.throws(() => parseCareerReasonListHttpQuery(input), isInvalid);
  });

  test('binds a canonical cursor to its scope and exact stock filter', () => {
    const query = {scope: 'everyone' as const, assetId: 'apple', variantMint};
    const encoded = encodeCareerReasonCursor(query, {savedAt, reasonId});
    assert.deepEqual(decodeCareerReasonCursor(encoded, query), {savedAt, reasonId});
    assert.deepEqual(parseCareerReasonListHttpQuery({
      scope: 'everyone', assetId: 'apple', variantMint, cursor: encoded,
    }).cursor, {savedAt, reasonId});

    assert.throws(() => decodeCareerReasonCursor(encoded, {
      scope: 'self', assetId: 'apple', variantMint,
    }), isInvalid);
    assert.throws(() => decodeCareerReasonCursor(encoded, {
      scope: 'everyone', assetId: 'tesla', variantMint,
    }), isInvalid);
    assert.throws(() => decodeCareerReasonCursor(`${encoded}=`, query), isInvalid);
    assert.throws(() => decodeCareerReasonCursor(Buffer.from(JSON.stringify([
      1, 'everyone', 'apple', variantMint, savedAt, reasonId, 'extra',
    ])).toString('base64url'), query), isInvalid);
    assert.throws(() => decodeCareerReasonCursor(Buffer.from(JSON.stringify({
      version: 1, savedAt, reasonId,
    })).toString('base64url'), query), isInvalid);

    const friendsQuery = {scope: 'friends' as const, assetId: 'apple', variantMint};
    const friends = encodeCareerReasonCursor(friendsQuery, {savedAt, reasonId}, socialId);
    assert.deepEqual(decodeCareerReasonCursor(friends, friendsQuery), {
      principalSocialId: socialId, savedAt, reasonId,
    });
    assert.deepEqual(JSON.parse(Buffer.from(friends, 'base64url').toString('utf8')), [
      2, 'career-reasons', socialId, 'friends', 'apple', variantMint, savedAt, reasonId,
    ]);
    assert.throws(() => encodeCareerReasonCursor(friendsQuery, {savedAt, reasonId}), isInvalid);
    assert.throws(() => decodeCareerReasonCursor(encoded, friendsQuery), isInvalid);
  });

  test('parses a minimal reason record without position or performance claims', () => {
    const item = parseCareerReasonListItem({
      reasonId,
      orderId,
      author: {handle: 'ada_trade', rank: {id: 'analyst', label: 'Analyst'}, isViewer: true},
      stock: {assetId: 'apple', variantMint, symbol: 'AAPLx'},
      note: 'Margins improved for a second quarter.',
      deskCycle: 'historical',
      savedAt,
    });
    assert.equal(item.author.rank.label, careerReasonRankLabel('analyst'));
    assert.equal(item.deskCycle, 'historical');
    assert.equal('holding' in item, false);

    for (const input of [
      {...item, deskCycle: 'archived'},
      {...item, author: {...item.author, rank: {id: 'analyst', label: 'Trader'}}},
      {...item, stock: {...item.stock, variantMint: 'not-a-mint'}},
      {...item, currentReturn: '+12%'},
      {...item, note: 'Line one\nLine two'},
      {...item, note: 'Column\tvalue'},
      {...item, note: 'Old\rline'},
    ]) assert.throws(() => parseCareerReasonListItem(input), isStorageInvalid);
  });

  test('parses the strict friends projection without private order fields', () => {
    const item = parseCareerReasonListItem({
      reasonId,
      author: {socialId, handle: 'ada_trade', persona: 'oracle',
        rank: {id: 'analyst', label: 'Analyst'}, isViewer: false},
      stock: {assetId: 'apple', variantMint, symbol: 'AAPLx'},
      note: 'Margins improved for a second quarter.',
      savedAt,
    });
    assert.equal(item.author.isViewer, false);
    assert.equal('orderId' in item, false);
    assert.equal('deskCycle' in item, false);
    assert.equal('socialId' in item.author && item.author.socialId, socialId);

    for (const input of [
      {...item, orderId},
      {...item, deskCycle: 'current'},
      {...item, author: {...item.author, socialId: undefined}},
      {...item, author: {...item.author, persona: 'spark'}},
      {...item, author: {...item.author, isViewer: true}},
      {...item, author: {...item.author, subject: '123456'}},
    ]) assert.throws(() => parseCareerReasonListItem(input), isStorageInvalid);
  });

  test('accepts only a strict, descending, bounded repository page', () => {
    const first = parseCareerReasonListItem({
      reasonId,
      orderId,
      author: {handle: 'ada_trade', rank: {id: 'analyst', label: 'Analyst'}, isViewer: true},
      stock: {assetId: 'apple', variantMint, symbol: 'AAPLx'},
      note: 'Margins improved.', deskCycle: 'current', savedAt,
    });
    assert.deepEqual(parseCareerReasonListPage({reasons: [first], hasMore: true}), {
      reasons: [first], hasMore: true,
    });
    for (const input of [
      {reasons: [], hasMore: true},
      {reasons: [first], hasMore: false, secret: 'do not expose'},
      {reasons: [{...first, secret: 'do not expose'}], hasMore: false},
      {reasons: [first, first], hasMore: false},
    ]) assert.throws(() => parseCareerReasonListPage(input), isStorageInvalid);
  });

  test('accepts only normalized repository queries', () => {
    assert.deepEqual(parseCareerReasonListQuery({
      scope: 'self', limit: 1, assetId: null, variantMint: null,
      cursor: {savedAt, reasonId: reasonId.toUpperCase()},
    }), {
      scope: 'self', limit: 1, assetId: null, variantMint: null,
      cursor: {savedAt, reasonId},
    });
    assert.throws(() => parseCareerReasonListQuery({
      scope: 'self', limit: 51, assetId: null, variantMint: null, cursor: null,
    }), isInvalid);
    assert.throws(() => parseCareerReasonListQuery({
      scope: 'everyone', limit: 20, assetId: null, variantMint: null, cursor: null,
    }), isInvalid);
    assert.equal(parseCareerReasonListQuery({
      scope: 'friends', limit: 20, assetId: 'apple', variantMint, cursor: null,
    }).scope, 'friends');
    assert.deepEqual(parseCareerReasonListQuery({
      scope: 'friends', limit: 20, assetId: 'apple', variantMint,
      cursor: {principalSocialId: socialId, savedAt, reasonId},
    }).cursor, {principalSocialId: socialId, savedAt, reasonId});
  });
});
