import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import Fastify from 'fastify';
import {buildApp} from '../src/app.js';
import {registerReminderRoutes, reminderAuthenticator, REMINDER_PREFERENCES_ROUTE as url, type ReminderAdapters} from '../src/reminder-preferences.js';
import {GuestSessionError, type GuestSessionRepository} from '../src/guest-session-repository.js';
const empty={schemaVersion:1 as const,revision:0,frequency:null,claimedGuestId:null};
const input={mutationId:randomUUID(),baseRevision:0,frequency:'daily' as const};
test('reminder routes validate writes and preserve version conflicts without disclosing storage errors',async()=>{
 let calls=0, conflict=false, failure=false;
 const app=Fastify({ajv:{customOptions:{removeAdditional:false}}});
 registerReminderRoutes(app,{authenticate:async r=>r.headers.authorization?{userId:'verified-user'}:null,store:{
  get:async p=>{calls++;assert.equal(p.userId,'verified-user');if(failure)throw Error('SECRET_DATABASE_DETAIL');return empty;},
  put:async(p,w)=>{calls++;assert.equal(p.userId,'verified-user');assert.deepEqual(w,input);return {...empty,revision:1,frequency:'off',conflict};},
 }});
 try {
  assert.equal((await app.inject({method:'GET',url})).statusCode,401);
  assert.equal(calls,0);
  const headers={authorization:'Bearer verified'};
  const get=await app.inject({method:'GET',url,headers});assert.equal(get.statusCode,200);assert.equal(get.headers['cache-control'],'no-store');assert.deepEqual(get.json(),empty);
  for(const payload of [{...input,frequency:'weekly'},{...input,baseRevision:-1},{...input,baseRevision:9007199254740991},{...input,mutationId:'bad'},{...input,userId:'someone-else'}]){
   assert.equal((await app.inject({method:'PUT',url,headers,payload})).statusCode,400);
  }
  assert.equal((await app.inject({method:'GET',url:url+'?userId=other',headers})).statusCode,400);assert.equal(calls,1);
  assert.equal((await app.inject({method:'PUT',url,headers,payload:input})).statusCode,200);
  conflict=true;assert.equal((await app.inject({method:'PUT',url,headers,payload:input})).statusCode,409);
  failure=true;const failed=await app.inject({method:'GET',url,headers});assert.equal(failed.statusCode,503);assert.ok(!failed.body.includes('SECRET'));
 }finally {await app.close();}
});
test('unconfigured and expired guest preferences fail closed; rate limits remain actionable',async()=>{
 const missing=Fastify();registerReminderRoutes(missing);
 assert.equal((await missing.inject({method:'GET',url})).statusCode,503);await missing.close();
 for(const [code,status] of [['GUEST_SESSION_EXPIRED',401],['GUEST_SESSION_REVOKED',401],['GUEST_SESSION_UNAUTHENTICATED',401],['GUEST_SESSION_RATE_LIMITED',429],['GUEST_SESSION_UNAVAILABLE',503]] as const){
  const app=Fastify();registerReminderRoutes(app,{authenticate:async()=>{throw new GuestSessionError(code,'private detail',25);},store:{get:async()=>{throw Error('must not reach');},put:async()=>{throw Error('must not reach');}}});
  const result=await app.inject({method:'GET',url});assert.equal(result.statusCode,status);assert.ok(!result.body.includes('private'));
  if(status===429)assert.equal(result.headers['retry-after'],'25');await app.close();
 }
});
test('guest authentication hashes the credential and only authorizes this route and method',async()=>{
 let scope='',hash='',accounts=0;
 const guests={authorize:async(h:string,s:string)=>{hash=h;scope=s;return {userId:'guest-user',guestId:'guest-id',expiresAt:''};}} as GuestSessionRepository;
 const authenticate=reminderAuthenticator(async()=>{accounts++;return {userId:'account'};},guests);
 const app=Fastify();registerReminderRoutes(app,{authenticate,store:{get:async p=>{assert.equal(p.guestId,'guest-id');return empty;},put:async()=>({...empty,revision:1,frequency:'daily',conflict:false})}});
 try {
  // Actual credential syntax used by the guest session API.
  const token='tg1_'+'a'.repeat(43);
  const get=await app.inject({method:'GET',url,headers:{authorization:'Guest '+token}});
  assert.equal(get.statusCode,200);assert.equal(scope,'profile_read');assert.match(hash,/^[a-f0-9]{64}$/);assert.notEqual(hash,token);
  assert.equal((await app.inject({method:'PUT',url,headers:{authorization:'Guest '+token},payload:input})).statusCode,200);assert.equal(scope,'profile_write');assert.equal(accounts,0);
  const request={method:'POST',routeOptions:{url},raw:{rawHeaders:['authorization','Guest '+token]},headers:{authorization:'Guest '+token}} as Parameters<ReminderAdapters['authenticate']>[0];
  assert.equal(await authenticate(request),null);
  assert.deepEqual(await authenticate({...request,headers:{authorization:'Bearer abc.def.ghi'}}),{userId:'account'});assert.equal(accounts,1);
 }finally {await app.close();}
});

test('the production app allows reminder consent writes independently of money capability',async()=>{
 const app=buildApp({logger:false,reminders:{authenticate:async()=>({userId:'viewer'}),store:{
  get:async()=>empty,put:async()=>({...empty,revision:1,frequency:'off',conflict:false}),
 }}});
 try {
  const saved=await app.inject({method:'PUT',url,payload:input});
  assert.equal(saved.statusCode,200,saved.body);
  for(const method of ['POST','DELETE','PATCH'] as const){
   const refused=await app.inject({method,url});assert.equal(refused.statusCode,503);assert.equal(refused.json().error.code,'FINANCIAL_OPERATIONS_DISABLED');
  }
 }finally {await app.close();}
});
