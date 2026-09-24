import assert from 'node:assert/strict';
import test from 'node:test';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {WorkdayScreen, type WorkdayScreenProps} from '../src/product/workday-screen.js';
import type {WorkdayAnswer, WorkdayAssignment} from '../src/product/practice-client.js';

const initial: WorkdayAssignment = {id: 'morning-brief', ordinal: 1, title: 'The morning brief', speaker: 'sal', district: 'First days',
  brief: 'Aster’s update is in. Tell me what actually changed.', sourceTitle: 'Aster · annual update', sourceLabel: 'Office simulation', art: 'newspaper',
  rows: [{id: 'before', label: '2024', value: '$1,000 sales · $600 costs', detail: 'Profit is what remains after the costs shown.'},
    {id: 'after', label: '2025', value: '$1,500 sales · $1,300 costs', detail: 'Compare the two periods.'},
    {id: 'headline', label: 'Draft headline', value: 'A record year for profit', detail: 'Check the claim against the figures.'}],
  evidence: {prompt: 'Pin the two periods you need to check profit.', count: 2},
  decision: {kind: 'number', prompt: 'What was Aster’s 2025 profit?', hint: 'Subtract 2025 costs from 2025 sales.', choices: [], unit: '$'},
  file: {prompt: 'File your update', count: 2, parts: [{id: 'fact-1', text: 'Sales rose from $1,000 to $1,500.'},
    {id: 'fact-2', text: 'Profit fell from $400 to $200.'}, {id: 'fact-3', text: 'Higher sales prove profit increased.'}]},
  revision: 0, step: 0, answers: {}, draft: '', completedAt: null, artifact: null, feedback: null, contextNote: null};
