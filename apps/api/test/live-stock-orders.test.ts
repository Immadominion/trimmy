import Fastify from 'fastify';
import test from 'node:test';
import assert from 'node:assert/strict';
import type {OpsAlerts} from '../src/ops-alerts.js';
import {generateKeyPairSync,sign} from 'node:crypto';
import {getAddressDecoder,getCompiledTransactionMessageEncoder,getTransactionEncoder} from '@solana/kit';
import type {CompiledTransactionMessage,TransactionMessageBytes} from '@solana/kit';
import {STOCK_TRADING_ASSETS} from '../src/stock-trading-catalog.js';
import type {StockTradingAsset} from '../src/stock-trading-catalog.js';
import {STOCK_ISSUERS} from '../src/stock-issuers.js';
/** The current attestation for the asset's issuer, as a new client sends it. */
const terms=(asset:StockTradingAsset)=>({issuerId:asset.issuerId,version:STOCK_ISSUERS[asset.issuerId].disclosure.attestation.version});
import {LiveStockOrders,verifyReviewedSignature,registerLiveStockRoutes,orderFill} from '../src/live-stock-orders.js';
import type {LiveOrder,LiveOrderStore,LiveStockAdapters} from '../src/live-stock-orders.js';
import type {ReviewedStockOrderIntent} from '../src/stock-order-review.js';
import {StockMarketStates} from '../src/stock-market-state.js';
import type {OndoMarketStatusReader} from '../src/ondo-market-status.js';
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

test('missing or malformed RPC outcomes keep confirmed signatures pending instead of declaring failure',async()=>{
 const invalid=[undefined,false,true,0,1,'',[],{},
  {InstructionError:[-1,'InvalidAccountData']},{InstructionError:[1,{Custom:-1}]},
  {InstructionError:[1,{Custom:0x100000000}]},{InstructionError:[1,{}]},
  {DuplicateInstruction:256},{InsufficientFundsForRent:{account_index:-1}},
  {InstructionError:[1,'InvalidAccountData'],extra:true}];
 for(const err of invalid)for(const confirmationStatus of ['confirmed','finalized']) {
  const f=fixture();let settlements=0;
  const pending={...f.order,status:'pending' as const,signature:'2'.repeat(88)};
  const store={read:async()=>pending,resolve:async()=>{settlements++;return {...pending,status:'failed' as const};}} as unknown as LiveOrderStore;
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:async()=>Response.json({jsonrpc:'2.0',id:1,
   result:{value:[{confirmationStatus,slot:501,...(err===undefined?{}:{err})}]}})});
  await assert.rejects(service.status('user','test'),{code:'LIVE_UNAVAILABLE'});
  assert.equal(settlements,0);
 }
});

test('explicit valid RPC success and transaction errors settle once with the observed slot',async()=>{
 for(const err of [null,'InsufficientFundsForFee',{InstructionError:[1,'InvalidAccountData']},
  {InstructionError:[1,{Custom:0}]},{DuplicateInstruction:2},
  {InsufficientFundsForRent:{account_index:4}},{ProgramExecutionTemporarilyRestricted:{account_index:0}}]) {
  const f=fixture();let settlements=0;
  let current:LiveOrder={...f.order,status:'pending',signature:'2'.repeat(88)};
  const store={read:async()=>current,resolve:async(_user:string,_id:string,status:LiveOrder['status'],confirmedSlot?:number)=>{settlements++;return current={...current,status,...(confirmedSlot===undefined?{}:{confirmedSlot})};}} as unknown as LiveOrderStore;
  const alerts:string[]=[];
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,alerts:{notify:(kind:string)=>alerts.push(kind)} as unknown as OpsAlerts,
   fetch:async()=>Response.json({jsonrpc:'2.0',id:1,result:{value:[{confirmationStatus:'confirmed',slot:501,err}]}})});
  const settled=await service.status('user','test');
  assert.equal(settled?.status,err===null?'confirmed':'failed');
  assert.equal(settled?.confirmedSlot,501);
  const restored=await service.status('user','test');assert.equal(settlements,1);
  assert.equal(restored?.confirmedSlot,501,'a later read retains the confirmed balance floor');
  // The operator hears about each failed order once, and never about a confirmed one.
  assert.deepEqual(alerts,err===null?[]:['order_failed']);
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
   const result=request.method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':request.method==='getBlockHeight'?100:{context:{slot:501},value:balance};
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
  const result=request.method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':request.method==='getBlockHeight'?100:{context:{slot:501},value:9_435_303};
  return Response.json({jsonrpc:'2.0',id:1,result});
 };
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:fake as typeof fetch});
 await assert.rejects(service.preview('user',wallet,{assetId:'apple',variantMint:'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',side:'buy',amountRaw:'5000000'}),/ADD_USDC/);
 assert.equal(orderRequests,1);
});

