import Fastify from 'fastify';
import test from 'node:test';import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {getAddressDecoder,getCompiledTransactionMessageEncoder,getTransactionEncoder} from '@solana/kit';
import type {CompiledTransactionMessage,TransactionMessageBytes} from '@solana/kit';
import {STOCK_TRADING_ASSETS} from '../src/stock-trading-catalog.js';
import {LiveStockOrders,verifyReviewedSignature,registerLiveStockRoutes} from '../src/live-stock-orders.js';
import type {LiveOrder,LiveOrderStore,LiveStockAdapters} from '../src/live-stock-orders.js';
import type {ReviewedStockOrderIntent} from '../src/stock-order-review.js';
function fixture(){
 const keys=generateKeyPairSync('ed25519');const publicBytes=keys.publicKey.export({type:'spki',format:'der'}).subarray(-32);const wallet=getAddressDecoder().decode(publicBytes);
 const message=getCompiledTransactionMessageEncoder().encode({version:0,header:{numSignerAccounts:1,numReadonlySignerAccounts:0,numReadonlyNonSignerAccounts:0},staticAccounts:[wallet],lifetimeToken:'11111111111111111111111111111111',instructions:[],addressTableLookups:[]} as CompiledTransactionMessage) as TransactionMessageBytes;
 const wire=(signature:Uint8Array|null)=>Buffer.from(getTransactionEncoder().encode({messageBytes:message,signatures:{[wallet]:signature}} as never)).toString('base64');
 const review={reviewDigestSha256:'a'.repeat(64),expiresAt:new Date(Date.now()+30000).toISOString(),evidence:{lastValidBlockHeight:'500'},requestId:'test-request'} as unknown as ReviewedStockOrderIntent;
 const order:LiveOrder={id:'test',user_id:'user',wallet,review,unsignedTransaction:wire(null),expires_at:review.expiresAt,status:'reviewed',signature:null};
 return {order,signed:wire(sign(null,Buffer.from(message),keys.privateKey)),wire};
}
test('only the verified wallet can sign the exact reviewed message',()=>{
 const f=fixture();assert.match(verifyReviewedSignature(f.order,f.signed),/^[1-9A-HJ-NP-Za-km-z]+$/);
 assert.throws(()=>verifyReviewedSignature(f.order,f.order.unsignedTransaction),/INVALID_SIGNATURE/);
 const modified=Buffer.from(f.signed,'base64');modified[modified.length-2]=modified[modified.length-2]!^1;
 assert.throws(()=>verifyReviewedSignature(f.order,modified.toString('base64')),/INVALID_SIGNATURE/);
 const other=fixture();assert.throws(()=>verifyReviewedSignature(f.order,other.signed),/INVALID_SIGNATURE/);
 assert.throws(()=>verifyReviewedSignature(f.order,f.signed+'\n'),/INVALID_SIGNATURE/);
});

test('a malformed confirmation slot cannot settle an order or authorize a stale holdings refresh',async()=>{
 for(const slot of [undefined,0,-1,1.5,Number.MAX_SAFE_INTEGER+1]) {
  const f=fixture();let settlements=0;
  const pending={...f.order,status:'pending' as const,signature:'2'.repeat(88)};
  const store={read:async()=>pending,resolve:async()=>{settlements++;return {...pending,status:'confirmed' as const};}} as unknown as LiveOrderStore;
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:async()=>Response.json({jsonrpc:'2.0',id:1,
   result:{value:[{confirmationStatus:'confirmed',err:null,slot}]}})});
  await assert.rejects(service.status('user','test'),{code:'LIVE_UNAVAILABLE'});
  assert.equal(settlements,0);
 }
});