function atStep(step: 0 | 1 | 2 | 3, draft = ''): WorkdayAssignment {
  return {...initial, revision: step, step, draft,
    answers: {...(step > 0 ? {'0': {ids: ['before', 'after']}} : {}), ...(step > 1 ? {'1': {value: '200'}} : {}), ...(step > 2 ? {'2': {ids: ['fact-1', 'fact-2']}} : {})},
    ...(step === 3 ? {completedAt: '2026-09-24T12:00:00Z', artifact: `Sales rose. Profit fell.${draft ? `\n${draft}` : ''}`, feedback: 'You found the part the headline missed.'} : {})};
}
function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(done => {resolve = done;}); return {promise, resolve};}
async function harness(overrides: Partial<WorkdayScreenProps> = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#workday/morning-brief', pretendToBeVisual: true});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document,
    navigator: dom.window.navigator, HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const calls = {submits: [] as {work: WorkdayAssignment; answer: WorkdayAnswer; draft: string | undefined}[], drafts: [] as string[], draftWrites: [] as {work: WorkdayAssignment; draft: string}[], recover: 0, back: 0, cues: [] as string[]};
  let guard: (() => Promise<boolean>) | null = null;
  const registerLeaveGuard = (value: (() => Promise<boolean>) | null) => {guard = value;};
  let props: WorkdayScreenProps = {assignment: initial, working: false, pending: false, error: null,
    onSubmit: async (work, answer, draft) => {calls.submits.push({work, answer, draft}); return true;},
    onSaveDraft: async (work, draft) => {calls.drafts.push(draft); calls.draftWrites.push({work, draft}); return true;},
    onRecover: async () => {calls.recover++; return true;}, onBack: () => {calls.back++;}, onCue: cue => {calls.cues.push(cue);}, registerLeaveGuard, ...overrides};
  const render = async (update: Partial<WorkdayScreenProps> = {}) => {props = {...props, ...update}; await act(async () => {root.render(createElement(WorkdayScreen, props));});};
  const button = (text: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')]
    .find(item => item.textContent?.trim() === text || item.getAttribute('aria-label') === text);
  const click = async (text: string) => {const target = button(text); assert.ok(target, `Button exists: ${text}`); await act(async () => {target.click();});};
  const pin = async (id: string) => {const row = initial.rows.find(item => item.id === id)!;
    const target = button(`Pin ${row.label}: ${row.value}`) ?? button(`Unpin ${row.label}: ${row.value}`); assert.ok(target); await act(async () => {target.click();});};
  const input = async (selector: string, value: string) => {
    const field = dom.window.document.querySelector<HTMLInputElement | HTMLTextAreaElement>(selector); assert.ok(field);
    const prototype = field.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
    await act(async () => {Object.getOwnPropertyDescriptor(prototype, 'value')!.set!.call(field, value); field.dispatchEvent(new dom.window.Event('input', {bubbles: true}));});
  };
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  await render(); return {dom, calls, render, click, pin, input, button, close, guard: () => guard, text: () => dom.window.document.body.textContent ?? ''};
}

test('whole source cards pin and unpin, exact count gates submission, and no stage is accepted locally', async () => {
  const h = await harness();
  try {
    assert.equal(h.button('Check the evidence')?.disabled, true);
    await h.pin('before'); assert.equal(h.dom.window.document.querySelectorAll('.workday-source[aria-pressed="true"]').length, 1);
    await h.pin('before'); assert.equal(h.dom.window.document.querySelectorAll('.workday-source[aria-pressed="true"]').length, 0);
    await h.pin('before'); await h.pin('after'); assert.equal(h.button('Check the evidence')?.disabled, false);
    await h.click('Check the evidence');
    assert.deepEqual(h.calls.submits[0]?.answer, {ids: ['before', 'after']}); assert.equal(h.calls.submits[0]?.work.step, 0);
    assert.equal(h.dom.window.document.querySelectorAll('.workday-stages li.complete').length, 0);
    assert.equal(h.dom.window.document.querySelector('.workday-reward'), null);
    await h.render({assignment: atStep(1)});
    assert.equal(h.dom.window.document.querySelectorAll('.workday-stages li.complete').length, 1);
    assert.equal(h.button('Send your decision')?.disabled, true);
    assert.equal(h.dom.window.document.querySelector('input')?.value, '');
  } finally {await h.close();}
});

test('a number decision is submitted unchanged and hints and sources never submit answers', async () => {
  const h = await harness({assignment: atStep(1)});
  try {
    await h.click('Hint?'); assert.match(h.text(), /Subtract 2025 costs/); assert.equal(h.calls.submits.length, 0);
    await h.click('Aster · annual update+'); assert.ok(h.dom.window.document.querySelector('.workday-source-reading'));
    await h.input('input', '200'); await h.click('Send your decision');
    assert.deepEqual(h.calls.submits[0]?.answer, {value: '200'}); assert.equal(h.calls.submits[0]?.draft, undefined);
    assert.equal(h.calls.cues.includes('paper'), true); assert.equal(h.calls.cues.includes('saved'), true);
  } finally {await h.close();}
});

test('a rejected choice displays its authored feedback and preserves it for correction', async () => {
  const decision = {kind: 'choice' as const, prompt: 'Which business is smaller?', hint: 'Count every share.', unit: null,
    choices: [{id: 'aster', label: 'Aster', feedback: 'Count all the shares, not just one share.'}, {id: 'helio', label: 'Helio', feedback: 'Exactly: the smaller whole business.'}]};
  const h = await harness({assignment: {...atStep(1), decision}, onSubmit: async () => false});
  try {
    await h.click('Aster'); await h.click('Send your decision'); await h.render({error: {code: 'CHECK_DECISION'}});
    assert.match(h.dom.window.document.querySelector('[role="alert"]')?.textContent ?? '', /Count all the shares/);
    assert.equal(h.button('Aster')?.getAttribute('aria-pressed'), 'true');
    assert.equal(h.calls.cues.includes('saved'), false);
    await h.click('Helio'); assert.equal(h.dom.window.document.querySelector('[role="alert"]'), null);
  } finally {await h.close();}
});

test('handoff submits chosen facts and current note once, and only a completed assignment displays earned Trims', async () => {
  const save = deferred<boolean>();
  const submitted: {answer: WorkdayAnswer; draft: string | undefined}[] = [];
  const h = await harness({assignment: atStep(2), onSubmit: async (_work, answer, draft) => {submitted.push({answer, draft}); return save.promise;}});
  try {
    await h.click('Sales rose from $1,000 to $1,500.'); await h.click('Profit fell from $400 to $200.');
    await h.input('textarea', 'Keep an eye on costs.'); await h.click('File update');
    assert.equal(h.button('Saving…')?.disabled, true); assert.equal(h.dom.window.document.querySelector('.workday-reward'), null);
    assert.equal(h.dom.window.document.querySelectorAll('.workday-stages li.complete').length, 2);
    assert.deepEqual(submitted, [{answer: {ids: ['fact-1', 'fact-2']}, draft: 'Keep an eye on costs.'}]);
    await h.click('Saving…'); assert.equal(submitted.length, 1);
    await h.render({assignment: atStep(3, 'Keep an eye on costs.')}); await act(async () => {save.resolve(true);});
    assert.match(h.text(), /20 Trims earned/); assert.equal(h.dom.window.document.querySelector('textarea'), null);
    assert.equal(h.button('File update'), undefined); assert.equal(h.dom.window.document.querySelectorAll('.workday-stages li.complete').length, 3);
    assert.equal(h.text().split('Keep an eye on costs.').length - 1, 1, 'The server artifact already includes the saved note');
  } finally {await h.close();}
});

test('a changed mobile note pauses autosave and requires explicit review before keeping local edits', async () => {
  const h = await harness({assignment: atStep(2, 'Saved on mobile.')});
  try {
    assert.equal(h.dom.window.document.querySelector('textarea')?.value, 'Saved on mobile.');
    await h.input('textarea', 'First edit'); await h.input('textarea', 'Latest edit');
    await h.render({assignment: {...atStep(2, 'A newer mobile note.'), revision: 3}});
    assert.equal(h.dom.window.document.querySelector('textarea')?.value, 'Latest edit');
    await act(async () => {await delay(700);});
    assert.deepEqual(h.calls.drafts, [], 'A new server revision must not silently authorize overwriting its draft');
    assert.match(h.text(), /This note changed on another device/); assert.match(h.text(), /A newer mobile note/);
    assert.equal(h.button('File update')?.disabled, true);
    await h.click('Keep my edits');
    assert.deepEqual(h.calls.drafts, ['Latest edit']); assert.equal(h.calls.draftWrites[0]?.work.revision, 3);
    await h.render({assignment: {...atStep(2, 'Latest edit'), revision: 4}});
    assert.equal(h.dom.window.document.querySelector('textarea')?.value, 'Latest edit');
    assert.equal(h.dom.window.document.querySelector('.workday-note-conflict'), null);
  } finally {await h.close();}
});

test('using the saved mobile note discards only the explicitly reviewed local edits without a write', async () => {
  const h = await harness({assignment: atStep(2, 'Original note.')});
  try {
    await h.input('textarea', 'Local changes.');
    await h.render({assignment: {...atStep(2, 'Saved on the phone.'), revision: 3}});
    await h.click('Use saved note');
    assert.equal(h.dom.window.document.querySelector('textarea')?.value, 'Saved on the phone.');
    assert.equal(h.dom.window.document.querySelector('.workday-note-conflict'), null);
    await act(async () => {await delay(700);}); assert.deepEqual(h.calls.drafts, []);
  } finally {await h.close();}
});

test('successive local autosaves retain their edit-base revision for the hook’s acknowledged revision chain', async () => {
  const firstSave = deferred<boolean>(), writes: {revision: number; text: string}[] = [];
  const h = await harness({assignment: atStep(2), onSaveDraft: async (work, text) => {
    writes.push({revision: work.revision, text}); return writes.length === 1 ? firstSave.promise : true;
  }});
  try {
    await h.input('textarea', 'First local version.'); await act(async () => {await delay(700);});
    await h.input('textarea', 'Second local version.');
    await h.render({assignment: {...atStep(2, 'First local version.'), revision: 3}});
    assert.equal(h.dom.window.document.querySelector('.workday-note-conflict'), null);
    await act(async () => {firstSave.resolve(true);});
    await act(async () => {await delay(700);});
    assert.deepEqual(writes, [{revision: 2, text: 'First local version.'}, {revision: 2, text: 'Second local version.'}]);
    assert.equal(h.dom.window.document.querySelector('textarea')?.value, 'Second local version.');
  } finally {await h.close();}
});

test('Back waits for text typed during its in-flight draft save instead of dropping the newer note', async () => {
  const firstSave = deferred<boolean>(), secondSave = deferred<boolean>(), writes: string[] = [];
  const h = await harness({assignment: atStep(2), onSaveDraft: async (_work, text) => {
    writes.push(text); return writes.length === 1 ? firstSave.promise : secondSave.promise;
  }});
  try {
    await h.input('textarea', 'First note.'); await h.click('← Back to Career');
    assert.equal(h.calls.back, 0); await h.input('textarea', 'Newer note while saving.');
    await act(async () => {firstSave.resolve(true);});
    assert.deepEqual(writes, ['First note.', 'Newer note while saving.']); assert.equal(h.calls.back, 0);
    await act(async () => {secondSave.resolve(true);}); assert.equal(h.calls.back, 1);
  } finally {await h.close();}
});

test('a mobile completion cancels autosave but retains unsent edits beside immutable filed work until explicit leave', async () => {
  const h = await harness({assignment: atStep(2)});
  try {
    await h.input('textarea', 'Local unfiled note.');
    await h.render({assignment: {...atStep(3, 'Filed on mobile.'), revision: 4}});
    await act(async () => {await delay(700);});
    assert.deepEqual(h.calls.drafts, []); assert.equal(h.dom.window.document.querySelector('textarea'), null);
    assert.match(h.text(), /Filed on mobile/); assert.match(h.text(), /20 Trims earned/);
    assert.match(h.dom.window.document.querySelector('.workday-unfiled-note')?.textContent ?? '', /Local unfiled note/);
    assert.match(h.text(), /These edits weren’t included in the filed update/);
    await h.click('Back to Career'); assert.equal(h.calls.back, 0); assert.ok(h.button('Keep reading'));
    await h.click('Keep reading'); assert.equal(h.calls.back, 0); assert.ok(h.dom.window.document.querySelector('.workday-unfiled-note'));
    await h.click('Back to Career'); await h.click('Discard edits and leave'); assert.equal(h.calls.back, 1);
    assert.deepEqual(h.calls.drafts, []); assert.equal(h.calls.submits.length, 0);
  } finally {await h.close();}
});

test('explicitly discarding retained unsent edits allows leaving without changing the filed assignment', async () => {
  const h = await harness({assignment: atStep(2)});
  try {
    await h.input('textarea', 'Not included.'); await h.render({assignment: atStep(3, 'Filed elsewhere.')});
    assert.ok(h.dom.window.document.querySelector('.workday-unfiled-note'));
    await h.click('Discard these edits'); assert.equal(h.dom.window.document.querySelector('.workday-unfiled-note'), null);
    await h.click('Back to Career'); assert.equal(h.calls.back, 1);
    assert.equal(h.dom.window.document.querySelector('[role="alertdialog"]'), null);
    assert.deepEqual(h.calls.drafts, []); assert.equal(h.calls.submits.length, 0);
  } finally {await h.close();}
});

test('failed draft save on Back offers Keep writing or explicit leave without discarding the note silently', async () => {
  const h = await harness({assignment: atStep(2), onSaveDraft: async () => false});
  try {
    await h.input('textarea', 'Still working on this.'); await h.click('← Back to Career');
    assert.equal(h.calls.back, 0); assert.ok(h.dom.window.document.querySelector('[role="alertdialog"]'));
    await h.click('Keep writing'); assert.equal(h.calls.back, 0); assert.equal(h.dom.window.document.querySelector('textarea')?.value, 'Still working on this.');
    await h.click('← Back to Career'); await h.click('Leave without saving'); assert.equal(h.calls.back, 1);
    assert.equal(await h.guard()?.(), true, 'The parent navigation may call the same already-approved guard');
  } finally {await h.close();}
});

test('registered sidebar/browser navigation guard flushes unsaved notes and waits for the leave choice on failure', async () => {
  const h = await harness({assignment: atStep(2), onSaveDraft: async () => false});
  try {
    await h.input('textarea', 'Navigation must wait.');
    let allowed: boolean | null = null;
    await act(async () => {void h.guard()!().then(value => {allowed = value;});});
    assert.equal(allowed, null); assert.ok(h.dom.window.document.querySelector('[role="alertdialog"]'));
    await h.click('Keep writing'); assert.equal(allowed, false);
    assert.equal(h.dom.window.document.querySelector('textarea')?.value, 'Navigation must wait.');
  } finally {await h.close();}
});

test('completed assignments remain read-only while a pending write keeps exact recovery available', async () => {
  const recovery = deferred<boolean>();
  const h = await harness({assignment: atStep(3), pending: true, onRecover: async () => recovery.promise});
  try {
    assert.equal(h.dom.window.document.querySelector('input,textarea'), null);
    assert.equal(h.button('Back to Career'), undefined); assert.ok(h.button('Check last save'));
    await h.click('Check last save'); assert.equal(h.button('Checking…')?.disabled, true);
    await h.render({pending: false}); await act(async () => {recovery.resolve(true);});
    assert.ok(h.button('Back to Career')); assert.equal(h.calls.submits.length, 0); assert.equal(h.calls.drafts.length, 0);
  } finally {await h.close();}
});
