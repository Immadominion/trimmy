import assert from 'node:assert/strict';
import test from 'node:test';
import {buildApp} from '../src/app.js';
import {STOCK_TRADING_ASSETS} from '../src/stock-trading-catalog.js';
import {JUPITER_QUOTE_ASSETS} from '../src/jupiter-quote-reader.js';
import type {LiveTradeHistoryAdapters, LiveHistoryPosition} from '../src/live-trade-history.js';

const user='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',other='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const wallet='FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';
function row(id=3,overrides:Record<string,unknown>={}) {
  return {id:`00000000-0000-0000-0000-${String(id).padStart(12,'0')}`,wallet,status:'confirmed',
    signature:'2'.repeat(88),createdAt:'2026-09-25T12:00:00.123456Z',updatedAt:'2026-09-25T12:00:01.654321Z',
    terms:{side:'buy',inputMint:JUPITER_QUOTE_ASSETS.USDC.mint,outputMint:STOCK_TRADING_ASSETS[0]!.mint,
      inputAmountRaw:'1000000',quotedOutputAmountRaw:'512345',minimumOutputAmountRaw:'510000'},...overrides};
}
function setup(rows:unknown[]=[]) {
  const calls:{userId:string;limit:number;before?:LiveHistoryPosition}[]=[];
  const adapters:LiveTradeHistoryAdapters={authenticate:async request=>request.headers.authorization==='Bearer signed-in'?{userId:user}:null,
    repository:{list:async(userId,limit,before)=>{calls.push({userId,limit,...(before?{before}:{})});return rows;}}};
  return {calls,adapters,app:buildApp({logger:false,liveTradeHistory:adapters})};
}
const auth={authorization:'Bearer signed-in'};

test('history requires an account, and remains available without a live execution adapter',async()=>{
  const {app,calls}=setup([row()]);
  try {
    assert.equal((await app.inject('/v1/trading/capabilities')).json().enabled,false);
    const anonymous=await app.inject('/v1/trading/history');
    assert.equal(anonymous.statusCode,401);assert.deepEqual(anonymous.json(),{code:'ACCOUNT_REQUIRED'});assert.equal(calls.length,0);
    const response=await app.inject({url:'/v1/trading/history',headers:auth});
    assert.equal(response.statusCode,200);assert.equal(response.headers['cache-control'],'no-store');
    assert.equal(response.json().orders[0].id,row().id);assert.deepEqual(calls,[{userId:user,limit:20}]);
  }finally{await app.close();}
});

test('history projects trusted asset identity and reviewed raw quantities, never wires or execution claims',async()=>{
  const data=row(3,{review:{unsignedTransaction:'private wire'},unsignedTransaction:'private wire',reviewDigest:'private digest'});
  const {app}=setup([data]);
  try {
    const result=(await app.inject({url:'/v1/trading/history',headers:auth})).json();
    assert.deepEqual(result,{schemaVersion:1,network:'solana:mainnet-beta',orders:[{
      id:data.id,wallet:data.wallet,status:'confirmed',signature:data.signature,createdAt:data.createdAt,updatedAt:data.updatedAt,
      asset:{assetId:'apple',mint:STOCK_TRADING_ASSETS[0]!.mint,symbol:'AAPLx',name:'Apple xStock',decimals:8},
      terms:data.terms,amountUnits:'raw_token_units',amountsStatus:'reviewed_quote',
    }],nextCursor:null});
  }finally{await app.close();}
});

test('history supports every submitted status and sell-side asset identity',async()=>{
  const rows=['pending','confirmed','failed','expired'].map((status,index)=>row(4-index,{status,
    terms:{...row().terms,side:'sell',inputMint:STOCK_TRADING_ASSETS[9]!.mint,outputMint:JUPITER_QUOTE_ASSETS.USDC.mint}}));
  const {app}=setup(rows);
  try {
    const response=await app.inject({url:'/v1/trading/history',headers:auth});
    assert.equal(response.statusCode,200);
    assert.deepEqual(response.json().orders.map((order:any)=>[order.status,order.asset.symbol,order.terms.side]),
      rows.map(order=>[order.status,'NFLXx','sell']));
  }finally{await app.close();}
});

test('keyset cursor preserves tied timestamps to microseconds, binds the account, and changes page size safely',async()=>{
  const rows=[row(3),row(2),row(1)];const {app,calls}=setup(rows);
  try {
    const first=await app.inject({url:'/v1/trading/history?limit=2',headers:auth});
    assert.equal(first.statusCode,200);const page=first.json();
    assert.deepEqual(page.orders.map((order:any)=>order.id),[row(3).id,row(2).id]);
    const cursor=page.nextCursor;assert.ok(typeof cursor==='string');
    rows.splice(0,2);
    const second=await app.inject({url:`/v1/trading/history?limit=1&cursor=${cursor}`,headers:auth});
    assert.equal(second.statusCode,200);assert.equal(second.json().orders[0].id,row(1).id);assert.equal(second.json().nextCursor,null);
    assert.deepEqual(calls[1],{userId:user,limit:1,before:{id:row(2).id,createdAt:row(2).createdAt}});
    const foreign=Buffer.from(JSON.stringify([1,other,row(2).createdAt,row(2).id])).toString('base64url');
    assert.equal((await app.inject({url:`/v1/trading/history?cursor=${foreign}`,headers:auth})).statusCode,400);
    assert.equal(calls.length,2);
  }finally{await app.close();}
});

