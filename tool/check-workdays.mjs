import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const source=JSON.parse(readFileSync(resolve(root,process.argv[2]??'content/workdays/intern-v1.json'),'utf8'));
assert.equal(source.schemaVersion,1);assert.match(source.contentVersion,/^[a-z0-9.-]+$/);
assert.ok(source.assignments.length>0&&source.assignments.length<=200);
const ids=new Set(),ordinals=new Set();
for(const item of source.assignments){
 assert.match(item.id,/^[a-z0-9]+(?:-[a-z0-9]+)*$/);assert.ok(!ids.has(item.id));ids.add(item.id);
 assert.ok(Number.isSafeInteger(item.ordinal)&&item.ordinal>0&&!ordinals.has(item.ordinal));ordinals.add(item.ordinal);
 for(const field of ['title','brief','speaker','district','sourceTitle','sourceLabel','feedback']) assert.ok(typeof item[field]==='string'&&item[field].trim().length>0,`${item.id}: missing ${field}`);
 assert.ok(existsSync(resolve(root,`apps/mobile/assets/images/career_world/${item.art}.png`)),`${item.id}: missing scenery`);
 assert.ok(item.speaker==='sal'||existsSync(resolve(root,`apps/mobile/assets/images/ui_review/persona-${item.speaker}-avatar-v1.png`)),`${item.id}: missing character`);
 for(const [choices,required]of [[item.rows,item.evidence.requiredIds],[item.file.parts,item.file.requiredIds]]){
  const choicesIds=new Set(choices.map(row=>row.id));assert.equal(choicesIds.size,choices.length);
  assert.ok(required.length>0&&required.length<choices.length);assert.equal(new Set(required).size,required.length);
  for(const id of required)assert.ok(choicesIds.has(id),`${item.id}: missing evidence ${id}`);
 }
 assert.ok(['number','choice'].includes(item.decision.kind));assert.ok(item.decision.acceptedAnswers.length>0);
 if(item.decision.kind==='choice')for(const id of item.decision.acceptedAnswers)assert.ok(item.decision.choices.some(choice=>choice.id===id));
 else for(const value of item.decision.acceptedAnswers)assert.match(value,/^-?[0-9]+(?:\.[0-9]+)?$/);
 if(item.context){const previous=source.assignments.find(x=>x.id===item.context.fromId);assert.ok(previous&&previous.ordinal<item.ordinal);}
}
if(!process.argv[2]){
 const sql=readFileSync(resolve(root,'infra/migrations/0030_intern_workdays.sql'),'utf8');
 const seeded=[...sql.matchAll(/\$work\$(.*?)\$work\$::jsonb/g)].map(match=>JSON.parse(match[1]));
 assert.deepEqual(seeded,source.assignments,'Released workdays must match their immutable seed. Add new assignments in a new migration.');
}
console.log(`${source.assignments.length} workdays checked: content, answers, assets and immutable release seed.`);
