// Scroll-position choreography. Scroll remains native; there is no pin/snap,
// continuous idle render loop, fixed reading speed or offscreen animation.
const clamp = n => Math.min(1, Math.max(0, n));
const mix = (a, b, t) => a + (b - a) * t;
const smooth = t => t * t * (3 - 2 * t);

export function createScrollScenes({ reducedMotion = false }) {
  let reduced = reducedMotion;
  let frame = 0;
  let destroyed = false;
  let progress = 1;
  const world = document.querySelector('.world-window');
  const stage = document.querySelector('.office-stage');
  const office = document.querySelector('.office-set');
  const holder = document.createElement('div');
  holder.className = 'origin-scene';
  holder.setAttribute('aria-hidden', 'true');
  holder.innerHTML = `<svg viewBox="0 0 420 350" focusable="false"><defs><linearGradient id="origin-material" x1="0" x2="1" y1="0" y2="1"><stop stop-color="#b6a5ff"/><stop offset="1" stop-color="#7455e8"/></linearGradient><clipPath id="origin-clip"><path class="origin-mask"/></clipPath></defs><ellipse class="origin-shadow" cx="212" cy="326" rx="106" ry="10" fill="#10071b" opacity=".25"/><g class="origin-object"><path class="origin-depth" fill="#5136a0"/><path class="origin-frame" fill="url(#origin-material)" stroke="#ebe6ff" stroke-width="5"/><g clip-path="url(#origin-clip)"><g class="origin-city"><path d="M63 300V161h52v-43l30-18 32 18v103h30v-82h51v63h35v-90h43v188Z" fill="#251b38"/><path d="M130 141h26m-26 30h26m-26 30h26m67-43h16m-16 30h16m62-33h15m-15 30h15m-93 54h16" stroke="#c4b5ed" stroke-width="7"/><path d="M78 95h262M201 80v231" stroke="#ebe6ff" stroke-width="8" opacity=".85"/></g><g class="origin-phone-screen"><rect x="141" y="112" width="138" height="131" rx="21" fill="#9176f1"/><image href="./assets/mark.png" x="156" y="124" width="108" height="108"/><path d="M168 263h84M184 279h52" stroke="#d6ccfc" stroke-width="5" stroke-linecap="round"/></g></g><rect class="origin-speaker" x="193" y="68" width="34" height="6" rx="3" fill="#251b38"/></g><g class="origin-spark" fill="#f8f37b"><path d="m72 82 4 13 13 4-13 4-4 13-4-13-13-4 13-4Z"/><path d="m337 246 3 9 9 3-9 3-3 9-3-9-9-3 9-3Z"/></g></svg>`;
  world.append(holder);
  world.classList.add('world-enhanced');
  const svg = holder.querySelector('svg');
  const shape = holder.querySelector('.origin-frame');
  const mask = holder.querySelector('.origin-mask');
  const depth = holder.querySelector('.origin-depth');
  const object = holder.querySelector('.origin-object');
  const city = holder.querySelector('.origin-city');
  const screen = holder.querySelector('.origin-phone-screen');
  const speaker = holder.querySelector('.origin-speaker');
  const sparks = holder.querySelector('.origin-spark');

  function outline(t, offset = 0) {
    const left = mix(65, 127, t) + offset, right = mix(355, 293, t) + offset;
    const top = mix(45, 50, t) + offset, bottom = mix(310, 311, t) + offset;
    const rx = mix(120, 27, t), bottomR = mix(4, 27, t);
    return `M${left + rx} ${top}H${right - rx}Q${right} ${top} ${right} ${top + rx}V${bottom - bottomR}Q${right} ${bottom} ${right - bottomR} ${bottom}H${left + bottomR}Q${left} ${bottom} ${left} ${bottom - bottomR}V${top + rx}Q${left} ${top} ${left + rx} ${top}Z`;
  }

  function draw(t) {
    progress = t;
    const p = smooth(t);
    shape.setAttribute('d', outline(p)); mask.setAttribute('d', outline(p));
    depth.setAttribute('d', outline(p, 9));
    object.setAttribute('transform', `rotate(${mix(-9, 9, p)} 210 175)`);
    city.setAttribute('opacity', String(1 - smooth(clamp((t - .12) / .55))));
    screen.setAttribute('opacity', String(smooth(clamp((t - .38) / .45))));
    speaker.setAttribute('opacity', String(smooth(clamp((t - .45) / .4))));
    sparks.setAttribute('opacity', String(.35 + .65 * Math.sin(t * Math.PI)));
    svg.dataset.progress = t.toFixed(3);
  }

  function update() {
    frame = 0;
    if (destroyed || document.hidden) return;
    if (reduced) {
      draw(1);
      office.style.removeProperty('transform');
      return;
    }
    const box = world.getBoundingClientRect();
    if (box.bottom > -100 && box.top < innerHeight + 100) {
      draw(clamp((innerHeight * .9 - box.top) / (innerHeight * .58)));
    }
    const room = stage.getBoundingClientRect();
    if (innerWidth <= 700) office.style.removeProperty('transform');
    if (room.bottom > 0 && room.top < innerHeight && innerWidth > 700) {
      const depth = clamp((innerHeight - room.top) / (innerHeight + room.height));
      // Independent room depth; reading copy and controls never translate.
      office.style.transform = `scaleX(-1) translateY(${mix(8, -8, depth)}px) scale(1.025)`;
    }
  }
  function queue() {
    if (!frame && !destroyed && !document.hidden) frame = requestAnimationFrame(update);
  }
  const onVisibility = () => { if (document.hidden) { cancelAnimationFrame(frame); frame = 0; } else queue(); };
  window.addEventListener('scroll', queue, { passive: true });
  window.addEventListener('resize', queue, { passive: true });
  document.addEventListener('visibilitychange', onVisibility);
  draw(1); queue();
  return {
    setReducedMotion(value) { reduced = Boolean(value); cancelAnimationFrame(frame); frame = 0; update(); },
    refresh: queue,
    getState: () => ({ frameActive: frame !== 0, progress, reduced }),
    destroy() {
      destroyed = true; cancelAnimationFrame(frame); frame = 0;
      window.removeEventListener('scroll', queue); window.removeEventListener('resize', queue);
      document.removeEventListener('visibilitychange', onVisibility);
      holder.remove(); world.classList.remove('world-enhanced'); office.style.removeProperty('transform');
    },
  };
}