test('invalid pagination is bounded before storage and cannot select another wallet/account',async()=>{
  const {app,calls}=setup();
  try {
    for(const query of ['limit=0','limit=51','limit=100000000000','limit=-1','limit=1.5','limit=01','limit=','limit=1&limit=2',
      'userId='+other,'wallet='+wallet,'cursor=','cursor=!!!','cursor='+('a'.repeat(513)),
      'cursor='+Buffer.from(JSON.stringify([1,user,'2026-02-30T12:00:00.000001Z',row().id])).toString('base64url')]){
      const response=await app.inject({url:'/v1/trading/history?'+query,headers:auth});
      assert.equal(response.statusCode,400,query);assert.deepEqual(response.json(),{code:'INVALID_REQUEST'});
    }
    assert.equal(calls.length,0);
  }finally{await app.close();}
});

test('empty history is valid; unknown adapter and storage failures are explicit and sanitized',async()=>{
  const {app,adapters}=setup();const disabled=buildApp({logger:false});
  try {
    assert.deepEqual((await app.inject({url:'/v1/trading/history',headers:auth})).json(),
      {schemaVersion:1,network:'solana:mainnet-beta',orders:[],nextCursor:null});
    assert.equal((await disabled.inject({url:'/v1/trading/history',headers:auth})).statusCode,503);
    adapters.repository.list=async()=>{throw new Error('private database credentials');};
    const response=await app.inject({url:'/v1/trading/history',headers:auth});
    assert.equal(response.statusCode,503);assert.deepEqual(response.json(),{code:'HISTORY_UNAVAILABLE'});
    adapters.repository.list=async()=>{throw new Error('ACCOUNT_REQUIRED');};
    assert.equal((await app.inject({url:'/v1/trading/history',headers:auth})).statusCode,401);
  }finally{await app.close();await disabled.close();}
});

test('malformed, unsubmitted, out-of-order or unsupported stored data never becomes financial history',async()=>{
  const rows:unknown[]=[];const {app}=setup(rows);
  try {
    for(const invalidRows of [[row(1),row(2)],[row(1),row(1)],[row(1,{status:'reviewed'})],[row(1,{signature:null})],
      [row(1,{createdAt:'2026-09-25T12:00:00.123Z'})],[row(1,{status:['pending']})],
      [row(1,{terms:{...row().terms,outputMint:wallet}})],
      [row(1,{terms:{...row().terms,inputAmountRaw:'1.5'}})],
      [row(1,{terms:{...row().terms,inputAmountRaw:'18446744073709551616'}})],
      [row(1,{terms:{...row().terms,minimumOutputAmountRaw:'999999999'}})]]){
      rows.splice(0,rows.length,...invalidRows);
      const response=await app.inject({url:'/v1/trading/history',headers:auth});
      assert.equal(response.statusCode,503);assert.deepEqual(response.json(),{code:'HISTORY_UNAVAILABLE'});
    }
  }finally{await app.close();}
});

test('configured web clients can read history through a bounded GET preflight',async()=>{
  const origin='https://trimmy.example';const {adapters,app:unused}=setup();await unused.close();
  const app=buildApp({logger:false,browserOrigins:[origin],liveTradeHistory:adapters});
  try {
    const headers={origin,'access-control-request-method':'GET','access-control-request-headers':'authorization'};
    const response=await app.inject({method:'OPTIONS',url:'/v1/trading/history?limit=20',headers});
    assert.equal(response.statusCode,204);assert.equal(response.headers['access-control-allow-methods'],'GET');
    assert.equal((await app.inject({method:'OPTIONS',url:'/v1/trading/history',headers:{...headers,'access-control-request-method':'POST'}})).statusCode,403);
    assert.equal((await app.inject({method:'OPTIONS',url:'/v1/trading/history',headers:{...headers,'access-control-request-headers':'x-trimmy-guest'}})).statusCode,403);
    assert.equal((await app.inject({method:'OPTIONS',url:'/v1/trading/order/'+row().id,headers})).statusCode,204);
    for(const url of ['/v1/trading/order/not-a-uuid','/v1/trading/order/:id','/v1/trading/order/'+row().id+'?extra=1','/v1/trading/execute']){
      assert.equal((await app.inject({method:'OPTIONS',url,headers})).statusCode,403);
    }
  }finally{await app.close();}
});
