import test from 'node:test';
import assert from 'node:assert/strict';
import {buildApp} from '../src/app.js';
import {createCareerAuthenticator} from '../src/career-routes.js';
import type {GuestSessionRepository} from '../src/guest-session-repository.js';
const user='f818dc74-d6e4-4b90-a769-5e6e5e3de05e';
const body={date:'2026-09-24',caseId:'the-cheap-share',choiceId:'compare'};
test('composed API allows daily completion and community follow; validates payload and fails closed',async()=>{
 let saves=0,follows=0;
 const app=buildApp({logger:false,dailyDesk:{authenticate:async r=>r.headers.authorization==='Bearer test'?{userId:user}:null,read:async()=>({date:body.date}),complete:async(id,value)=>{assert.equal(id,user);assert.deepEqual(value,body);saves++;return {completedChoice:value.choiceId};}},community:{authenticate:async()=>({userId:user}),read:async()=>[],follow:async()=>{follows++;return true;}}});
 try{
  assert.equal((await app.inject({method:'GET',url:'/v1/career/daily-desk'})).statusCode,401);
  const result=await app.inject({method:'POST',url:'/v1/career/daily-desk/complete',headers:{authorization:'Bearer test'},payload:body});
  assert.equal(result.statusCode,200,result.body);assert.equal(saves,1);assert.equal(result.headers['cache-control'],'no-store');
  for(const payload of [{...body,trims:999},{...body,date:'2026-02-31'},{...body,choiceId:'../bad'}])assert.equal((await app.inject({method:'POST',url:'/v1/career/daily-desk/complete',headers:{authorization:'Bearer test'},payload})).statusCode,400);
  assert.equal(saves,1);
  assert.equal((await app.inject({method:'PUT',url:`/v1/community/following/${user}`,payload:{following:true,notifications:false}})).statusCode,200);assert.equal(follows,1);
  assert.equal((await app.inject({method:'POST',url:'/v1/career/daily-desk/unknown',payload:body})).statusCode,503);
 }finally{await app.close();}
});
test('guest daily routes receive only their existing career scopes',async()=>{
 const scopes:string[]=[];
 const authenticate=createCareerAuthenticator(async()=>null,{authorize:async(_hash:string,scope:string)=>{scopes.push(scope);return {userId:user};}} as unknown as GuestSessionRepository);
 const app=buildApp({logger:false,dailyDesk:{authenticate,read:async()=>({}),complete:async()=>({})}});
 try{
 const headers={authorization:'Guest tg1_'+ 'a'.repeat(43)};
 for(const [method,url,payload] of [['GET','/v1/career/daily-desk',undefined],['POST','/v1/career/daily-desk/complete',body]] as const){
  const response=await app.inject({method,url,headers,...(payload?{payload}:{})});assert.equal(response.statusCode,200,response.body);
 }
 assert.deepEqual(scopes,['career_read','career_write']);
 }finally{await app.close();}
});
test('daily conflicts and temporary outages remain distinguishable',async()=>{
 let code='DAY_CHANGED';
 const app=buildApp({logger:false,dailyDesk:{authenticate:async()=>({userId:user}),read:async()=>({}),complete:async()=>{throw Error(code);}}});
 try{for(const [error,status] of [['DAY_CHANGED',409],['SHIFT_ALREADY_COMPLETE',409],['INVALID_CHOICE',400],['secret provider details',503]] as const){code=error;const response=await app.inject({method:'POST',url:'/v1/career/daily-desk/complete',payload:body});assert.equal(response.statusCode,status);if(status===503)assert.ok(!response.body.includes('secret'));}}
 finally{await app.close();}
});
