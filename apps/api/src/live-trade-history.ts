import type {FastifyInstance, FastifyRequest} from 'fastify';
import type {Pool} from 'pg';
import {JUPITER_QUOTE_ASSETS} from './jupiter-quote-reader.js';
import {findStockTradingAssetByMint} from './stock-trading-catalog.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const BASE58 = /^[1-9A-HJ-NP-Za-km-z]+$/;
const U64_MAX = 18_446_744_073_709_551_615n;
export interface LiveHistoryPosition {readonly createdAt:string; readonly id:string}
export interface LiveTradeHistoryRepository {
  /** Returns at most limit + 1 account-owned rows, newest first. No settlement writes. */
  list(userId:string, limit:number, before?:LiveHistoryPosition):Promise<readonly unknown[]>;
}
export interface LiveTradeHistoryAdapters {
  authenticate(request:FastifyRequest):Promise<{userId:string}|null>;
  repository:LiveTradeHistoryRepository;
}
class HistoryError extends Error {
  constructor(readonly code:'INVALID_REQUEST'|'HISTORY_UNAVAILABLE'){super(code);}
}
function invalid():never {throw new HistoryError('INVALID_REQUEST');}
function unavailable():never {throw new HistoryError('HISTORY_UNAVAILABLE');}
function record(value:unknown):Record<string,unknown> {
  if(!value || typeof value!=='object' || Array.isArray(value))return unavailable();
  return value as Record<string,unknown>;
}
function timestamp(value:unknown):value is string {
  if(typeof value!=='string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(value))return false;
  const milliseconds=Date.parse(value);
  return Number.isFinite(milliseconds) && new Date(milliseconds).toISOString().slice(0,19)===value.slice(0,19);
}
function amount(value:unknown):string {
  if(typeof value!=='string' || !/^[1-9][0-9]{0,19}$/.test(value) || BigInt(value)>U64_MAX)return unavailable();
  return value;
}
function parseCursor(raw:unknown,userId:string):LiveHistoryPosition|undefined {
  if(raw===undefined)return undefined;
  if(typeof raw!=='string' || raw.length>512 || !/^[A-Za-z0-9_-]+$/.test(raw))return invalid();
  try {
    const decoded=Buffer.from(raw,'base64url');
    if(decoded.toString('base64url')!==raw)return invalid();
    const value:unknown=JSON.parse(decoded.toString('utf8'));
    if(!Array.isArray(value) || value.length!==4 || value[0]!==1 || value[1]!==userId ||
      !timestamp(value[2]) || typeof value[3]!=='string' || !UUID.test(value[3]))return invalid();
    return {createdAt:value[2],id:value[3]};
  }catch{return invalid();}
}
function cursor(userId:string,position:LiveHistoryPosition):string {
  return Buffer.from(JSON.stringify([1,userId,position.createdAt,position.id])).toString('base64url');
}
function project(value:unknown) {
  const row=record(value),terms=record(row['terms']);
  const {id,wallet,status,signature,createdAt,updatedAt}=row;
  if(typeof id!=='string' || !UUID.test(id) || typeof wallet!=='string' || wallet.length<32 || wallet.length>44 || !BASE58.test(wallet) ||
    typeof signature!=='string' || signature.length<64 || signature.length>88 || !BASE58.test(signature) ||
    typeof status!=='string' || !['pending','confirmed','failed','expired'].includes(status) || !timestamp(createdAt) || !timestamp(updatedAt))return unavailable();
  const side=terms['side'];
  if(side!=='buy' && side!=='sell')return unavailable();
  const inputMint=terms['inputMint'],outputMint=terms['outputMint'];
  // Preserve historical identities if execution eligibility is narrowed later;
  // deleting a catalog identity must first migrate history metadata separately.
  const asset=findStockTradingAssetByMint(side==='buy'?outputMint:inputMint);
  if(!asset || (side==='buy'?inputMint:outputMint)!==JUPITER_QUOTE_ASSETS.USDC.mint)return unavailable();
  const inputAmountRaw=amount(terms['inputAmountRaw']);
  const quotedOutputAmountRaw=amount(terms['quotedOutputAmountRaw']);
  const minimumOutputAmountRaw=amount(terms['minimumOutputAmountRaw']);
  if(BigInt(minimumOutputAmountRaw)>BigInt(quotedOutputAmountRaw))return unavailable();
  return {
    id,wallet,status:status as 'pending'|'confirmed'|'failed'|'expired',signature,createdAt,updatedAt,
    asset:{assetId:asset.assetId,mint:asset.mint,symbol:asset.symbol,name:asset.name,decimals:asset.decimals},
    terms:{side,inputMint:inputMint as string,outputMint:outputMint as string,inputAmountRaw,quotedOutputAmountRaw,minimumOutputAmountRaw},
    amountUnits:'raw_token_units' as const,amountsStatus:'reviewed_quote' as const,
  };
}
export class PostgresLiveTradeHistory implements LiveTradeHistoryRepository {
  constructor(private readonly pool:Pool){}
  async list(userId:string,limit:number,before?:LiveHistoryPosition):Promise<readonly unknown[]> {
    const client=await this.pool.connect();
    try {
      await client.query('BEGIN READ ONLY');
      await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[userId]);
      const result=await client.query('SELECT trimmy.live_order_history($1,$2,$3,$4) AS value',
        [userId,limit,before?.createdAt??null,before?.id??null]);
      const rows:unknown=result.rows[0]?.value;
      if(!Array.isArray(rows) || rows.length>limit+1)unavailable();
      await client.query('COMMIT');
      return rows as unknown[];
    }catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}
  }
}
export function registerLiveTradeHistoryRoute(app:FastifyInstance,adapters?:LiveTradeHistoryAdapters):void {
  app.get('/v1/trading/history',async(request,reply)=>{
    reply.header('cache-control','no-store');
    if(!adapters)return reply.code(503).send({code:'HISTORY_UNAVAILABLE'});
    try {
      const account=await adapters.authenticate(request);
      if(!account)return reply.code(401).send({code:'ACCOUNT_REQUIRED'});
      if(!UUID.test(account.userId))return unavailable();
      const query=request.query as Record<string,unknown>;
      if(Object.keys(query).some(key=>key!=='limit' && key!=='cursor'))return invalid();
      const rawLimit=query['limit'];
      if(rawLimit!==undefined && (typeof rawLimit!=='string' || !/^[1-9][0-9]?$/.test(rawLimit)))return invalid();
      const limit=rawLimit===undefined?20:Number(rawLimit);
      if(limit>50)return invalid();
      const before=parseCursor(query['cursor'],account.userId);
      const rows=await adapters.repository.list(account.userId,limit,before);
      if(!Array.isArray(rows) || rows.length>limit+1)return unavailable();
      const projected=rows.map(project);
      let previous=before;
      for(const row of projected){
        if(previous && (row.createdAt>previous.createdAt || row.createdAt===previous.createdAt && row.id>=previous.id))return unavailable();
        previous=row;
      }
      const orders=projected.slice(0,limit);
      const last=orders.at(-1);
      return {schemaVersion:1,network:'solana:mainnet-beta',orders,
        nextCursor:projected.length>limit && last?cursor(account.userId,last):null};
    }catch(error){
      if(error instanceof HistoryError)return reply.code(error.code==='INVALID_REQUEST'?400:503).send({code:error.code});
      if(error instanceof Error && error.message==='ACCOUNT_REQUIRED')return reply.code(401).send({code:'ACCOUNT_REQUIRED'});
      request.log.warn({historyFailure:'HISTORY_UNAVAILABLE'},'Trade history request failed');
      return reply.code(503).send({code:'HISTORY_UNAVAILABLE'});
    }
  });
}
