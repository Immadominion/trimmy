import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID, randomBytes} from 'node:crypto';
import {Pool} from 'pg';
import {postgresReminders} from '../../src/reminder-preferences.js';
const host = process.env['TRIMMY_WORKDAYS_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.workdays-runtime/socket'));

test('reminders follow a genuine guest claim, isolate saved accounts, and reject stale or duplicate writes', async () => {
 const owner = new Pool({host, port:65455, database:'postgres', user:'trimmy_daily_owner'});
 let runtime:Pool|undefined;
 try {
  await owner.query(`CREATE ROLE reminder_test_runtime LOGIN NOSUPERUSER NOBYPASSRLS;
   GRANT USAGE ON SCHEMA trimmy TO reminder_test_runtime;
   GRANT EXECUTE ON FUNCTION trimmy.reminder_preference_get(uuid,uuid),trimmy.reminder_preference_put(uuid,uuid,uuid,bigint,text) TO reminder_test_runtime`);
  runtime = new Pool({host,port:65455,database:'postgres',user:'reminder_test_runtime'});
  const store = postgresReminders(runtime);
  async function guest() {
   const hash=()=>randomBytes(32).toString('hex'), source=hash(), credential=hash(), id=randomUUID();
   const attempt = (await owner.query('SELECT * FROM trimmy.guest_take_creation_attempt($1)',[source])).rows[0];
   const result = (await owner.query('SELECT * FROM trimmy.guest_create_session($1,$2,$3,$4,$5,$6)',[source,attempt.attempt_id,hash(),hash(),id,credential])).rows[0];
   assert.equal(result.outcome,'created');
   const row=(await owner.query('SELECT user_id FROM trimmy.guest_sessions WHERE id=$1',[id])).rows[0];
   return {p:{userId:row.user_id as string,guestId:id},credential};
  }
  const a=await guest();
  assert.deepEqual(await store.get(a.p),{schemaVersion:1,revision:0,frequency:null,claimedGuestId:null});
  const first={mutationId:randomUUID(),baseRevision:0,frequency:'daily' as const};
  assert.equal((await store.put(a.p,first)).revision,1);
  const claimed=(await owner.query('SELECT * FROM trimmy.guest_claim_session($1,$2,$3,$4)',[a.credential,'reminder-test','did:privy:reminderone',randomUUID()])).rows[0];
  assert.equal(claimed.outcome,'claimed');
  const account={userId:a.p.userId};
  assert.deepEqual(await store.get(account),{schemaVersion:1,revision:1,frequency:'daily',claimedGuestId:a.p.guestId});
  await assert.rejects(store.get(a.p),/ACCOUNT_REQUIRED/);
  await store.put(account,{mutationId:randomUUID(),baseRevision:1,frequency:'off'});
  const stale=await store.put(account,{mutationId:randomUUID(),baseRevision:1,frequency:'daily'});
  assert.equal(stale.conflict,true);assert.equal(stale.frequency,'off');
  // A lost acknowledgement must return today's value, never restore old consent.
  const replay=await store.put(account,first);
  assert.equal(replay.conflict,false);assert.equal(replay.revision,2);assert.equal(replay.frequency,'off');
  await assert.rejects(store.put(account,{...first,frequency:'off'}),/IDEMPOTENCY_CONFLICT/);
  const b=await guest();await store.put(b.p,{mutationId:randomUUID(),baseRevision:0,frequency:'daily'});
  const conflict=(await owner.query('SELECT * FROM trimmy.guest_claim_session($1,$2,$3,$4)',[b.credential,'reminder-test','did:privy:reminderone',randomUUID()])).rows[0];
  assert.equal(conflict.outcome,'identity_bound');
  assert.equal((await store.get(account)).frequency,'off');
  await assert.rejects(store.get({userId:account.userId,guestId:b.p.guestId}),/ACCOUNT_REQUIRED/);
  await assert.rejects(store.get({userId:b.p.userId}),/ACCOUNT_REQUIRED/);
  await owner.query("UPDATE trimmy.guest_sessions SET state='revoked',revoked_at=clock_timestamp() WHERE id=$1",[b.p.guestId]);
  await assert.rejects(store.get(b.p),/ACCOUNT_REQUIRED/);
  // Construct an already-expired guest fixture without rewriting immutable history.
  const expiredUser=randomUUID(),expiredGuest=randomUUID();
  await owner.query('INSERT INTO trimmy.users(id) VALUES($1)',[expiredUser]);
  await owner.query(`INSERT INTO trimmy.guest_sessions(id,user_id,credential_hash,created_at,expires_at,hard_expires_at,last_seen_at)
   VALUES($1,$2,$3,now()-interval '91 days',now()-interval '1 day',now()-interval '1 day',now()-interval '91 days')`,[expiredGuest,expiredUser,randomBytes(32).toString('hex')]);
  await assert.rejects(store.get({userId:expiredUser,guestId:expiredGuest}),/ACCOUNT_REQUIRED/);
  // Parallel devices observing one revision cannot both overwrite it.
  const races=await Promise.all(['daily','occasional'].map(frequency=>store.put(account,{mutationId:randomUUID(),baseRevision:2,frequency:frequency as 'daily'|'occasional'})));
  assert.equal(races.filter(x=>!x.conflict).length,1);
  await assert.rejects(runtime.query('SELECT * FROM trimmy.reminder_preferences'),/permission denied/);
  await assert.rejects(runtime.query('DELETE FROM trimmy.reminder_preference_receipts'),/permission denied/);
  await assert.rejects(runtime.query('SELECT trimmy.reminder_preference_get($1,NULL)',[account.userId]),/ACCOUNT_REQUIRED/);
  await owner.query("UPDATE trimmy.users SET status='closed' WHERE id=$1",[account.userId]);
  await assert.rejects(store.get(account),/ACCOUNT_REQUIRED/);
 } finally {await runtime?.end();await owner.end();}
});
