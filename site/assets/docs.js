// Documentation page behaviour: a diagram viewer, and the AI affordances.
//
// No dependencies, no build step. The docs are static HTML generated from
// markdown, and adding a bundler to get a lightbox would be a bad trade.
//
// Two problems this solves, both found by looking at the rendered page:
//
// 1. A diagram that is legible at its natural size is unreadable at the width
//    of a prose column. One of ours is 1453px wide against a 653px column, so
//    the type lands at about 6px. Scaling it down is not a fix, it is the bug.
//    So every figure gets an expand control and opens full screen.
//
// 2. A page that says it is AI friendly should be readable by one without a
//    scraper. Every page already has a markdown twin; these controls make it
//    reachable in one click rather than by knowing the convention.

(() => {
  'use strict';

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  // ---------------------------------------------------------------------
  // Diagram viewer
  // ---------------------------------------------------------------------

  const ICON = {
    expand:
      '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M7.5 2.5h-5v5M12.5 2.5h5v5M17.5 12.5v5h-5M2.5 12.5v5h5"/></svg>',
    download:
      '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 2.5v11M5.5 9.5 10 14l4.5-4.5M3 16.5h14"/></svg>',
    close:
      '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4 4l12 12M16 4L4 16"/></svg>',
  };

  let overlay = null;

  function buildOverlay() {
    if (overlay) return overlay;
    overlay = document.createElement('div');
    overlay.className = 'figview';
    overlay.hidden = true;
    overlay.innerHTML = `
      <div class="figview__bar">
        <p class="figview__cap"></p>
        <div class="figview__acts">
          <a class="figview__btn" data-dl download>${ICON.download}<span>Download</span></a>
          <button class="figview__btn" data-close type="button">${ICON.close}<span>Close</span></button>
        </div>
      </div>
      <div class="figview__stage" data-stage><img alt=""></div>
      <p class="figview__hint">Scroll or pinch to zoom. Drag to move.</p>`;
    document.body.appendChild(overlay);

    $('[data-close]', overlay).addEventListener('click', close);
    overlay.addEventListener('click', (e) => {
      // Clicking the backdrop closes; clicking the image itself must not,
      // because the image is the thing you came here to interact with.
      if (e.target === overlay || e.target.hasAttribute('data-stage')) close();
    });
    return overlay;
  }

  let scale = 1;
  let panX = 0;
  let panY = 0;
  let lastFocus = null;

  function applyTransform() {
    const img = $('img', overlay);
    img.style.transform = `translate(${panX}px, ${panY}px) scale(${scale})`;
  }

  function open(fig) {
    const src = fig.querySelector('img').getAttribute('src');
    const cap = fig.querySelector('figcaption');
    lastFocus = document.activeElement;
    buildOverlay();

    const img = $('img', overlay);
    img.src = src;
    img.alt = fig.querySelector('img').alt || '';
    $('.figview__cap', overlay).textContent = cap ? cap.textContent.trim() : '';
    const dl = $('[data-dl]', overlay);
    dl.href = src;
    dl.setAttribute('download', src.split('/').pop());

    scale = 1; panX = 0; panY = 0;
    applyTransform();
    overlay.hidden = false;
    document.documentElement.style.overflow = 'hidden';
    $('[data-close]', overlay).focus();
  }

  function close() {
    if (!overlay || overlay.hidden) return;
    overlay.hidden = true;
    document.documentElement.style.overflow = '';
    // Returning focus is the whole reason a lightbox is usable by keyboard.
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  function wireZoom() {
    const stage = $('[data-stage]', overlay);
    stage.addEventListener('wheel', (e) => {
      e.preventDefault();
      const next = scale * (e.deltaY < 0 ? 1.12 : 1 / 1.12);
      scale = Math.min(8, Math.max(0.4, next));
      applyTransform();
    }, { passive: false });

    let dragging = false;
    let ox = 0;
    let oy = 0;
    stage.addEventListener('pointerdown', (e) => {
      dragging = true; ox = e.clientX - panX; oy = e.clientY - panY;
      stage.setPointerCapture(e.pointerId);
      stage.classList.add('is-dragging');
    });
    stage.addEventListener('pointermove', (e) => {
      if (!dragging) return;
      panX = e.clientX - ox; panY = e.clientY - oy; applyTransform();
    });
    const stop = () => { dragging = false; stage.classList.remove('is-dragging'); };
    stage.addEventListener('pointerup', stop);
    stage.addEventListener('pointercancel', stop);
  }

  function enhanceFigures() {
    const figs = $$('.doc-fig');
    if (!figs.length) return;

    for (const fig of figs) {
      const img = fig.querySelector('img');
      if (!img) continue;
      const src = img.getAttribute('src');

      const acts = document.createElement('div');
      acts.className = 'doc-fig__acts';
      acts.innerHTML = `
        <button class="doc-fig__btn" type="button" data-expand
                title="View full size" aria-label="View this diagram full size">${ICON.expand}</button>
        <a class="doc-fig__btn" href="${src}" download="${src.split('/').pop()}"
           title="Download SVG" aria-label="Download this diagram as SVG">${ICON.download}</a>`;
      fig.insertBefore(acts, fig.firstChild);

      $('[data-expand]', acts).addEventListener('click', () => open(fig));
      // The image itself is the biggest click target, so it opens too.
      img.addEventListener('click', () => open(fig));
      img.style.cursor = 'zoom-in';
    }

    buildOverlay();
    wireZoom();
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') close();
    });
  }

  // ---------------------------------------------------------------------
  // Page actions: the markdown twin, made reachable
  // ---------------------------------------------------------------------

  function mdUrl() {
    const path = location.pathname.endsWith('/') ? location.pathname : location.pathname + '/';
    return location.origin + path + 'index.md';
  }

  async function copyMarkdown(btn) {
    const label = btn.querySelector('span');
    const original = label.textContent;
    try {
      const res = await fetch(mdUrl());
      if (!res.ok) throw new Error(`the markdown twin returned ${res.status}`);
      await navigator.clipboard.writeText(await res.text());
      label.textContent = 'Copied';
    } catch (e) {
      // Say which of the two things failed, because the fixes are different:
      // a missing twin is our bug, a clipboard refusal is the browser's rule.
      label.textContent = String(e.message).includes('returned')
        ? 'Not available'
        : 'Press Cmd+C';
      window.prompt('Copy the markdown URL:', mdUrl());
    }
    setTimeout(() => { label.textContent = original; }, 2200);
  }

  function wirePageActions() {
    const host = $('[data-page-actions]');
    if (!host) return;
    const title = document.title.replace(' | Trimmy', '');
    const ask =
      `Read ${mdUrl()} and answer questions about it. ` +
      `It documents Trimmy, which turns one XRPL payment into a standing rule on Flare. ` +
      `My question about "${title}" is: `;

    host.innerHTML = `
      <button class="page-act" type="button" data-copy-md>
        ${ICON.download}<span>Copy page as markdown</span></button>
      <a class="page-act" href="https://claude.ai/new?q=${encodeURIComponent(ask)}"
         target="_blank" rel="noopener"><span>Ask Claude</span></a>
      <a class="page-act" href="https://chatgpt.com/?q=${encodeURIComponent(ask)}"
         target="_blank" rel="noopener"><span>Ask ChatGPT</span></a>
      <a class="page-act" href="${mdUrl()}"><span>View as markdown</span></a>`;
    $('[data-copy-md]', host).addEventListener('click', (e) =>
      copyMarkdown(e.currentTarget));
  }

  const start = () => { enhanceFigures(); wirePageActions(); };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
