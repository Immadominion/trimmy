import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Pool} from 'pg';
import {PostgresLiveTradeHistory} from '../../src/live-trade-history.js';
import {STOCK_TRADING_ASSETS} from '../../src/stock-trading-catalog.js';
import {JUPITER_QUOTE_ASSETS} from '../../src/jupiter-quote-reader.js';
import {buildApp} from '../../src/app.js';
const host=process.env['TRIMMY_WORKDAYS_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.workdays-runtime/socket'));

test('real history is a bounded read of only the authenticated active account, with stable microsecond pagination',async()=>{
  const owner=new Pool({host,port:65455,database:'postgres',user:'trimmy_daily_owner'});
  let runtime:Pool|undefined,unprivileged:Pool|undefined;
  try {
    await owner.query(`CREATE ROLE history_test_runtime LOGIN NOSUPERUSER NOBYPASSRLS;
      CREATE ROLE history_test_other LOGIN NOSUPERUSER NOBYPASSRLS;
      GRANT USAGE ON SCHEMA trimmy TO history_test_runtime,history_test_other;
      GRANT EXECUTE ON FUNCTION trimmy.live_order_history(uuid,integer,timestamptz,uuid) TO history_test_runtime`);
    runtime=new Pool({host,port:65455,database:'postgres',user:'history_test_runtime'});
    unprivileged=new Pool({host,port:65455,database:'postgres',user:'history_test_other'});
    const repository=new PostgresLiveTradeHistory(runtime);
    const user=randomUUID(),other=randomUUID(),wallet='FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';
    await owner.query('INSERT INTO trimmy.users(id) VALUES($1),($2)',[user,other]);
    const review={userId:user,taker:wallet,reviewDigestSha256:'a'.repeat(64),privateField:'not public',
      terms:{side:'buy',inputMint:JUPITER_QUOTE_ASSETS.USDC.mint,outputMint:STOCK_TRADING_ASSETS[0]!.mint,
        inputAmountRaw:'1000000',quotedOutputAmountRaw:'400001',minimumOutputAmountRaw:'390000',simulatedOutputReceivedRaw:'400000'}};
    const fixtures=[
      {id:'cccccccc-cccc-cccc-cccc-000000000004',status:'pending',at:'2026-09-25T12:00:00.123457Z',signature:'W'.repeat(88)},
      {id:'cccccccc-cccc-cccc-cccc-000000000003',status:'confirmed',at:'2026-09-25T12:00:00.123456Z',signature:'X'.repeat(88)},
      {id:'cccccccc-cccc-cccc-cccc-000000000002',status:'failed',at:'2026-09-25T12:00:00.123456Z',signature:'Y'.repeat(88)},
      {id:'cccccccc-cccc-cccc-cccc-000000000001',status:'expired',at:'2026-09-25T12:00:00.123455Z',signature:'Z'.repeat(88)},
      {id:randomUUID(),status:'reviewed',at:'2026-09-25T12:00:01.000000Z',signature:null},
      {id:randomUUID(),status:'expired',at:'2026-09-25T12:00:01.000000Z',signature:null},
    ];
    for(const fixture of fixtures){
      await owner.query(`INSERT INTO trimmy.live_stock_orders(id,user_id,wallet,review,unsigned_transaction,expires_at,status,signature,created_at,updated_at)
        VALUES($1,$2,$3,$4,$5,clock_timestamp(),$6,$7,$8,$8)`,
      [fixture.id,user,wallet,review,Buffer.alloc(100),fixture.status,fixture.signature,fixture.at]);
    }
    const before=await owner.query('SELECT id,status,signature,created_at::text,updated_at::text FROM trimmy.live_stock_orders WHERE user_id=$1 ORDER BY id',[user]);
    assert.deepEqual(await repository.list(other,20),[]);
    const first=await repository.list(user,2) as any[];
    assert.deepEqual(first.map(row=>row.id),fixtures.slice(0,3).map(row=>row.id));
    assert.equal(first[0].createdAt,fixtures[0]!.at);
    assert.deepEqual(Object.keys(first[0]).sort(),['createdAt','id','signature','status','terms','updatedAt','wallet']);
    assert.deepEqual(Object.keys(first[0].terms).sort(),['inputAmountRaw','inputMint','minimumOutputAmountRaw','outputMint','quotedOutputAmountRaw','side']);
    const second=await repository.list(user,2,{createdAt:first[1].createdAt,id:first[1].id}) as any[];
    assert.deepEqual(second.map(row=>row.id),fixtures.slice(2,4).map(row=>row.id));
    assert.deepEqual(await repository.list(user,50,{createdAt:second[1].createdAt,id:second[1].id}),[]);

    // End-to-end HTTP projection retains precision and the account-only cursor.
    const app=buildApp({logger:false,liveTradeHistory:{authenticate:async()=>({userId:user}),repository}});
    try {
      const page1=(await app.inject('/v1/trading/history?limit=2')).json();
      assert.equal(page1.orders.length,2);assert.equal(page1.orders[0].asset.symbol,'AAPLx');
      const page2=(await app.inject('/v1/trading/history?limit=2&cursor='+page1.nextCursor)).json();
      assert.deepEqual(page2.orders.map((row:any)=>row.id),fixtures.slice(2,4).map(row=>row.id));
      assert.equal(page2.nextCursor,null);
    }finally{await app.close();}

    const client=await runtime.connect();
    try {
      await client.query('BEGIN');await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[other]);
      await assert.rejects(client.query('SELECT trimmy.live_order_history($1)',[user]),/ACCOUNT_REQUIRED/);
      await client.query('ROLLBACK');
    }finally{client.release();}
    for(const limit of [0,51,999999])await assert.rejects(repository.list(user,limit),/INVALID_REQUEST/);
    await assert.rejects(runtime.query('SELECT * FROM trimmy.live_stock_orders'),/permission denied/);
    await assert.rejects(runtime.query("UPDATE trimmy.live_stock_orders SET status='failed'"),/permission denied/);
    await assert.rejects(unprivileged.query('SELECT trimmy.live_order_history($1)',[user]),/permission denied/);
    const after=await owner.query('SELECT id,status,signature,created_at::text,updated_at::text FROM trimmy.live_stock_orders WHERE user_id=$1 ORDER BY id',[user]);
    assert.deepEqual(after.rows,before.rows,'history must not reconcile or mutate order status');
    await owner.query("UPDATE trimmy.users SET status='closed' WHERE id=$1",[user]);
    await assert.rejects(repository.list(user,20),/ACCOUNT_REQUIRED/);
  }finally{await runtime?.end();await unprivileged?.end();await owner.end();}
});
