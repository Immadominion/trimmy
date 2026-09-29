import {createPublicKey, randomUUID, verify} from 'node:crypto';
import {address, getAddressEncoder, getBase58Decoder, getTransactionDecoder, getTransactionEncoder} from '@solana/kit';
import type {Pool} from 'pg';
import type {FastifyInstance, FastifyRequest, FastifyReply} from 'fastify';
import type {ExistingPracticeAccountAuthentication} from './practice-session-routes.js';
import type {PrivyLinkedIdentityResolution} from './privy-linked-identities.js';
import type {PracticeIdentity} from './practice-identity.js';
import {STOCK_ASSET_ID_PATTERN,STOCK_MINT_PATTERN,STOCK_TRADING_ASSETS,findStockTradingAsset,findStockTradingAssetByMint,stockTradingAssets} from './stock-trading-catalog.js';
import type {StockTradingAsset} from './stock-trading-catalog.js';
import {LEGACY_STOCK_ISSUER,STOCK_ISSUER_IDS,acceptsIssuerTerms} from './stock-issuers.js';
import {stockIssuerCapabilities,unavailableVariantsNow} from './stock-market-availability.js';
import type {StockTokenDirectory} from './stock-token-directory.js';
import {orderPriceAcceptable} from './stock-order-price.js';
import {JupiterTokenPrices, orderReferencePrices} from './stock-token-prices.js';
import type {OpsAlerts} from './ops-alerts.js';
import {calendarMarketStates} from './stock-market-state.js';
import type {StockMarketStates,StockMarketStateOf} from './stock-market-state.js';
import {usMarketMoment} from './us-equity-calendar.js';
import type {StockIssuerId,StockTermsAcceptance} from './stock-issuers.js';
import {JUPITER_QUOTE_ASSETS, orderSlippageBps, parseEstimate, stockQuoteAsset} from './jupiter-quote-reader.js';
import {bindStockOrderDraft, copyStockDraftBytesForReview, STOCK_DRAFT_MAINNET_GENESIS} from './stock-order-draft.js';
import {SolanaMainnetLookupTableResolver} from './stock-order-lookup-resolver.js';
import {SolanaMainnetStockOrderLifetimeVerifier} from './stock-order-lifetime-verifier.js';
import {SolanaMainnetStockOrderSemanticsReader} from './stock-order-semantics.js';
import {SolanaMainnetStockOrderSimulator} from './stock-order-simulation.js';
import {reviewStockOrder} from './stock-order-review.js';
import type {ReviewedStockOrderIntent,StockOrderReviewStages} from './stock-order-review.js';
import {validateStockEstimateInput} from './stock-estimates.js';
import type {StockEstimateInput,StockEstimate} from './stock-estimates.js';

/** What the user accepted before this order was quoted. A legacy client only
 * ever showed the original xStocks checkbox, recorded as its own version. */
export interface LiveOrderTermsAcceptance {readonly issuerId:StockIssuerId;readonly version:string;readonly acceptedAt:string}
export interface LiveOrder {
 id:string;user_id:string;wallet:string;review:ReviewedStockOrderIntent&{termsAcceptance?:LiveOrderTermsAcceptance};unsignedTransaction:string;
 expires_at:string;status:'reviewed'|'pending'|'confirmed'|'failed'|'expired';signature:string|null;dispatch?:boolean;
 /** Confirmed RPC slot persisted with settlement; absent on legacy orders. */
 confirmedSlot?:number;
}
export interface LiveOrderStore {
 read(user:string,id?:string):Promise<LiveOrder|null>;
 create(user:string,id:string,wallet:string,review:ReviewedStockOrderIntent,wire:Uint8Array,terms?:LiveOrderTermsAcceptance):Promise<LiveOrder>;
 begin(user:string,id:string,digest:string,signature:string):Promise<LiveOrder>;
 resolve(user:string,id:string,status:'confirmed'|'failed'|'expired',confirmedSlot?:number):Promise<LiveOrder>;
 /** What a confirmed order moved (migration 0033); false when already recorded. */
 recordFill?(user:string,id:string,inputRaw:string,outputRaw:string):Promise<boolean>;
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
 async create(user:string,id:string,wallet:string,review:ReviewedStockOrderIntent,wire:Uint8Array,terms?:LiveOrderTermsAcceptance){
  // The acceptance is stored beside the reviewed intent; its digest is unchanged.
  const stored=terms===undefined?review:{...review,termsAcceptance:terms};
  return (await this.call(user,'SELECT trimmy.live_order_create($1,$2,$3,$4,$5,$6) AS value',[user,id,wallet,JSON.stringify(stored),Buffer.from(wire),review.expiresAt]))!;
 }
 async begin(user:string,id:string,digest:string,signature:string){return (await this.call(user,'SELECT trimmy.live_order_begin($1,$2,$3,$4) AS value',[user,id,digest,signature]))!;}
 async resolve(user:string,id:string,status:'confirmed'|'failed'|'expired',confirmedSlot?:number){return (await this.call(user,'SELECT trimmy.live_order_resolve($1,$2,$3,$4::bigint) AS value',[user,id,status,confirmedSlot??null]))!;}
 async recordFill(user:string,id:string,inputRaw:string,outputRaw:string){
  return (await this.call(user,'SELECT trimmy.live_order_record_fill($1,$2,$3,$4) AS value',[user,id,inputRaw,outputRaw])) as unknown===true;
 }
}

