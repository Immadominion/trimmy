import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {Pool} from 'pg';
import {postgresWorkdays} from '../../src/workday-routes.js';
const host=process.env['TRIMMY_WORKDAYS_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.workdays-runtime/socket'));
test('twenty saved workdays: evidence, decisions, drafts, branching, exact retries and one reward',async()=>{
 const owner=new Pool({host,port:65455,database:'postgres',user:'trimmy_daily_owner'});
 let runtime:Pool|undefined;
 try {
  await owner.query(`CREATE ROLE workday_runtime LOGIN NOSUPERUSER NOBYPASSRLS; GRANT USAGE ON SCHEMA trimmy TO workday_runtime;
   GRANT EXECUTE ON FUNCTION trimmy.workday_read(uuid),trimmy.workday_save(uuid,text,integer,integer,jsonb,text) TO workday_runtime`);
  const user=randomUUID(),other=randomUUID();
  await owner.query('INSERT INTO trimmy.users(id) VALUES($1),($2)',[user,other]);
  runtime=new Pool({host,port:65455,database:'postgres',user:'workday_runtime'});
  const api=postgresWorkdays(runtime);
  const content=JSON.parse(await readFile(new URL('../../../../content/workdays/intern-v1.json',import.meta.url),'utf8'));
  let journey=await api.read(user);
  const entries=()=>journey['assignments'] as Record<string,any>[];
  assert.equal(entries().length,20);
  assert.ok(!JSON.stringify(journey).includes('requiredIds'));
  assert.ok(!JSON.stringify(journey).includes('acceptedAnswers'));
  await assert.rejects(api.save(user,{assignmentId:content.assignments[1].id,revision:0,step:0,answer:{ids:[]}}),/WORK_LOCKED/);
  for(const definition of content.assignments) {
   const id=definition.id;
   const state=()=>entries().find(e=>e['id']===id)!;
   if(definition.ordinal===5) assert.match(state()['contextNote'],/cost|asked|figures/i);
   await assert.rejects(api.save(user,{assignmentId:id,revision:0,step:0,answer:{ids:['wrong']}}),/CHECK_EVIDENCE/);
   const evidence={assignmentId:id,revision:0,step:0,answer:{ids:definition.evidence.requiredIds}};
   const retry=await Promise.all([api.save(user,evidence),api.save(user,evidence)]);
   journey=retry[1]!; assert.equal(state()['step'],1);
   await assert.rejects(api.save(user,{assignmentId:id,revision:state()['revision'],step:1,answer:{value:'nonsense'}}),/CHECK_DECISION/);
   journey=await api.save(user,{assignmentId:id,revision:state()['revision'],step:1,answer:{value:definition.decision.acceptedAnswers[0]}});
   assert.equal(state()['step'],2);
   journey=await api.save(user,{assignmentId:id,revision:state()['revision'],step:-1,answer:{ids:[]},draft:'My evidence-led note.'});
   assert.equal(state()['draft'],'My evidence-led note.');
   const file={assignmentId:id,revision:state()['revision'],step:2,answer:{ids:[...definition.file.requiredIds].reverse()},draft:'My evidence-led note.'};
   journey=(await Promise.all([api.save(user,file),api.save(user,file),api.save(user,file)]))[0]!;
   assert.equal(state()['step'],3); assert.ok(state()['completedAt']); assert.match(state()['artifact'],/My evidence-led note/);
   await assert.rejects(api.save(user,{...file,draft:'Changed after filing'}),/WORK_CHANGED/);
  }
  assert.equal(journey['completedCount'],20);
  const counts=(await owner.query(`SELECT (SELECT count(*) FROM trimmy.workday_completions WHERE user_id=$1) AS files,
   (SELECT count(*) FROM trimmy.career_trim_ledger WHERE user_id=$1 AND entry_kind='workday') AS rewards,
   (SELECT count(*) FROM trimmy.career_activity_events WHERE user_id=$1 AND activity_kind='workday') AS events,
   (SELECT trims_total FROM trimmy.career_profiles WHERE user_id=$1) AS trims,
   (SELECT count(*) FROM trimmy.paper_orders WHERE user_id=$1) AS orders`,[user])).rows[0];
  assert.deepEqual(counts,{files:'20',rewards:'20',events:'20',trims:'400',orders:'0'});
  assert.equal((await api.read(other))['completedCount'],0);
  await assert.rejects(runtime.query('SELECT * FROM trimmy.workday_attempts'),/permission denied/);
  await assert.rejects(owner.query('DELETE FROM trimmy.workday_completions WHERE user_id=$1',[user]),/append.only|immutable|mutation/i);
  const client=await runtime.connect();
  try {
   await client.query('BEGIN'); await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[other]);
   await assert.rejects(client.query('SELECT trimmy.workday_read($1)',[user]),/ACCOUNT_REQUIRED/);
  } finally { await client.query('ROLLBACK');client.release(); }
  await owner.query("UPDATE trimmy.users SET status='closed' WHERE id=$1",[other]);
  await assert.rejects(api.read(other),/ACCOUNT_REQUIRED/);
 } finally { await runtime?.end(); await owner.end(); }
});
