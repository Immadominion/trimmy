import test from 'node:test';
import assert from 'node:assert/strict';
import {buildApp} from '../src/app.js';
import {createCareerAuthenticator} from '../src/career-routes.js';
import type {GuestSessionRepository} from '../src/guest-session-repository.js';
test('workday endpoints authenticate guests with career scope, validate stages and do not leak errors',async()=>{
 const scopes:string[]=[];let writes=0;let error='';let miss:unknown=null;
 const auth=createCareerAuthenticator(async()=>null,{authorize:async(_hash:string,scope:string)=>{scopes.push(scope);return {userId:'test-user'};}} as unknown as GuestSessionRepository);
 const app=buildApp({logger:false,workdays:{authenticate:auth,read:async()=>({assignments:[]}),save:async()=>{if(error)throw Error(error);writes++;return miss?{assignments:[],miss}:{assignments:[]};}}});
 const headers={authorization:'Guest tg1_'+'a'.repeat(43)};
 const input={assignmentId:'morning-brief',revision:0,step:0,answer:{ids:['report','cost']}};
 try {
  assert.equal((await app.inject({url:'/v1/career/workdays'})).statusCode,401);
  assert.equal((await app.inject({url:'/v1/career/workdays',headers})).statusCode,200);
  assert.equal((await app.inject({method:'POST',url:'/v1/career/workdays/step',headers,payload:input})).statusCode,200);
  assert.equal((await app.inject({method:'POST',url:'/v1/career/workdays/draft',headers,payload:{assignmentId:'morning-brief',revision:2,draft:'my note'}})).statusCode,200);
  assert.deepEqual(scopes,['career_read','career_write','career_write']);
  for(const payload of [{...input,step:-1},{...input,revision:-1},{...input,trims:900},{...input,answer:{ids:['same','same']}},{...input,answer:{value:'',ids:[]}}]) {
   assert.equal((await app.inject({method:'POST',url:'/v1/career/workdays/step',headers,payload})).statusCode,400);
  }
  assert.equal(writes,2);
  for(const [code,status] of [['WORK_CHANGED',409],['WORK_TOMORROW',409],['WORK_CLOSED',409],['CHECK_EVIDENCE',400],['CHECK_DECISION',400],['secret SQL details',503]] as const) {
   error=code; const result=await app.inject({method:'POST',url:'/v1/career/workdays/step',headers,payload:input});assert.equal(result.statusCode,status);assert.equal(result.headers['cache-control'],'no-store');assert.ok(!result.body.includes('secret'));
  }
  // A recorded miss answers 400 with the code installed apps know, the missed choice's note and the updated journey.
  error='';miss={code:'CHECK_DECISION',step:1,feedback:'Count all the shares.'};
  let result=await app.inject({method:'POST',url:'/v1/career/workdays/step',headers,payload:input});
  assert.equal(result.statusCode,400);assert.deepEqual(result.json(),{code:'CHECK_DECISION',step:1,feedback:'Count all the shares.',journey:{assignments:[]}});
  miss={code:'anything else',step:'2',feedback:7};
  result=await app.inject({method:'POST',url:'/v1/career/workdays/step',headers,payload:input});
  assert.deepEqual(result.json(),{code:'CHECK_EVIDENCE',step:null,feedback:null,journey:{assignments:[]}});
 } finally { await app.close(); }
});
