// Small, authored office-map symbols. These are not the final character rigs.
// Everything settles; nothing here owns a perpetual timer or animation frame.
const SVG_NS = 'http://www.w3.org/2000/svg';
let instanceCount = 0;

function svgGroup(document, markup, className = '') {
  const group = document.createElementNS(SVG_NS, 'g');
  group.setAttribute('class', className);
  group.innerHTML = markup;
  return group;
}

const ink = '#251B38';
const paper = '#FFFBEF';

// All three interiors use the building's existing isometric wall plane.
const roomArt = {
  1: `
    <path d="M12 113H290" stroke="#9E5276" stroke-width="2"/>
    <g class="room-evidence" transform="translate(18 19)">
      <path d="M0 0H67V78H0Z" fill="${ink}"/><path d="M4 4H63V74H4Z" fill="${paper}"/>
      <path d="M11 15H51M11 21H36" stroke="#7B6689" stroke-width="3"/>
      <path d="M11 34H25V52H11ZM32 30H48V52H32Z" fill="#B598EB"/>
      <path d="M9 62H51" stroke="#DB7093" stroke-width="3"/>
      <path class="room-evidence-stroke" d="M31 62H51" stroke="${ink}" stroke-width="3"/>
      <path d="M25 -3H42V5H25Z" fill="#7455E8"/>
    </g>
    <g transform="translate(112 44)">
      <path d="M2 42Q-3 7 13 8H32Q44 8 40 44Z" fill="#AA6490"/>
      <path d="M15 51V73M2 73H29" stroke="${ink}" stroke-width="4"/>
      <path d="M13 18 31 15 45 42 8 44Z" fill="#7455E8"/>
      <path d="M13 18 22 28 29 16" fill="${paper}"/>
      <path d="M20 10 21 21 29 20 31 9Z" fill="#B55D46"/>
      <path d="M11 -3Q15-14 31-9L38 0 33 14 19 15 12 6Z" fill="#D68757"/>
      <path d="M10 0 11-8 20-14 34-10 38 1 29-3 17 3Z" fill="${ink}"/>
      <path d="M32 1 38 4 33 7" fill="#B55D46"/>
      <path d="M35 28 46 41 66 34" stroke="#D68757" stroke-width="7" fill="none" stroke-linecap="round"/>
      <path d="M17 44 14 57 28 68M28 44 38 55 41 68" stroke="${ink}" stroke-width="7" fill="none"/>
    </g>
    <g transform="translate(104 85)">
      <path d="M0 0H175V10H0Z" fill="#53364E"/><path d="M5 10H11V43H5ZM163 10H169V43H163Z" fill="${ink}"/>
      <path d="M1 0H175V3H1Z" fill="#BE7E99"/>
      <g class="room-report"><path d="M55-13H96V0H55Z" fill="${paper}"/><path d="M60-9H90M60-5H78" stroke="#8B78A0" stroke-width="2"/></g>
      <path d="M103-35H130V-3H103Z" fill="${ink}"/><path d="M106-32H127V-7H106Z" fill="#D4C4EF"/>
      <path d="M110-27H122M110-21H120M110-15H123" stroke="#7455E8" stroke-width="2"/>
      <path d="M113-3H122V0H113Z" fill="${ink}"/>
      <path d="M142-19H148V0H142Z" fill="#7455E8"/><path d="M150-24H157V0H150Z" fill="#F8F37B"/><path d="M159-17H166V0H159Z" fill="#E86B97"/>
      <path d="M143-6H147M151-7H156M160-5H165" stroke="${paper}" stroke-width="1.5"/>
    </g>`,
  2: `
    <path d="M12 113H290" stroke="#9270B2" stroke-width="2"/>
    <g class="room-evidence" transform="translate(18 18)">
      <path d="M0 0H96V73H0Z" fill="${ink}"/><path d="M4 4H92V69H4Z" fill="#F1EBC4"/>
      <path d="M13 15H67M13 21H49" stroke="#8B789B" stroke-width="3"/>
      <path d="M15 52V41H27V52ZM33 52V31H45V52ZM51 52V35H63V52Z" fill="#7455E8"/>
      <path d="M13 55H70" stroke="#8B789B" stroke-width="2"/>
      <path class="room-evidence-stroke" d="M75 34V53M70 43H80" stroke="#E66891" stroke-width="3"/>
      <path d="M75 5 90 5 90 18Z" fill="#F55984"/>
    </g>
    <g transform="translate(148 40)">
      <path d="M7 34Q4 12 17 10H34Q43 13 43 43Z" fill="#8D71AF"/>
      <path d="M22 51V79M7 79H40" stroke="${ink}" stroke-width="4"/>
      <path d="M16 22 33 19 47 52 11 53Z" fill="#DA557B"/>
      <path d="M22 14V25L29 25 30 13" fill="#844C3F"/>
      <path d="M11-5Q20-14 34-5L38 5 31 20 18 17 12 10Z" fill="#AC684F"/>
      <path d="M10 5 7-2 12-13 30-15 39-5 38 6 29 3 25-4 15 1Z" fill="${ink}"/>
      <path d="M31 6 37 9 32 11" fill="#844C3F"/>
      <path d="M35 29 47 40 69 37" stroke="#AC684F" stroke-width="7" fill="none" stroke-linecap="round"/>
      <path d="M19 51 13 65 29 74M34 51 46 62 46 74" stroke="${ink}" stroke-width="7" fill="none"/>
    </g>
    <g transform="translate(124 87)">
      <path d="M0 0H157V10H0Z" fill="#58416B"/><path d="M7 10H13V42H7ZM143 10H149V42H143Z" fill="${ink}"/>
      <path d="M0 0H157V3H0Z" fill="#B998CB"/>
      <path d="M84-35H125V-4H84Z" fill="${ink}"/><path d="M87-32H122V-8H87Z" fill="#FFCCDC"/>
      <path d="M93-14V-20H98V-14ZM101-14V-26H106V-14ZM109-14V-23H114V-14Z" fill="#AB5D91"/>
      <path d="M101-4H109V0H101Z" fill="${ink}"/>
      <g class="room-report"><path d="M27-9H67V0H27Z" fill="${paper}"/><path d="M33-6H54" stroke="#8B78A0" stroke-width="2"/></g>
    </g>
    <g transform="translate(22 110)"><path d="M0 0H62V12H0Z" fill="#7455E8"/><path d="M3-9H61V0H3Z" fill="#F8F37B"/><path d="M7-17H65V-9H7Z" fill="#F55984"/><path d="M15-13H60M10-4H56M7 6H55" stroke="${paper}" stroke-width="2"/></g>`,
  3: `
    <path d="M12 113H290" stroke="#B6974C" stroke-width="2"/>
    <g class="room-evidence" transform="translate(97 16)">
      <path d="M0 0H104V54H0Z" fill="${ink}"/><path d="M4 4H100V50H4Z" fill="${paper}"/>
      <path d="M13 14H60" stroke="#8B789B" stroke-width="3"/>
      <path d="M13 23H35V41H13Z" fill="#C8B5EC"/><path d="M40 23H62V41H40Z" fill="#FFD1E0"/><path d="M67 23H90V41H67Z" fill="#BCE8C8"/>
      <path class="room-evidence-stroke" d="M73 32 77 36 85 27" fill="none" stroke="#397659" stroke-width="3"/>
      <path d="M39-3H64V5H39Z" fill="#E2698F"/>
    </g>
    <g transform="translate(28 47)">
      <path d="M0 19Q0 4 13 5H27Q37 8 36 39Z" fill="#A8863D"/><path d="M15 49V72M2 72H30" stroke="${ink}" stroke-width="4"/>
      <path d="M11 19 28 16 41 48H6Z" fill="#397659"/><path d="M17 12 18 23 25 21 27 10Z" fill="#A8443F"/>
      <path d="M8-8 25-11 32-1 29 11 19 17 9 8Z" fill="#D27158"/>
      <path d="M6 0 6-9 14-16 29-10 34-1 24-3 15 1Z" fill="${ink}"/>
      <path d="M28 1 34 5 29 8" fill="#A8443F"/>
      <path d="M29 25 40 39 59 33" stroke="#D27158" stroke-width="7" fill="none" stroke-linecap="round"/>
      <path d="M17 48 11 60 27 70M29 48 40 61 42 70" stroke="${ink}" stroke-width="7" fill="none"/>
    </g>
    <g transform="translate(248 41)">
      <path d="M-5 24Q-5 9 10 9H23Q37 10 37 41Z" fill="#A8863D"/><path d="M17 52V77M2 77H34" stroke="${ink}" stroke-width="4"/>
      <path d="M7 23 25 22 29 49-31 49Z" fill="#7455E8"/>
      <path d="M9 14 11 26 19 24 20 12Z" fill="#814640"/>
      <path d="M-1-4 15-10 28-2 26 12 12 19 2 11Z" fill="#A3664E"/>
      <path d="M-3 4 -5-7 4-16 22-11 29 0 20 0 13-5 5 3Z" fill="${ink}"/>
      <path d="M1 4 -5 8 2 10" fill="#814640"/>
      <path d="M4 29 -10 40 -29 36" stroke="#A3664E" stroke-width="7" fill="none" stroke-linecap="round"/>
      <path d="M10 49 0 62 4 75M22 49 29 62 21 75" stroke="${ink}" stroke-width="7" fill="none"/>
    </g>
    <g transform="translate(85 91)">
      <path d="M0 0H160V10H0Z" fill="#795540"/><path d="M9 10H15V40H9ZM145 10H151V40H145Z" fill="${ink}"/>
      <path d="M0 0H160V3H0Z" fill="#D9AA6F"/>
      <g class="room-report"><path d="M25-12H72V0H25Z" fill="${paper}"/><path d="M30-8H64M30-4H50" stroke="#8B78A0" stroke-width="2"/></g>
      <path d="M86-8H122V0H86Z" fill="#FFD1E0"/><path d="M96-5H117" stroke="#A45F7D" stroke-width="2"/>
      <path d="M128-16H141V0H128Z" fill="#7455E8"/><path d="M141-13Q150-14 148-6L141-5" stroke="#7455E8" stroke-width="3" fill="none"/>
    </g>
    <g transform="translate(19 115)"><path d="M0-21H8V0H0Z" fill="#7455E8"/><path d="M10-26H18V0H10Z" fill="#F55984"/><path d="M20-18H28V0H20Z" fill="#FFFBEF"/><path d="M2-7H6M12-8H16M22-6H26" stroke="#FFFBEF" stroke-width="1.5"/></g>`,
};

