import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Pool} from 'pg';
import {PostgresWalletTransferStore,type StoredTransfer} from '../../src/wallet-transfer-store.js';
const host=process.env['TRIMMY_WORKDAYS_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.workdays-runtime/socket'));
test('durable sends are scoped, dispatch once across connections, and keep terminal outcomes',async()=>{
 const owner=new Pool({host,port:65455,database:'postgres',user:'trimmy_daily_owner'});let runtime:Pool|undefined;
 try {
  await owner.query(`CREATE ROLE transfer_test_runtime LOGIN NOSUPERUSER NOBYPASSRLS;GRANT USAGE ON SCHEMA trimmy TO transfer_test_runtime;
   GRANT EXECUTE ON FUNCTION trimmy.wallet_transfer_read(uuid,uuid),trimmy.wallet_transfer_create(uuid,uuid,jsonb),trimmy.wallet_transfer_begin(uuid,uuid,text),trimmy.wallet_transfer_resolve(uuid,uuid,text) TO transfer_test_runtime`);
  runtime=new Pool({host,port:65455,database:'postgres',user:'transfer_test_runtime'});
  const store=new PostgresWalletTransferStore(runtime),user=randomUUID(),other=randomUUID();
  await owner.query('INSERT INTO trimmy.users(id) VALUES($1),($2)',[user,other]);
  const wallet='FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';
  const make=()=>({id:randomUUID(),user_id:user,wallet,review:{from:wallet,expiresAt:new Date(Date.now()+90_000).toISOString()},unsignedTransaction:'A'.repeat(100),reviewToken:'test.token',status:'reviewed',signature:null} as StoredTransfer);
  const first=make();await store.create(user,first);
  const next=make();await store.create(user,next);
  await assert.rejects(store.begin(user,first.id,'3'.repeat(88)),/REVIEW_EXPIRED/);
  assert.equal(await store.read(other,next.id),null);
  await assert.rejects(store.begin(other,next.id,'3'.repeat(88)),/INVALID_REVIEW/);
  const results=await Promise.all([1,2,3].map(()=>store.begin(user,next.id,'3'.repeat(88))));
  assert.equal(results.filter(x=>x.dispatch).length,1);
  await assert.rejects(store.create(user,make()),/TRANSFER_PENDING/);
  assert.equal((await new PostgresWalletTransferStore(runtime).read(user))?.signature,'3'.repeat(88));
  await store.resolve(user,next.id,'confirmed');await store.resolve(user,next.id,'failed');
  assert.equal((await store.read(user,next.id))?.status,'confirmed');
  await assert.rejects(runtime.query('UPDATE trimmy.wallet_transfers SET status=\'reviewed\''),/permission denied/);
  await owner.query("UPDATE trimmy.users SET status='closed' WHERE id=$1",[user]);
  await assert.rejects(store.read(user),/ACCOUNT_REQUIRED/);
 }finally {await runtime?.end();await owner.end();}
});
