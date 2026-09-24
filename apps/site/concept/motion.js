import {createAdaActor} from './ada-actor.js';
import {createLiquidToken} from './liquid-token.js';
import {createPaperFlight} from './paper-flight.js';
import {createRoomDetails} from './room-details.js';
import {createScrollScenes} from './scroll-scenes.js';
import {createActivityFeedback} from './activity-feedback.js';

const root = document.documentElement;
const media = matchMedia('(prefers-reduced-motion: reduce)');
let paused = media.matches;
let suspended = false;
let destroyed = false;
let actor = null;
let responseActor = null;
let token = null;
let closingToken = null;
let officeEntered = false;
let reportEntered = false;
let closingEntered = false;
let responseBeat = 'listen';
const activeAnimations = new Set();
const timers = new Set();
const motionStopped = () => paused || suspended || destroyed || document.hidden;
function later(fn, delay) {
  const id = setTimeout(() => { timers.delete(id); if (!motionStopped()) fn(); }, delay);
  timers.add(id);
}
function animate(el, frames, options) {
  if (!el || motionStopped()) return;
  const animation = el.animate(frames, {duration: 700, easing: 'cubic-bezier(.16,1,.3,1)', ...options});
  activeAnimations.add(animation);
  animation.finished.catch(() => {}).finally(() => activeAnimations.delete(animation));
  return animation;
}
function cancelTimelines() {
  for (const animation of activeAnimations) animation.cancel();
  activeAnimations.clear();
  for (const timer of timers) clearTimeout(timer);
  timers.clear();
}

const paperFlight = createPaperFlight({
  source: document.querySelector('.envelope-paper'),
  target: document.querySelector('.report'),
  anchor: document.querySelector('#practice-title'),
  reducedMotion: paused,
});
const rooms = createRoomDetails({root: document, reducedMotion: paused});
const scrollScenes = createScrollScenes({reducedMotion: paused});
const activityFeedback = createActivityFeedback({reducedMotion: paused});

async function initToken() {
  const [hero, close] = await Promise.all([
    createLiquidToken({
      button: document.querySelector('.token-button'),
      canvas: document.querySelector('.token-canvas'),
      image: document.querySelector('.token-fallback'),
      reducedMotion: motionStopped(),
    }),
    createLiquidToken({
      button: document.querySelector('.closing-token'),
      canvas: document.querySelector('.closing-token-canvas'),
      image: document.querySelector('.closing-token-fallback'),
      reducedMotion: motionStopped(),
      interactive: false,
    }),
  ]);
  token = hero; closingToken = close;
  if (destroyed) { token.destroy(); closingToken.destroy(); return; }
  token.setReducedMotion(motionStopped());
  closingToken.setReducedMotion(motionStopped());
  if (!motionStopped()) token.play();
  if (closingEntered && !motionStopped()) later(() => closingToken.play(), 80);
}
async function initActors() {
  await Promise.all([
    ['.ada-canvas', '.ada-fallback', false],
    ['.response-ada', null, true],
  ].map(async ([selector, fallback, isResponse]) => {
    const canvas = document.querySelector(selector);
    if (!canvas) return;
    try {
      const candidate = await createAdaActor(canvas);
      if (destroyed) { candidate?.destroy(); return; }
      // The actor factory returns a no-op on asset failure; readiness is explicit.
      if (canvas.dataset.adaStatus !== 'ready') { canvas.hidden = true; return; }
      candidate.setReducedMotion(motionStopped());
      if (isResponse) responseActor = candidate;
      else actor = candidate;
      if (fallback) document.querySelector(fallback).hidden = true;
      // Asset loading can finish after a scene has entered. The renderer
      // checks its own visibility, so a departed scene does not replay.
      if (isResponse ? (reportEntered || responseBeat !== 'listen') : officeEntered) {
        candidate.play(isResponse ? responseBeat : 'offer');
      }
    } catch { canvas.hidden = true; }
  }));
}

function syncMotion() {
  const stop = motionStopped();
  root.dataset.motion = stop ? 'off' : 'on';
  actor?.setReducedMotion(stop);
  responseActor?.setReducedMotion(stop);
  token?.setReducedMotion(stop);
  closingToken?.setReducedMotion(stop);
  paperFlight.setReducedMotion(stop);
  rooms.setReducedMotion(stop);
  scrollScenes.setReducedMotion(stop);
  activityFeedback.setReducedMotion(stop);
  if (stop) cancelTimelines();
}
media.addEventListener('change', () => { paused = media.matches; syncMotion(); });
document.addEventListener('visibilitychange', syncMotion);
syncMotion();

