const SVG_NS = 'http://www.w3.org/2000/svg';

function svgNode(name, attributes = {}) {
  const node = document.createElementNS(SVG_NS, name);
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
  return node;
}

/** Finite ink marks on the report. The form owns its answer and live feedback. */
export function createActivityFeedback({root = document, reducedMotion = false} = {}) {
  const practice = root.querySelector('.practice');
  const report = practice?.querySelector('.report');
  const seal = report?.querySelector('.answer-seal');
  const noop = {
    show() {}, clear() {}, setReducedMotion() {}, destroy() {},
    getState: () => ({ready: false, activeAnimations: 0}),
  };
  if (!practice || !report || !seal) return noop;

  const originalSeal = seal.innerHTML;
  const originalEnhanced = practice.getAttribute('data-activity-enhanced');
  const originalOutcome = practice.getAttribute('data-activity-outcome');
  const animations = new Set();
  let reduced = reducedMotion;
  let destroyed = false;
  let outcome = null;
  let visible = false;

  // An uneven double impression, with small dry-ink breaks. No raster texture,
  // duplicated SVG IDs, or animated filter is needed for this paper mark.
  const frame = svgNode('svg', {
    viewBox: '0 0 116 104', class: 'activity-stamp-frame', 'aria-hidden': 'true',
  });
  frame.append(svgNode('path', {
    d: 'M10 8 106 12 111 94 8 97 5 21Z',
    class: 'activity-stamp-paper',
  }));
  const ink = svgNode('g', {class: 'activity-stamp-ink'});
  ink.append(svgNode('path', {
    d: 'm11 10 92 3 5 78-98 3-3-72m8-3 82 3 4 62-80 3-3-59',
    class: 'activity-stamp-edge',
  }));
  ink.append(svgNode('path', {
    d: 'm23 15 5 .2m48 1.8 7 .3M106 49l.3 5M68 92l7-.2M11 66l.1 3M22 83l3-.1',
    class: 'activity-stamp-wear',
  }));
  frame.append(ink);
  seal.prepend(frame);
  const checkSvg = seal.querySelector('svg:not(.activity-stamp-frame)');
  const check = checkSvg?.querySelector('path');
  checkSvg?.classList.add('activity-stamp-check');
  const originalPathLength = check?.getAttribute('pathLength');
  check?.setAttribute('pathLength', '1');

  const markers = [
    ...report.querySelectorAll('.chart-col strong'),
    report.querySelector('.report-date [data-date]'),
  ].filter(Boolean).map((label, index) => {
    const alreadyMarked = label.classList.contains('activity-date');
    label.classList.add('activity-date');
    const svg = svgNode('svg', {
      viewBox: '0 0 100 10', preserveAspectRatio: 'none',
      class: `activity-date-ink${index === 2 ? ' activity-publication-ink' : ''}`,
      'aria-hidden': 'true',
    });
    const line = svgNode('path', {
      d: index === 1 ? 'M3 6 Q38 2 97 5' : 'M3 5 Q47 2 97 6',
      pathLength: '1',
    });
    svg.append(line);
    label.append(svg);
    return {label, svg, line, alreadyMarked};
  });
  practice.dataset.activityEnhanced = '';

  function inViewport() {
    const box = report.getBoundingClientRect();
    return box.width > 0 && box.height > 0 && box.bottom > 0 && box.top < innerHeight
      && box.right > 0 && box.left < innerWidth;
  }
  function stop() {
    for (const animation of animations) animation.cancel();
    animations.clear();
  }
  function animate(node, keyframes, options) {
    if (!node?.animate) return;
    const animation = node.animate(keyframes, options);
    animations.add(animation);
    animation.finished.catch(() => {}).finally(() => animations.delete(animation));
  }
  function show(correct) {
    if (destroyed) return;
    stop();
    outcome = correct ? 'correct' : 'retry';
    practice.dataset.activityOutcome = outcome;
    visible = inViewport();
    // In the stacked mobile layout the report can be above the answer controls.
    // Leave the final ink marks there without scrolling or playing unseen work.
    if (reduced || document.hidden || !visible) return;
    if (correct) {
      animate(seal, [
        {opacity: 0, transform: 'translateY(-15px) rotate(20deg) scale(1.16)', offset: 0},
        {opacity: 1, transform: 'translateY(0) rotate(11deg) scale(.96)', offset: .19},
        {opacity: 1, transform: 'translateY(0) rotate(12.4deg) scale(1.015)', offset: .38},
        {opacity: 1, transform: 'translateY(0) rotate(12deg) scale(1)', offset: 1},
      ], {duration: 700, easing: 'cubic-bezier(.2,.7,.3,1)'});
      animate(ink, [{opacity: .2}, {opacity: 1}], {
        duration: 260, delay: 120, fill: 'backwards', easing: 'ease-out',
      });
      animate(check, [{strokeDashoffset: '1'}, {strokeDashoffset: '0'}], {
        duration: 310, delay: 180, fill: 'backwards', easing: 'cubic-bezier(.35,0,.2,1)',
      });
    } else {
      // Read left to right: the comparison years, then the publication date.
      markers.forEach(({line}, index) => animate(line, [
        {strokeDashoffset: '1'}, {strokeDashoffset: '0'},
      ], {
        duration: 300, delay: [0, 150, 420][index] ?? 420,
        fill: 'backwards', easing: 'cubic-bezier(.3,.05,.2,1)',
      }));
    }
  }
  function clear() {
    if (destroyed) return;
    stop(); outcome = null;
    delete practice.dataset.activityOutcome;
  }
  function setReducedMotion(value) {
    reduced = Boolean(value);
    if (reduced) stop();
  }
  function onVisibility() { if (document.hidden) stop(); }
  const observer = typeof IntersectionObserver === 'function'
    ? new IntersectionObserver(entries => {
      visible = entries.some(entry => entry.isIntersecting);
      if (!visible) stop();
    }, {threshold: 0}) : null;
  observer?.observe(report);
  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('pagehide', stop);
  visible = inViewport();

  function restoreAttribute(node, name, value) {
    if (value === null) node.removeAttribute(name);
    else node.setAttribute(name, value);
  }
  function destroy() {
    if (destroyed) return;
    stop(); destroyed = true; outcome = null;
    observer?.disconnect();
    document.removeEventListener('visibilitychange', onVisibility);
    window.removeEventListener('pagehide', stop);
    for (const {label, svg, alreadyMarked} of markers) {
      svg.remove();
      if (!alreadyMarked) label.classList.remove('activity-date');
    }
    if (check) restoreAttribute(check, 'pathLength', originalPathLength);
    seal.innerHTML = originalSeal;
    restoreAttribute(practice, 'data-activity-enhanced', originalEnhanced);
    restoreAttribute(practice, 'data-activity-outcome', originalOutcome);
  }
  return {
    show, clear, setReducedMotion, destroy,
    getState: () => ({
      ready: true, outcome, reducedMotion: reduced, visible, destroyed,
      activeAnimations: animations.size,
    }),
  };
}
