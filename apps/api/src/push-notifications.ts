import {createPrivateKey, randomUUID, sign} from 'node:crypto';
import type {FastifyInstance, FastifyRequest} from 'fastify';
import type {Pool} from 'pg';

export interface PushJob {id:string; deviceId:string; userId:string; orderId:string; status:'confirmed'|'failed'|'expired'}
export type PushOutcome='sent'|'retry'|'invalid_token'|'drop';
export interface PushStore {
 register(user:string,installation:string,token:string,platform:'android'|'ios'):Promise<void>;
 remove(user:string,installation:string):Promise<void>;
 claim(worker:string):Promise<PushJob[]>;
 target(job:string,worker:string):Promise<string|null>;
 finish(job:string,worker:string,outcome:PushOutcome):Promise<void>;
}
export function postgresPush(pool:Pool):PushStore {
 async function scoped(user:string,sql:string,values:unknown[]) {
  const client=await pool.connect();
  try {await client.query('BEGIN');await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[user]);
   await client.query(sql,values);await client.query('COMMIT');
  }catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}
 }
 return {
  register:(user,id,token,platform)=>scoped(user,'SELECT trimmy.push_device_set($1,$2,$3,$4)',[user,id,token,platform]),
  remove:(user,id)=>scoped(user,'SELECT trimmy.push_device_remove($1,$2)',[user,id]),
  claim:async worker=>(await pool.query('SELECT trimmy.trade_push_claim($1,5) AS jobs',[worker])).rows[0].jobs,
  target:async(id,worker)=>(await pool.query('SELECT trimmy.trade_push_target($1,$2) AS token',[id,worker])).rows[0].token,
  finish:async(id,worker,outcome)=>{await pool.query('SELECT trimmy.trade_push_finish($1,$2,$3)',[id,worker,outcome]);},
 };
}
export interface PushAdapters {
 authenticate(request:FastifyRequest):Promise<{userId:string}|null>;
 store:PushStore;
 /** iOS is exposed only after APNs is configured and validated. */
 platforms:readonly ('android'|'ios')[];
}
export function registerPushRoutes(app:FastifyInstance,adapters?:PushAdapters) {
 app.get('/v1/notifications/capabilities',async(_request,reply)=>{
  reply.header('cache-control','no-store');return {tradePush:adapters!==undefined,platforms:adapters?.platforms??[]};
 });
 const params={type:'object',required:['installationId'],additionalProperties:false,properties:{installationId:{type:'string',format:'uuid'}}};
 app.put<{Params:{installationId:string};Body:{token:string;platform:'android'|'ios'}}>('/v1/notifications/devices/:installationId',{
  schema:{params,body:{type:'object',required:['token','platform'],additionalProperties:false,properties:{
   token:{type:'string',pattern:'^[A-Za-z0-9:_-]{20,4096}$'},platform:{type:'string',enum:['android','ios']}}}},
 },async(request,reply)=>{
  reply.header('cache-control','no-store');
  if(!adapters)return reply.code(503).send({code:'PUSH_UNAVAILABLE'});
  try {
   const account=await adapters.authenticate(request);if(!account)return reply.code(401).send({code:'ACCOUNT_REQUIRED'});
   if(!adapters.platforms.includes(request.body.platform))return reply.code(409).send({code:'PLATFORM_UNAVAILABLE'});
   await adapters.store.register(account.userId,request.params.installationId,request.body.token,request.body.platform);
   return {enabled:true};
  }catch{return reply.code(503).send({code:'PUSH_UNAVAILABLE'});}
 });
 app.delete<{Params:{installationId:string}}>('/v1/notifications/devices/:installationId',{schema:{params}},async(request,reply)=>{
  reply.header('cache-control','no-store');if(!adapters)return reply.code(503).send({code:'PUSH_UNAVAILABLE'});
  try {
   const account=await adapters.authenticate(request);if(!account)return reply.code(401).send({code:'ACCOUNT_REQUIRED'});
   await adapters.store.remove(account.userId,request.params.installationId);return {enabled:false};
  }catch{return reply.code(503).send({code:'PUSH_UNAVAILABLE'});}
 });
}

/** Keep iOS opt-in at deployment until device delivery has been verified. */
export function readPushPlatforms(env:Readonly<Record<string,string|undefined>>):readonly ('android'|'ios')[] {
 const raw=env['TRIMMY_PUSH_PLATFORMS'];
 if(raw===undefined)return ['android'];
 if(raw==='')return [];
 const platforms=raw.split(',').map(value=>value.trim());
 if(new Set(platforms).size!==platforms.length || platforms.some(value=>value!=='android' && value!=='ios'))throw Error('Push platform configuration is invalid.');
 return platforms as ('android'|'ios')[];
}