test('a fresh preview refuses malformed or regressing confirmed balance context before asking for a route',async()=>{
 for(const slot of [undefined,0,1.5,500,501]) {
  const f=fixture();let orderRequests=0;
  const store={read:async()=>({...f.order,status:'confirmed',confirmedSlot:501})} as unknown as LiveOrderStore;
  const fake:typeof fetch=async(url,options)=>{
   if(String(url).includes('/order')){orderRequests++;return Response.json({error:'no route'},{status:400});}
   const request=JSON.parse(String(options?.body));
   if(request.method==='getBalance')assert.deepEqual(request.params,[f.order.wallet,{commitment:'confirmed',minContextSlot:501}]);
   const result=request.method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':
    request.method==='getBlockHeight'?100:{context:{slot},value:9_435_303};
   return Response.json({jsonrpc:'2.0',id:1,result});
  };
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:fake});
  await assert.rejects(service.preview('user',f.order.wallet,{assetId:'apple',variantMint:STOCK_TRADING_ASSETS[0]!.mint,
   side:'sell',amountRaw:'1000000'}),{code:slot===501?'NO_ROUTE':'LIVE_UNAVAILABLE'});
  assert.equal(orderRequests,slot===501?1:0);
 }
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
    // Transfer-fee tokens widen the tolerance by their own fee; RFQ tokens use market makers only.
    assert.equal(url.searchParams.get('slippageBps'),String(50+asset.transferFeeBps));
    const route=orderRequests===1?asset.route:asset.route==='rfq'?'aggregator':'rfq';
    assert.equal(url.searchParams.get('excludeRouters'),route==='rfq'?'metis,dflow,okx':'jupiterz,dflow,okx');
    return Response.json({error:'Failed to get quotes'},{status:400});
   }
   const request=JSON.parse(String(options?.body));
   assert.ok(['getGenesisHash','getBlockHeight','getBalance'].includes(request.method));
   const result=request.method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':request.method==='getBlockHeight'?100:{context:{slot:501},value:9_435_303};
   return Response.json({jsonrpc:'2.0',id:1,result});
  };
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:fake as typeof fetch});
  const amountRaw=side==='sell' && BigInt(asset.maxSellInputRaw)<1000000n?asset.maxSellInputRaw:'1000000';
  await assert.rejects(service.preview('user',wallet,{assetId:asset.assetId,variantMint:asset.mint,side,amountRaw,termsAccepted:terms(asset)}),/NO_ROUTE/);
  // With no quote on its usual route, a token tries the other one; Ondo's trade only with market makers.
  assert.equal(orderRequests,asset.issuerId==='ondo'?1:2);
 }
});

test('live preview refuses a swapped issuer/company identity before touching a wallet or provider',async()=>{
 let reads=0;
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store:{} as LiveOrderStore,fetch:async()=>{reads++;throw Error('unexpected');}});
 await assert.rejects(service.preview('user',fixture().order.wallet,{assetId:'apple',variantMint:STOCK_TRADING_ASSETS[1]!.mint,side:'buy',amountRaw:'1000000'}),{code:'MARKET_INPUT_INVALID'});
 assert.equal(reads,0);
});