/**
 * What an order moved for the wallet, from its confirmed transaction's token
 * balances: the input token's decrease and the output token's increase, across
 * all of the wallet's accounts for each. Null when either is not positive.
 */
export function orderFill(meta:unknown,wallet:string,inputMint:string,outputMint:string):{inputRaw:string;outputRaw:string}|null {
 const m=meta as {preTokenBalances?:unknown;postTokenBalances?:unknown}|null;
 const total=(rows:unknown,mint:string)=>{
  if(!Array.isArray(rows))return null;
  let sum=0n;
  for(const row of rows as {mint?:unknown;owner?:unknown;uiTokenAmount?:{amount?:unknown}}[]) {
   if(row?.mint!==mint || row.owner!==wallet)continue;
   const amount=row.uiTokenAmount?.amount;
   if(typeof amount!=='string' || !/^(0|[1-9][0-9]{0,19})$/.test(amount))return null;
   sum+=BigInt(amount);
  }
  return sum;
 };
 const inBefore=total(m?.preTokenBalances,inputMint),inAfter=total(m?.postTokenBalances,inputMint);
 const outBefore=total(m?.preTokenBalances,outputMint),outAfter=total(m?.postTokenBalances,outputMint);
 if(inBefore===null||inAfter===null||outBefore===null||outAfter===null)return null;
 const spent=inBefore-inAfter,received=outAfter-outBefore;
 return spent>0n && received>0n?{inputRaw:String(spent),outputRaw:String(received)}:null;
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
/** An issuer can raise its Token-2022 transfer fee after admission. Never open a
 * position above the fee disclosed at admission; selling out stays possible
 * (review and simulation already price the fee into the reviewed terms). */
export function transferFeeWithinDisclosure(side:'buy'|'sell',outputMint:{readonly transferFeeMaxBasisPoints:number|null},disclosedBps:number):boolean {
 return side!=='buy' || (outputMint.transferFeeMaxBasisPoints??0)<=disclosedBps;
}
export function verifyReviewedSignature(order:LiveOrder,encoded:string):string {
 try {
  if(encoded.length>1644 || Buffer.from(encoded,'base64').toString('base64')!==encoded) return fail('INVALID_SIGNATURE');
  const wire=Buffer.from(encoded,'base64'), unsigned=Buffer.from(order.unsignedTransaction,'base64');
  const before=getTransactionDecoder().decode(unsigned),after=getTransactionDecoder().decode(wire);
  // The same signer slots as the reviewed transaction. Only the user's may be
  // signed here; an RFQ market maker adds its signature later through Jupiter.
  const expected=Object.keys(before.signatures),actual=Object.keys(after.signatures);
  if(!Buffer.from(getTransactionEncoder().encode(after)).equals(wire) || !Buffer.from(before.messageBytes).equals(Buffer.from(after.messageBytes)) ||
   actual.length<1 || actual.length>2 || actual.length!==expected.length || actual.some((key,index)=>key!==expected[index]) ||
   !actual.includes(order.wallet) || actual.some(key=>key!==order.wallet && after.signatures[address(key)]!==null)) return fail('INVALID_SIGNATURE');
  const signature=after.signatures[address(order.wallet)];
  if(!signature || signature.length!==64) return fail('INVALID_SIGNATURE');
  const key=createPublicKey({key:Buffer.concat([Buffer.from('302a300506032b6570032100','hex'),Buffer.from(getAddressEncoder().encode(address(order.wallet)))]),format:'der',type:'spki'});
  if(!verify(null,Buffer.from(after.messageBytes),key,Buffer.from(signature))) return fail('INVALID_SIGNATURE');
  return getBase58Decoder().decode(signature);
 }catch(e){if(e instanceof LiveTradeError)throw e;return fail('INVALID_SIGNATURE');}
}

interface Options {rpcUrl:string;store:LiveOrderStore;apiKey?:string;fetch?:typeof fetch;stages?:StockOrderReviewStages;now?:()=>number;
 /** Live market states; without them the published session calendar alone decides. */
 marketStates?:StockMarketStates;
 /** Finds tokens the Market lists that no order has named yet; without it only known tokens trade. */
 directory?:StockTokenDirectory;
 /** Trusted token prices for the order price check; read from Jupiter by default. */
 prices?:JupiterTokenPrices;
 /** Operator alerts when a signed order fails or never executes. */
 alerts?:OpsAlerts}

/** Market states now, live when configured. */
export async function marketStatesNow(states:StockMarketStates|undefined,now:number):Promise<StockMarketStateOf>{
 return states?states.snapshot():calendarMarketStates(now);
}
export class LiveStockOrders {
 readonly #fetch:typeof fetch;readonly #now:()=>number;readonly #stages:StockOrderReviewStages;
 readonly #inFlight=new Set<string>();readonly #next=new Map<string,number>();
 /** Order id to the RFQ transaction id Jupiter reported; verified before use. */
 readonly #rfqHints=new Map<string,string>();
 constructor(private readonly options:Options) {
  const url=new URL(options.rpcUrl);if(url.protocol!=='https:'||url.username||url.password)fail('LIVE_UNAVAILABLE');
  this.#fetch=options.fetch??fetch;this.#now=options.now??Date.now;
  this.#prices=options.prices??new JupiterTokenPrices({...(options.fetch?{fetch:options.fetch}:{}),...(options.apiKey?{apiKey:options.apiKey}:{}),now:this.#now});
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
 /** Trusted prices per token (stock-token-prices.ts), cached briefly. */
 readonly #prices:JupiterTokenPrices;
 /** Refuses an order priced far worse than the issuer's price or a liquid market (stock-order-price.ts). */
 async #checkMarketPrice(stock:StockTradingAsset,buying:boolean,inputRaw:string,outputRaw:string,feeBps:number,payload:any):Promise<void> {
  const price=(await this.#prices.read([stock.mint])).get(stock.mint);
  if(!orderPriceAcceptable({buying,inputRaw,outputRaw,decimals:stock.decimals,transferFeeBps:stock.transferFeeBps,swapFeeBps:feeBps,
   referencesUsd:orderReferencePrices(price),priceImpactPct:payload?.priceImpactPct}))fail('PRICE_OFF_MARKET');
 }
 private async chain() {
  if(await this.rpc('getGenesisHash')!==STOCK_DRAFT_MAINNET_GENESIS)fail('WRONG_NETWORK');
  const height=await this.rpc('getBlockHeight',[{commitment:'finalized'}]);
  if(!Number.isSafeInteger(height)||height<1)fail('LIVE_UNAVAILABLE');
  return {genesisHash:STOCK_DRAFT_MAINNET_GENESIS,blockHeight:String(height),observedAt:new Date(this.#now()).toISOString()} as const;
 }
 async preview(user:string,wallet:string,request:StockEstimateInput&{termsAccepted?:StockTermsAcceptance}):Promise<LiveOrder> {
  if(!request || typeof request!=='object')fail('MARKET_INPUT_INVALID');
  const {termsAccepted,...input}=request;
  // A token the Market lists that no order has named yet is checked now.
  if(typeof input.assetId==='string' && typeof input.variantMint==='string')await this.options.directory?.ensure(input.assetId,input.variantMint);
  const requestedAsset=input && findStockTradingAsset(input.assetId,input.variantMint);
  if(requestedAsset && Object.keys(input).length===4 && ['buy','sell'].includes(input.side) &&
    typeof input.amountRaw==='string' && /^[1-9][0-9]{0,19}$/.test(input.amountRaw) &&
    BigInt(input.amountRaw)>BigInt(input.side==='buy'?requestedAsset.maxBuyInputRaw:requestedAsset.maxSellInputRaw))fail('TRADE_LIMIT');
  validateStockEstimateInput(input);
  // Each issuer's disclosure must be accepted at its current version before any
  // quote. Older clients (no field) may only trade the original xStocks issuer.
  const selected=findStockTradingAsset(input.assetId,input.variantMint)!;
  if(!acceptsIssuerTerms(selected.issuerId,termsAccepted))fail('TERMS_REQUIRED');
  // A legacy client cannot sign an RFQ order (a market maker co-signs), so it
  // never receives one.
  if(termsAccepted===undefined && selected.route!=='aggregator')fail('TERMS_REQUIRED');
  const acceptance:LiveOrderTermsAcceptance=Object.freeze({issuerId:selected.issuerId,
   version:termsAccepted?.version??'legacy_client_checkbox',acceptedAt:new Date(this.#now()).toISOString()});
  if(this.#inFlight.has(user)||(this.#next.get(user)??0)>this.#now()||this.#inFlight.size>=3)fail('LIVE_BUSY');
  this.#inFlight.add(user);this.#next.set(user,this.#now()+3000);
  if(this.#next.size>1000)for(const [id,time]of this.#next)if(time<this.#now())this.#next.delete(id);
  try {
   const previous=await this.status(user);
   if(previous?.status==='pending')fail('ORDER_PENDING');
   const observation=await this.chain();
   const previousSlot=previous?.confirmedSlot;
   const balance=await this.rpc('getBalance',[wallet,{commitment:'confirmed',...(previousSlot===undefined?{}:{minContextSlot:previousSlot})}]);
   if(!Number.isSafeInteger(balance?.value)||balance.value<0 || !Number.isSafeInteger(balance?.context?.slot) ||
    balance.context.slot<1 || (previousSlot!==undefined && balance.context.slot<previousSlot))fail('LIVE_UNAVAILABLE');
   if(balance.value<LIVE_STOCK_MIN_SOL_LAMPORTS)fail('ADD_SOL');
   const stock=findStockTradingAsset(input.assetId,input.variantMint)!;
   const buying=input.side==='buy';const stockSide=stockQuoteAsset(stock);
   const pair={inputAsset:buying?'USDC' as const:stockSide,outputAsset:buying?stockSide:'USDC' as const,amountRaw:input.amountRaw};
   const inputMint=buying?JUPITER_QUOTE_ASSETS.USDC.mint:stock.mint,outputMint=buying?stock.mint:JUPITER_QUOTE_ASSETS.USDC.mint;
   // Two reviewed routes: Jupiter's aggregator (metis) and JupiterZ market makers
   // (RFQ). The token's usual route goes first and the other is tried when it has no
   // quote. Ondo's tokens trade only with market makers, and a client without issuer
   // terms cannot sign a market maker's order.
   const routes:readonly ('aggregator'|'rfq')[]=stock.issuerId==='ondo'?['rfq']:termsAccepted===undefined?['aggregator']:
    stock.route==='rfq'?['rfq','aggregator']:['aggregator','rfq'];
   // A token's own transfer fee is withheld from what arrives; Jupiter quotes before it.
   const slippageBps=orderSlippageBps(stock.transferFeeBps);
   let route=routes[0]!,payload:any,started=0,received=0,providerText='';
   for(const candidate of routes) {
    route=candidate;
    const url=new URL('https://api.jup.ag/swap/v2/order');
    url.search=new URLSearchParams({inputMint,outputMint,amount:input.amountRaw,taker:wallet,slippageBps:String(slippageBps),excludeRouters:route==='rfq'?'metis,dflow,okx':'jupiterz,dflow,okx',priorityFeeLamports:'100000',broadcastFeeType:'maxCap'}).toString();
    started=this.#now();payload=await this.json(url.toString(),{method:'GET',headers:this.headers()},true);received=this.#now();
    providerText=[payload?.error,payload?.errorMessage].filter(value=>typeof value==='string').join(' ');
    // Only a route with no quote at all moves on; a funding or hours answer is final.
    if(payload?.transaction || payload?.errorCode!==undefined || /market hours/i.test(providerText))break;
   }
   const expectedRouter=route==='rfq'?'jupiterz':'metis';
   if(/market hours/i.test(providerText)) {
    // Ondo's market makers give one message for a closed market and for an order
    // under their $1 minimum after fees; the token's own market state tells them apart.
    const state=(await marketStatesNow(this.options.marketStates,this.#now()))(stock.issuerId,stock.symbol,stock.mint);
    fail(route==='rfq' && /minimum trade size/i.test(providerText) && state.status==='open'?'BELOW_MINIMUM':'MARKET_CLOSED');
   }
   if(payload?.router && payload.router!==expectedRouter)fail('NO_ROUTE');
   if(!payload?.transaction)fail(payload?.errorCode===1?(buying?'ADD_USDC':'INSUFFICIENT_HOLDINGS'):[2,3].includes(payload?.errorCode)?'ADD_SOL':'NO_ROUTE');
   if(route==='rfq') {
    // The market maker pays the network fee; the user pays only rent for their own
    // accounts. Below 0.01 SOL Jupiter sponsors that rent for a much larger fee
    // through a third signer: ask for a little SOL instead.
    if(payload.gasless!==true || payload.signatureFeePayer!==payload.maker || payload.rentFeePayer!==wallet)fail('ADD_SOL');
   } else if(payload.gasless===true || payload.signatureFeePayer!==wallet) {
    // Official opt-out: fee payer must be the taker. The draft decoder then
    // independently proves the signer set and checks all fee payers.
    fail('ADD_SOL');
   }
   if(payload.router!==expectedRouter)fail('NO_ROUTE');
   // This reference is only an unsigned candidate. The existing pipeline
   // independently decodes instructions, resolves accounts and simulates it.
   const quote=parseEstimate({...payload,transaction:null,taker:null},pair,started,received,slippageBps);
   if(quote.swapFee.basisPoints>100)fail('FEE_TOO_HIGH');
   await this.#checkMarketPrice(stock,buying,input.amountRaw,quote.output.estimatedAmountRaw,quote.swapFee.basisPoints,payload);
   const expected:StockEstimate={...quote,...input,executionEnabled:false,eligibility:'unverified',amountUnits:'raw_token_units'};
   const draft=bindStockOrderDraft(payload,{authenticatedUserId:user,verifiedTaker:wallet,expected,requestStartedAt:new Date(received).toISOString(),chainObservation:observation,validityAuthority:{now:this.#now,readChainObservation:()=>this.chain()}});
   const binding={authenticatedUserId:user,verifiedTaker:wallet,requestId:draft.summary.requestId,transactionMessageHash:draft.summary.transactionMessageHash,bindingHash:draft.summary.bindingHash};
   const reviewed=await reviewStockOrder(draft,binding,this.#stages,balance.context.slot).catch(error=>{
    if(error?.code==='RECONCILIATION_TAKER_SOL_INSUFFICIENT')fail('ADD_SOL');
    if(error?.code==='RECONCILIATION_SOURCE_BALANCE_INSUFFICIENT')fail(buying?'ADD_USDC':'INSUFFICIENT_HOLDINGS');
    throw error;
   });
   if(BigInt(reviewed.intent.terms.totalLamportsUpperBound)>10000000n)fail('FEE_TOO_HIGH');
   if(!transferFeeWithinDisclosure(input.side,reviewed.evidence.reconciliation.accountState.outputMint,stock.transferFeeBps))fail('FEE_TOO_HIGH');
   return await this.options.store.create(user,randomUUID(),wallet,reviewed.intent,await copyStockDraftBytesForReview(draft,binding),acceptance);
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
   const executed=await this.json('https://api.jup.ag/swap/v2/execute',{method:'POST',headers:{...this.headers(),'content-type':'application/json'},body:JSON.stringify({signedTransaction:signed,requestId:order.review.requestId,lastValidBlockHeight:order.review.evidence.lastValidBlockHeight})});
   // An RFQ transaction is identified by the market maker's signature, known
   // only after Jupiter co-signs. It is a hint: status() verifies it on chain.
   if(order.review.terms?.route==='rfq' && typeof executed?.signature==='string' && TRANSACTION_SIGNATURE.test(executed.signature)) {
    this.#rfqHints.set(order.id,executed.signature);
    if(this.#rfqHints.size>1000)this.#rfqHints.delete(this.#rfqHints.keys().next().value!);
   }
  }catch(_){return pending;}
  try{return (await this.status(user,id))!;}catch(_){return pending;}
 }
 async status(user:string,id?:string):Promise<LiveOrder|null> {
  const order=await this.options.store.read(user,id);if(order?.status==='reviewed' && Date.parse(order.expires_at)<=this.#now())return {...order,status:'expired'};
  // A fill that could not be read at confirmation is tried again for an hour.
  const stored=order as (LiveOrder&{filled_input_raw?:string|null;updated_at?:string})|null;
  if(stored?.status==='confirmed' && stored.filled_input_raw===null && Date.parse(stored.updated_at??'')>this.#now()-3_600_000) {
   const transaction=stored.review.terms?.route==='rfq'?(await this.rfqTransaction(stored).catch(()=>null))?.signature:stored.signature;
   if(transaction)await this.#recordFill(user,stored,transaction);
  }
  if(!order||order.status!=='pending')return order;
  if(order.review.terms?.route==='rfq')return this.rfqStatus(user,order);
  const result=await this.rpc('getSignatureStatuses',[[order.signature],{searchTransactionHistory:true}]);
  if(!Array.isArray(result?.value)||result.value.length!==1)fail('LIVE_UNAVAILABLE');
  const status=result.value[0];
  if(status && ['confirmed','finalized'].includes(status.confirmationStatus)) {
   if(!Number.isSafeInteger(status.slot)||status.slot<1 || !Object.hasOwn(status,'err') ||
    (status.err!==null && !reportedTransactionError(status.err)))fail('LIVE_UNAVAILABLE');
   const settled=this.#alertSettled(order,await this.options.store.resolve(user,order.id,status.err===null?'confirmed':'failed',status.slot));
   if(settled.status==='confirmed')await this.#recordFill(user,order,order.signature!);
   return {...settled,confirmedSlot:status.slot};
  }
  if(status===null) {
   const chain=await this.chain();
   // A confirmed-height cutoff alone can race a fork. Require finalized height
   // past expiry, then a fresh history lookup before declaring no execution.
   const finalized=await this.rpc('getBlockHeight',[{commitment:'finalized'}]);
   if(Number.isSafeInteger(finalized) && BigInt(finalized)>BigInt(order.review.evidence.lastValidBlockHeight) && BigInt(chain.blockHeight)>BigInt(order.review.evidence.lastValidBlockHeight)) {
    const again=await this.rpc('getSignatureStatuses',[[order.signature],{searchTransactionHistory:true}]);
    if(again?.value?.length===1 && again.value[0]===null)return this.#alertSettled(order,await this.options.store.resolve(user,order.id,'expired'));
   }
  }
  return order;
 }
 /** The confirmed transaction that carries the user's signature for this RFQ order.
  * Solana indexes a transaction by its first signature (the market maker's), so
  * the user's signature alone cannot be looked up. A hint from the execute reply
  * is verified; otherwise the wallet's recent transactions are searched. */
 private async rfqTransaction(order:LiveOrder):Promise<{signature:string;slot:number;err:unknown}|null> {
  const owns=async(candidate:string)=>{
   const tx=await this.rpc('getTransaction',[candidate,{commitment:'confirmed',maxSupportedTransactionVersion:0,encoding:'json'}]);
   const signatures=tx?.transaction?.signatures;
   if(tx===null || !Array.isArray(signatures) || !signatures.includes(order.signature) || signatures[0]!==candidate)return null;
   if(!Number.isSafeInteger(tx.slot) || tx.slot<1 || tx.meta===null || typeof tx.meta!=='object' || !Object.hasOwn(tx.meta,'err'))fail('LIVE_UNAVAILABLE');
   return {signature:candidate,slot:tx.slot as number,err:tx.meta.err as unknown};
  };
  const hint=this.#rfqHints.get(order.id);
  if(hint!==undefined){const found=await owns(hint);if(found)return found;}
  const since=Math.floor(Date.parse(order.review.reviewedAt)/1000)-60;
  const recent=await this.rpc('getSignaturesForAddress',[order.wallet,{limit:25,commitment:'confirmed'}]);
  if(!Array.isArray(recent))fail('LIVE_UNAVAILABLE');
  for(const entry of recent) {
   if(typeof entry?.signature!=='string' || !TRANSACTION_SIGNATURE.test(entry.signature))continue;
   if(Number.isSafeInteger(entry.blockTime) && entry.blockTime<since)break;
   const found=await owns(entry.signature);
   if(found)return found;
  }
  return null;
 }
 private async rfqStatus(user:string,order:LiveOrder):Promise<LiveOrder> {
  const found=await this.rfqTransaction(order);
  if(found) {
   if(found.err!==null && !reportedTransactionError(found.err))fail('LIVE_UNAVAILABLE');
   const settled=this.#alertSettled(order,await this.options.store.resolve(user,order.id,found.err===null?'confirmed':'failed',found.slot));
   if(settled.status==='confirmed')await this.#recordFill(user,order,found.signature);
   return {...settled,confirmedSlot:found.slot};
  }
  // Same rule as aggregator orders: finalized and confirmed heights past the
  // blockhash bound, then a fresh search, before declaring no execution.
  const chain=await this.chain();
  const finalized=await this.rpc('getBlockHeight',[{commitment:'finalized'}]);
  const bound=BigInt(order.review.evidence.lastValidBlockHeight);
  if(Number.isSafeInteger(finalized) && BigInt(finalized)>bound && BigInt(chain.blockHeight)>bound && await this.rfqTransaction(order)===null) {
   return this.#alertSettled(order,await this.options.store.resolve(user,order.id,'expired'));
  }
  return order;
 }
 /**
  * Records what a confirmed order actually moved. Best effort: history shows the
  * reviewed quote until a fill is recorded, and a database without migration 0033
  * simply records nothing.
  */
 async #recordFill(user:string,order:LiveOrder,transaction:string):Promise<void> {
  if(!this.options.store.recordFill)return;
  try {
   const tx=await this.rpc('getTransaction',[transaction,{commitment:'confirmed',maxSupportedTransactionVersion:0,encoding:'json'}]);
   const fill=orderFill(tx?.meta,order.wallet,order.review.terms.inputMint,order.review.terms.outputMint);
   if(fill)await this.options.store.recordFill(user,order.id,fill.inputRaw,fill.outputRaw);
  }catch{/* The fill can be recorded on a later read of this order. */}
 }
 /** Tells the operator when a signed order failed on chain or was never executed. */
 #alertSettled(order:LiveOrder,settled:LiveOrder):LiveOrder {
  if(settled.status==='failed'||settled.status==='expired') {
   const token=findStockTradingAssetByMint(order.review.terms?.side==='sell'?order.review.terms?.inputMint:order.review.terms?.outputMint);
   this.options.alerts?.notify(settled.status==='failed'?'order_failed':'order_not_executed',
    `order ${order.id}, ${token?.symbol??'unknown token'} (${token?.issuerId??'unknown issuer'}), ${order.review.terms?.route??'aggregator'} route`);
  }
  return settled;
 }
}
const TRANSACTION_SIGNATURE=/^[1-9A-HJ-NP-Za-km-z]{64,88}$/;

export interface LiveStockAdapters {
 /** Disable new financial requests without hiding settlement of existing orders. */
 readonly executionEnabled?:boolean;
 authenticate(request:FastifyRequest):Promise<ExistingPracticeAccountAuthentication|null>;
 identities:{resolveFresh(identity:PracticeIdentity):Promise<PrivyLinkedIdentityResolution>};
 service:LiveStockOrders;
 /** Live market states for capabilities; the calendar alone without them. */
 marketStates?:StockMarketStates;
 /** Tokens found automatically, and why others were refused. */
 directory?:StockTokenDirectory;
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
   const known=['ACCOUNT_REQUIRED','WALLET_REQUIRED','ORDER_PENDING','QUOTE_EXPIRED','INVALID_REVIEW','INVALID_SIGNATURE','ADD_USDC','ADD_SOL','INSUFFICIENT_HOLDINGS','NO_ROUTE','FEE_TOO_HIGH','LIVE_BUSY','TRADE_LIMIT','TERMS_REQUIRED','MARKET_CLOSED','BELOW_MINIMUM','PRICE_OFF_MARKET','MARKET_INPUT_INVALID'];
   // Log only bounded internal reason codes, never provider payloads, tokens or signed transactions.
   const detail=error instanceof Error && 'code' in error ? error.code : null;
   const reviewCode=typeof detail==='string' && /^(?:STOCK_DRAFT|LOOKUP|LIFETIME|SEMANTICS|RECONCILIATION|SIMULATION|REVIEW)_[A-Z_]{1,64}$/.test(detail)?detail:null;
   request.log.warn({tradeFailure:reviewCode??(known.includes(code)?code:'LIVE_UNAVAILABLE')},'Live stock request failed');
   // Each user may request one quote every 3 seconds.
   if(code==='LIVE_BUSY')reply.header('retry-after','3');
   return reply.code(code==='ACCOUNT_REQUIRED'?401:code==='MARKET_INPUT_INVALID'?400:code==='LIVE_BUSY'?429:known.includes(code)?409:503).send({code:known.includes(code)?code:'LIVE_UNAVAILABLE'});
  }
 }
 // schema=3 lists every tradeable token; schema=2 keeps installed apps' limit of 600.
 app.get<{Querystring:{schema?:'2'|'3'}}>('/v1/trading/capabilities',{schema:{querystring:{type:'object',additionalProperties:false,properties:{schema:{enum:['2','3']}}}}},async request=>{
  const common={enabled:liveStockExecutionEnabled(adapters),network:'solana:mainnet-beta',maxBuyUsdc:'100',minimumSolBalanceLamports:String(LIVE_STOCK_MIN_SOL_LAMPORTS)};
  if(request.query.schema===undefined) {
   // Installed clients reject more than 128 assets, only know the original
   // issuer's disclosure and sign single-signer transactions only. Keep their
   // contract exactly: active xStocks on the aggregator route.
   const legacy=STOCK_TRADING_ASSETS.filter(asset=>asset.issuerId===LEGACY_STOCK_ISSUER && asset.route==='aggregator').slice(0,120);
   return {...common,assets:legacy.map(({assetId,mint,symbol,name,decimals,maxBuyInputRaw,maxSellInputRaw,installedAppSellCapRaw})=>
    ({assetId,mint,symbol,name,decimals,maxBuyInputRaw,maxSellInputRaw:installedAppSellCapRaw??maxSellInputRaw}))};
  }
  const now=Date.now();
  const stateOf=await marketStatesNow(adapters?.marketStates,now);
  const moment=usMarketMoment(now);
  return {schemaVersion:2,...common,issuers:stockIssuerCapabilities(),
   // The US session in force, for context: most tokens trade around the clock regardless.
   usMarket:{session:moment.session,between:moment.gap,changesAt:new Date(moment.changesAt).toISOString()},
   assets:(request.query.schema==='3'?stockTradingAssets():stockTradingAssets().slice(0,600)).map(({assetId,mint,symbol,name,issuerId,decimals,maxBuyInputRaw,maxSellInputRaw,installedAppSellCapRaw,transferFeeBps,route})=>
    ({assetId,mint,symbol,name,issuerId,decimals,maxBuyInputRaw,
     // Schema 3 apps show no sell cap; older apps keep the limit line they display.
     maxSellInputRaw:request.query.schema==='3'?maxSellInputRaw:installedAppSellCapRaw??maxSellInputRaw,transferFeeBps,route,
     // Market makers need at least $1 after fees; $2 leaves room for the fee and price moves.
     minBuyInputRaw:route==='rfq'?'2000000':'1',
     market:stateOf(issuerId,symbol,mint)})),
   // Market variants that cannot be traded, with the reason to show instead of a buy button.
   unavailable:unavailableVariantsNow(adapters?.directory?.refusals()??[])};
 });
 app.get<{Params:{id:string}}>('/v1/trading/order/:id',{schema:{querystring:noQuery,params:{type:'object',additionalProperties:false,required:['id'],properties:{id:{type:'string',format:'uuid'}}}}},(request,reply)=>run(request,reply,user=>adapters!.service.status(user,request.params.id)));
 app.get('/v1/trading/order',{schema:{querystring:noQuery}},(request,reply)=>run(request,reply,user=>adapters!.service.status(user)));
 app.post<{Body:StockEstimateInput&{termsAccepted?:StockTermsAcceptance}}>('/v1/trading/preview',{bodyLimit:2048,schema:{querystring:noQuery,body:{type:'object',additionalProperties:false,required:['assetId','variantMint','side','amountRaw'],properties:{assetId:{type:'string',maxLength:100,pattern:STOCK_ASSET_ID_PATTERN.source},variantMint:{type:'string',pattern:STOCK_MINT_PATTERN.source},side:{enum:['buy','sell']},amountRaw:{type:'string',pattern:'^[1-9][0-9]{0,19}$'},
   termsAccepted:{type:'object',additionalProperties:false,required:['issuerId','version'],properties:{issuerId:{enum:[...STOCK_ISSUER_IDS]},version:{type:'string',pattern:'^[0-9]{4}-[0-9]{2}-[0-9]{2}$'}}}}}}},(request,reply)=>run(request,reply,(user,wallet)=>adapters!.service.preview(user,wallet,request.body),true));
 app.post<{Body:{id:string;reviewDigest:string;signedTransaction:string}}>('/v1/trading/execute',{bodyLimit:4096,schema:{querystring:noQuery,body:{type:'object',additionalProperties:false,required:['id','reviewDigest','signedTransaction'],properties:{id:{type:'string',format:'uuid'},reviewDigest:{type:'string',pattern:'^[0-9a-f]{64}$'},signedTransaction:{type:'string',minLength:88,maxLength:1644,pattern:'^[A-Za-z0-9+/]+={0,2}$'}}}}},(request,reply)=>run(request,reply,(user,wallet)=>adapters!.service.execute(user,wallet,request.body.id,request.body.reviewDigest,request.body.signedTransaction),true));
}
