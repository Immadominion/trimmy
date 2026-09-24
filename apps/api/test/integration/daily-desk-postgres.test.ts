import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Pool} from 'pg';
import {postgresDailyDesk} from '../../src/daily-desk-routes.js';
const host=process.env['TRIMMY_DAILY_DESK_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.daily-desk-runtime/socket'));
test('daily decisions: atomic rewards, retries, local dates, principals and immutable history',async()=>{
 const owner=new Pool({host,port:65454,database:'postgres',user:'trimmy_daily_owner'});
 let runtime:Pool|undefined;
 try{
  await owner.query(`CREATE ROLE trimmy_daily_runtime LOGIN NOSUPERUSER NOBYPASSRLS; GRANT USAGE ON SCHEMA trimmy TO trimmy_daily_runtime;
  GRANT EXECUTE ON FUNCTION trimmy.daily_desk_get(uuid),trimmy.daily_desk_complete(uuid,date,text,text) TO trimmy_daily_runtime`);
  const user=randomUUID(),other=randomUUID();
  await owner.query('INSERT INTO trimmy.users(id) VALUES($1),($2)',[user,other]);
  runtime=new Pool({host,port:65454,database:'postgres',user:'trimmy_daily_runtime'});
  const api=postgresDailyDesk(runtime);
  const before=await api.read(user);
  const story=before['story'] as {id:string,choices:{id:string}[]};
  assert.equal(before['completedChoice'],null);
  assert.equal(story.choices.length,3);
  const choice={date:before['date'] as string,caseId:story.id,choiceId:story.choices[0]!.id};
  await assert.rejects(api.complete(user,{...choice,date:'2020-01-01'}),/DAY_CHANGED/);
  await assert.rejects(api.complete(user,{...choice,choiceId:'forged'}),/INVALID_CHOICE/);
  const results=await Promise.all([api.complete(user,choice),api.complete(user,choice),api.complete(user,choice)]);
  for(const result of results){assert.equal(result['completedChoice'],choice.choiceId);assert.equal(result['trimsEarned'],10);}
  assert.equal((await owner.query('SELECT trims_total,streak_days FROM trimmy.career_profiles WHERE user_id=$1',[user])).rows[0].trims_total,'10');
  assert.equal((await owner.query("SELECT count(*) FROM trimmy.career_trim_ledger WHERE user_id=$1 AND entry_kind='daily-shift'",[user])).rows[0].count,'1');
  assert.equal((await owner.query("SELECT count(*) FROM trimmy.career_activity_events WHERE user_id=$1 AND activity_kind='daily-shift'",[user])).rows[0].count,'1');
  assert.equal((await owner.query('SELECT count(*) FROM trimmy.paper_orders WHERE user_id=$1',[user])).rows[0].count,'0');
  await assert.rejects(api.complete(user,{...choice,choiceId:story.choices[1]!.id}),/SHIFT_ALREADY_COMPLETE/);
  assert.equal((await api.read(other))['completedChoice'],null);
  const client=await runtime.connect();
  try{await client.query('BEGIN'); await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[other]);
    await assert.rejects(client.query('SELECT trimmy.daily_desk_get($1)',[user]),/ACCOUNT_REQUIRED/);
  } finally{await client.query('ROLLBACK');client.release();}
  await assert.rejects(runtime.query('SELECT * FROM trimmy.daily_desk_shifts'),/permission denied/);
  await assert.rejects(owner.query('DELETE FROM trimmy.daily_desk_shifts WHERE user_id=$1',[user]),/append.only|immutable|mutation/i);
  // A forged pair without its fixed reward must roll back at commit.
  const forged=await owner.connect();
  try{await forged.query('BEGIN');const id=randomUUID(),at=new Date();
   await forged.query('INSERT INTO trimmy.daily_desk_shifts(id,user_id,shift_date,case_id,choice_id,completed_at) VALUES($1,$2,current_date,$3,$4,$5)',[id,other,story.id,choice.choiceId,at]);
   await forged.query("INSERT INTO trimmy.career_activity_events(user_id,activity_kind,source_id,observed_at) VALUES($1,'daily-shift',$2,$3)",[other,id,at]);
   await assert.rejects(forged.query('COMMIT'),/Daily shift requires its reward/);
  }finally{await forged.query('ROLLBACK');forged.release();}
  assert.equal((await api.read(other))['completedChoice'],null);
  await owner.query("UPDATE trimmy.users SET status='closed' WHERE id=$1",[other]);
  await assert.rejects(api.read(other),/ACCOUNT_REQUIRED/);
 }finally{await runtime?.end();await owner.end();}
});