const observer = new IntersectionObserver(entries => {
  for (const {target, isIntersecting} of entries) {
    if (!isIntersecting) continue;
    observer.unobserve(target);
    if (motionStopped()) continue;
    switch (target.dataset.scene) {
      case 'office':
        officeEntered = true;
        animate(target, [{clipPath:'inset(5% 3% 0 round 80px 80px 0 0)'}, {clipPath:'inset(0% 0% 0 round 56px 56px 0 0)'}], {duration:1000});
        actor?.play('offer');
        animate(target.querySelector('.speech'), [{opacity:0, transform:'rotate(-6deg) scale(.9)'}, {opacity:1, transform:'rotate(-4deg) scale(1)'}], {duration:650, delay:350});
        later(() => target.classList.add('offered'), 1200);
        break;
      case 'report':
        reportEntered = true;
        // The shared paper already supplies this entrance. Keep the evidence
        // at its final pose so its chart cannot restart underneath the landing.
        if (paperFlight.getState().active) { responseActor?.play(responseBeat); break; }
        animate(target, [{transform:'rotate(-7deg) translateY(25px)'}, {transform:'rotate(-3deg) translateY(0)'}], {duration:850});
        target.querySelectorAll('.bar').forEach((bar, i) => animate(bar, [{transform:'scaleY(.03)'}, {transform:'scaleY(1)'}], {duration:800, delay:150 + i * 160}));
        responseActor?.play(responseBeat);
        break;
      case 'closing':
        closingEntered = true;
        // Let the token's own visibility observer see the footer before the
        // finite settle begins.
        later(() => closingToken?.play(), 80);
        break;
    }
  }
}, {threshold:.3});
for (const [selector, scene] of [['.office-stage','office'], ['.report','report'], ['.closing-token','closing']]) {
  const el = document.querySelector(selector);
  el.dataset.scene = scene;
  observer.observe(el);
}
document.querySelectorAll('.title-row>span').forEach((el, i) => animate(el, [{transform:'translateY(110%) rotate(2deg)'}, {transform:'translateY(0) rotate(0deg)'}], {duration:850, delay:80 + i * 90}));

// Native radios preserve keyboard, validation and touch behavior.
const form = document.querySelector('#practice-form');
const feedback = document.querySelector('#practice-feedback');
const practice = document.querySelector('.practice');
form.querySelector('fieldset').disabled = false;
const check = form.querySelector('button');
check.type = 'submit'; check.disabled = false;
form.addEventListener('submit', event => {
  event.preventDefault();
  const value = new FormData(form).get('headline');
  if (!value) return;
  const correct = value === 'dated';
  practice.classList.toggle('is-correct', correct);
  practice.classList.toggle('is-retry', !correct);
  feedback.dataset.outcome = correct ? 'correct' : 'retry';
  feedback.textContent = correct
    ? 'That’s right. The report came out in 2026, but the growth happened in 2025.'
    : 'Check the dates again. The report compares 2024 with 2025. It was published in 2026.';
  responseBeat = correct ? 'success' : 'correct';
  responseActor?.play(responseBeat);
  activityFeedback.show(correct);
});
form.addEventListener('change', () => {
  feedback.textContent = ''; delete feedback.dataset.outcome;
  practice.classList.remove('is-correct', 'is-retry');
  activityFeedback.clear();
  responseBeat = 'read';
  responseActor?.play(responseBeat);
});

const labels = {1:'Read the evidence', 2:'Understand the numbers', 3:'Work with the team'};
const floorButtons = [...document.querySelectorAll('[data-floor]')];
floorButtons.forEach(button => {
  button.disabled = false;
  button.addEventListener('click', () => {
    const floor = button.dataset.floor;
    for (const b of floorButtons) {
      const active = b === button;
      b.classList.toggle('active', active); b.setAttribute('aria-pressed', String(active));
    }
    const tower = document.querySelector('.tower');
    tower.dataset.activeFloor = floor;
    tower.setAttribute('aria-label', `An illustrated three-floor office. Floor ${floor} is highlighted.`);
    document.querySelector('.floor-caption').textContent = `Floor ${floor}: ${labels[floor]}`;
    rooms.selectFloor(floor);
  });
});

const sectionObserver = new IntersectionObserver(entries => {
  for (const {target, isIntersecting} of entries) if (isIntersecting) {
    document.querySelectorAll('.header nav>a').forEach(a => a.classList.toggle('active', a.hash === `#${target.id}`));
  }
}, {rootMargin:'-15% 0px -50% 0px'});
document.querySelectorAll('#the-game,#why-trimmy,#practice-title').forEach(el => sectionObserver.observe(el));
document.querySelectorAll('a[href="#practice-title"]').forEach(a => a.addEventListener('click', event => {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  // Keep native anchor history and scrolling. The travelling paper is decorative.
  if (a.classList.contains('envelope')) { actor?.play('offer'); paperFlight.play(); }
  document.querySelector('#practice-title').focus({preventScroll:true});
}));

// BFCache retains these live instances. Settle on departure and restore on return.
window.addEventListener('pagehide', event => {
  suspended = true; syncMotion(); paperFlight.cancel('pagehide');
  if (event.persisted) return;
  destroyed = true;
  token?.destroy(); closingToken?.destroy(); actor?.destroy(); responseActor?.destroy();
  paperFlight.destroy(); rooms.destroy(); scrollScenes.destroy(); activityFeedback.destroy();
  observer.disconnect(); sectionObserver.disconnect();
});
window.addEventListener('pageshow', event => {
  if (!event.persisted || destroyed) return;
  suspended = false; syncMotion(); scrollScenes.refresh();
});

await Promise.allSettled([initToken(), initActors()]);
// Read-only diagnostics: no analytics, account data, credentials or persistence.
window.trimmyMotionStudy = {getState: () => ({
  paused, suspended, destroyed,
  tokenFrameActive: token?.getState().frameActive ?? false,
  activeTimelines: activeAnimations.size, queuedDelays: timers.size,
  actorReady: !!actor, responseActorReady: !!responseActor,
  token: token?.getState() ?? null,
  closingToken: closingToken?.getState() ?? null,
  flight: paperFlight.getState(), rooms: rooms.getState(), scroll: scrollScenes.getState(),
  activityFeedback: activityFeedback.getState(),
})};
