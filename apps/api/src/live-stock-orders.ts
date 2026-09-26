import {createPublicKey, randomUUID, verify} from 'node:crypto';
import {address, getAddressEncoder, getBase58Decoder, getTransactionDecoder, getTransactionEncoder} from '@solana/kit';
import type {Pool} from 'pg';
import type {FastifyInstance, FastifyRequest, FastifyReply} from 'fastify';
import type {ExistingPracticeAccountAuthentication} from './practice-session-routes.js';
import type {PrivyLinkedIdentityResolution} from './privy-linked-identities.js';
import type {PracticeIdentity} from './practice-identity.js';
import {STOCK_TRADING_ASSETS,findStockTradingAsset} from './stock-trading-catalog.js';
import {JUPITER_QUOTE_ASSETS, parseEstimate} from './jupiter-quote-reader.js';
import {bindStockOrderDraft, copyStockDraftBytesForReview, STOCK_DRAFT_MAINNET_GENESIS} from './stock-order-draft.js';
import {SolanaMainnetLookupTableResolver} from './stock-order-lookup-resolver.js';
import {SolanaMainnetStockOrderLifetimeVerifier} from './stock-order-lifetime-verifier.js';
import {SolanaMainnetStockOrderSemanticsReader} from './stock-order-semantics.js';
import {SolanaMainnetStockOrderSimulator} from './stock-order-simulation.js';
import {reviewStockOrder} from './stock-order-review.js';
import type {ReviewedStockOrderIntent,StockOrderReviewStages} from './stock-order-review.js';
import {validateStockEstimateInput} from './stock-estimates.js';
import type {StockEstimateInput,StockEstimate} from './stock-estimates.js';

export interface LiveOrder {
 id:string;user_id:string;wallet:string;review:ReviewedStockOrderIntent;unsignedTransaction:string;
 expires_at:string;status:'reviewed'|'pending'|'confirmed'|'failed'|'expired';signature:string|null;dispatch?:boolean;
 /** Confirmed RPC slot for a newly settled order; absent on legacy persisted reads. */
 confirmedSlot?:number;
}
export interface LiveOrderStore {
 read(user:string,id?:string):Promise<LiveOrder|null>;
 create(user:string,id:string,wallet:string,review:ReviewedStockOrderIntent,wire:Uint8Array):Promise<LiveOrder>;
 begin(user:string,id:string,digest:string,signature:string):Promise<LiveOrder>;
 resolve(user:string,id:string,status:'confirmed'|'failed'|'expired'):Promise<LiveOrder>;
}
export class PostgresLiveOrderStore implements LiveOrderStore {
 constructor(private readonly pool:Pool) {}
 private async call(user:string,sql:string,params:unknown[]):Promise<LiveOrder|null> {
  const client=await this.pool.connect();
  try {
   await client.query('BEGIN');await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[user]);
   const result=await client.query(sql,params);await client.query('COMMIT');return result.rows[0]?.value??null;
  } catch(e) {await client.query('ROLLBACK');throw e;}finally{client.release();}
 }
 read(user:string,id?:string){return this.call(user,'SELECT trimmy.live_order_read($1,$2) AS value',[user,id??null]);}
 async create(user:string,id:string,wallet:string,review:ReviewedStockOrderIntent,wire:Uint8Array){return (await this.call(user,'SELECT trimmy.live_order_create($1,$2,$3,$4,$5,$6) AS value',[user,id,wallet,JSON.stringify(review),Buffer.from(wire),review.expiresAt]))!;}
 async begin(user:string,id:string,digest:string,signature:string){return (await this.call(user,'SELECT trimmy.live_order_begin($1,$2,$3,$4) AS value',[user,id,digest,signature]))!;}
 async resolve(user:string,id:string,status:'confirmed'|'failed'|'expired'){return (await this.call(user,'SELECT trimmy.live_order_resolve($1,$2,$3) AS value',[user,id,status]))!;}
}

export class LiveTradeError extends Error {constructor(readonly code:string){super(code);}}
function fail(code:string):never {throw new LiveTradeError(code);}
/** JSON representation of a reported Solana TransactionError. A missing or
 * malformed outcome must keep recovery pending, never imply a failed trade.
 * https://docs.rs/solana-client/latest/solana_client/rpc_response/enum.TransactionError.html */