test('confirmed status exposes its slot while retaining backward compatibility for persisted orders',async()=>{
 const f=fixture();let includeSlot=true;
 const adapters={authenticate:async()=>({userId:'user',identity:{subject:'did:privy:test'}}),
  identities:{resolveFresh:async()=>({subject:'did:privy:test',embeddedSolanaWallet:{status:'candidate',address:f.order.wallet}})},
  service:{status:async()=>({...f.order,status:'confirmed',signature:'2'.repeat(88),...(includeSlot?{confirmedSlot:501}:{})})},
 } as unknown as LiveStockAdapters;
 const app=Fastify();registerLiveStockRoutes(app,adapters);
 try {
  const fresh=await app.inject('/v1/trading/order');
  assert.equal(fresh.json().order.confirmedSlot,501);assert.equal(fresh.json().order.transaction,undefined);
  includeSlot=false;
  const legacy=await app.inject('/v1/trading/order');
  assert.equal(legacy.json().order.confirmedSlot,undefined);assert.equal(legacy.json().order.status,'confirmed');
 }finally{await app.close();}
});
test('a lost dispatch response stays pending; retry never sends a second trade',async()=>{
 const f=fixture();let current=f.order,dispatches=0;
 const store:LiveOrderStore={read:async()=>current,create:async()=>{throw Error('unexpected')},begin:async(_u,_id,_d,signature)=>{if(current.status==='reviewed'){current={...current,status:'pending',signature};return {...current,dispatch:true};}return {...current,dispatch:false};},resolve:async(_u,_id,status)=>current={...current,status}};
 let confirmed=false;
 const fake=async(url:URL|RequestInfo,options?:RequestInit)=>{
  if(String(url).includes('/execute')){dispatches++;throw Error('response lost');}
  const method=JSON.parse(String(options?.body)).method;
  const result=method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':method==='getBlockHeight'?100:{value:[confirmed?{confirmationStatus:'confirmed',err:null,slot:501}:null]};
  return Response.json({jsonrpc:'2.0',id:1,result});
 };
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:fake as typeof fetch});
 const first=await service.execute('user',f.order.wallet,'test','a'.repeat(64),f.signed);assert.equal(first.status,'pending');
 await service.execute('user',f.order.wallet,'test','a'.repeat(64),f.signed);assert.equal(dispatches,1);
 confirmed=true;const settled=await service.status('user','test');assert.equal(settled?.status,'confirmed');
 assert.equal(settled?.confirmedSlot,501);assert.equal(dispatches,1);
});

test('less than one signature fee reports funding before requesting an order', async () => {
 const wallet=fixture().order.wallet;
 const store:LiveOrderStore={read:async()=>null,create:async()=>{throw Error('unexpected write');},begin:async()=>{throw Error('unexpected dispatch');},resolve:async()=>{throw Error('unexpected write');}};
 for(const [balance,expected] of [[0,'ADD_SOL'],[4_999,'ADD_SOL'],[-1,'LIVE_UNAVAILABLE'],[null,'LIVE_UNAVAILABLE']] as const) {
  let orderRequests=0;
  const fake=async(url:URL|RequestInfo,options?:RequestInit)=>{
   if(String(url).includes('/order')){orderRequests++;throw Error('unexpected order');}
   const request=JSON.parse(String(options?.body));
   const result=request.method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':request.method==='getBlockHeight'?100:{value:balance};
   if(request.method==='getBalance')assert.deepEqual(request.params,[wallet,{commitment:'confirmed'}]);
   return Response.json({jsonrpc:'2.0',id:1,result});
  };
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:fake as typeof fetch});
  await assert.rejects(service.preview('user',wallet,{assetId:'apple',variantMint:'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',side:'buy',amountRaw:'5000000'}),new RegExp(expected));
  assert.equal(orderRequests,0);
 }
});

test('a wallet below the sponsorship heuristic can request an order without spending or reserving SOL',async()=>{
 const wallet=fixture().order.wallet;let orderRequests=0;
 const store:LiveOrderStore={read:async()=>null,create:async()=>{throw Error('unexpected write');},begin:async()=>{throw Error('unexpected dispatch');},resolve:async()=>{throw Error('unexpected write');}};
 const fake=async(url:URL|RequestInfo,options?:RequestInit)=>{
  if(String(url).includes('/order')){orderRequests++;return Response.json({transaction:'',router:'metis',errorCode:1});}
  const request=JSON.parse(String(options?.body));
  assert.ok(['getGenesisHash','getBlockHeight','getBalance'].includes(request.method));
  const result=request.method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':request.method==='getBlockHeight'?100:{value:9_435_303};
  return Response.json({jsonrpc:'2.0',id:1,result});
 };
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:fake as typeof fetch});
 await assert.rejects(service.preview('user',wallet,{assetId:'apple',variantMint:'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',side:'buy',amountRaw:'5000000'}),/ADD_USDC/);
 assert.equal(orderRequests,1);
});


