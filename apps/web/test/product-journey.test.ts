import assert from 'node:assert/strict';
import test from 'node:test';
import {firstTradeEvidence, journeyView, needsAccountChoice} from '../src/product/journey.js';
import type {FirstTradeEvidence, JourneyInput} from '../src/product/journey.js';
import {JourneyStorageError, JourneyStore, journeyPrincipal} from '../src/product/journey-store.js';
import {firstReminderDate, reminderCalendar} from '../src/product/reminder-calendar.js';
import type {CareerSummary, LaunchCheckpoint, PaperReceipt, ProductProfile} from '../src/product/practice-client.js';

const ORDER = '33333333-3333-4333-8333-333333333333';
const GUEST = '11111111-1111-4111-8111-111111111111';
const ACCOUNT = '22222222-2222-4222-8222-222222222222';
const AT = '2026-09-27T10:00:00.000Z';
function profile(launchCheckpoint: LaunchCheckpoint, hasConfirmedPaperTrade = launchCheckpoint !== 'first-trade'): ProductProfile {
  return {revision: 2, onboarding: {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null},
    launchCheckpoint, hasConfirmedPaperTrade, createdAt: AT, updatedAt: AT};
}
const evidence: FirstTradeEvidence = {orderId: ORDER, assetId: 'apple', variantMint: 'mint', symbol: 'AAPLx', quantityMicros: '2000000', cashDebitPaperMicros: '100000000'};
function input(overrides: Partial<JourneyInput> = {}): JourneyInput {
  return {identity: 'guest', profile: profile('first-trade', false), guestChosen: false, gateOpen: false,
    step: null, celebratedOrder: null, evidence: null, ...overrides};
}
class Store {
  data = new Map<string, string>(); failWrites = false; failReads = false;
  getItem(key: string) {if (this.failReads) throw new Error('blocked'); return this.data.get(key) ?? null;}
  setItem(key: string, value: string) {if (this.failWrites) throw new Error('quota'); this.data.set(key, value);}
}

test('a fresh visitor, an unknown profile and a guest without a profile stay outside the follow-up', () => {
  assert.equal(journeyView(input({identity: 'none'})).kind, 'outside');
  assert.equal(journeyView(input({profile: undefined})).kind, 'outside');
  assert.equal(journeyView(input({profile: null})).kind, 'outside');
});

test('before a confirmed order the first day stays in practice and never asks for an account', () => {
  assert.equal(journeyView(input()).kind, 'practice');
  assert.equal(needsAccountChoice(input()), false);
});

test('confirmed order evidence resumes the celebration instead of offering a second purchase', () => {
  assert.deepEqual(journeyView(input({evidence})), {kind: 'celebration', evidence});
  assert.deepEqual(journeyView(input({profile: profile('first-trade', true)})), {kind: 'celebration', evidence: null});
  // A step saved before the checkpoint moved still waits for the server checkpoint.
  assert.equal(journeyView(input({evidence, step: 1})).kind, 'celebration');
});

test('after the celebration a guest must choose; Back-free state keeps asking until the explicit choice', () => {
  const afterCelebration = input({profile: profile('first-position'), evidence, step: 1});
  assert.equal(journeyView(afterCelebration).kind, 'gate');
  assert.equal(journeyView({...afterCelebration, guestChosen: true}).kind, 'reminders');
  assert.equal(journeyView({...afterCelebration, step: 2, guestChosen: true}).kind, 'money');
  // First position before its celebration is acknowledged shows the celebration, not the gate.
  assert.equal(journeyView(input({profile: profile('first-position'), evidence})).kind, 'celebration');
});

test('Skip and existing anonymous progress at the app checkpoint still require the account choice', () => {
  assert.equal(journeyView(input({profile: profile('app', false)})).kind, 'gate');
  assert.equal(journeyView(input({profile: profile('app', false), guestChosen: true})).kind, 'app');
  assert.equal(journeyView(input({profile: profile('streak')})).kind, 'gate');
  assert.equal(journeyView(input({profile: profile('save-desk')})).kind, 'gate');
});

test('an open gate stays open until a choice or sign-in closes it', () => {
  assert.equal(journeyView(input({gateOpen: true})).kind, 'gate');
  assert.equal(journeyView(input({gateOpen: true, guestChosen: true})).kind, 'practice');
  assert.equal(journeyView(input({gateOpen: true, identity: 'account'})).kind, 'practice');
});

test('signed-in accounts never see the guest gate and continue their own saved checkpoint', () => {
  assert.equal(journeyView(input({identity: 'account', profile: profile('app')})).kind, 'app');
  assert.equal(journeyView(input({identity: 'account', profile: profile('first-position'), evidence, step: 1})).kind, 'reminders');
  // A claimed desk changes principal; the same celebrated order continues at reminders.
  assert.equal(journeyView(input({identity: 'account', profile: profile('first-position'), evidence, celebratedOrder: ORDER})).kind, 'reminders');
  assert.equal(journeyView(input({identity: 'account', profile: profile('first-position'), evidence, celebratedOrder: '44444444-4444-4444-8444-444444444444'})).kind, 'celebration');
  // Mobile's legacy checkpoints open at the matching follow-up step.
  assert.equal(journeyView(input({identity: 'account', profile: profile('streak')})).kind, 'reminders');
  assert.equal(journeyView(input({identity: 'account', profile: profile('save-desk')})).kind, 'money');
});