function reportedTransactionError(value:unknown):boolean {
 const variant=(input:unknown):input is string=>typeof input==='string' && /^[A-Z][A-Za-z0-9]{0,95}$/.test(input);
 const index=(input:unknown):input is number=>Number.isInteger(input) && Number(input)>=0 && Number(input)<=255;
 if(variant(value))return true;
 if(value===null || typeof value!=='object' || Array.isArray(value) || Object.keys(value).length!==1)return false;
 const error=value as Record<string,unknown>;
 if(Object.hasOwn(error,'DuplicateInstruction'))return index(error.DuplicateInstruction);
 if(Object.hasOwn(error,'InstructionError')) {
  const detail=error.InstructionError;
  if(!Array.isArray(detail)||detail.length!==2||!index(detail[0]))return false;
  if(variant(detail[1]))return true;
  const custom=detail[1];
  return custom!==null && typeof custom==='object' && !Array.isArray(custom) && Object.keys(custom).length===1 &&
   Object.hasOwn(custom,'Custom') && Number.isInteger(custom.Custom) && custom.Custom>=0 && custom.Custom<=0xffffffff;
 }
 for(const kind of ['InsufficientFundsForRent','ProgramExecutionTemporarilyRestricted']) {
  if(!Object.hasOwn(error,kind))continue;
  const detail=error[kind];
  return detail!==null && typeof detail==='object' && !Array.isArray(detail) && Object.keys(detail).length===1 &&
   Object.hasOwn(detail,'account_index') && index((detail as Record<string,unknown>).account_index);
 }
 return false;
}
// One sole-signer transaction costs at least 5,000 lamports. The actual fee +
// account rent are independently reconciled and simulated for each order below.
// Jupiter's 0.01 SOL sponsorship heuristic is NOT a minimum trading balance:
// self-paid orders can still be built below it. Never infer solvency from it.
export const LIVE_STOCK_MIN_SOL_LAMPORTS = 5_000;
export function verifyReviewedSignature(order:LiveOrder,encoded:string):string {
 try {
  if(encoded.length>1644 || Buffer.from(encoded,'base64').toString('base64')!==encoded) return fail('INVALID_SIGNATURE');
  const wire=Buffer.from(encoded,'base64'), unsigned=Buffer.from(order.unsignedTransaction,'base64');
  const before=getTransactionDecoder().decode(unsigned),after=getTransactionDecoder().decode(wire);
  if(!Buffer.from(getTransactionEncoder().encode(after)).equals(wire) || !Buffer.from(before.messageBytes).equals(Buffer.from(after.messageBytes)) || Object.keys(after.signatures).length!==1) return fail('INVALID_SIGNATURE');
  const signature=after.signatures[address(order.wallet)];
  if(!signature || signature.length!==64) return fail('INVALID_SIGNATURE');
  const key=createPublicKey({key:Buffer.concat([Buffer.from('302a300506032b6570032100','hex'),Buffer.from(getAddressEncoder().encode(address(order.wallet)))]),format:'der',type:'spki'});
  if(!verify(null,Buffer.from(after.messageBytes),key,Buffer.from(signature))) return fail('INVALID_SIGNATURE');
  return getBase58Decoder().decode(signature);
 }catch(e){if(e instanceof LiveTradeError)throw e;return fail('INVALID_SIGNATURE');}
}

