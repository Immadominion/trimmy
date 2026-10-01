import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,createPublicKey,verify} from 'node:crypto';
import {buildApp} from '../src/app.js';
import {FcmPushSender,readPushConfig,readPushPlatforms,TRADE_PUSH_COPY,TradePushWorker,type PushStore,type PushJob} from '../src/push-notifications.js';
import {OrderRecoveryWorker} from '../src/order-recovery-worker.js';
const device='cf350000-0000-4000-a000-000000000001';
const job:PushJob={id:device,deviceId:device,userId:'user',orderId:'order',status:'confirmed'};
function store():PushStore {return {register:async()=>{},remove:async()=>{},claim:async()=>[job],target:async()=> 'device-token',finish:async()=>{}};}
const {privateKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const credentials={project_id:'trimmy-test',client_email:'push@trimmy-test.iam.gserviceaccount.com',private_key:privateKey.export({format:'pem',type:'pkcs8'}).toString()};

test('capability stays off without delivery; registration is account-bound and validated',async()=>{
 const off=buildApp({logger:false});assert.deepEqual((await off.inject('/v1/notifications/capabilities')).json(),{tradePush:false,platforms:[]});await off.close();
 const calls:unknown[]=[];const s=store();s.register=async(...args)=>{calls.push(args);};s.remove=async(...args)=>{calls.push(args);};
 const app=buildApp({logger:false,push:{platforms:['android'],store:s,authenticate:async req=>req.headers.authorization==='Bearer valid'?{userId:'verified-user'}:null}});
 const url=`/v1/notifications/devices/${device}`,payload={token:'a'.repeat(24),platform:'android'},headers={authorization:'Bearer valid'};
 assert.equal((await app.inject({method:'PUT',url,payload})).statusCode,401);
 assert.equal((await app.inject({method:'PUT',url,headers,payload:{...payload,userId:'someone'}})).statusCode,400);
 assert.equal((await app.inject({method:'PUT',url,headers,payload:{...payload,token:'bad token'}})).statusCode,400);
 assert.equal((await app.inject({method:'PUT',url,headers,payload:{...payload,platform:'ios'}})).statusCode,409);
 assert.equal((await app.inject({method:'PUT',url,headers,payload})).statusCode,200);
 assert.equal((await app.inject({method:'DELETE',url,headers})).statusCode,200);
 assert.deepEqual(calls,[['verified-user',device,payload.token,'android'],['verified-user',device]]);await app.close();
});
test('configuration fails safely without printing a private key',()=>{
 assert.equal(readPushConfig({}),null);
 assert.throws(()=>readPushConfig({TRIMMY_PUSH_SERVICE_ACCOUNT_JSON:'secret-value'}),/^Error: Push service account configuration is invalid\.$/);
 assert.deepEqual(readPushConfig({TRIMMY_PUSH_SERVICE_ACCOUNT_JSON:JSON.stringify(credentials)}),credentials);
 assert.throws(()=>readPushConfig({TRIMMY_PUSH_SERVICE_ACCOUNT_JSON:JSON.stringify({...credentials,client_email:'someone@else.iam.gserviceaccount.com'})}));
});
test('FCM uses a signed short-lived assertion, generic copy, account-bound route and cached OAuth',async()=>{
 let oauth=0,sends=0;
 const sender=new FcmPushSender(credentials,async(url,init)=>{
  if(String(url).includes('oauth2')) {
   oauth++;const assertion=new URLSearchParams(String(init?.body)).get('assertion')!;
   const [header,claims,signature]=assertion.split('.');
   assert(verify('RSA-SHA256',Buffer.from(`${header}.${claims}`),createPublicKey(privateKey),Buffer.from(signature!,'base64url')));
   const body=JSON.parse(Buffer.from(claims!,'base64url').toString());assert.equal(body.exp-body.iat,3600);
   assert.equal(body.scope,'https://www.googleapis.com/auth/firebase.messaging');
   return Response.json({access_token:'access-token',expires_in:3600});
  }
  sends++;assert.equal(String(url),'https://fcm.googleapis.com/v1/projects/trimmy-test/messages:send');
  const body=JSON.parse(String(init?.body));assert.equal(body.message.token,'device-token');
  assert.deepEqual(body.message.data,{kind:'trade_update',accountId:'user',orderId:'order',notificationId:device});
  assert.equal(body.message.notification.body,'Your trade is confirmed. Open Trimmy for details.');
  assert.equal(body.message.android.notification.tag,device);assert.equal(body.validate_only,true);
  return Response.json({name:'projects/trimmy-test/messages/accepted'});
 });
 assert.equal(await sender.send(job,'device-token',true),'sent');assert.equal(await sender.send(job,'device-token',true),'sent');
 assert.equal(oauth,1);assert.equal(sends,2);
});
test('only typed UNREGISTERED removes a token; other malformed requests are dropped',async()=>{
 for(const [body,expected] of [
  [{error:{status:'INVALID_ARGUMENT'}},'drop'],[{error:{status:'UNAUTHENTICATED'}},'drop'],
  [{error:{details:[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:'UNREGISTERED'}]}},'invalid_token'],
  [{error:{details:[{errorCode:'UNREGISTERED'}]}},'drop'],
 ] as const){
  const sender=new FcmPushSender(credentials,async url=>String(url).includes('oauth2')?Response.json({access_token:'a',expires_in:3600}):Response.json(body,{status:400}));
  assert.equal(await sender.send(job,'device-token'),expected);
 }
 const sender=new FcmPushSender(credentials,async()=>{throw Error('sensitive-provider-error');});assert.equal(await sender.send(job,'device-token'),'retry');
});
test('worker checks opt-out at delivery time and serializes concurrent ticks',async()=>{
 const s=store();let claims=0,sends=0;const outcomes:string[]=[];
 let release!:()=>void;const gate=new Promise<void>(resolve=>{release=resolve;});
 s.claim=async()=>{claims++;await gate;return [job];};s.target=async()=>null;s.finish=async(_id,_worker,outcome)=>{outcomes.push(outcome);};
 const worker=new TradePushWorker(s,{send:async()=>{sends++;return 'sent';}});
 const a=worker.tick(),b=worker.tick();assert.equal(a,b);release();await a;
 assert.equal(claims,1);assert.equal(sends,0);assert.deepEqual(outcomes,['drop']);await worker.stop();
});
test('crashed delivery remains leased for retry; failures expose no provider payload',async()=>{
 const s=store();s.target=async()=>{throw Error('token secret');};let errors=0,finished=0;s.finish=async()=>{finished++;};
 const worker=new TradePushWorker(s,{send:async()=> 'sent'},()=>{errors++;});await worker.tick();assert.equal(errors,1);assert.equal(finished,0);
});
test('order recovery only calls status and releases work even when RPC is unavailable',async()=>{
 const calls:unknown[]=[];let errors=0;
 const worker=new OrderRecoveryWorker({claim:async()=>[{id:'order',userId:'owner'}],release:async id=>{calls.push(['release',id]);}},
  {status:async(...args)=>{calls.push(args);throw Error('RPC unavailable');}},()=>{errors++;});
 await worker.tick();assert.deepEqual(calls,[['owner','order'],['release','order']]);assert.equal(errors,1);await worker.stop();
});

