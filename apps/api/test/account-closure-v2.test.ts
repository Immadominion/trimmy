import assert from 'node:assert/strict';
import {test} from 'node:test';
import type {Pool, PoolClient} from 'pg';
import {PostgresAccountClosure} from '../src/account-closure.js';

const userId = '7c000000-0000-4000-8000-000000000001';

function harness(row: Record<string, unknown>) {
  const queries: Array<{sql: string; values?: readonly unknown[]}> = [];
  const client = {
    query: async (raw: string, values?: readonly unknown[]) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      queries.push(values === undefined ? {sql} : {sql, values});
      if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: false}]};
      if (sql.includes('social_close_current_account')) return {rows: [row]};
      return {rows: []};
    },
    release: () => {},
  } as unknown as PoolClient;
  const pool = {connect: async () => client} satisfies Pick<Pool, 'connect'>;
  return {repository: new PostgresAccountClosure(pool), queries};
}

test('0025 closure uses one function-only mutation and preserves canceled invitation count', async () => {
  const h = harness({
    outcome: 'saved', closed: true, canceled_invitations: 3, removed_friendships: 2,
  });

  const result = await h.repository.close(userId, '18446744073709551615');

  assert.deepEqual(result, {closed: true, canceledInvitations: 3});
  const mutations = h.queries.filter(query => query.sql.includes('social_close_current_account'));
  assert.equal(mutations.length, 1);
  assert.deepEqual(mutations[0]?.values, ['18446744073709551615']);
  assert.equal(h.queries.some(query => /^UPDATE trimmy\.invitations/iu.test(query.sql)), false);
  assert.equal(h.queries.some(query => query.sql.includes('practice_close_current_account')), false);
  assert.deepEqual(h.queries.find(query => query.sql.includes('AS unsafe_role'))?.values,
    ['trimmy_social_moderator']);
  assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
});

test('closure passes null without optional fresh X proof and exact retry remains successful', async () => {
  const h = harness({
    outcome: 'saved', closed: false, canceled_invitations: 0, removed_friendships: 0,
  });

  const result = await h.repository.close(userId);

  assert.deepEqual(result, {closed: false, canceledInvitations: 0});
  const call = h.queries.find(query => query.sql.includes('social_close_current_account'));
  assert.deepEqual(call?.values, [null]);
});