test('live preview requests each selected stock in both directions and reports no-route without generic server errors',async()=>{
 const wallet=fixture().order.wallet;
 const store:LiveOrderStore={read:async()=>null,create:async()=>{throw Error('unexpected write');},begin:async()=>{throw Error('unexpected dispatch');},resolve:async()=>{throw Error('unexpected write');}};
 for(const asset of STOCK_TRADING_ASSETS) for(const side of ['buy','sell'] as const) {
  let orderRequests=0;
  const fake=async(rawUrl:URL|RequestInfo,options?:RequestInit)=>{
   const url=new URL(String(rawUrl));
   if(url.pathname.endsWith('/order')) {
    orderRequests++;
    assert.equal(url.searchParams.get(side==='buy'?'outputMint':'inputMint'),asset.mint);
    assert.equal(url.searchParams.get('taker'),wallet);
    assert.equal(url.searchParams.get('slippageBps'),'50');
    assert.equal(url.searchParams.get('excludeRouters'),'jupiterz,dflow,okx');
    return Response.json({error:'Failed to get quotes'},{status:400});
   }
   const request=JSON.parse(String(options?.body));
   assert.ok(['getGenesisHash','getBlockHeight','getBalance'].includes(request.method));
   const result=request.method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':request.method==='getBlockHeight'?100:{value:9_435_303};
   return Response.json({jsonrpc:'2.0',id:1,result});
  };
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:fake as typeof fetch});
  await assert.rejects(service.preview('user',wallet,{assetId:asset.assetId,variantMint:asset.mint,side,amountRaw:'1000000'}),/NO_ROUTE/);
  assert.equal(orderRequests,1);
 }
});

test('live preview refuses a swapped issuer/company identity before touching a wallet or provider',async()=>{
 let reads=0;
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store:{} as LiveOrderStore,fetch:async()=>{reads++;throw Error('unexpected');}});
 await assert.rejects(service.preview('user',fixture().order.wallet,{assetId:'apple',variantMint:STOCK_TRADING_ASSETS[1]!.mint,side:'buy',amountRaw:'1000000'}),{code:'MARKET_INPUT_INVALID'});
 assert.equal(reads,0);
});

test('buy and sell caps return an explicit limit error before reading providers or spending funds',async()=>{
 let reads=0;
 const wallet=fixture().order.wallet;
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store:{} as LiveOrderStore,fetch:async()=>{reads++;throw Error('unexpected');}});
 const adapters={authenticate:async()=>({userId:'user',identity:{subject:'did:privy:test'}}),
  identities:{resolveFresh:async()=>({subject:'did:privy:test',embeddedSolanaWallet:{status:'candidate',address:wallet}})},service,
 } as unknown as LiveStockAdapters;
 const app=Fastify();registerLiveStockRoutes(app,adapters);
 try {
  for(const asset of STOCK_TRADING_ASSETS)for(const side of ['buy','sell'] as const)for(const amountRaw of ['100000001','1000000000']) {
   const input={assetId:asset.assetId,variantMint:asset.mint,side,amountRaw};
   await assert.rejects(service.preview('user',wallet,input),{code:'TRADE_LIMIT'});
   const response=await app.inject({method:'POST',url:'/v1/trading/preview',payload:input});
   assert.equal(response.statusCode,409);assert.deepEqual(response.json(),{code:'TRADE_LIMIT'});
  }
  assert.equal(reads,0);
 }finally{await app.close();}
});


test('disabling new trades preserves authenticated pending-order reconciliation',async()=>{
 const f=fixture();let statusReads=0,financialCalls=0;
 const adapters={executionEnabled:false,
  authenticate:async()=>({userId:'user',identity:{subject:'did:privy:test'}}),
  identities:{resolveFresh:async()=>({subject:'did:privy:test',embeddedSolanaWallet:{status:'candidate',address:f.order.wallet}})},
  service:{status:async()=>{statusReads++;return {...f.order,status:'pending'};},preview:async()=>{financialCalls++;},execute:async()=>{financialCalls++;}},
 } as unknown as LiveStockAdapters;
 const app=Fastify();registerLiveStockRoutes(app,adapters);
 try {
  const caps=await app.inject('/v1/trading/capabilities');assert.equal(caps.json().enabled,false);
  const status=await app.inject('/v1/trading/order');assert.equal(status.statusCode,200);assert.equal(status.json().order.status,'pending');assert.equal(statusReads,1);
  const stock=STOCK_TRADING_ASSETS[0]!;
  const preview=await app.inject({method:'POST',url:'/v1/trading/preview',payload:{assetId:stock.assetId,variantMint:stock.mint,side:'buy',amountRaw:'1000000'}});
  assert.equal(preview.statusCode,503);assert.equal(preview.json().code,'LIVE_UNAVAILABLE');
  const execute=await app.inject({method:'POST',url:'/v1/trading/execute',payload:{id:'12345678-1234-4567-8123-123456789abc',reviewDigest:'a'.repeat(64),signedTransaction:f.signed}});
  assert.equal(execute.statusCode,503);assert.equal(financialCalls,0);
 }finally{await app.close();}
});