function lampArt(floor) {
  const x = floor === 3 ? 67 : 258;
  return `<g class="room-light"><path class="room-light-pool" d="M${x - 12} 30 ${x - 36} 95H${x + 36}L${x + 12} 30Z" fill="#FFF8CB" opacity=".2"/><path d="M${x} 3V16" stroke="${ink}" stroke-width="2"/><path d="M${x - 13} 28 ${x - 8} 16H${x + 8}L${x + 13} 28Z" fill="${ink}"/><path class="room-lamp-bulb" d="M${x - 10} 28H${x + 10}" stroke="#FFFBEF" stroke-width="3"/></g>`;
}

/** Enhance the existing tower and desk without changing product state. */
export function createRoomDetails({ root = document, reducedMotion = false } = {}) {
  const doc = root.ownerDocument || root;
  const tower = root.querySelector('.tower');
  const lift = tower?.querySelector('.lift');
  const office = root.querySelector('.office-stage');
  const envelope = office?.querySelector('.envelope');
  const coffee = office?.querySelector('.coffee');
  const originalNodes = [];
  const additions = [];
  const rooms = new Map();
  const animations = new Set();
  let reduced = Boolean(reducedMotion);
  let destroyed = false;
  let activeFloor = [1, 2, 3].includes(Number(tower?.dataset.activeFloor)) ? Number(tower.dataset.activeFloor) : 1;
  let lastCupAt = -Infinity;
  const id = `room-lift-${++instanceCount}`;

  function conceal(node) {
    node.classList.add('room-details-original');
    originalNodes.push(node);
  }
  function add(parent, node) {
    parent.append(node);
    additions.push(node);
    return node;
  }
  function cancel() {
    for (const animation of animations) animation.cancel();
    animations.clear();
  }
  function animate(node, frames, options) {
    if (destroyed || reduced || doc.hidden || !node?.animate) return;
    const animation = node.animate(frames, { duration: 600, easing: 'cubic-bezier(.2,.8,.2,1)', fill: 'backwards', ...options });
    animations.add(animation);
    animation.finished.catch(() => {}).finally(() => animations.delete(animation));
  }

  for (const floor of [1, 2, 3]) {
    const room = tower?.querySelector(`.room-${['', 'one', 'two', 'three'][floor]}`);
    if (!room) continue;
    [...room.children].slice(2).forEach(conceal);
    const details = svgGroup(doc, lampArt(floor) + roomArt[floor], 'room-details-interior');
    details.setAttribute('transform', `matrix(1 -.31 0 1 231 ${801 - floor * 190})`);
    details.dataset.roomFloor = String(floor);
    add(room, details);
    rooms.set(floor, room);
  }

  let doors;
  if (lift) {
    [...lift.children].forEach(conceal);
    doors = add(lift, svgGroup(doc, `
      <defs><clipPath id="${id}"><path d="M0 0H64V88H0Z"/></clipPath></defs>
      <g transform="matrix(1 .6 0 1 106 519)">
        <path d="M-3-3H67V91H-3Z" fill="#DCE1B8"/><path d="M0 0H64V88H0Z" fill="#392844"/>
        <path d="M8 8H56V83H8Z" fill="#755D82"/><path d="M9 79H55" stroke="#B198A3" stroke-width="2"/>
        <g clip-path="url(#${id})">
          <path class="room-door room-door-left" d="M0 0H32V88H0Z" fill="#F8F37B"/>
          <path class="room-door room-door-right" d="M32 0H64V88H32Z" fill="#DCC563"/>
        </g>
        <path d="M15-16H49V-6H15Z" fill="${ink}"/>
        <circle class="room-lift-dot" data-indicator-floor="1" cx="23" cy="-11" r="2"/>
        <circle class="room-lift-dot" data-indicator-floor="2" cx="32" cy="-11" r="2"/>
        <circle class="room-lift-dot" data-indicator-floor="3" cx="41" cy="-11" r="2"/>
      </g>`, 'room-details-lift'));
  }
  tower?.classList.add('room-details-ready');
  coffee?.classList.add('room-details-cup');

  function settle(floor) {
    for (const [number, room] of rooms) room.classList.toggle('room-details-active', number === floor);
    doors?.querySelectorAll('[data-indicator-floor]').forEach(dot => {
      dot.classList.toggle('is-current', Number(dot.dataset.indicatorFloor) === floor);
    });
  }
  settle(activeFloor);

  function selectFloor(value) {
    const floor = Number(value);
    if (destroyed || !rooms.has(floor) || floor === activeFloor) return;
    activeFloor = floor;
    cancel();
    settle(floor);
    const room = rooms.get(floor);
    // Close, travel with the host lift, then part. CSS provides the final pose.
    animate(doors?.querySelector('.room-door-left'), [
      { transform: 'translateX(-22px)', offset: 0 },
      { transform: 'translateX(0)', offset: .13 },
      { transform: 'translateX(0)', offset: .72 },
      { transform: 'translateX(-22px)', offset: 1 },
    ], { duration: 1320, easing: 'ease-in-out' });
    animate(doors?.querySelector('.room-door-right'), [
      { transform: 'translateX(22px)', offset: 0 },
      { transform: 'translateX(0)', offset: .13 },
      { transform: 'translateX(0)', offset: .72 },
      { transform: 'translateX(22px)', offset: 1 },
    ], { duration: 1320, easing: 'ease-in-out' });
    animate(room.querySelector('.room-light-pool'), [{ opacity: 0 }, { opacity: .32 }], { delay: 650, duration: 430 });
    animate(room.querySelector('.room-lamp-bulb'), [{ opacity: .25 }, { opacity: 1 }], { delay: 620, duration: 320 });
    animate(doors?.querySelector('.room-lift-dot.is-current'), [{ opacity: .25 }, { opacity: 1 }], { delay: 780, duration: 300 });
    animate(room.querySelector('.room-evidence-stroke'), [{ opacity: .25 }, { opacity: 1 }], { delay: 940, duration: 400 });
    animate(room.querySelector('.room-report'), [
      { transform: 'translate(0, 0) rotate(0deg)' },
      { transform: 'translate(2px, -2px) rotate(-3deg)', offset: .45 },
      { transform: 'translate(0, 0) rotate(0deg)' },
    ], { delay: 950, duration: 520 });
  }

  function respondCup(event) {
    if (event?.type === 'pointerenter' && event.pointerType !== 'mouse') return;
    const now = doc.defaultView?.performance.now() || 0;
    if (now - lastCupAt < 1100 || reduced || destroyed || doc.hidden) return;
    lastCupAt = now;
    animate(coffee, [
      { transform: 'rotate(-8deg)' },
      { transform: 'rotate(-5deg)', offset: .22 },
      { transform: 'rotate(-9deg)', offset: .52 },
      { transform: 'rotate(-7.7deg)', offset: .76 },
      { transform: 'rotate(-8deg)' },
    ], { duration: 820, easing: 'ease-in-out' });
  }
  envelope?.addEventListener('pointerenter', respondCup);
  envelope?.addEventListener('focusin', respondCup);
  envelope?.addEventListener('click', respondCup);
  const StageObserver = doc.defaultView?.MutationObserver;
  const stageObserver = StageObserver && office ? new StageObserver(records => {
    if (records.some(record => !String(record.oldValue).split(' ').includes('offered')) && office.classList.contains('offered')) respondCup();
  }) : null;
  stageObserver?.observe(office, { attributes: true, attributeFilter: ['class'], attributeOldValue: true });

  function onVisibility() { if (doc.hidden) cancel(); }
  doc.addEventListener('visibilitychange', onVisibility);

  function setReducedMotion(value) {
    if (destroyed) return;
    reduced = Boolean(value);
    tower?.classList.toggle('room-details-reduced', reduced);
    if (reduced) cancel();
  }
  setReducedMotion(reduced);

  return {
    selectFloor,
    setReducedMotion,
    getState: () => ({ activeFloor, reducedMotion: reduced, destroyed, roomCount: rooms.size, activeAnimations: animations.size }),
    destroy() {
      if (destroyed) return;
      destroyed = true;
      cancel();
      stageObserver?.disconnect();
      envelope?.removeEventListener('pointerenter', respondCup);
      envelope?.removeEventListener('focusin', respondCup);
      envelope?.removeEventListener('click', respondCup);
      doc.removeEventListener('visibilitychange', onVisibility);
      additions.forEach(node => node.remove());
      originalNodes.forEach(node => node.classList.remove('room-details-original'));
      for (const room of rooms.values()) room.classList.remove('room-details-active');
      tower?.classList.remove('room-details-ready', 'room-details-reduced');
      coffee?.classList.remove('room-details-cup');
    },
  };
}
