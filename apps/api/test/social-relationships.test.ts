import assert from 'node:assert/strict';
import {test} from 'node:test';
import {
  SocialRelationshipError, parseSocialInstant, parseSocialRevision,
  parseSocialUuid, socialFields,
} from '../src/social-relationships.js';

test('social request fields reject accessors, symbols and prototype-bearing objects without executing them', () => {
  let reads = 0;
  const accessor = {} as Record<string, unknown>;
  Object.defineProperty(accessor, 'schemaVersion', {enumerable: true, get: () => {
    reads++;
    return 1;
  }});
  for (const value of [accessor, Object.assign(Object.create({inherited: true}), {schemaVersion: 1}),
    Object.assign({schemaVersion: 1}, {[Symbol('hidden')]: true})]) {
    assert.throws(() => socialFields(value, ['schemaVersion']),
      (error: unknown) => error instanceof SocialRelationshipError &&
        error.code === 'SOCIAL_INVALID_INPUT');
  }
  assert.equal(reads, 0);
  const nullPrototype = Object.create(null) as Record<string, unknown>;
  nullPrototype['schemaVersion'] = 1;
  assert.deepEqual({...socialFields(nullPrototype, ['schemaVersion'])}, {schemaVersion: 1});
});

test('social identifiers, timestamps and revisions are canonical and safe', () => {
  const id = '73abcdef-abcd-4abc-8abc-abcdefabcdef';
  const instant = '2026-09-20T12:00:00.000Z';
  assert.equal(parseSocialUuid(id), id);
  assert.equal(parseSocialInstant(instant), instant);
  assert.equal(parseSocialRevision(Number.MAX_SAFE_INTEGER), Number.MAX_SAFE_INTEGER);
  for (const operation of [
    () => parseSocialUuid(id.toUpperCase()),
    () => parseSocialInstant('2026-09-20T12:00:00Z'),
    () => parseSocialRevision(0),
    () => parseSocialRevision(Number.MAX_SAFE_INTEGER + 1),
  ]) assert.throws(operation, SocialRelationshipError);
});
