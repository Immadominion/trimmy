/**
 * Two sounds in sequence: the floor ambience, then quiet piano from screen 8.
 *
 * Browsers only let a page start audio after a click, a key or a touch. A wheel
 * does not count, so a visitor who only scrolls hears nothing until their first
 * real gesture; the first one starts everything that is due. The visitor's
 * choice to turn sound off lasts for the session.
 *
 * Volumes never jump. Each channel eases toward its target every frame, so a
 * screen's sound arrives and leaves with the screen and the switch fades rather
 * than cuts.
 */

const KEY = "trimmy.sound";
/** Quietly mastered piano has a 30 percent runtime ceiling. */
const MUSIC = 0.3;
/** A screen's ambience tops out at 50 percent. */
const AMBIENCE = 0.5;
/** Fraction of the remaining distance to the target covered per frame at 60 fps. */
const EASE = 0.06;

type Channel = {
  element: HTMLAudioElement | null;
  src: string;
  /** How much of its ceiling the channel wants, 0 to 1. */
  wanted: number;
  ceiling: number;
  pending: boolean;
  blocked: boolean;
  failed: boolean;
  attempt: number;
};

const channel = (wanted: number, ceiling: number): Channel => ({
  element: null, src: "", wanted, ceiling,
  pending: false, blocked: false, failed: false, attempt: 0,
});
const music = channel(0, MUSIC);
const ambience = channel(0, AMBIENCE);
const channels = [music, ambience];

let enabled = true;
try {
  enabled = sessionStorage.getItem(KEY) !== "off";
} catch {
  // Sound still works when the browser disallows storage.
}
let unlocked = false;
let suspended = document.hidden;
const listeners = new Set<() => void>();

export const isEnabled = () => enabled;

export function setEnabled(value: boolean) {
  enabled = value;
  try {
    sessionStorage.setItem(KEY, value ? "on" : "off");
  } catch {
    // Retain the choice in memory for this visit.
  }
  if (value) unlock();
  listeners.forEach((fn) => fn());
}

export function onChange(fn: () => void) {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
}

function load(channel: Channel, src: string) {
  if (channel.element && channel.src === src) return channel.element;
  channel.element?.pause();
  channel.attempt++;
  channel.pending = false;
  channel.blocked = false;
  channel.failed = false;
  const el = new Audio(src);
  el.loop = true;
  el.preload = "auto";
  el.volume = 0;
  channel.element = el;
  channel.src = src;
  el.addEventListener("error", () => {
    if (channel.element !== el) return;
    channel.failed = true;
    channel.pending = false;
  });
  return el;
}

/** Load the piano without starting it. Narrative position decides when it is due. */
export function setMusic(src: string) {
  load(music, src);
}

/** Music starts on arrival at screen 8, after the floor ambience has ended. */
export function setMusicPosition(position: number) {
  music.wanted = position >= 8 ? 1 : 0;
  // Returning toward the floor fades first, then guarantees silence before its sound arrives.
  if (position <= 7.65 && music.element) {
    music.element.volume = 0;
    if (!music.element.paused || music.pending) pause(music);
  }
}

/** How present a screen's ambience should be right now, 0 to 1. Call every frame. */
export function setAmbience(src: string, level: number) {
  load(ambience, src);
  ambience.wanted = Math.max(0, Math.min(1, level));
}

const target = (c: Channel) => {
  if (!enabled || !unlocked || suspended) return 0;
  // A fading room tail must finish before the first piano note can play.
  if (c === music && (ambience.wanted > 0 || (ambience.element?.volume ?? 0) > 0.001)) return 0;
  return c.wanted * c.ceiling;
};

/** One in-flight play request. A rejection waits for another real gesture. */
function play(c: Channel) {
  const el = c.element;
  if (!el || !el.paused || c.pending || c.blocked || c.failed || !unlocked || target(c) === 0) return;
  const attempt = ++c.attempt;
  c.pending = true;
  el.play().then(() => {
    if (attempt !== c.attempt || c.element !== el) return;
    c.pending = false;
    if (target(c) === 0) el.pause();
  }).catch(() => {
    if (attempt !== c.attempt || c.element !== el) return;
    c.pending = false;
    c.blocked = true;
  });
}

function pause(c: Channel) {
  c.attempt++;
  c.pending = false;
  c.element?.pause();
}

function settle(c: Channel, step: number) {
  const el = c.element;
  if (!el) return;
  const goal = target(c);
  const next = el.volume + (goal - el.volume) * step;
  el.volume = Math.abs(next - goal) < 0.002 ? goal : next;

  if (el.volume > 0.001 && goal > 0) {
    play(c);
  } else if (el.volume <= 0.001 && goal === 0 && (!el.paused || c.pending)) {
    pause(c);
  }
}

/** Advance both channels one frame. `dt` is seconds since the last frame. */
export function tick(dt: number) {
  const step = 1 - Math.pow(1 - EASE, dt * 60);
  settle(music, step);
  settle(ambience, step);
}

/** A real gesture also retries a previous browser autoplay-policy rejection. */
function unlock() {
  unlocked = true;
  for (const c of channels) {
    c.blocked = false;
    play(c);
  }
}

const gestures = ["pointerdown", "keydown", "touchend"] as const;
for (const g of gestures) {
  window.addEventListener(g, unlock, { passive: true });
}

/** Background tabs pause immediately; returning fades the existing tracks in. */
function onVisibility() {
  suspended = document.hidden;
  for (const c of channels) {
    if (suspended) {
      pause(c);
      if (c.element) c.element.volume = 0;
    } else {
      play(c);
    }
  }
}
document.addEventListener("visibilitychange", onVisibility);

if (import.meta.hot) {
  import.meta.hot.dispose(() => {
    for (const g of gestures) window.removeEventListener(g, unlock);
    document.removeEventListener("visibilitychange", onVisibility);
    channels.forEach(pause);
    listeners.clear();
  });
}

// Dev only: lets a browser check read the live elements, which are not in the DOM.
if (import.meta.env.DEV) {
  (window as unknown as { __sound: () => unknown }).__sound = () => ({
    enabled,
    unlocked,
    suspended,
    music: music.element && { src: music.src, paused: music.element.paused, volume: music.element.volume, wanted: music.wanted, pending: music.pending, blocked: music.blocked, failed: music.failed },
    ambience: ambience.element && { src: ambience.src, paused: ambience.element.paused, volume: ambience.element.volume, wanted: ambience.wanted, pending: ambience.pending, blocked: ambience.blocked, failed: ambience.failed },
  });
}
