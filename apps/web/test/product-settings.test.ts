import assert from 'node:assert/strict';
import test from 'node:test';
import {act} from 'react';
import {MemoryStorage, harness, json} from './support/product-harness.js';
import {JourneyStore} from '../src/product/journey-store.js';
import type {Harness} from './support/product-harness.js';

async function openSettings(h: Harness) {await h.app(); await h.click('Profile'); await h.click('Settings'); assert.match(h.text(), /Settings/);}
function chosenGuest() {const storage = new MemoryStorage(); new JourneyStore(storage, '/api').chooseGuest(); return storage;}
async function type(h: Harness, label: string, value: string) {
  const field = h.dom.window.document.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`); assert.ok(field, `Field exists: ${label}`);
  await act(async () => {Object.getOwnPropertyDescriptor(h.dom.window.HTMLInputElement.prototype, 'value')!.set!.call(field, value); field.dispatchEvent(new h.dom.window.Event('input', {bubbles: true}));});
  await h.flush();
}

test('guest Settings offers sign-in, honest browser limits and no account closure', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await openSettings(h);
    for (const text of ['Sign in to keep your progress.', 'Sounds for key moments.', 'Haptics', 'Not available in a browser.', 'Paper limit', '10,000 paper',
      'Reset paper', 'Clear paper trades and start again.', 'Who can see my comments', 'Only you can see your comments.', 'Terms', 'Privacy']) assert.ok(h.text().includes(text), text);
    assert.doesNotMatch(h.text(), /Close account|Sign out/);
    assert.equal(h.dom.window.document.querySelector('nav [aria-current="page"]')?.textContent?.trim(), 'Profile');
  } finally {await h.close();}
});

test('comment privacy saves through the server and shows only what it confirmed', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await openSettings(h); await h.click('Change who can see my comments');
    const dialog = () => h.dom.window.document.querySelector('[role="dialog"]');
    assert.ok(dialog()); assert.match(dialog()!.textContent ?? '', /Now: Nobody\./);
    await h.pick('Everyone');
    assert.match(h.text(), /Your comments and your handle will show on that stock’s page for anyone in Trimmy\. Money never shows\./);
    await h.click('Save');
    const put = h.api.calls.find(call => call.path === '/v1/career/reason-privacy' && call.method === 'PUT');
    assert.equal(put?.body?.['visibility'], 'everyone'); assert.equal(put?.body?.['baseRevision'], 1); assert.equal(put?.body?.['schemaVersion'], 1);
    assert.match(h.text(), /Saved\. Anyone in Trimmy can see them on each stock page\./);
  } finally {await h.close();}
});

test('a privacy change from another device refreshes instead of overwriting it', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await openSettings(h);
    Object.assign(h.api.state.privacy, {revision: 2, visibility: 'everyone', configured: true, updatedAt: new Date(Date.now() + 5000).toISOString()});
    await h.click('Change who can see my comments'); await h.pick('Friends'); await h.click('Save');
    assert.match(h.text(), /Changed on another device\. Refreshed\. Anyone in Trimmy can see them on each stock page\./);
    assert.equal(h.api.state.privacy['visibility'], 'everyone');
  } finally {await h.close();}
});

test('an interrupted privacy save keeps the exact choice and Try again replays the same command', async () => {
  let lose = true;
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest(), reply: call => {
    if (call.path === '/v1/career/reason-privacy' && call.method === 'PUT' && lose) {lose = false; throw new TypeError('Lost');}
    return undefined;
  }});
  try {
    await openSettings(h); await h.click('Change who can see my comments'); await h.pick('Everyone'); await h.click('Save');
    assert.match(h.text(), /You are offline\. Everyone is not saved yet\./);
    await h.click('Try again');
    const puts = h.api.calls.filter(call => call.path === '/v1/career/reason-privacy' && call.method === 'PUT');
    assert.equal(puts.length, 2); assert.deepEqual(puts[1]?.body, puts[0]?.body);
    assert.match(h.text(), /Saved\. Anyone in Trimmy/);
  } finally {await h.close();}
});

test('paper reset needs the exact typed phrase and reports the fresh balance', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await openSettings(h); await h.click('Reset');
    assert.match(h.text(), /Reset your paper desk\?/); assert.match(h.text(), /Past receipts stay in your record\. Your Career, Trims, rank, streak and money do not change\./);
    assert.equal(h.button('Reset paper desk')?.disabled, true);
    await type(h, 'Confirmation phrase. Type reset my paper desk.', 'reset my desk');
    assert.equal(h.button('Reset paper desk')?.disabled, true);
    // Phones capitalize the first word and keyboards add a space; neither should block the reset.
    await type(h, 'Confirmation phrase. Type reset my paper desk.', 'Reset my paper desk ');
    assert.equal(h.button('Reset paper desk')?.disabled, false);
    await type(h, 'Confirmation phrase. Type reset my paper desk.', 'reset my paper desk');
    await h.click('Reset paper desk');
    const reset = h.api.calls.find(call => call.path === '/v1/account/paper/reset');
    assert.equal(reset?.body?.['baseRevision'], 1); assert.equal(reset?.body?.['confirm'], 'reset my paper desk');
    assert.match(h.text(), /Paper desk reset/); assert.match(h.text(), /Your desk is ready with 10,000\.00 paper\./);
  } finally {await h.close();}
});

test('an unconfirmed reset keeps its exact request and Finish reset replays it', async () => {
  let lose = true;
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest(), reply: call => {
    if (call.path === '/v1/account/paper/reset' && lose) {lose = false; throw new TypeError('Lost');}
    return undefined;
  }});
  try {
    await openSettings(h); await h.click('Reset'); await type(h, 'Confirmation phrase. Type reset my paper desk.', 'reset my paper desk'); await h.click('Reset paper desk');
    assert.match(h.text(), /You are offline\. Your exact reset request is saved for a safe retry\./);
    assert.match(h.text(), /Your confirmed reset is waiting to finish\./);
    await h.click('Finish reset');
    const resets = h.api.calls.filter(call => call.path === '/v1/account/paper/reset');
    assert.equal(resets.length, 2); assert.deepEqual(resets[1]?.body, resets[0]?.body);
    assert.match(h.text(), /Paper desk reset/);
  } finally {await h.close();}
});

test('a stale reset refreshes the desk and asks for a new confirmation', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest(), reply: call => call.path === '/v1/account/paper/reset'
    ? json({error: {code: 'PAPER_PORTFOLIO_CHANGED', message: 'Changed.', requestId: 'x'}}, 409) : undefined});
  try {
    await openSettings(h); await h.click('Reset'); await type(h, 'Confirmation phrase. Type reset my paper desk.', 'reset my paper desk'); await h.click('Reset paper desk');
    assert.match(h.text(), /Your paper desk changed\. It was refreshed\. Review it, then confirm the reset again\./);
    assert.doesNotMatch(h.text(), /waiting to finish/);
  } finally {await h.close();}
});

test('a signed-in account can close its account after an explicit confirmation, then leaves the account', async () => {
  const h = await harness({account: true, checkpoint: 'app'});
  try {
    await openSettings(h);
    assert.match(h.text(), /Review what happens to your records and wallet\./);
    await h.click('Close account');
    assert.match(h.text(), /Close your account\?/); assert.match(h.text(), /Closing will not move its funds\./);
    await h.click('Cancel'); assert.equal(h.api.state.closed, false);
    await h.click('Close account');
    const confirm = [...h.dom.window.document.querySelectorAll<HTMLButtonElement>('[role="dialog"] button')].find(item => item.textContent === 'Close account')!;
    await act(async () => {confirm.click();}); await h.flush();
    assert.equal(h.api.state.closed, true);
    assert.equal(h.api.calls.find(call => call.path === '/v1/account/closure')?.body?.['confirm'], 'close my account');
  } finally {await h.close();}
});

test('sound and animation preferences apply immediately and are kept on this browser', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await openSettings(h);
    const sound = h.dom.window.document.querySelector<HTMLInputElement>('input[aria-label="Sound"]')!;
    const before = sound.checked;
    await act(async () => {sound.click();}); await h.flush();
    assert.equal(h.dom.window.document.querySelector<HTMLInputElement>('input[aria-label="Sound"]')!.checked, !before);
    assert.equal(h.dom.window.localStorage.getItem('trimmy.web.workSound'), before ? 'off' : 'on');
  } finally {await h.close();}
});

test('reminders open from Settings and closing them changes nothing', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await openSettings(h);
    assert.match(h.text(), /Not set on this browser\./);
    await h.click('Change reminders');
    assert.match(h.text(), /A little nudge\?/);
    await h.escape();
    assert.match(h.text(), /Not set on this browser\./, 'Escape closes without turning reminders off');
    await h.click('Change reminders'); await h.pick('A few times a week'); await h.click('Continue'); await h.click('Continue');
    assert.match(h.text(), /Mon, Wed and Fri, around 7 PM\. Saved on this browser\./);
  } finally {await h.close();}
});

test('an open dialog keeps Tab inside it, holds the page still and gives focus back when it closes', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await openSettings(h);
    const opener = h.button('Change who can see my comments')!;
    opener.focus(); await h.click('Change who can see my comments');
    const dialog = h.dom.window.document.querySelector<HTMLElement>('[role="dialog"]')!;
    assert.ok(dialog);
    assert.ok(h.dom.window.document.documentElement.classList.contains('modal-open'), 'the page behind is held still');
    const focusable = [...dialog.querySelectorAll<HTMLElement>('button:not([disabled]), input:not([disabled])')];
    const tab = (shiftKey = false) => h.dom.window.document.dispatchEvent(new h.dom.window.KeyboardEvent('keydown', {key: 'Tab', shiftKey, bubbles: true, cancelable: true}));
    focusable.at(-1)!.focus(); tab();
    assert.equal(h.dom.window.document.activeElement, focusable[0], 'Tab from the last control wraps to the first');
    tab(true);
    assert.equal(h.dom.window.document.activeElement, focusable.at(-1), 'Shift+Tab from the first wraps to the last');
    await h.escape();
    assert.equal(h.dom.window.document.querySelector('[role="dialog"]'), null);
    assert.equal(h.dom.window.document.documentElement.classList.contains('modal-open'), false);
    assert.equal(h.dom.window.document.activeElement, opener, 'focus is back on what opened it');
  } finally {await h.close();}
});
