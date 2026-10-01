import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {Pool} from 'pg';
import {postgresWorkdays} from '../../src/workday-routes.js';
const host=process.env['TRIMMY_WORKDAYS_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.workdays-runtime/socket'));
type Journey=Record<string,any>;
test('weekday workdays: one new assignment per desk day, recorded misses, desk-day streaks and the serving role',async()=>{
 const owner=new Pool({host,port:65455,database:'postgres',user:'trimmy_daily_owner'});
 let runtime:Pool|undefined;
 try {
  await owner.query(`CREATE ROLE workday_runtime LOGIN NOSUPERUSER NOBYPASSRLS; GRANT USAGE ON SCHEMA trimmy TO workday_runtime;
   GRANT EXECUTE ON FUNCTION trimmy.runtime_schema_has(text),trimmy.workday_read(uuid),trimmy.workday_save(uuid,text,integer,integer,jsonb,text) TO workday_runtime`);
  const content=JSON.parse(await readFile(new URL('../../../../content/workdays/intern-v1.json',import.meta.url),'utf8'));
  const defs:Record<string,any>[]=content.assignments;
  const users=async(count:number)=>{const ids=Array.from({length:count},()=>randomUUID());
   await owner.query('INSERT INTO trimmy.users(id) SELECT unnest($1::uuid[])',[ids]);return ids;};
  // The owner can pass an explicit instant; the serving role only reaches the clock-bound wrappers.
  const scoped=async(user:string,sql:string,params:unknown[])=>{const client=await owner.connect();
   try {await client.query('BEGIN');await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[user]);
    const row=(await client.query(sql,params)).rows[0];await client.query('COMMIT');return row.j as Journey;}
   catch(error){await client.query('ROLLBACK');throw error;} finally {client.release();}};
  const readAt=(user:string,at:string)=>scoped(user,'SELECT trimmy.workday_read_at($1,$2) AS j',[user,at]);
  const entry=(journey:Journey,id:string)=>(journey['assignments'] as Journey[]).find(e=>e['id']===id)!;
  const step=async(user:string,at:string,id:string,answer:unknown,draft?:string)=>{
   const current=entry(await readAt(user,at),id);
   return scoped(user,'SELECT trimmy.workday_save_at($1,$2,$3,$4,$5,$6,$7) AS j',[user,id,current['revision'],current['step'],JSON.stringify(answer),draft??null,at]);};
  const evidence=(d:Record<string,any>)=>({ids:d['evidence'].requiredIds});
  const decision=(d:Record<string,any>)=>({value:d['decision'].acceptedAnswers[0]});
  const file=(d:Record<string,any>)=>({ids:d['file'].requiredIds});
  const fileAt=async(user:string,at:string,d:Record<string,any>)=>{
   await step(user,at,d['id'],evidence(d));await step(user,at,d['id'],decision(d));return step(user,at,d['id'],file(d),'Filed note.');};
  const streak=async(user:string,zone:string,day:string)=>(await owner.query(
   'SELECT streak_days AS days,streak_status AS status FROM trimmy.career_streak_get($1,$2,$3)',[user,zone,day])).rows[0];
  const instant=(value:unknown)=>value===null?null:new Date(value as string).toISOString();
  const schedule=(j:Journey)=>({...j['schedule'],opensAt:instant(j['schedule'].opensAt)});
  const trims=async(user:string)=>(await owner.query("SELECT coalesce(sum(trims),0)::int AS t FROM trimmy.career_trim_ledger WHERE user_id=$1 AND entry_kind='workday'",[user])).rows[0].t;

  // The serving role: today's clock, the first assignment on any day, retries, and no answers in reads.
  const [fresh,other]=await users(2); assert.ok(fresh); assert.ok(other);
  runtime=new Pool({host,port:65455,database:'postgres',user:'workday_runtime'});
  const api=postgresWorkdays(runtime);
  assert.equal((await runtime.query("SELECT trimmy.runtime_schema_has('0036_weekday_workdays') AS ready")).rows[0].ready,true);
  assert.equal((await runtime.query("SELECT trimmy.runtime_schema_has('9999_not_installed') AS ready")).rows[0].ready,false);
  await assert.rejects(runtime.query('SELECT * FROM trimmy.schema_migrations'),/permission denied/);
  let journey:Journey=await api.read(fresh);
  assert.deepEqual((journey['assignments'] as Journey[]).map(e=>e['id']),['morning-brief']);
  assert.equal(journey['schedule'].state,'available');assert.equal(journey['upcoming'],null);assert.equal(journey['total'],20);
  for(const leak of ['requiredIds','acceptedAnswers','"feedback":"'])assert.ok(!JSON.stringify(journey).includes(leak),leak);
  const first=defs[0]!;
  journey=await api.save(fresh,{assignmentId:first['id'],revision:0,step:0,answer:{ids:['headline']}});
  assert.deepEqual(journey['miss'],{code:'CHECK_EVIDENCE',step:0,feedback:null});
  assert.equal(entry(journey,first['id'])['misses'],1);assert.equal(entry(journey,first['id'])['step'],0);
  const pinned={assignmentId:first['id'],revision:0,step:0,answer:{ids:first['evidence'].requiredIds}};
  journey=(await Promise.all([api.save(fresh,pinned),api.save(fresh,pinned)]))[1]!;
  assert.equal(entry(journey,first['id'])['step'],1);
  await assert.rejects(api.save(fresh,{assignmentId:first['id'],revision:0,step:0,answer:{ids:['headline','after']}}),/WORK_CHANGED/);
  assert.equal(entry(await api.read(fresh),first['id'])['misses'],1,'a stale wrong answer is not a miss');
  journey=await api.save(fresh,{assignmentId:first['id'],revision:entry(journey,first['id'])['revision'],step:1,answer:{value:'200.000'}});
  const filing={assignmentId:first['id'],revision:entry(journey,first['id'])['revision'],step:2,answer:{ids:[...first['file'].requiredIds].reverse()},draft:'My note.'};
  journey=(await Promise.all([api.save(fresh,filing),api.save(fresh,filing),api.save(fresh,filing)]))[0]!;
  assert.equal(entry(journey,first['id'])['trims'],10);assert.match(entry(journey,first['id'])['artifact'],/My note/);
  assert.deepEqual((journey['assignments'] as Journey[]).length,1,'day two stays out of the list until it opens');
  assert.ok(['tomorrow','closed'].includes(journey['schedule'].state));
  assert.equal(journey['upcoming'].id,defs[1]!['id']);assert.ok(Date.parse(journey['upcoming'].opensAt)>Date.now());
  await assert.rejects(api.save(fresh,{assignmentId:defs[1]!['id'],revision:0,step:0,answer:evidence(defs[1]!)}),/WORK_TOMORROW|WORK_CLOSED/);
  assert.equal(await trims(fresh),10);

  // One player through the whole intern month, Monday 5 October 2026 onwards, in UTC.
  const [month]=await users(1);const id=(n:number)=>defs[n-1]!['id'];
  journey=await fileAt(month!,'2026-10-05T10:00:00Z',defs[0]!);
  assert.equal(entry(journey,id(1))['trims'],20);
  assert.deepEqual(schedule(journey),{today:'2026-10-05',deskOpen:true,holiday:null,state:'tomorrow',opensAt:'2026-10-06T00:00:00.000Z'});
  assert.deepEqual({...journey['upcoming'],opensAt:instant(journey['upcoming'].opensAt)},{id:id(2),ordinal:2,title:defs[1]!['title'],speaker:defs[1]!['speaker'],district:defs[1]!['district'],art:defs[1]!['art'],opensAt:'2026-10-06T00:00:00.000Z'});
  await assert.rejects(scoped(month!,'SELECT trimmy.workday_save_at($1,$2,0,0,$3,NULL,$4) AS j',[month,id(2),JSON.stringify(evidence(defs[1]!)),'2026-10-05T23:59:59Z']),/WORK_TOMORROW/);
  await assert.rejects(scoped(month!,'SELECT trimmy.workday_save_at($1,$2,0,0,$3,NULL,$4) AS j',[month,id(3),JSON.stringify(evidence(defs[2]!)),'2026-10-06T09:00:00Z']),/WORK_LOCKED/);
  // Tuesday: start day two and stop. Wednesday: finish it, then day three may still start.
  await step(month!,'2026-10-06T09:00:00Z',id(2),evidence(defs[1]!));
  journey=await readAt(month!,'2026-10-07T08:00:00Z');assert.equal(journey['schedule'].state,'available');
  await step(month!,'2026-10-07T08:00:00Z',id(2),{value:'aster'});
  journey=await readAt(month!,'2026-10-07T08:00:01Z');
  assert.equal(entry(journey,id(2))['misses'],1);assert.equal(entry(journey,id(2))['decisionNote'],null);
  await step(month!,'2026-10-07T08:01:00Z',id(2),decision(defs[1]!));
  assert.equal(entry(await readAt(month!,'2026-10-07T08:01:01Z'),id(2))['decisionNote'],'Exactly: $100 × 100,000 = $10 million.');
  journey=await step(month!,'2026-10-07T08:02:00Z',id(2),file(defs[1]!));
  assert.equal(entry(journey,id(2))['trims'],10);assert.equal(journey['schedule'].state,'available','nothing new has started on Wednesday yet');
  journey=await fileAt(month!,'2026-10-07T09:00:00Z',defs[2]!);assert.equal(journey['schedule'].state,'tomorrow');
  await fileAt(month!,'2026-10-08T12:00:00Z',defs[3]!);
  journey=await fileAt(month!,'2026-10-09T12:00:00Z',defs[4]!);
  assert.match(entry(journey,id(5))['contextNote'],/cost|asked|figures/i);
  // Tuesday's work was started but not filed, so Tuesday does not count: the run restarts on Wednesday.
  assert.deepEqual(await streak(month!,'UTC','2026-10-09'),{days:3,status:'active'});
  // The weekend: nothing new opens and the streak rests.
  journey=await readAt(month!,'2026-10-10T12:00:00Z');
  assert.deepEqual(schedule(journey),{today:'2026-10-10',deskOpen:false,holiday:null,state:'closed',opensAt:'2026-10-12T00:00:00.000Z'});
  await assert.rejects(scoped(month!,'SELECT trimmy.workday_save_at($1,$2,0,0,$3,NULL,$4) AS j',[month,id(6),JSON.stringify(evidence(defs[5]!)),'2026-10-11T12:00:00Z']),/WORK_CLOSED/);
  assert.deepEqual(await streak(month!,'UTC','2026-10-10'),{days:3,status:'grace'});
  assert.deepEqual(await streak(month!,'UTC','2026-10-12'),{days:3,status:'at-risk'});
  assert.deepEqual(await streak(month!,'UTC','2026-10-13'),{days:0,status:'not-started'},'a missed weekday ends the streak');
  // Days six to twenty on the following weekdays.
  let day=new Date('2026-10-12T15:00:00Z');
  for(let n=6;n<=20;n++){
   while(day.getUTCDay()===0||day.getUTCDay()===6)day=new Date(day.getTime()+86_400_000);
   journey=await fileAt(month!,day.toISOString(),defs[n-1]!);day=new Date(day.getTime()+86_400_000);
  }
  assert.equal(journey['completedCount'],20);assert.equal(journey['schedule'].state,'done');assert.equal(journey['upcoming'],null);
  assert.equal((journey['assignments'] as Journey[]).length,20);
  assert.deepEqual(await streak(month!,'UTC','2026-10-30'),{days:18,status:'active'});
  assert.equal(await trims(month!),19*20+10);
  const counts=(await owner.query(`SELECT (SELECT count(*) FROM trimmy.workday_completions WHERE user_id=$1) AS files,
   (SELECT count(*) FROM trimmy.career_trim_ledger WHERE user_id=$1 AND entry_kind='workday') AS rewards,
   (SELECT count(*) FROM trimmy.career_activity_events WHERE user_id=$1 AND activity_kind='workday') AS events,
   (SELECT count(DISTINCT started_date) FROM trimmy.workday_attempts WHERE user_id=$1) AS start_days`,[month])).rows[0];
  assert.deepEqual(counts,{files:'20',rewards:'20',events:'20',start_days:'20'});

  // A market holiday closes the desk by name; the streak waits through it.
  const [holiday,weekend,lagos]=await users(3);
  await fileAt(holiday!,'2026-11-25T12:00:00Z',defs[0]!);
  journey=await readAt(holiday!,'2026-11-26T12:00:00Z');
  assert.deepEqual(schedule(journey),{today:'2026-11-26',deskOpen:false,holiday:'thanksgiving-day',state:'closed',opensAt:'2026-11-27T00:00:00.000Z'});
  assert.deepEqual(await streak(holiday!,'UTC','2026-11-26'),{days:1,status:'grace'});
  assert.deepEqual(await streak(holiday!,'UTC','2026-11-27'),{days:1,status:'at-risk'});
  await fileAt(holiday!,'2026-11-27T12:00:00Z',defs[1]!);
  assert.deepEqual(await streak(holiday!,'UTC','2026-11-30'),{days:2,status:'at-risk'});

  // A first workday is never closed; weekend activity earns Trims without inventing a trading-day streak.
  await fileAt(weekend!,'2026-10-10T10:00:00Z',defs[0]!);
  await assert.rejects(scoped(weekend!,'SELECT trimmy.workday_save_at($1,$2,0,0,$3,NULL,$4) AS j',[weekend,id(2),JSON.stringify(evidence(defs[1]!)),'2026-10-10T11:00:00Z']),/WORK_CLOSED/);
  assert.deepEqual(await streak(weekend!,'UTC','2026-10-12'),{days:0,status:'not-started'});
  await step(weekend!,'2026-10-12T09:00:00Z',id(2),evidence(defs[1]!));
  // Work started before this rule (no start date) can always be finished, even on a closed day.
  await owner.query('UPDATE trimmy.workday_attempts SET started_at=NULL,started_date=NULL WHERE user_id=$1 AND assignment_id=$2',[weekend,id(2)]);
  await step(weekend!,'2026-10-17T09:00:00Z',id(2),decision(defs[1]!));
  journey=await step(weekend!,'2026-10-17T09:01:00Z',id(2),file(defs[1]!));
  assert.equal(entry(journey,id(2))['trims'],20);assert.equal(journey['schedule'].state,'closed');

  // Local midnight decides, in the player's own zone.
  const zone=await scoped(lagos!,"SELECT to_jsonb(r) AS j FROM trimmy.career_day_context_put($1,gen_random_uuid(),repeat('a',64),1,'Africa/Lagos') r",[lagos]);
  assert.equal(zone['outcome'],'saved');assert.equal(zone['time_zone'],'Africa/Lagos');
  await fileAt(lagos!,'2026-10-05T22:30:00Z',defs[0]!);
  journey=await readAt(lagos!,'2026-10-05T22:59:00Z');
  assert.equal(journey['schedule'].today,'2026-10-05');assert.equal(schedule(journey).opensAt,'2026-10-05T23:00:00.000Z');
  journey=await fileAt(lagos!,'2026-10-05T23:30:00Z',defs[1]!);
  assert.equal(journey['schedule'].today,'2026-10-06');assert.equal(instant(journey['upcoming'].opensAt),'2026-10-06T23:00:00.000Z');

  // The serving role reaches only the wrappers; other accounts and closed accounts stay out.
  await assert.rejects(runtime.query('SELECT trimmy.workday_read_at($1,now())',[fresh]),/permission denied/);
  await assert.rejects(runtime.query('SELECT trimmy.workday_save_at($1,$2,0,0,$3,NULL,now())',[fresh,id(1),'{}']),/permission denied/);
  await assert.rejects(runtime.query('SELECT * FROM trimmy.workday_attempts'),/permission denied/);
  await assert.rejects(runtime.query('SELECT * FROM trimmy.us_market_holidays'),/permission denied/);
  assert.equal((await api.read(other!))['completedCount'],0);
  await assert.rejects(owner.query('DELETE FROM trimmy.workday_completions WHERE user_id=$1',[month]),/append.only|immutable|mutation/i);
  await assert.rejects(owner.query("INSERT INTO trimmy.career_trim_ledger(user_id,career_revision,entry_kind,source_id,trims,awarded_on,created_at) VALUES($1,999,'workday',gen_random_uuid(),15,'2026-10-05',now())",[month]),/kind_reward|check/i);
  const client=await runtime.connect();
  try {
   await client.query('BEGIN'); await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[other]);
   await assert.rejects(client.query('SELECT trimmy.workday_read($1)',[fresh]),/ACCOUNT_REQUIRED/);
  } finally { await client.query('ROLLBACK');client.release(); }
  await owner.query("UPDATE trimmy.users SET status='closed' WHERE id=$1",[other]);
  await assert.rejects(api.read(other!),/ACCOUNT_REQUIRED/);
 } finally { await runtime?.end(); await owner.end(); }
});
