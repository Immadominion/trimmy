// The stepper.
//
// This page used to be one long screen: address, rule, verdict and payment all
// visible at once, with the last two empty until you acted. That is a form, and
// it reads as a form. Arming a rule is four decisions, and the third one is
// "should I sign this at all", which deserves a screen of its own rather than a
// panel somebody scrolls past on the way to the memo.
//
// This file owns ONLY visibility and the rail. Everything that computes,
// validates or refuses stays in arm.js, so there is exactly one place where
// safety lives and it is not this one.
//
// Progress is deliberately NOT persisted. A half-finished arming payment is
// built from live chain state (a nonce that moves, an executor fee governance
// can change), so restoring one from yesterday would hand somebody a stale
// payment that looks finished. Reloading starts over, on purpose.

const steps = [...document.querySelectorAll('[data-step]')];
const rail = document.getElementById('rail');

/** Steps that are not applicable to the current rule, by id. */
const skipped = new Set();

const isLive = (el) => !skipped.has(el.dataset.step);

function visible() {
  return steps.filter(isLive);
}

export function markSkipped(id, yes) {
  if (yes) skipped.add(id); else skipped.delete(id);
  renderRail();
}

let current = 0;

function renderRail() {
  if (!rail) return;
  const live = visible();
  rail.innerHTML = live
    .map((el, i) => {
      const state = i === current ? 'current' : i < current ? 'done' : 'todo';
      return `<li data-state="${state}"><b><span>${i + 1}</span></b>${el.dataset.label}</li>`;
    })
    .join('');
}

export function goTo(index, { focus = true } = {}) {
  const live = visible();
  current = Math.max(0, Math.min(index, live.length - 1));
  for (const el of steps) el.hidden = true;
  const el = live[current];
  el.hidden = false;
  renderRail();

  // Focus the heading rather than scrolling to it. Scrolling alone announces
  // nothing, so a screen reader user would be told a step had changed by
  // nothing at all. Native focus scrolling honours prefers-reduced-motion.
  const h = el.querySelector('h2');
  if (focus && h) {
    h.setAttribute('tabindex', '-1');
    h.focus({ preventScroll: false });
  }
}

/** Advance to the step after the one with this id, whether or not it is live. */
export function advanceFrom(id) {
  const live = visible();
  const at = live.findIndex((el) => el.dataset.step === id);
  goTo(at < 0 ? current + 1 : at + 1);
}

export function goToStep(id) {
  const live = visible();
  const at = live.findIndex((el) => el.dataset.step === id);
  if (at >= 0) goTo(at);
}

// Back buttons are declarative: any element with data-back moves one step
// earlier. Forward moves are never declarative, because every one of them is
// gated on something that had to succeed first.
document.addEventListener('click', (e) => {
  const back = e.target.closest('[data-back]');
  if (!back) return;
  e.preventDefault();
  goTo(current - 1);
});

goTo(0, { focus: false });