interface ServiceAccount {project_id:string;client_email:string;private_key:string}
export function readPushConfig(env:Readonly<Record<string,string|undefined>>):ServiceAccount|null {
 const raw=env['TRIMMY_PUSH_SERVICE_ACCOUNT_JSON'];if(!raw)return null;
 if(raw.length>32_768)throw Error('Push service account configuration is invalid.');
 try {
  const value=JSON.parse(raw) as ServiceAccount;
  if(!/^[a-z][a-z0-9-]{5,62}$/.test(value.project_id) || !value.client_email.endsWith(`@${value.project_id}.iam.gserviceaccount.com`) ||
   createPrivateKey(value.private_key).asymmetricKeyType!=='rsa')throw Error();
  return {project_id:value.project_id,client_email:value.client_email,private_key:value.private_key};
 }catch{throw Error('Push service account configuration is invalid.');}
}
/** Provider acceptance is not proof that a notification appeared on a phone. */
export class FcmPushSender {
 #access:{token:string;until:number}|null=null;
 constructor(private readonly account:ServiceAccount,private readonly fetcher:typeof fetch=fetch,private readonly now:()=>number=Date.now){}
 async #json(url:string,init:RequestInit) {
  const response=await this.fetcher(url,{...init,redirect:'error',signal:AbortSignal.timeout(10_000)});
  const reader=response.body?.getReader();if(!reader)throw Error('PUSH_RESPONSE_INVALID');
  const chunks:Uint8Array[]=[];let size=0;
  try {for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;
   if(size>32_768)throw Error('PUSH_RESPONSE_INVALID');chunks.push(value);}}
  finally {await reader.cancel();}
  return {ok:response.ok,status:response.status,body:JSON.parse(Buffer.concat(chunks).toString('utf8'))};
 }
 async #bearer() {
  if(this.#access && this.#access.until>this.now())return this.#access.token;
  const iat=Math.floor(this.now()/1000),encode=(v:unknown)=>Buffer.from(JSON.stringify(v)).toString('base64url');
  const claims=`${encode({alg:'RS256',typ:'JWT'})}.${encode({iss:this.account.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat,exp:iat+3600})}`;
  const assertion=claims+'.'+sign('RSA-SHA256',Buffer.from(claims),this.account.private_key).toString('base64url');
  const result=await this.#json('https://oauth2.googleapis.com/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},
   body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}).toString()});
  if(!result.ok || typeof result.body.access_token!=='string' || !Number.isFinite(result.body.expires_in) || result.body.expires_in<60)throw Error('PUSH_AUTH_UNAVAILABLE');
  this.#access={token:result.body.access_token,until:this.now()+Math.min(result.body.expires_in-30,3500)*1000};return this.#access.token;
 }
 async send(job:PushJob,token:string,validateOnly=false):Promise<PushOutcome> {
  try {
   const result=await this.#json(`https://fcm.googleapis.com/v1/projects/${this.account.project_id}/messages:send`,{
    method:'POST',headers:{authorization:`Bearer ${await this.#bearer()}`,'content-type':'application/json'},
    body:JSON.stringify({validate_only:validateOnly,message:{token,
     notification:{title:'Trimmy',body:job.status==='confirmed'?'Your trade is confirmed. Open Trimmy for details.':job.status==='failed'?'Your trade did not complete. Open Trimmy for details.':'Your trade expired. Open Trimmy for details.'},
     data:{kind:'trade_update',accountId:job.userId,orderId:job.orderId,notificationId:job.id},
     android:{ttl:'86400s',collapse_key:'trade_updates',notification:{tag:job.id,channel_id:'trimmy_trade_updates',icon:'ic_stat_trimmy'}},
     apns:{headers:{'apns-collapse-id':job.id,'apns-expiration':String(Math.floor(this.now()/1000)+86400)},payload:{aps:{sound:'default'}}},
    }}),
   });
   if(result.ok && typeof result.body.name==='string')return 'sent';
   if(result.status===401)this.#access=null;
   const details=result.body?.error?.details;
   if(Array.isArray(details) && details.some(d=>d?.['@type']==='type.googleapis.com/google.firebase.fcm.v1.FcmError' && d.errorCode==='UNREGISTERED'))return 'invalid_token';
   if(result.status===400 || result.status===403 || result.status===404)return 'drop';
   return 'retry';
  }catch{return 'retry';}
 }
}
export class TradePushWorker {
 #active:Promise<void>|null=null; #timer:ReturnType<typeof setTimeout>|null=null; #stopped=true;
 constructor(private readonly store:PushStore,private readonly sender:Pick<FcmPushSender,'send'>,private readonly onError:()=>void=()=>{}){}
 start(){if(!this.#stopped)return;this.#stopped=false;this.#schedule(0);}
 #schedule(ms=15_000){if(!this.#stopped)this.#timer=setTimeout(()=>{void this.tick().finally(()=>this.#schedule());},ms);}
 tick():Promise<void>{
  if(this.#active)return this.#active;
  this.#active=this.#run().catch(()=>this.onError()).finally(()=>{this.#active=null;});return this.#active;
 }
 async #run(){
  const worker=randomUUID();
  for(const job of await this.store.claim(worker)) {
   const token=await this.store.target(job.id,worker);
   const outcome=token ? await this.sender.send(job,token) : 'drop';
   await this.store.finish(job.id,worker,outcome);
   if(outcome==='retry' || (token && outcome==='drop'))this.onError();
  }
 }
 async stop(){this.#stopped=true;if(this.#timer)clearTimeout(this.#timer);await this.#active;}
}