test('live previews refuse sponsorship and map genuine provider funding failures by side',async()=>{
 const wallet=fixture().order.wallet;
 const cases=[
  {payload:{router:'metis',transaction:'candidate',gasless:true,signatureFeePayer:wallet},side:'buy',code:'ADD_SOL'},
  {payload:{router:'metis',transaction:'candidate',gasless:false,signatureFeePayer:fixture().order.wallet},side:'buy',code:'ADD_SOL'},
  {payload:{router:'metis',transaction:'',errorCode:3},side:'buy',code:'ADD_SOL'},
  {payload:{router:'metis',transaction:'',errorCode:1},side:'sell',code:'INSUFFICIENT_HOLDINGS'},
  {payload:{router:'jupiterz',transaction:'',errorCode:2},side:'buy',code:'NO_ROUTE'},
 ] as const;
 for(const item of cases){
  const store={read:async()=>null,create:async()=>{throw Error('unexpected');}} as unknown as LiveOrderStore;
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:async(rawUrl,options)=>{
   if(String(rawUrl).includes('/order'))return Response.json(item.payload);
   const {method}=JSON.parse(String(options?.body));
   return Response.json({jsonrpc:'2.0',id:1,result:method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':method==='getBlockHeight'?100:{value:9_435_303}});
  }});
  const asset=STOCK_TRADING_ASSETS[0]!;
  await assert.rejects(service.preview('user',wallet,{assetId:asset.assetId,variantMint:asset.mint,side:item.side,amountRaw:'1000000'}),new RegExp(item.code));
 }
});

test('unsupported or moved routes decline the candidate with actionable public errors',async()=>{
 const wallet=fixture().order.wallet;
 for(const [internal,expected,status] of [
  ['SEMANTICS_PROGRAM_UNSUPPORTED','NO_ROUTE',409],
  ['SEMANTICS_INSTRUCTION_UNSUPPORTED','NO_ROUTE',409],
  ['RECONCILIATION_UNEXPECTED_MOVEMENT','NO_ROUTE',409],
  ['SIMULATION_EFFECTS_MISMATCH','NO_ROUTE',409],
  ['SIMULATION_BLOCKHASH_EXPIRED','QUOTE_EXPIRED',409],
  ['REVIEW_EXPIRED','QUOTE_EXPIRED',409],
  ['SEMANTICS_RPC_RESPONSE_INVALID','LIVE_UNAVAILABLE',503],
  ['RECONCILIATION_AUTHORITY_MISMATCH','LIVE_UNAVAILABLE',503],
 ] as const) {
  let attempts=0;
  const adapters={authenticate:async()=>({userId:'user',identity:{subject:'did:privy:test'}}),
   identities:{resolveFresh:async()=>({subject:'did:privy:test',embeddedSolanaWallet:{status:'candidate',address:wallet}})},
   service:{preview:async()=>{attempts++;throw Object.assign(new Error('private provider information'),{code:internal});}},
  } as unknown as LiveStockAdapters;
  const app=Fastify();registerLiveStockRoutes(app,adapters);
  try{
   const asset=STOCK_TRADING_ASSETS[0]!;
   const response=await app.inject({method:'POST',url:'/v1/trading/preview',payload:{assetId:asset.assetId,variantMint:asset.mint,side:'buy',amountRaw:'1000000'}});
   assert.equal(response.statusCode,status);assert.deepEqual(response.json(),{code:expected});assert.equal(attempts,1);
  }finally{await app.close();}
 }
});