test('push platform rollout is explicit and rejects typos',()=>{assert.deepEqual(readPushPlatforms({}),['android']);assert.deepEqual(readPushPlatforms({TRIMMY_PUSH_PLATFORMS:'android,ios'}),['android','ios']);assert.deepEqual(readPushPlatforms({TRIMMY_PUSH_PLATFORMS:''}),[]);for(const value of ['web','ios,ios','android,'])assert.throws(()=>readPushPlatforms({TRIMMY_PUSH_PLATFORMS:value}));});


test('FCM retries transient HTTP failures and refreshes OAuth after unauthorized',async()=>{
 for (const status of [401,429,500,503]) {
  let oauth=0;
  const sender=new FcmPushSender(credentials,async url=>{
   if(String(url).includes('oauth2')){oauth++;return Response.json({access_token:'a',expires_in:3600});}
   return Response.json({error:{status:'UNAVAILABLE'}},{status});
  });
  assert.equal(await sender.send(job,'device-token'),'retry');
  assert.equal(await sender.send(job,'device-token'),'retry');
  assert.equal(oauth,status===401?2:1);
 }
 for (const status of [400,403,404]) {
  const sender=new FcmPushSender(credentials,async url=>String(url).includes('oauth2')
   ?Response.json({access_token:'a',expires_in:3600}):Response.json({error:{}},{status}));
  assert.equal(await sender.send(job,'device-token'),'drop');
 }
});

