import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Pool} from 'pg';
import {PostgresLiveOrderStore} from '../../src/live-stock-orders.js';
import type {ReviewedStockOrderIntent} from '../../src/stock-order-review.js';
const host=process.env['TRIMMY_WORKDAYS_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.workdays-runtime/socket'));
test('financial dispatch is account-scoped, once-only and survives lost responses',async()=>{
 const owner=new Pool({host,port:65455,database:'postgres',user:'trimmy_daily_owner'});let runtime:Pool|undefined;
 try{
  await owner.query(`CREATE ROLE live_test_runtime LOGIN NOSUPERUSER NOBYPASSRLS;GRANT USAGE ON SCHEMA trimmy TO live_test_runtime;
   GRANT EXECUTE ON FUNCTION trimmy.live_order_read(uuid,uuid),trimmy.live_order_create(uuid,uuid,text,jsonb,bytea,timestamptz),trimmy.live_order_begin(uuid,uuid,text,text),trimmy.live_order_resolve(uuid,uuid,text) TO live_test_runtime`);
  runtime=new Pool({host,port:65455,database:'postgres',user:'live_test_runtime'});const api=new PostgresLiveOrderStore(runtime);
  const user=randomUUID(),other=randomUUID(),wallet='FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';
  await owner.query('INSERT INTO trimmy.users(id) VALUES($1),($2)',[user,other]);
  const review={userId:user,taker:wallet,reviewDigestSha256:'a'.repeat(64),expiresAt:new Date(Date.now()+40000).toISOString()} as ReviewedStockOrderIntent;
  const id=randomUUID(),sig='2'.repeat(88);await api.create(user,id,wallet,review,Buffer.alloc(100));
  assert.equal(await api.read(other,id),null);
  await assert.rejects(api.begin(other,id,review.reviewDigestSha256,sig),/INVALID_REVIEW/);
  await assert.rejects(api.begin(user,id,'b'.repeat(64),sig),/INVALID_REVIEW/);
  const results=await Promise.all([api.begin(user,id,review.reviewDigestSha256,sig),api.begin(user,id,review.reviewDigestSha256,sig),api.begin(user,id,review.reviewDigestSha256,sig)]);
  assert.equal(results.filter(x=>x.dispatch).length,1);
  assert.equal((await api.read(user))?.signature,sig);
  await assert.rejects(api.create(user,randomUUID(),wallet,review,Buffer.alloc(100)),/ORDER_PENDING/);
  await assert.rejects(api.begin(user,id,review.reviewDigestSha256,'3'.repeat(88)),/INVALID_REVIEW/);
  await api.resolve(user,id,'confirmed');await api.resolve(user,id,'failed');assert.equal((await api.read(user,id))?.status,'confirmed');
  await assert.rejects(runtime.query('UPDATE trimmy.live_stock_orders SET status=\'reviewed\''),/permission denied/);
  const expired=randomUUID();await api.create(user,expired,wallet,review,Buffer.alloc(100));
  await owner.query("UPDATE trimmy.live_stock_orders SET expires_at=clock_timestamp()-interval '1 second' WHERE id=$1",[expired]);
  await assert.rejects(api.begin(user,expired,review.reviewDigestSha256,'4'.repeat(88)),/QUOTE_EXPIRED/);
  await owner.query("UPDATE trimmy.users SET status='closed' WHERE id=$1",[user]);await assert.rejects(api.read(user),/ACCOUNT_REQUIRED/);
 }finally{await runtime?.end();await owner.end();}
});
