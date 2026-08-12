/* ==========================================================================
   MOTION

   Kept in its own file, and out of page.js, for one reason: page.js owns the
   things the page needs to work (the tabs, the carousel, the builder preview).
   Nothing in here is needed for the page to work, so if it breaks or is
   blocked, the page still renders in its final state.

   That is also why the CSS is gated on html.motion-ready, added below rather
   than in the markup. No script, no hiding. Reduced motion, no hiding either.
   ========================================================================== */
(() => {
  const root = document.documentElement;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  const fine = window.matchMedia('(hover: hover) and (pointer: fine)');
  const wide = window.matchMedia('(min-width: 64rem)');

  if (reduce.matches) return;
  root.classList.add('motion-ready');

  // Turning motion off mid-session must not leave anything invisible: the
  // reveal state is a class, so the fix is to grant it to everything at once.
  reduce.addEventListener?.('change', () => {
    if (!reduce.matches) return;
    root.classList.remove('motion-ready');
    document.querySelectorAll('[data-reveal]').forEach((el) => el.classList.add('is-in'));
  });

  /* ---- entrance ---------------------------------------------------------
     Anything with data-reveal arrives once, when it first comes into view.
     Siblings that share a parent are staggered so a grid of six cards lands
     as a sequence rather than a single flash. */
  const revealables = [...document.querySelectorAll('[data-reveal]')];

  if (!('IntersectionObserver' in window)) {
    revealables.forEach((el) => el.classList.add('is-in'));
  } else {
    // Group by parent, then index within the group, so the stagger is a
    // property of position on the page rather than of document order.
    const seen = new Map();
    revealables.forEach((el) => {
      const key = el.parentElement || document.body;
      const index = seen.get(key) ?? 0;
      seen.set(key, index + 1);
      el.style.setProperty('--reveal-delay', `${Math.min(index, 6) * 85}ms`);
    });

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-in');
        observer.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -12% 0px', threshold: 0.08 });

    revealables.forEach((el) => observer.observe(el));

    // Anything already on screen at load should not wait for a scroll that may
    // never come. One frame later, so the transition has an initial state to
    // animate away from.
    requestAnimationFrame(() => {
      revealables.forEach((el) => {
        if (el.getBoundingClientRect().top < window.innerHeight * 0.92) {
          el.classList.add('is-in');
        }
      });
    });
  }

  /* ---- the sheen on the ecosystem rail ---------------------------------- */
  const rail = document.querySelector('.ecosystem__inner');
  if (rail && !rail.querySelector('.ecosystem__sheen')) {
    const sheen = document.createElement('span');
    sheen.className = 'ecosystem__sheen';
    sheen.setAttribute('aria-hidden', 'true');
    rail.append(sheen);
  }

  /* ---- response: the hero light and the card lean -----------------------
     One rAF loop, started only while the pointer is over the hero, and stopped
     the moment it leaves. Two trailing values at different speeds, because a
     single light pinned exactly to the cursor reads as a bug rather than as
     depth. */
  const hero = document.querySelector('.hero');
  const card = document.querySelector('.hero-rule');

  // The card's entrance owns its transform until it finishes. Handing the lean
  // over any earlier fights the keyframes for the same property.
  card?.addEventListener('animationend', (event) => {
    if (event.animationName === 'hero-card-in') card.classList.add('is-landed');
  });

  if (hero && fine.matches) {
    // Where the light rests when nobody is pointing at anything.
    const REST = { x: 0.58, y: 0.48 };

    let target = { ...REST };
    let slow = { ...REST };
    let fast = { ...REST };
    let running = false;
    let inside = false;

    const lerp = (a, b, t) => a + (b - a) * t;

    function frame() {
      fast.x = lerp(fast.x, target.x, 0.12);
      fast.y = lerp(fast.y, target.y, 0.12);
      slow.x = lerp(slow.x, target.x, 0.055);
      slow.y = lerp(slow.y, target.y, 0.055);

      hero.style.setProperty('--hero-glow-x', `${(fast.x * 100).toFixed(2)}%`);
      hero.style.setProperty('--hero-glow-y', `${(fast.y * 100).toFixed(2)}%`);
      hero.style.setProperty('--hero-glow2-x', `${(slow.x * 100).toFixed(2)}%`);
      hero.style.setProperty('--hero-glow2-y', `${(slow.y * 100).toFixed(2)}%`);

      // The graph paper moves against the pointer, a handful of pixels.
      hero.style.setProperty('--hero-tilt-x', `${((0.5 - slow.x) * 26).toFixed(1)}px`);
      hero.style.setProperty('--hero-tilt-y', `${((0.5 - slow.y) * 18).toFixed(1)}px`);

      if (card && wide.matches) {
        card.style.setProperty('--card-ry', `${((fast.x - 0.5) * 4).toFixed(2)}deg`);
        card.style.setProperty('--card-rx', `${((0.5 - fast.y) * 3).toFixed(2)}deg`);
      }

      const settled =
        Math.abs(fast.x - target.x) < 0.0015 && Math.abs(fast.y - target.y) < 0.0015 &&
        Math.abs(slow.x - target.x) < 0.0015 && Math.abs(slow.y - target.y) < 0.0015;

      if (settled && !inside) { running = false; return; }
      requestAnimationFrame(frame);
    }

    function start() {
      if (running) return;
      running = true;
      requestAnimationFrame(frame);
    }

    hero.addEventListener('pointermove', (event) => {
      if (event.pointerType !== 'mouse') return;
      const rect = hero.getBoundingClientRect();
      inside = true;
      target = {
        x: (event.clientX - rect.left) / rect.width,
        y: (event.clientY - rect.top) / rect.height
      };
      hero.style.setProperty('--hero-glow-o', '1');
      start();
    }, { passive: true });

    hero.addEventListener('pointerleave', () => {
      inside = false;
      target = { ...REST };
      hero.style.setProperty('--hero-glow-o', '.85');
      start();
    });
  }
})();