test('permanent provider rejection is finished and reported without device payload',async()=>{
 const s=store();let alerts=0;const outcomes:string[]=[];
 s.finish=async(_id,_worker,outcome)=>{outcomes.push(outcome);};
 const worker=new TradePushWorker(s,{send:async()=> 'drop'},()=>{alerts++;});
 await worker.tick();assert.deepEqual(outcomes,['drop']);assert.equal(alerts,1);await worker.stop();
});

test('a device may ask for its pushes in its language; any other language is refused',async()=>{
 const calls:unknown[][]=[];const s=store();s.register=async(...args)=>{calls.push(args);};
 const app=buildApp({logger:false,push:{platforms:['android'],store:s,authenticate:async()=>({userId:'verified-user'})}});
 const url=`/v1/notifications/devices/${device}`,payload={token:'a'.repeat(24),platform:'android'};
 try {
  assert.equal((await app.inject({method:'PUT',url,payload:{...payload,language:'fr'}})).statusCode,200);
  assert.equal((await app.inject({method:'PUT',url,payload:{...payload,language:'de'}})).statusCode,400);
  assert.equal((await app.inject({method:'PUT',url,payload})).statusCode,200);
  assert.deepEqual(calls,[['verified-user',device,payload.token,'android','fr'],['verified-user',device,payload.token,'android']]);
 } finally {await app.close();}
});
test('trade updates are written in the device language, English for any other',async()=>{
 const bodies:string[]=[];
 const sender=new FcmPushSender(credentials,async(url,init)=>{
  if(String(url).includes('oauth2'))return Response.json({access_token:'access-token',expires_in:3600});
  bodies.push(JSON.parse(String(init?.body)).message.notification.body);return Response.json({name:'projects/trimmy-test/messages/accepted'});
 });
 for(const language of ['es','pt','fr','en','de',null])await sender.send(job,'device-token',true,language);
 assert.deepEqual(bodies,['Tu operación se confirmó. Abre Trimmy para ver los detalles.','Sua operação foi confirmada. Abra o Trimmy para ver os detalhes.',
  'Ton opération est confirmée. Ouvre Trimmy pour voir les détails.','Your trade is confirmed. Open Trimmy for details.',
  'Your trade is confirmed. Open Trimmy for details.','Your trade is confirmed. Open Trimmy for details.']);
 for(const copy of Object.values(TRADE_PUSH_COPY))for(const text of Object.values(copy))assert.doesNotMatch(text,/[—–]|\d/,'no dash, no amount');
 // The worker reads the device language for the job it holds and passes it on.
 const seen:(string|null)[]=[];const s=store();s.language=async()=> 'pt';
 await new TradePushWorker(s,{send:async(_job,_token,_validate,language=null)=>{seen.push(language);return 'sent';}}).tick();
 const old=store();
 await new TradePushWorker(old,{send:async(_job,_token,_validate,language=null)=>{seen.push(language);return 'sent';}}).tick();
 assert.deepEqual(seen,['pt','en'],'a store without languages sends English');
});
