import assert from 'node:assert/strict';
import test from 'node:test';
import {ProductEvents, arrivalProps, eventToken, type ProductEventsStorage} from '../src/product/product-events.js';

class Store implements ProductEventsStorage {
  values = new Map<string, string>(); fail = false;
  getItem(key: string) {if (this.fail) throw new Error('blocked'); return this.values.get(key) ?? null;}
  setItem(key: string, value: string) {if (this.fail) throw new Error('blocked'); this.values.set(key, value);}
  removeItem(key: string) {this.values.delete(key);}
}
function harness(statuses: number[] = []) {
  let now = Date.parse('2026-10-01T12:00:00.000Z'), n = 0;
  const storage = new Store(), calls: {url: string; body: any; headers: Record<string, string>}[] = [], timers: (() => void)[] = [];
  const uuid = () => `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`;
  const make = () => new ProductEvents({apiBase: 'https://api.example', appVersion: 'web-test', locale: () => 'pt-BR', storage, now: () => now, uuid,
    authorization: async () => 'Guest tg1_token', schedule: callback => {timers.push(callback);},
    fetch: async (url, init) => {calls.push({url: String(url), body: JSON.parse(String(init?.body)), headers: init?.headers as Record<string, string>});
      const status = statuses.shift() ?? 202; return new Response(status === 204 ? null : '{}', {status});}});
  return {storage, calls, timers, make, advance: (ms: number) => {now += ms;}};
}

test('events carry only the catalogued shape, batch, survive reloads and stop entirely when switched off', async () => {
  const h = harness([503, 202]);
  const events = h.make();
  events.track({name: 'app_open', props: {source: 'launch'}});
  events.once({name: 'onboarding_step', props: {step: 'welcome'}});
  events.once({name: 'onboarding_step', props: {step: 'welcome'}});
  events.once({name: 'tab_view', props: {tab: 'desk'}}, {perSession: true});
  events.once({name: 'tab_view', props: {tab: 'desk'}}, {perSession: true});
  await events.flush();
  assert.equal(h.calls.length, 1, 'the server was down');
  // A reload keeps what is unsent; the next flush delivers it once.
  const reloaded = h.make(); await reloaded.flush();
  assert.equal(h.calls.length, 2);
  const sent = h.calls[1]!.body;
  assert.equal(sent.schemaVersion, 1);
  assert.deepEqual(sent.events.map((e: any) => [e.name, e.props]), [['app_open', {source: 'launch'}], ['onboarding_step', {step: 'welcome'}], ['tab_view', {tab: 'desk'}]]);
  for (const event of sent.events) {
    assert.deepEqual(Object.keys(event).sort(), ['appVersion', 'id', 'installId', 'locale', 'name', 'occurredAt', 'platform', 'props', 'sessionId']);
    assert.equal(event.platform, 'web'); assert.equal(event.locale, 'pt-BR'); assert.equal(event.installId, sent.events[0].installId);
  }
  assert.equal(h.storage.values.get('trimmy.events.queue.v1'), undefined);
  // Thirty quiet minutes start a new session.
  h.advance(31 * 60_000); reloaded.resumed(); await reloaded.flush();
  const resumed = h.calls.at(-1)!.body.events[0];
  assert.equal(resumed.name, 'app_open'); assert.deepEqual(resumed.props, {source: 'resume'}); assert.notEqual(resumed.sessionId, sent.events[0].sessionId);
  // Off means nothing is recorded or kept.
  reloaded.track({name: 'mode_switch', props: {to: 'real'}});
  reloaded.setEnabled(false);
  reloaded.track({name: 'mode_switch', props: {to: 'practice'}});
  await reloaded.flush();
  assert.equal(h.calls.length, 3);
  assert.equal(h.make().enabled, false, 'the choice is remembered');
  assert.equal(h.storage.values.get('trimmy.events.queue.v1'), undefined);
});

test('a rejected batch is dropped, failures back off, and linking needs a credential once per desk', async () => {
  const h = harness([400, 204]);
  const events = h.make();
  events.track({name: 'startup_failed', props: {stage: 'network'}});
  await events.flush(); await events.flush();
  assert.equal(h.calls.length, 1, 'a 400 is never retried');
  await events.link('desk-1'); await events.link('desk-1');
  const link = h.calls[1]!;
  assert.equal(link.url, 'https://api.example/v1/events/link'); assert.equal(link.headers['Authorization'], 'Guest tg1_token');
  assert.deepEqual(link.body, {schemaVersion: 1, installId: events.installId});
  assert.equal(h.calls.length, 2, 'linked once per desk');
  // Blocked storage never breaks the app.
  h.storage.fail = true;
  const blocked = h.make();
  assert.doesNotThrow(() => blocked.track({name: 'app_open', props: {source: 'launch'}}));
});

test('arrival props keep only API-safe tokens and ignore this site as a referrer', () => {
  assert.deepEqual(arrivalProps('https://app.trimmy.xyz/?utm_source=X.com&utm_campaign=Stocklana Demo!', 'https://www.x.com/someone/status/1').props,
    {source: 'link', referrer: 'x.com', utm_source: 'x.com', utm_campaign: 'stocklana-demo'});
  assert.deepEqual(arrivalProps('https://app.trimmy.xyz/#desk', 'https://app.trimmy.xyz/', ['app.trimmy.xyz']).props, {source: 'launch'});
  assert.deepEqual(arrivalProps('not a url', 'also not').props, {source: 'launch'});
  assert.equal(eventToken('   '), undefined); assert.equal(eventToken('a'.repeat(80))?.length, 40);
});