interface Options {rpcUrl:string;store:LiveOrderStore;apiKey?:string;fetch?:typeof fetch;stages?:StockOrderReviewStages;now?:()=>number}
export class LiveStockOrders {
 readonly #fetch:typeof fetch;readonly #now:()=>number;readonly #stages:StockOrderReviewStages;
 readonly #inFlight=new Set<string>();readonly #next=new Map<string,number>();
 constructor(private readonly options:Options) {
  const url=new URL(options.rpcUrl);if(url.protocol!=='https:'||url.username||url.password)fail('LIVE_UNAVAILABLE');
  this.#fetch=options.fetch??fetch;this.#now=options.now??Date.now;
  const rpc={rpcUrl:options.rpcUrl,...(options.fetch?{fetch:options.fetch}:{}),now:this.#now};
  this.#stages=options.stages??{lookupResolver:new SolanaMainnetLookupTableResolver(rpc),lifetimeVerifier:new SolanaMainnetStockOrderLifetimeVerifier(rpc),semanticsReader:new SolanaMainnetStockOrderSemanticsReader(rpc),simulator:new SolanaMainnetStockOrderSimulator(rpc),now:this.#now};
 }
 private async json(url:string,init:RequestInit,acceptOrderError=false):Promise<any> {
  const abort=new AbortController();const timer=setTimeout(()=>abort.abort(),15000);
  try {
   const response=await this.#fetch(url,{...init,redirect:'error',signal:abort.signal});
   if(!response.ok && !(acceptOrderError && response.status===400))fail(response.status===429?'LIVE_BUSY':'LIVE_UNAVAILABLE');
   if(!response.body)fail('LIVE_UNAVAILABLE');
   const reader=response.body.getReader();const chunks:Uint8Array[]=[];let size=0;
   try {for(;;){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>524288)fail('LIVE_UNAVAILABLE');chunks.push(part.value);}}finally{await reader.cancel().catch(()=>{});}
   return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  }catch(e){if(e instanceof LiveTradeError)throw e;return fail('LIVE_UNAVAILABLE');}finally{clearTimeout(timer);abort.abort();}
 }
 private async rpc(method:string,params:unknown[]=[]):Promise<any> {
  const result=await this.json(this.options.rpcUrl,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params})});
  if(result?.jsonrpc!=='2.0'||result.id!==1||result.error||!Object.hasOwn(result,'result'))fail('LIVE_UNAVAILABLE');
  return result.result;
 }
 private headers(){return {'accept':'application/json',...(this.options.apiKey?{'x-api-key':this.options.apiKey}:{})};}
 private async chain() {
  if(await this.rpc('getGenesisHash')!==STOCK_DRAFT_MAINNET_GENESIS)fail('WRONG_NETWORK');
  const height=await this.rpc('getBlockHeight',[{commitment:'finalized'}]);
  if(!Number.isSafeInteger(height)||height<1)fail('LIVE_UNAVAILABLE');
  return {genesisHash:STOCK_DRAFT_MAINNET_GENESIS,blockHeight:String(height),observedAt:new Date(this.#now()).toISOString()} as const;
 }
 async preview(user:string,wallet:string,input:StockEstimateInput):Promise<LiveOrder> {
  const requestedAsset=input && findStockTradingAsset(input.assetId,input.variantMint);
  if(requestedAsset && Object.keys(input).length===4 && ['buy','sell'].includes(input.side) &&
    typeof input.amountRaw==='string' && /^[1-9][0-9]{0,19}$/.test(input.amountRaw) &&
    BigInt(input.amountRaw)>BigInt(input.side==='buy'?requestedAsset.maxBuyInputRaw:requestedAsset.maxSellInputRaw))fail('TRADE_LIMIT');
  validateStockEstimateInput(input);
  if(this.#inFlight.has(user)||(this.#next.get(user)??0)>this.#now()||this.#inFlight.size>=3)fail('LIVE_BUSY');
  this.#inFlight.add(user);this.#next.set(user,this.#now()+3000);
  if(this.#next.size>1000)for(const [id,time]of this.#next)if(time<this.#now())this.#next.delete(id);
  try {
   const previous=await this.status(user);
   if(previous?.status==='pending')fail('ORDER_PENDING');
   const observation=await this.chain();
   const balance=await this.rpc('getBalance',[wallet,{commitment:'confirmed'}]);
   if(!Number.isSafeInteger(balance?.value)||balance.value<0)fail('LIVE_UNAVAILABLE');
   if(balance.value<LIVE_STOCK_MIN_SOL_LAMPORTS)fail('ADD_SOL');
   const stock=findStockTradingAsset(input.assetId,input.variantMint)!;
   const buying=input.side==='buy';const pair={inputAsset:buying?'USDC':stock.symbol,outputAsset:buying?stock.symbol:'USDC',amountRaw:input.amountRaw} as const;
   const url=new URL('https://api.jup.ag/swap/v2/order');
   url.search=new URLSearchParams({inputMint:JUPITER_QUOTE_ASSETS[pair.inputAsset].mint,outputMint:JUPITER_QUOTE_ASSETS[pair.outputAsset].mint,amount:input.amountRaw,taker:wallet,slippageBps:'50',excludeRouters:'jupiterz,dflow,okx',priorityFeeLamports:'100000',broadcastFeeType:'maxCap'}).toString();
   const started=this.#now();const payload=await this.json(url.toString(),{method:'GET',headers:this.headers()},true);const received=this.#now();
   if(payload?.router && payload.router!=='metis')fail('NO_ROUTE');
   if(!payload?.transaction)fail(payload?.errorCode===1?(buying?'ADD_USDC':'INSUFFICIENT_HOLDINGS'):[2,3].includes(payload?.errorCode)?'ADD_SOL':'NO_ROUTE');
   // Official opt-out: fee payer must be the taker. The draft decoder then
   // independently proves there is exactly one signer and checks all fee payers.
   if(payload.gasless===true || payload.signatureFeePayer!==wallet)fail('ADD_SOL');
   if(payload.router!=='metis')fail('NO_ROUTE');
   // This reference is only an unsigned candidate. The existing pipeline
   // independently decodes instructions, resolves accounts and simulates it.
   const quote=parseEstimate({...payload,transaction:null,taker:null},pair,started,received);
   if(quote.swapFee.basisPoints>100)fail('FEE_TOO_HIGH');
   const expected:StockEstimate={...quote,...input,executionEnabled:false,eligibility:'unverified',amountUnits:'raw_token_units'};
   const draft=bindStockOrderDraft(payload,{authenticatedUserId:user,verifiedTaker:wallet,expected,requestStartedAt:new Date(received).toISOString(),chainObservation:observation,validityAuthority:{now:this.#now,readChainObservation:()=>this.chain()}});
   const binding={authenticatedUserId:user,verifiedTaker:wallet,requestId:draft.summary.requestId,transactionMessageHash:draft.summary.transactionMessageHash,bindingHash:draft.summary.bindingHash};
   const reviewed=await reviewStockOrder(draft,binding,this.#stages).catch(error=>{
    if(error?.code==='RECONCILIATION_TAKER_SOL_INSUFFICIENT')fail('ADD_SOL');
    if(error?.code==='RECONCILIATION_SOURCE_BALANCE_INSUFFICIENT')fail(buying?'ADD_USDC':'INSUFFICIENT_HOLDINGS');
    throw error;
   });
   if(BigInt(reviewed.intent.terms.totalLamportsUpperBound)>10000000n)fail('FEE_TOO_HIGH');
   return await this.options.store.create(user,randomUUID(),wallet,reviewed.intent,await copyStockDraftBytesForReview(draft,binding));
  }finally{this.#inFlight.delete(user);}
 }
 async execute(user:string,wallet:string,id:string,digest:string,signed:string):Promise<LiveOrder> {
  const order=await this.options.store.read(user,id);
  if(!order||order.wallet!==wallet||order.review.reviewDigestSha256!==digest)fail('INVALID_REVIEW');
  const signature=verifyReviewedSignature(order,signed);
  if(order.status!=='reviewed') {
   if(order.signature!==signature)fail('INVALID_REVIEW');
   return (await this.status(user,id))!;
  }
  if(Date.parse(order.review.expiresAt)<=this.#now())fail('QUOTE_EXPIRED');
  const chain=await this.chain();
  if(BigInt(chain.blockHeight)>BigInt(order.review.evidence.lastValidBlockHeight))fail('QUOTE_EXPIRED');
  // Persist the exact signed message's signature BEFORE the one dispatch. A
  // lost HTTP reply can only be reconciled, never create a replacement trade.
  const pending=await this.options.store.begin(user,id,digest,signature);
  if(!pending.dispatch)return (await this.status(user,id))!;
  try {
   await this.json('https://api.jup.ag/swap/v2/execute',{method:'POST',headers:{...this.headers(),'content-type':'application/json'},body:JSON.stringify({signedTransaction:signed,requestId:order.review.requestId,lastValidBlockHeight:order.review.evidence.lastValidBlockHeight})});
  }catch(_){return pending;}
  try{return (await this.status(user,id))!;}catch(_){return pending;}
 }
 async status(user:string,id?:string):Promise<LiveOrder|null> {
  const order=await this.options.store.read(user,id);if(order?.status==='reviewed' && Date.parse(order.expires_at)<=this.#now())return {...order,status:'expired'};if(!order||order.status!=='pending')return order;
  const result=await this.rpc('getSignatureStatuses',[[order.signature],{searchTransactionHistory:true}]);
  if(!Array.isArray(result?.value)||result.value.length!==1)fail('LIVE_UNAVAILABLE');
  const status=result.value[0];
  if(status && ['confirmed','finalized'].includes(status.confirmationStatus)) {
   if(!Number.isSafeInteger(status.slot)||status.slot<1 || !Object.hasOwn(status,'err') ||
    (status.err!==null && !reportedTransactionError(status.err)))fail('LIVE_UNAVAILABLE');
   const settled=await this.options.store.resolve(user,order.id,status.err===null?'confirmed':'failed');
   return {...settled,confirmedSlot:status.slot};
  }
  if(status===null) {
   const chain=await this.chain();
   // A confirmed-height cutoff alone can race a fork. Require finalized height
   // past expiry, then a fresh history lookup before declaring no execution.
   const finalized=await this.rpc('getBlockHeight',[{commitment:'finalized'}]);
   if(Number.isSafeInteger(finalized) && BigInt(finalized)>BigInt(order.review.evidence.lastValidBlockHeight) && BigInt(chain.blockHeight)>BigInt(order.review.evidence.lastValidBlockHeight)) {
    const again=await this.rpc('getSignatureStatuses',[[order.signature],{searchTransactionHistory:true}]);
    if(again?.value?.length===1 && again.value[0]===null)return this.options.store.resolve(user,order.id,'expired');
   }
  }
  return order;
 }
}

export interface LiveStockAdapters {
 /** Disable new financial requests without hiding settlement of existing orders. */
 readonly executionEnabled?:boolean;
 authenticate(request:FastifyRequest):Promise<ExistingPracticeAccountAuthentication|null>;
 identities:{resolveFresh(identity:PracticeIdentity):Promise<PrivyLinkedIdentityResolution>};
 service:LiveStockOrders;
}
export function liveStockExecutionEnabled(adapters?:LiveStockAdapters):boolean {return !!adapters && adapters.executionEnabled!==false;}
function publicOrder(order:LiveOrder|null) {
 if(!order)return null;
 return {id:order.id,status:order.status,wallet:order.wallet,signature:order.signature,expiresAt:order.review.expiresAt,reviewDigest:order.review.reviewDigestSha256,
  ...(order.confirmedSlot===undefined?{}:{confirmedSlot:order.confirmedSlot}),
  terms:order.review.terms,reviewFlags:order.review.reviewFlags,...(order.status==='reviewed'?{transaction:order.unsignedTransaction.replace(/\s/g,'')}:{})};
}
export function registerLiveStockRoutes(app:FastifyInstance,adapters?:LiveStockAdapters) {
 const noQuery={type:'object',additionalProperties:false,properties:{}};
 async function run(request:FastifyRequest,reply:FastifyReply,operation:(user:string,wallet:string)=>Promise<LiveOrder|null>,financial=false) {
  reply.header('cache-control','no-store');
  if(!adapters || financial && !liveStockExecutionEnabled(adapters))return reply.code(503).send({code:'LIVE_UNAVAILABLE'});
  try {
   const account=await adapters.authenticate(request);if(!account)return reply.code(401).send({code:'ACCOUNT_REQUIRED'});
   const identity=await adapters.identities.resolveFresh(account.identity);
   if(identity.subject!==account.identity.subject||identity.embeddedSolanaWallet.status!=='candidate')fail('WALLET_REQUIRED');
   return {order:publicOrder(await operation(account.userId,identity.embeddedSolanaWallet.address))};
  }catch(error){
   const rawCode=error instanceof Error && 'code' in error && typeof error.code==='string'?error.code:error instanceof Error?error.message:'';
   // A provider can offer a route outside our reviewed instruction set, or a
   // quote can stop meeting its floor before simulation. Neither is an outage
   // or permission to skip review: decline this candidate with a useful retry.
   const unavailableRoute=['SEMANTICS_PROGRAM_UNSUPPORTED','SEMANTICS_INSTRUCTION_UNSUPPORTED',
    'RECONCILIATION_PROGRAM_UNEXPECTED','RECONCILIATION_UNEXPECTED_MOVEMENT','SIMULATION_EFFECTS_MISMATCH'];
   const expiredReview=['STOCK_DRAFT_EXPIRED','LOOKUP_DRAFT_EXPIRED','LIFETIME_EXPIRED','SEMANTICS_DRAFT_EXPIRED',
    'RECONCILIATION_EXPIRED','SIMULATION_DRAFT_EXPIRED','SIMULATION_BLOCKHASH_EXPIRED','REVIEW_EXPIRED'];
   const code=unavailableRoute.includes(rawCode)?'NO_ROUTE':expiredReview.includes(rawCode)?'QUOTE_EXPIRED':rawCode;
   const known=['ACCOUNT_REQUIRED','WALLET_REQUIRED','ORDER_PENDING','QUOTE_EXPIRED','INVALID_REVIEW','INVALID_SIGNATURE','ADD_USDC','ADD_SOL','INSUFFICIENT_HOLDINGS','NO_ROUTE','FEE_TOO_HIGH','LIVE_BUSY','TRADE_LIMIT','MARKET_INPUT_INVALID'];
   // Log only bounded internal reason codes, never provider payloads, tokens or signed transactions.
   const detail=error instanceof Error && 'code' in error ? error.code : null;
   const reviewCode=typeof detail==='string' && /^(?:STOCK_DRAFT|LOOKUP|LIFETIME|SEMANTICS|RECONCILIATION|SIMULATION|REVIEW)_[A-Z_]{1,64}$/.test(detail)?detail:null;
   request.log.warn({tradeFailure:reviewCode??(known.includes(code)?code:'LIVE_UNAVAILABLE')},'Live stock request failed');
   return reply.code(code==='ACCOUNT_REQUIRED'?401:code==='MARKET_INPUT_INVALID'?400:code==='LIVE_BUSY'?429:known.includes(code)?409:503).send({code:known.includes(code)?code:'LIVE_UNAVAILABLE'});
  }
 }
 app.get('/v1/trading/capabilities',{schema:{querystring:noQuery}},async()=>({enabled:liveStockExecutionEnabled(adapters),network:'solana:mainnet-beta',assets:STOCK_TRADING_ASSETS.map(({assetId,mint,symbol,name,decimals,maxBuyInputRaw,maxSellInputRaw})=>({assetId,mint,symbol,name,decimals,maxBuyInputRaw,maxSellInputRaw})),maxBuyUsdc:'100',minimumSolBalanceLamports:String(LIVE_STOCK_MIN_SOL_LAMPORTS)}));
 app.get<{Params:{id:string}}>('/v1/trading/order/:id',{schema:{querystring:noQuery,params:{type:'object',additionalProperties:false,required:['id'],properties:{id:{type:'string',format:'uuid'}}}}},(request,reply)=>run(request,reply,user=>adapters!.service.status(user,request.params.id)));
 app.get('/v1/trading/order',{schema:{querystring:noQuery}},(request,reply)=>run(request,reply,user=>adapters!.service.status(user)));
 app.post<{Body:StockEstimateInput}>('/v1/trading/preview',{bodyLimit:2048,schema:{querystring:noQuery,body:{type:'object',additionalProperties:false,required:['assetId','variantMint','side','amountRaw'],properties:{assetId:{enum:STOCK_TRADING_ASSETS.map(asset=>asset.assetId)},variantMint:{enum:STOCK_TRADING_ASSETS.map(asset=>asset.mint)},side:{enum:['buy','sell']},amountRaw:{type:'string',pattern:'^[1-9][0-9]{0,19}$'}}}}},(request,reply)=>run(request,reply,(user,wallet)=>adapters!.service.preview(user,wallet,request.body),true));
 app.post<{Body:{id:string;reviewDigest:string;signedTransaction:string}}>('/v1/trading/execute',{bodyLimit:4096,schema:{querystring:noQuery,body:{type:'object',additionalProperties:false,required:['id','reviewDigest','signedTransaction'],properties:{id:{type:'string',format:'uuid'},reviewDigest:{type:'string',pattern:'^[0-9a-f]{64}$'},signedTransaction:{type:'string',minLength:88,maxLength:1644,pattern:'^[A-Za-z0-9+/]+={0,2}$'}}}}},(request,reply)=>run(request,reply,(user,wallet)=>adapters!.service.execute(user,wallet,request.body.id,request.body.reviewDigest,request.body.signedTransaction),true));
}