test('first-trade evidence prefers the server first buy and only takes the amount from the same receipt', () => {
  const first = {orderId: ORDER, assetId: 'apple', variantMint: 'mint', symbol: 'AAPLx', quantityMicros: '2000000', confirmedAt: AT};
  const career = {firstConfirmedBuy: first} as unknown as CareerSummary;
  const receipt = {id: ORDER, action: 'buy', assetId: 'apple', variantMint: 'mint', symbol: 'AAPLx', quantityMicros: '2000000', cashDebitPaperMicros: '100000000'} as unknown as PaperReceipt;
  assert.equal(firstTradeEvidence(career, receipt)?.cashDebitPaperMicros, '100000000');
  assert.equal(firstTradeEvidence(career, {...receipt, id: '55555555-5555-4555-8555-555555555555'})?.cashDebitPaperMicros, null);
  assert.equal(firstTradeEvidence(null, receipt)?.orderId, ORDER);
  assert.equal(firstTradeEvidence(null, {...receipt, action: 'sell'} as PaperReceipt), null);
  assert.equal(firstTradeEvidence(null, null), null);
});

test('the journey store saves only explicit choices, verifies writes and namespaces by API and principal', () => {
  const storage = new Store(), store = new JourneyStore(storage, '/api'), guest = journeyPrincipal({guestId: GUEST});
  assert.equal(store.guestChosen(), false);
  store.chooseGuest(); assert.equal(store.guestChosen(), true);
  assert.equal(new JourneyStore(storage, 'https://api.example').guestChosen(), false);
  store.acknowledgeCelebration(guest, ORDER);
  assert.equal(store.step(guest), 1); assert.equal(store.celebratedOrder(), ORDER);
  assert.equal(store.step(journeyPrincipal({accountId: ACCOUNT})), null);
  store.setStep(guest, 2); store.acknowledgeCelebration(guest, ORDER);
  assert.equal(store.step(guest), 2, 'acknowledging again never moves a saved step backwards');
  assert.equal(store.saveReminder(guest, 'daily').choice, 'daily'); assert.equal(store.reminder(guest)?.choice, 'daily');
  storage.data.set([...storage.data.keys()].find(key => key.includes(':reminders:'))!, '{"version":1,"choice":"hourly","savedAt":"x"}');
  assert.equal(store.reminder(guest), null);
  store.forgetGuestChoice(); assert.equal(store.guestChosen(), false);
});

test('unreadable storage asks again and failed writes are reported instead of assumed', () => {
  const storage = new Store(), store = new JourneyStore(storage, '/api');
  storage.failWrites = true;
  assert.throws(() => store.chooseGuest(), JourneyStorageError); assert.equal(store.guestChosen(), false);
  storage.failWrites = false; store.chooseGuest(); storage.failReads = true;
  assert.equal(store.guestChosen(), false);
  assert.equal(store.step(journeyPrincipal({guestId: GUEST})), null);
});

test('sign-in intents are short-lived hints consumed once', () => {
  let now = Date.parse(AT);
  const storage = new Store(), store = new JourneyStore(storage, '/api', () => now);
  store.setSignInIntent('fund'); assert.equal(store.consumeSignInIntent(), 'fund'); assert.equal(store.consumeSignInIntent(), null);
  store.setSignInIntent('app'); now += 16 * 60_000; assert.equal(store.consumeSignInIntent(), null);
  storage.data.set([...storage.data.keys()].find(key => key.endsWith(':sign-in-intent'))!, '{"intent":"admin","at":1}');
  assert.equal(store.consumeSignInIntent(), null);
});

test('reminder calendar files repeat at 7 PM local time with mobile’s schedule and no permission request', () => {
  const now = new Date(2026, 8, 27, 20, 30); // Sunday evening, after 7 PM.
  assert.equal(firstReminderDate('daily', now).getDate(), 28);
  assert.equal(firstReminderDate('occasional', now).getDay(), 1);
  assert.equal(firstReminderDate('daily', new Date(2026, 8, 28, 9)).getDate(), 28);
  const daily = reminderCalendar('daily', {now, url: 'https://app.trimmy.xyz/#career', uid: 'abc'});
  assert.match(daily, /^BEGIN:VCALENDAR\r\n/); assert.match(daily, /\r\nRRULE:FREQ=DAILY\r\n/);
  assert.match(daily, /\r\nDTSTART:20260928T190000\r\n/, 'floating local time keeps 7 PM in the person’s own time zone');
  assert.doesNotMatch(daily, /DTSTART:[^\r]*Z/);
  const weekly = reminderCalendar('occasional', {now, url: 'https://app.trimmy.xyz/#career', uid: 'abc'});
  assert.match(weekly, /\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\r\n/);
  for (const line of weekly.split('\r\n')) assert.ok(new TextEncoder().encode(line).length <= 75, `folded: ${line}`);
  assert.throws(() => reminderCalendar('daily', {now, url: 'http://example.com/', uid: 'abc'}));
});
