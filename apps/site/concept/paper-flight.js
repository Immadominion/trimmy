// A decorative shared-document handoff alongside ordinary anchor navigation.
// One visible paper travels; the semantic report keeps its layout and content.
// The browser owns scrolling, history and focus.
export function createPaperFlight({ source, target, anchor, reducedMotion = false }) {
  let reduced = reducedMotion;
  let frame = 0;
  let ghost = null;
  let destroyed = false;
  let reason = 'idle';
  let samples = 0;

  function cancel(why = 'cancelled') {
    cancelAnimationFrame(frame);
    frame = 0;
    ghost?.remove();
    ghost = null;
    target?.removeAttribute('data-report-in-transit');
    source?.closest('.office-stage')?.classList.remove('is-handing-over');
    reason = why;
  }

  function play() {
    cancel('replaced');
    if (destroyed || reduced || document.hidden || !source || !target) return;
    const start = source.getBoundingClientRect();
    if (start.bottom < 0 || start.top > innerHeight) return;
    const width = target.offsetWidth;
    const height = target.offsetHeight;
    if (!width || !height) return;

    // Detach from the desk in viewport space while native navigation continues.
    // The destination is measured live, so a fast browser scroll cannot throw
    // the paper above the viewport before its own travel has caught up.
    const from = { x: start.left, y: start.top };
    const end = target.getBoundingClientRect();
    const heading = anchor?.getBoundingClientRect();
    const scrollPadding = parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) || 0;
    const scrollMargin = anchor ? parseFloat(getComputedStyle(anchor).scrollMarginTop) || 0 : 0;
    const expectedTop = heading ? end.top - heading.top + scrollPadding + scrollMargin : end.top;
    const initialScale = Math.min(start.width / width, .55);
    const clone = target.cloneNode(true);
    clone.removeAttribute('id');
    clone.removeAttribute('aria-labelledby');
    clone.querySelectorAll('[id]').forEach(el => el.removeAttribute('id'));
    clone.querySelectorAll('[aria-labelledby]').forEach(el => el.removeAttribute('aria-labelledby'));
    clone.setAttribute('aria-hidden', 'true');
    clone.setAttribute('inert', '');
    clone.classList.add('report-flight');
    clone.style.width = `${width}px`;
    clone.style.height = `${height}px`;
    clone.style.minHeight = '0';
    clone.style.margin = '0';
    clone.style.opacity = '0';
    document.body.append(clone);
    ghost = clone;
    // Hide only the duplicate visual after the replacement exists. Keep the
    // original in the accessibility tree and restore it on every interruption.
    target.setAttribute('data-report-in-transit', '');
    source.closest('.office-stage')?.classList.add('is-handing-over');
    const began = performance.now();
    const duration = matchMedia('(max-width: 700px)').matches ? 950 : 1100;
    reason = 'playing';
    samples = 0;

    function tick(now) {
      frame = 0;
      if (destroyed || reduced || document.hidden || ghost !== clone) {
        cancel('interrupted'); return;
      }
      const t = Math.min(1, (now - began) / duration);
      const travel = Math.min(1, t / .88);
      const smooth = travel * travel * (3 - 2 * travel);
      const sweep = Math.sin(Math.PI * travel);
      const destination = target.getBoundingClientRect();
      const liveBlend = Math.max(0, (t - .65) / .23);
      const destinationTop = expectedTop + (destination.top - expectedTop) * Math.min(1, liveBlend);
      const angle = innerWidth <= 700 ? -2 : -3;
      const x = from.x + (destination.left - from.x) * smooth
        + sweep * Math.min(50, innerWidth * .045);
      const landingY = destinationTop - Math.sin(angle * Math.PI / 180) * width;
      const y = from.y + (landingY - from.y) * smooth - sweep * 55;
      const scale = initialScale + (1 - initialScale) * smooth;
      const rotation = -11 + (11 + angle) * smooth + Math.sin(travel * Math.PI * 2) * 3;
      clone.style.transform = `translate3d(${x}px,${y}px,0) rotate(${rotation}deg) scale(${scale})`;
      // The paper reveals itself, then merges with the original document.
      clone.style.opacity = String(Math.min(1, t / .1) * Math.min(1, (1 - t) / .12));
      clone.style.borderRadius = `${3 + Math.sin(travel * Math.PI) * 16}px`;
      // The copy has reached the exact document position. Restore the real
      // paper underneath its short final fade, with no second flying report.
      if (t >= .88) target.removeAttribute('data-report-in-transit');
      samples += 1;
      if (t < 1) frame = requestAnimationFrame(tick);
      else cancel('settled');
    }
    frame = requestAnimationFrame(tick);
  }

  const onResize = () => cancel('resize');
  const onWheel = () => cancel('wheel');
  const onTouch = () => cancel('touch');
  const onKey = event => {
    if (['Escape', 'ArrowDown', 'ArrowUp', 'PageDown', 'PageUp', 'Home', 'End', ' '].includes(event.key)) cancel('keyboard');
  };
  const onVisibility = () => { if (document.hidden) cancel('hidden'); };
  const onClick = event => {
    if (!ghost) return;
    const a = event.target.closest?.('a');
    if (a && a.hash !== '#practice-title') cancel('navigation');
  };
  window.addEventListener('resize', onResize, { passive: true });
  window.addEventListener('wheel', onWheel, { passive: true });
  window.addEventListener('touchmove', onTouch, { passive: true });
  window.addEventListener('keydown', onKey);
  document.addEventListener('visibilitychange', onVisibility);
  document.addEventListener('click', onClick);

  return {
    play, cancel,
    setReducedMotion(value) { reduced = Boolean(value); if (reduced) cancel('reduced'); },
    getState: () => ({ active: !!ghost, frameActive: frame !== 0, targetHidden: target?.hasAttribute('data-report-in-transit') ?? false, reason, samples }),
    destroy() {
      destroyed = true; cancel('destroyed');
      window.removeEventListener('resize', onResize);
      window.removeEventListener('wheel', onWheel);
      window.removeEventListener('touchmove', onTouch);
      window.removeEventListener('keydown', onKey);
      document.removeEventListener('visibilitychange', onVisibility);
      document.removeEventListener('click', onClick);
    },
  };
}