test('the buy cap returns an explicit limit error before reading providers or spending funds',async()=>{
 let reads=0;
 const wallet=fixture().order.wallet;
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store:{} as LiveOrderStore,fetch:async()=>{reads++;throw Error('unexpected');}});
 const adapters={authenticate:async()=>({userId:'user',identity:{subject:'did:privy:test'}}),
  identities:{resolveFresh:async()=>({subject:'did:privy:test',embeddedSolanaWallet:{status:'candidate',address:wallet}})},service,
 } as unknown as LiveStockAdapters;
 const app=Fastify();registerLiveStockRoutes(app,adapters);
 try {
  // Sells are bounded by holdings and each order's market price check, not a per-token cap.
  for(const asset of STOCK_TRADING_ASSETS)for(const side of ['buy'] as const) {
   const cap=BigInt(asset.maxBuyInputRaw);
   for(const amountRaw of [String(cap+1n),String(cap*10n)]) {
   const input={assetId:asset.assetId,variantMint:asset.mint,side,amountRaw};
   await assert.rejects(service.preview('user',wallet,input),{code:'TRADE_LIMIT'});
   const response=await app.inject({method:'POST',url:'/v1/trading/preview',payload:input});
   assert.equal(response.statusCode,409);assert.deepEqual(response.json(),{code:'TRADE_LIMIT'});
  }}
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
   return Response.json({jsonrpc:'2.0',id:1,result:method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':method==='getBlockHeight'?100:{context:{slot:501},value:9_435_303}});
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

test('an RFQ refusal reads as under the minimum while its market is open, and as closed otherwise',async()=>{
 const wallet=fixture().order.wallet;
 const asset=STOCK_TRADING_ASSETS.find(item=>item.route==='rfq')!;
 const ondoMessage='Ondo tokens are only available via JupiterZ. Trading is not available outside of market hours. There is a minimum trade size of $1.';
 const sunday=Date.parse('2026-09-27T18:40:00Z');
 for(const [sessions,code] of [[['overnight','premarket','regular','postmarket','offhours'],'BELOW_MINIMUM'],[['overnight','premarket','regular','postmarket'],'MARKET_CLOSED']] as const){
  const status={observedAt:sunday,timestamp:sunday,isOpen:false,reasonCode:'MARKET_CLOSED',nextOpen:Date.parse('2026-09-28T00:05:00Z'),offhoursOpen:true,
   sessions:new Map([[asset.symbol,new Set(sessions)]])};
  const marketStates=new StockMarketStates({ondo:{read:async()=>status,peek:()=>status} as unknown as OndoMarketStatusReader,pauses:null,mints:[],now:()=>sunday});
  const store={read:async()=>null,create:async()=>{throw Error('unexpected');}} as unknown as LiveOrderStore;
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,marketStates,fetch:async(rawUrl,options)=>{
   if(String(rawUrl).includes('/order'))return Response.json({error:ondoMessage},{status:400});
   const {method}=JSON.parse(String(options?.body));
   return Response.json({jsonrpc:'2.0',id:1,result:method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':method==='getBlockHeight'?100:{context:{slot:501},value:9_435_303}});
  }});
  await assert.rejects(service.preview('user',wallet,{assetId:asset.assetId,variantMint:asset.mint,side:'buy',amountRaw:'1000000',termsAccepted:terms(asset)}),{code});
 }
});

test('a busy quote request says when to retry',async()=>{
 const f=fixture();
 const adapters={
  authenticate:async()=>({userId:'user',identity:{subject:'did:privy:test'}}),
  identities:{resolveFresh:async()=>({subject:'did:privy:test',embeddedSolanaWallet:{status:'candidate',address:f.order.wallet}})},
  service:{preview:async()=>{throw Object.assign(new Error('LIVE_BUSY'),{code:'LIVE_BUSY'});}},
 } as unknown as LiveStockAdapters;
 const app=Fastify();registerLiveStockRoutes(app,adapters);
 try {
  const stock=STOCK_TRADING_ASSETS[0]!;
  const preview=await app.inject({method:'POST',url:'/v1/trading/preview',payload:{assetId:stock.assetId,variantMint:stock.mint,side:'buy',amountRaw:'1000000',termsAccepted:terms(stock)}});
  assert.equal(preview.statusCode,429);assert.equal(preview.json().code,'LIVE_BUSY');assert.equal(preview.headers['retry-after'],'3');
 }finally{await app.close();}
});

test('a confirmed order records what the wallet actually moved, from its transaction',async()=>{
 const f=fixture();const usdc='EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',stock='XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
 const review={...f.order.review,terms:{side:'buy',inputMint:usdc,outputMint:stock,route:'aggregator'}} as unknown as ReviewedStockOrderIntent;
 let current:LiveOrder={...f.order,review,status:'pending',signature:'2'.repeat(88)};
 const fills:string[][]=[];
 const store={read:async()=>current,resolve:async(_u:string,_i:string,status:LiveOrder['status'])=>current={...current,status},
  recordFill:async(_u:string,id:string,input:string,output:string)=>{fills.push([id,input,output]);return true;}} as unknown as LiveOrderStore;
 const balance=(mint:string,owner:string,amount:string)=>({mint,owner,uiTokenAmount:{amount}});
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:async(_url,init)=>{
  const {method}=JSON.parse(String(init?.body));
  const result=method==='getSignatureStatuses'?{value:[{confirmationStatus:'confirmed',slot:501,err:null}]}
   :method==='getTransaction'?{slot:501,meta:{err:null,
    preTokenBalances:[balance(usdc,f.order.wallet,'5000000'),balance(usdc,'Other1111111111111111111111111111111111111','9')],
    postTokenBalances:[balance(usdc,f.order.wallet,'3000000'),balance(stock,f.order.wallet,'587000'),balance(usdc,'Other1111111111111111111111111111111111111','2000009')]}}:null;
  return Response.json({jsonrpc:'2.0',id:1,result});
 }});
 const settled=await service.status('user','test');
 assert.equal(settled?.status,'confirmed');
 // The wallet's USDC fell by 2 and it received its first stock tokens; the other owner is not counted.
 assert.deepEqual(fills,[['test','2000000','587000']]);
});

test('a fill needs a positive spend and delivery by the wallet itself',()=>{
 const wallet='FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1',a='A'.repeat(43),b='B'.repeat(43);
 const row=(mint:string,owner:string,amount:string)=>({mint,owner,uiTokenAmount:{amount}});
 assert.deepEqual(orderFill({preTokenBalances:[row(a,wallet,'10'),row(a,wallet,'5')],postTokenBalances:[row(a,wallet,'3'),row(b,wallet,'7')]},wallet,a,b),
  {inputRaw:'12',outputRaw:'7'});
 assert.equal(orderFill({preTokenBalances:[row(a,wallet,'10')],postTokenBalances:[row(a,wallet,'10'),row(b,wallet,'7')]},wallet,a,b),null);
 assert.equal(orderFill({preTokenBalances:[row(a,wallet,'x')],postTokenBalances:[]},wallet,a,b),null);
 assert.equal(orderFill(null,wallet,a,b),null);
});


test('pending orders do not expire at a provider cutoff while the blockhash remains valid',async()=>{
 for(const [value,slot] of [[true,502],[false,502],[undefined,502],['false',502],[false,500],[false,undefined]] as const) {
  const f=fixture();let resolutions=0,historyReads=0;
  const pending={...f.order,status:'pending' as const,signature:'2'.repeat(88),
   review:{...f.order.review,evidence:{...f.order.review.evidence,observationSlot:'501'}}};
  const store={read:async()=>pending,resolve:async(_u:string,_id:string,status:string)=>{resolutions++;return {...pending,status};}} as unknown as LiveOrderStore;
  const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:async(_url,init)=>{
   const {method,params}=JSON.parse(String(init?.body));
   let result:unknown;
   if(method==='getGenesisHash')result='5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
   else if(method==='getBlockHeight')result=501;
   else if(method==='getSignatureStatuses'){historyReads++;result={value:[null]};}
   else if(method==='isBlockhashValid'){
    assert.equal(typeof params[0],'string');assert.deepEqual(params[1],{commitment:'finalized',minContextSlot:501});
    result={value,context:{slot}};
   }else throw Error('unexpected RPC');
   return Response.json({jsonrpc:'2.0',id:1,result});
  }});
  const valid=typeof value==='boolean' && typeof slot==='number' && slot>=501;
  if(!valid)await assert.rejects(service.status('user','test'),{code:'LIVE_UNAVAILABLE'});
  else assert.equal((await service.status('user','test'))?.status,value?'pending':'expired');
  assert.equal(resolutions,valid && value===false?1:0);
  assert.equal(historyReads,valid && value===false?2:1,'expiry requires a fresh history lookup after invalidity');
 }
});
