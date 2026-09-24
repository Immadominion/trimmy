import assert from 'node:assert/strict';
import {test} from 'node:test';
import type {Pool} from 'pg';
import {PostgresRelationshipSafetyReadiness} from
  '../src/postgres-relationship-safety-readiness.js';

const blockGet = 'trimmy.social_block_get(uuid,uuid)';

function poolWithFunctions(available: ReadonlySet<string>) {
  const calls: Array<{sql: string; values: readonly unknown[]}> = [];
  const pool = {
    query: async (raw: string, values: readonly unknown[]) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      calls.push({sql, values});
      const required = values[0] as readonly string[];
      return {rows: [{ready: required.every(signature => available.has(signature))}]};
    },
  } as unknown as Pick<Pool, 'query'>;
  return {pool, calls};
}

test('relationship readiness requires the complete outer function surface including target block reads', async () => {
  const initial = poolWithFunctions(new Set<string>());
  const probe = new PostgresRelationshipSafetyReadiness(initial.pool);
  assert.equal(await probe.ready(), false);
  const required = initial.calls[0]?.values[0] as readonly string[];
  assert.equal(required.includes(blockGet), true);

  const missingGet = poolWithFunctions(new Set(required.filter(signature => signature !== blockGet)));
  assert.equal(await new PostgresRelationshipSafetyReadiness(missingGet.pool).ready(), false);

  const complete = poolWithFunctions(new Set(required));
  assert.equal(await new PostgresRelationshipSafetyReadiness(complete.pool).ready(), true);
  assert.equal(complete.calls[0]?.values[3], 'trimmy_social_moderator');
  assert.match(complete.calls[0]?.sql ?? '', /has_any_column_privilege/u);
  assert.match(complete.calls[0]?.sql ?? '', /social_reason_moderation_put/u);
});
