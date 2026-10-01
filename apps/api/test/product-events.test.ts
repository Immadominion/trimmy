import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {buildApp} from '../src/app.js';
import {PRODUCT_EVENT_CATALOG, ProductEventBudget, parseProductEvent, type ProductEvent, type ProductEventStore} from '../src/product-events.js';

const NOW = Date.parse('2026-10-01T12:00:00.000Z');
const base = () => ({id: randomUUID(), installId: '0b3c6a7e-2f4d-4b1a-9c8e-1d2f3a4b5c6d', sessionId: randomUUID(),
 platform: 'ios', appVersion: '0.1.0+3', locale: 'es-419', name: 'app_open', props: {source: 'launch'}, occurredAt: '2026-10-01T11:59:00.000Z'});

test('the catalog accepts only allowlisted names, properties and value shapes', () => {
 const ok = parseProductEvent(base(), NOW);
 assert.ok(ok); assert.equal(ok.occurredAt, '2026-10-01T11:59:00.000Z'); assert.ok(Object.isFrozen(ok.props));
 assert.ok(parseProductEvent({...base(), name: 'app_open', props: {source: 'link', utm_source: 'x.com', utm_campaign: 'stocklana-demo'}}, NOW));
 assert.ok(parseProductEvent({...base(), name: 'workday_open', props: {ordinal: 3, resumed: false}}, NOW));
 assert.ok(parseProductEvent({...base(), name: 'language_set', props: {language: 'pt-BR'}, platform: 'web', appVersion: 'web-d0a5cbe'}, NOW));
 for (const [label, change] of [
  ['unknown event', {name: 'purchase'}],
  ['unknown property', {props: {source: 'launch', email: 'a@b.co'}}],
  ['missing required property', {props: {}}],
  ['value outside the enum', {props: {source: 'ad'}}],
  ['free text in a token', {name: 'app_open', props: {source: 'link', utm_campaign: 'My Campaign!'}}],
  ['integer out of range', {name: 'workday_open', props: {ordinal: 0, resumed: true}}],
  ['wrong type', {name: 'workday_open', props: {ordinal: '3', resumed: true}}],
  ['bad uuid', {installId: 'device-123'}],
  ['bad platform', {platform: 'desktop'}],
  ['bad locale', {locale: 'Spanish'}],
  ['local time', {occurredAt: '2026-10-01T11:59:00+01:00'}],
  ['too old', {occurredAt: '2026-09-20T12:00:00.000Z'}],
  ['in the future', {occurredAt: '2026-10-01T12:10:00.000Z'}],
  ['extra top-level field', {userId: randomUUID()}],
 ] as const) assert.equal(parseProductEvent({...base(), ...change}, NOW), null, label);
 assert.equal(parseProductEvent(null, NOW), null); assert.equal(parseProductEvent([base()], NOW), null);
 // Every catalogued property has a closed shape; none takes arbitrary text.
 for (const rules of Object.values(PRODUCT_EVENT_CATALOG)) for (const rule of Object.values(rules)) assert.ok(['enum', 'int', 'bool', 'token'].includes(rule.kind));
});

test('the per-minute budget caps each install and the process, and resets each minute', () => {
 let now = NOW; const budget = new ProductEventBudget({perInstall: 2, total: 3, now: () => now});
 assert.deepEqual([budget.take('a'), budget.take('a'), budget.take('a')], [true, true, false]);
 assert.deepEqual([budget.take('b'), budget.take('c')], [true, false]);
 now += 60_000; assert.equal(budget.take('a'), true);
});

test('events record without sign-in, refuse malformed batches whole, and link only with a credential', async () => {
 const recorded: ProductEvent[][] = [], links: [string, string][] = []; let fail = false;
 const store: ProductEventStore = {record: async events => {if (fail) throw Error('down'); recorded.push([...events]); return events.length;},
  link: async (userId, installId) => {links.push([userId, installId]);}, prune: async () => 0};
 const app = buildApp({logger: false, events: {store, now: () => NOW, budget: new ProductEventBudget({perInstall: 2, total: 100, now: () => NOW}),
  authenticate: async request => request.headers.authorization === 'Bearer good' ? {userId: 'user-1'} : null}});
 try {
  const post = (payload: Record<string, unknown>, headers: Record<string, string> = {}) => app.inject({method: 'POST', url: '/v1/events', payload, headers});
  let result = await post({schemaVersion: 1, events: [base(), {...base(), name: 'tab_view', props: {tab: 'market'}}]});
  assert.equal(result.statusCode, 202); assert.deepEqual(result.json(), {schemaVersion: 1, accepted: 2});
  assert.equal(result.headers['cache-control'], 'no-store');
  // Over this install's budget: accepted quietly, not stored, not an error a client would retry.
  result = await post({schemaVersion: 1, events: [base()]});
  assert.equal(result.statusCode, 202); assert.deepEqual(result.json(), {schemaVersion: 1, accepted: 0});
  assert.equal(recorded.length, 1);
  result = await post({schemaVersion: 1, events: [{...base(), installId: randomUUID()}, {...base(), name: 'nope'}]});
  assert.equal(result.statusCode, 400); assert.deepEqual(result.json(), {code: 'EVENTS_INVALID'}); assert.equal(recorded.length, 1);
  for (const payload of [{schemaVersion: 2, events: [base()]}, {schemaVersion: 1, events: []}, {schemaVersion: 1, events: Array.from({length: 51}, base)}, {schemaVersion: 1}])
   assert.equal((await post(payload)).statusCode, 400);
  fail = true;
  result = await post({schemaVersion: 1, events: [{...base(), installId: randomUUID()}]});
  assert.equal(result.statusCode, 503); assert.ok(!result.body.includes('down'));
  const install = randomUUID();
  assert.equal((await app.inject({method: 'POST', url: '/v1/events/link', payload: {schemaVersion: 1, installId: install}})).statusCode, 401);
  assert.equal((await app.inject({method: 'POST', url: '/v1/events/link', payload: {schemaVersion: 1, installId: 'not-a-uuid'}, headers: {authorization: 'Bearer good'}})).statusCode, 400);
  result = await app.inject({method: 'POST', url: '/v1/events/link', payload: {schemaVersion: 1, installId: install}, headers: {authorization: 'Bearer good'}});
  assert.equal(result.statusCode, 204); assert.deepEqual(links, [['user-1', install]]);
 } finally { await app.close(); }
 // Without a database the routes exist but say so.
 const bare = buildApp({logger: false});
 try {assert.equal((await bare.inject({method: 'POST', url: '/v1/events', payload: {schemaVersion: 1, events: [base()]}})).statusCode, 503);}
 finally {await bare.close();}
});
