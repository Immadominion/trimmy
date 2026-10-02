import assert from 'node:assert/strict';
import test from 'node:test';
import {ProductEvents, type ProductEventsStorage} from '../src/product/product-events.js';
import {JourneyStore} from '../src/product/journey-store.js';
import {MemoryStorage, harness} from './support/product-harness.js';

class Store implements ProductEventsStorage {
  readonly values = new Map<string, string>();
  getItem(key: string) {return this.values.get(key) ?? null;}
  setItem(key: string, value: string) {this.values.set(key, value);}
  removeItem(key: string) {this.values.delete(key);}
}
function recorder() {
  const sent: {name: string; props: Record<string, unknown>}[] = [], links: string[] = [];
  let n = 0;
  const usage = new ProductEvents({apiBase: '/api', appVersion: '0.1.0+test', locale: () => 'en', storage: new Store(),
    uuid: () => `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`, schedule: () => undefined,
    fetch: async (url, init) => {
      if (String(url).endsWith('/v1/events/link')) {links.push(new Headers(init?.headers).get('authorization') ?? ''); return new Response(null, {status: 204});}
      const body = JSON.parse(String(init?.body)) as {events: {name: string; props: Record<string, unknown>}[]};
      sent.push(...body.events.map(event => ({name: event.name, props: event.props})));
      return Response.json({accepted: body.events.length}, {status: 202});
    }});
  return {usage, sent, links};
}
function chosenGuest() {const storage = new MemoryStorage(); new JourneyStore(storage, '/api').chooseGuest(); return storage;}

test('the workspace records arrivals, tabs and money sheets, and ties the browser to its desk', async () => {
  const {usage, sent, links} = recorder();
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest(), usage});
  try {
    await h.app(); await h.flush(60);
    await h.click('Market'); await h.flush(40);
    await h.click('Career'); await h.flush(40);
    await h.click('Desk'); await h.flush(40);
    await h.click('Fast buy'); await h.flush(40);
    await usage.flush();
    const names = sent.map(event => `${event.name}${event.props['tab'] ? `:${event.props['tab']}` : ''}${event.props['action'] ? `:${event.props['action']}` : ''}`);
    assert.equal(names[0], 'app_open');
    assert.deepEqual(sent[0]!.props, {source: 'launch'});
    for (const expected of ['tab_view:market', 'tab_view:career', 'tab_view:desk', 'money_action:fast_buy_open']) assert.ok(names.includes(expected), `${expected} in ${names.join(', ')}`);
    assert.ok(sent.some(event => event.name === 'onboarding_step' && event.props['step'] === 'home'), 'reaching the desk counts as home');
    assert.equal(links.length, 1, 'the browser is tied to the guest desk once');
    assert.match(links[0]!, /^Guest tg1_/);
    for (const event of sent) for (const value of Object.values(event.props)) assert.ok(typeof value !== 'string' || value.length <= 40, 'only short tokens leave the browser');
  } finally {await h.close();}
});

test('turning Share usage data off in Settings stops recording and forgets what was waiting', async () => {
  const {usage, sent} = recorder();
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest(), usage});
  try {
    await h.app(); await h.flush(40);
    await h.click('Profile'); await h.click('Settings'); await h.flush(40);
    const toggle = h.dom.window.document.querySelector<HTMLInputElement>('input[aria-label="Share usage data"]');
    assert.ok(toggle, 'the switch is in Settings'); assert.equal(toggle.checked, true);
    await h.flush(); toggle.click(); await h.flush(40);
    assert.equal(usage.enabled, false);
    await h.click('← Back to Profile').catch(() => undefined);
    await h.click('Market'); await h.flush(40);
    await usage.flush();
    assert.equal(sent.length, 0, 'nothing waiting was sent and nothing new was recorded');
  } finally {await h.close();}
});

test('without a recorder the product records nothing and shows no switch', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await h.app(); await h.click('Profile'); await h.click('Settings'); await h.flush(40);
    assert.equal(h.dom.window.document.querySelector('input[aria-label="Share usage data"]'), null);
  } finally {await h.close();}
});

test('a new install records each first-day step once, and a skip with its step', async () => {
  const {usage, sent} = recorder();
  const h = await harness({usage});
  try {
    await h.app(); await h.flush(40);
    await h.click('Start my first day'); await h.flush(40);
    await h.click('Skip the first day').catch(async () => {
      const skip = h.dom.window.document.querySelector<HTMLButtonElement>('.intro-close'); assert.ok(skip, 'the skip button'); skip.click(); await h.flush(40);
      // The × asks first.
      const confirm = h.dom.window.document.querySelector<HTMLButtonElement>('.workday-leave-dialog .text-button'); assert.ok(confirm, 'the skip question'); confirm.click(); await h.flush(40);
    });
    await usage.flush();
    const steps = sent.filter(event => event.name === 'onboarding_step').map(event => event.props['step']);
    assert.deepEqual(steps.slice(0, 2), ['welcome', 'note']);
    assert.ok(sent.some(event => event.name === 'onboarding_skip' && event.props['step'] === 'note'), JSON.stringify(sent));
  } finally {await h.close();}
});
