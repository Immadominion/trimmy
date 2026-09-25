import test from 'node:test';import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {getAddressDecoder,getCompiledTransactionMessageEncoder,getTransactionEncoder} from '@solana/kit';
import type {CompiledTransactionMessage,TransactionMessageBytes} from '@solana/kit';
import {LiveStockOrders,verifyReviewedSignature} from '../src/live-stock-orders.js';
import type {LiveOrder,LiveOrderStore} from '../src/live-stock-orders.js';
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
test('a lost dispatch response stays pending; retry never sends a second trade',async()=>{
 const f=fixture();let current=f.order,dispatches=0;
 const store:LiveOrderStore={read:async()=>current,create:async()=>{throw Error('unexpected')},begin:async(_u,_id,_d,signature)=>{if(current.status==='reviewed'){current={...current,status:'pending',signature};return {...current,dispatch:true};}return {...current,dispatch:false};},resolve:async(_u,_id,status)=>current={...current,status}};
 let confirmed=false;
 const fake=async(url:URL|RequestInfo,options?:RequestInit)=>{
  if(String(url).includes('/execute')){dispatches++;throw Error('response lost');}
  const method=JSON.parse(String(options?.body)).method;
  const result=method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':method==='getBlockHeight'?100:{value:[confirmed?{confirmationStatus:'confirmed',err:null}:null]};
  return Response.json({jsonrpc:'2.0',id:1,result});
 };
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:fake as typeof fetch});
 const first=await service.execute('user',f.order.wallet,'test','a'.repeat(64),f.signed);assert.equal(first.status,'pending');
 await service.execute('user',f.order.wallet,'test','a'.repeat(64),f.signed);assert.equal(dispatches,1);
 confirmed=true;assert.equal((await service.status('user','test'))?.status,'confirmed');assert.equal(dispatches,1);
});

test('low SOL reports the self-paid funding requirement before requesting a Jupiter order', async () => {
 const wallet=fixture().order.wallet;
 const store:LiveOrderStore={read:async()=>null,create:async()=>{throw Error('unexpected write');},begin:async()=>{throw Error('unexpected dispatch');},resolve:async()=>{throw Error('unexpected write');}};
 for(const [balance,expected] of [[3_000_000,'ADD_SOL'],[9_999_999,'ADD_SOL'],[-1,'LIVE_UNAVAILABLE'],[null,'LIVE_UNAVAILABLE']] as const) {
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

test('the provider SOL threshold admits an order request without spending or reserving SOL',async()=>{
 const wallet=fixture().order.wallet;let orderRequests=0;
 const store:LiveOrderStore={read:async()=>null,create:async()=>{throw Error('unexpected write');},begin:async()=>{throw Error('unexpected dispatch');},resolve:async()=>{throw Error('unexpected write');}};
 const fake=async(url:URL|RequestInfo,options?:RequestInit)=>{
  if(String(url).includes('/order')){orderRequests++;return Response.json({transaction:'',router:'metis',errorCode:1});}
  const request=JSON.parse(String(options?.body));
  assert.ok(['getGenesisHash','getBlockHeight','getBalance'].includes(request.method));
  const result=request.method==='getGenesisHash'?'5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d':request.method==='getBlockHeight'?100:{value:10_000_000};
  return Response.json({jsonrpc:'2.0',id:1,result});
 };
 const service=new LiveStockOrders({rpcUrl:'https://rpc.example',store,fetch:fake as typeof fetch});
 await assert.rejects(service.preview('user',wallet,{assetId:'apple',variantMint:'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',side:'buy',amountRaw:'5000000'}),/ADD_USDC/);
 assert.equal(orderRequests,1);
});
