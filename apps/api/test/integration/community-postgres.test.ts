import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Pool} from 'pg';
import {postgresCommunity} from '../../src/community-routes.js';
const host=process.env['TRIMMY_COMMUNITY_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.community-runtime/socket'));
test('real restricted database: privacy, following, muting and principal isolation',async()=>{
 const pool=new Pool({host,port:65453,database:'postgres',user:'trimmy_community_owner'});
 let runtime:Pool|undefined;
 try {
 await pool.query(`CREATE ROLE trimmy_community_runtime LOGIN NOSUPERUSER NOBYPASSRLS;
 GRANT USAGE ON SCHEMA trimmy TO trimmy_community_runtime;
 GRANT EXECUTE ON FUNCTION trimmy.community_feed_get(uuid,text,timestamptz,uuid),trimmy.community_follow_set(uuid,uuid,boolean,boolean) TO trimmy_community_runtime`);
 const viewer=randomUUID(),author=randomUUID();
 for(const [id,handle] of [[viewer,'community_viewer'],[author,'community_author']]){
  await pool.query('INSERT INTO trimmy.users(id) VALUES($1)',[id]);
  await pool.query("INSERT INTO trimmy.practice_auth_identities(app_id,subject,user_id) VALUES('test',$1,$2)",['did:privy:'+id!.replaceAll('-',''),id]);
  const client=await pool.connect();try{await client.query('BEGIN');await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[id]);
  await client.query("SELECT * FROM trimmy.product_profile_put($1,$2,repeat('a',64),0,'practice','basics','wolf','one-mission',$3,'first-trade')",[id,randomUUID(),handle]);await client.query('COMMIT');}finally{client.release();}
 }
 const target=(await pool.query('SELECT public_id FROM trimmy.social_profiles WHERE user_id=$1',[author])).rows[0].public_id;
 runtime=new Pool({host,port:65453,database:'postgres',user:'trimmy_community_runtime'});
 const api=postgresCommunity(runtime);
 await api.follow(viewer,target,true,true);
 const order=(await pool.query("SELECT public.paper_reset_test_buy($1,'apple','XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',clock_timestamp()) AS id",[author])).rows[0].id;
 await pool.query('SELECT public.paper_reset_test_historical_reason($1,$2,$3,clock_timestamp())',[author,order,randomUUID()]);
 assert.equal((await api.read(viewer,'everyone',null,null)).length,0,'private stays private');
 const client=await pool.connect();try{await client.query('BEGIN');await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[author]);
 await client.query("SELECT * FROM trimmy.career_reason_privacy_put($1,$2,repeat('b',64),1,'everyone')",[author,randomUUID()]);await client.query('COMMIT');}finally{client.release();}
 assert.equal((await api.read(viewer,'following',null,null)).length,1);
 assert.equal((await api.read(viewer,'notifications',null,null)).length,1);
 await api.follow(viewer,target,true,false);
 assert.equal((await api.read(viewer,'notifications',null,null)).length,0,'muting hides updates');
 assert.equal((await api.read(viewer,'following',null,null)).length,1);
 await api.follow(viewer,target,false,false);
 assert.equal((await api.read(viewer,'following',null,null)).length,0);
 await assert.rejects(runtime.query("SELECT * FROM trimmy.community_feed_get($1,'everyone',NULL,NULL)",[viewer]),/ACCOUNT_REQUIRED/);
 await assert.rejects(runtime.query('SELECT * FROM trimmy.community_follows'),/permission denied/);
 }finally{await runtime?.end();await pool.end();}
});
