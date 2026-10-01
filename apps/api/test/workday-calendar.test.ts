import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {HOLIDAYS} from '../src/us-equity-calendar.js';
test('the career desk closes on exactly the NYSE holidays the trading calendar knows',async()=>{
 const sql=await readFile(new URL('../../../infra/migrations/0036_weekday_workdays.sql',import.meta.url),'utf8');
 const seeded=[...sql.matchAll(/\('(\d{4}-\d{2}-\d{2})','([a-z-]+)'\)/g)].map(match=>match[1]!);
 assert.equal(new Set(seeded).size,seeded.length);
 assert.deepEqual([...seeded].sort(),[...HOLIDAYS].sort());
 for(const day of seeded)assert.ok(![0,6].includes(new Date(`${day}T12:00:00Z`).getUTCDay()),`${day} is a weekday`);
});
