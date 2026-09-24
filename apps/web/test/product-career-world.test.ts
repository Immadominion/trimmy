import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {CareerWorld, careerScenery, careerSceneryUrl} from '../src/product/career-world.js';
import type {CareerWorldAssignment, CareerWorldProps} from '../src/product/career-world.js';

const authored = JSON.parse(await readFile(new URL('../../../content/workdays/intern-v1.json', import.meta.url), 'utf8')) as {assignments: Omit<CareerWorldAssignment, 'completedAt'>[]};
const assignments: readonly CareerWorldAssignment[] = authored.assignments.map(item => ({...item, completedAt: null, step: 0}));

async function harness(initial: Partial<CareerWorldProps> = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#career', pretendToBeVisual: true});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document, navigator: dom.window.navigator,
    HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const opened: string[] = []; let retries = 0;
  let props: CareerWorldProps = {assignments, onOpen: id => {opened.push(id);}, onRetry: () => {retries++;}, ...initial};
  const render = async (update: Partial<CareerWorldProps> = {}) => {props = {...props, ...update}; await act(async () => {root.render(createElement(CareerWorld, props));});};
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  await render();
  return {dom, render, close, opened, retries: () => retries, text: () => dom.window.document.body.textContent ?? ''};
}

test('the street uses the twenty authored assignments, with only the current and filed days opening work', async () => {
  assert.equal(assignments.length, 20);
  const h = await harness({assignments: assignments.map((item, index) => index === 0 ? {...item, completedAt: '2026-09-24T19:00:00Z'} : item)});
  try {
    const doc = h.dom.window.document;
    assert.equal(doc.querySelectorAll('[data-assignment-id]').length, 20);
    const buttons = [...doc.querySelectorAll<HTMLButtonElement>('button.career-world-node')];
    assert.equal(buttons.length, 2);
    assert.match(buttons[0]!.getAttribute('aria-label')!, /Day 1, The morning brief, filed/);
    assert.equal(buttons[1]!.getAttribute('aria-current'), 'step');
    await act(async () => {buttons[0]!.click(); buttons[1]!.click();});
    assert.deepEqual(h.opened, [assignments[0]!.id, assignments[1]!.id]);
    const locked = doc.querySelector<HTMLElement>('.career-world-locked summary')!;
    await act(async () => {locked.click();});
    assert.equal(doc.querySelector('.career-world-locked')?.hasAttribute('open'), true);
    assert.match(doc.querySelector('.career-world-preview small')!.textContent!, /Complete day 2/);
    assert.equal(h.opened.length, 2, 'locked preview never opens the assignment flow');
    assert.equal(doc.querySelector('[role="region"]')?.getAttribute('tabindex'), '0');
  } finally {await h.close();}
});

test('a server completion moves the current day and renders a seal without pretending future scenery is playable', async () => {
  const h = await harness();
  try {
    assert.equal(h.dom.window.document.querySelectorAll('.career-world-seal').length, 0);
    await h.render({assignments: assignments.map((item, index) => index === 0 ? {...item, completedAt: '2026-09-24T19:00:00Z'} : item)});
    assert.equal(h.dom.window.document.querySelectorAll('.career-world-seal').length, 1);
    assert.equal(h.dom.window.document.querySelector('[data-current="true"]')?.getAttribute('data-assignment-id'), assignments[1]!.id);
    await h.render({assignments: assignments.map(item => ({...item, completedAt: '2026-09-24T19:00:00Z'}))});
    assert.equal(h.dom.window.document.querySelector('[data-current="true"]'), null);
    assert.equal(h.dom.window.document.querySelectorAll('.career-world-seal').length, 20);
    const future = [...h.dom.window.document.querySelectorAll('.career-world-row.future')];
    assert.equal(future.length, 10);
    assert.ok(future.every(row => row.querySelector('button,summary,a,[tabindex]') === null));
    assert.ok(future.every(row => row.textContent?.includes('Coming later')));
    assert.doesNotMatch(h.text(), /Clocked out|Review today/);
  } finally {await h.close();}
});

test('scrolling past the released work extends the same street with inert future neighbourhoods', async () => {
  const h = await harness();
  try {
    const scroll = h.dom.window.document.querySelector<HTMLElement>('.career-world-scroll')!;
    Object.defineProperties(scroll, {scrollHeight: {value: 9000, configurable: true}, clientHeight: {value: 600, configurable: true}, scrollTop: {value: 8250, writable: true, configurable: true}});
    await act(async () => {scroll.dispatchEvent(new h.dom.window.Event('scroll', {bubbles: true}));});
    assert.equal(h.dom.window.document.querySelectorAll('.career-world-row.future').length, 20);
    assert.equal(h.dom.window.document.querySelectorAll('[data-assignment-id]').length, 20);
    assert.equal(h.dom.window.document.querySelectorAll('.career-world-road-bed').length, 1, 'one connected SVG path spans the whole street');
    assert.equal(h.dom.window.document.querySelectorAll('.future button,.future a,.future summary').length, 0);
    assert.equal(h.opened.length, 0);
  } finally {await h.close();}
});

test('optional motion stops when disabled or the document is hidden, while artwork reserves its layout', async () => {
  const h = await harness({motion: false});
  try {
    assert.equal(h.dom.window.document.querySelector('.career-world')?.getAttribute('data-motion'), 'off');
    await h.render({motion: true}); assert.equal(h.dom.window.document.querySelector('.career-world')?.getAttribute('data-motion'), 'on');
    Object.defineProperty(h.dom.window.document, 'hidden', {value: true, configurable: true});
    await act(async () => {h.dom.window.document.dispatchEvent(new h.dom.window.Event('visibilitychange'));});
    assert.equal(h.dom.window.document.querySelector('.career-world')?.getAttribute('data-motion'), 'off');
    const images = [...h.dom.window.document.querySelectorAll('.career-world-street img')];
    assert.ok(images.every(img => img.getAttribute('width') && img.getAttribute('height') && img.getAttribute('loading') === 'lazy'));
    const css = await readFile(new URL('../src/product/career-world.css', import.meta.url), 'utf8');
    assert.match(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{[^}]*animation:none/s);
  } finally {await h.close();}
});

test('missing assignments show a retry instead of invented days, and arbitrary art paths cannot escape the scenery collection', async () => {
  const h = await harness({assignments: null, error: 'Your assignments couldn’t load.'});
  try {
    assert.equal(h.dom.window.document.querySelector('[data-assignment-id]'), null);
    assert.equal(h.dom.window.document.querySelector('.career-world-row.future'), null);
    await act(async () => {h.dom.window.document.querySelector<HTMLButtonElement>('button')!.click();});
    assert.equal(h.retries(), 1);
    assert.equal(careerSceneryUrl('../../external'), '/trimmy/career-world/exchange.png');
  } finally {await h.close();}
});

test('all thirty web scenery images preserve the current mobile PNG bytes', async () => {
  assert.equal(careerScenery.length, 30);
  for (const name of careerScenery) {
    const [web, mobile] = await Promise.all([
      readFile(new URL(`../public/trimmy/career-world/${name}.png`, import.meta.url)),
      readFile(new URL(`../../mobile/assets/images/career_world/${name}.png`, import.meta.url)),
    ]);
    assert.equal(createHash('sha256').update(web).digest('hex'), createHash('sha256').update(mobile).digest('hex'), name);
  }
});
