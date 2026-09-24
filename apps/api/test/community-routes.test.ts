import test from 'node:test';
import assert from 'node:assert/strict';
import Fastify from 'fastify';
import {registerCommunityRoutes} from '../src/community-routes.js';
const user='92800000-0000-4000-8000-000000000001';
test('community authenticates, bounds pages and does not publish order data',async()=>{
 const app=Fastify({ajv:{customOptions:{removeAdditional:false,coerceTypes:false,useDefaults:false}}});
 const reads:unknown[]=[];
 registerCommunityRoutes(app,{authenticate:async r=>r.headers.authorization==='Bearer valid'?{userId:user}:null,
 read:async(...args)=>{reads.push(args);return Array.from({length:21},()=>({reason_id:user,social_id:user,handle:'sam',persona:'wolf',asset_id:'apple',variant_mint:'mint',symbol:'AAPLx',note:'A long view',saved_at:'2026-09-24T10:00:00Z',following:false,notifications:false,is_viewer:false,order_id:'SECRET',quantity:'SECRET'}));},
 follow:async()=>true});
 assert.equal((await app.inject({url:'/v1/community'})).statusCode,401);
 assert.equal((await app.inject({url:'/v1/community?scope=private',headers:{authorization:'Bearer valid'}})).statusCode,400);
 const response=await app.inject({url:'/v1/community',headers:{authorization:'Bearer valid'}});
 assert.equal(response.statusCode,200);assert.equal(response.json().items.length,20);
 assert.equal(response.headers['cache-control'],'no-store');assert.ok(response.json().next);
 assert.ok(!response.body.includes('SECRET'));assert.equal(reads.length,1);
 await app.close();
});
test('follow writes use verified identity and explicit desired state',async()=>{
 const app=Fastify({ajv:{customOptions:{removeAdditional:false,coerceTypes:false,useDefaults:false}}});let written:unknown[]=[];
 registerCommunityRoutes(app,{authenticate:async()=>({userId:user}),read:async()=>[],follow:async(...args)=>{written=args;return args[2];}});
 const response=await app.inject({method:'PUT',url:`/v1/community/following/${user}`,payload:{following:true,notifications:false}});
 assert.equal(response.statusCode,200);assert.deepEqual(written,[user,user,true,false]);
 assert.equal((await app.inject({method:'PUT',url:`/v1/community/following/${user}`,payload:{following:true,notifications:true,userId:'spoof'}})).statusCode,400);
 await app.close();
});
