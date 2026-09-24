import type Lenis from "lenis";

/**
 * Where the visitor is in the story.
 *
 * The page scrolls natively, but every animation reads a smoothed copy of the
 * scroll, not the raw one. Lenis eases the wheel toward its target each frame
 * (lerp 0.1, the reference's setting), so a long flick glides instead of
 * jumping, and every layer moves on the same eased value. Nothing is locked: a
 * fast gesture can still cross several beats, it just travels smoothly.
 *
 * Screens are not all one viewport long. Each has a length, in viewports of
 * scroll, so the opening can breathe while product screens stay one screen each.
 * Position is measured in screens: 3 means screen 3 has just arrived, 3.5 means
 * halfway through its length.
 */

let count = 1;
let lengths: number[] = [1];
let offsets: number[] = [0];
let reduced = false;
let viewportHeight = typeof window === "undefined" ? 1 : Math.max(1, window.innerHeight);
let lenis: Lenis | null = null;

const clamp = (value: number, min: number, max: number) =>
  Math.min(max, Math.max(min, value));

const nativeScroll = () => {
  if (typeof window === "undefined") return 0;
  return document.scrollingElement?.scrollTop ?? window.scrollY;
};

/** Smoothed scroll, in pixels. Falls back to native scroll without Lenis. */
const smoothedScroll = () => (lenis ? lenis.animatedScroll : nativeScroll());

/** Smoothed scroll in viewports. Layers that move with the scroll read this. */
export const getScroll = () => smoothedScroll() / viewportHeight;

/** Where screen `index` starts, in viewports of scroll. */
export const getOffset = (index: number) =>
  offsets[clamp(Math.round(index), 0, count - 1)] ?? 0;

/** Total scroll distance of the story, in viewports, first screen to last. */
export const getTotalLength = () => offsets[count - 1] ?? 0;

/** Story position for a scroll distance in viewports. */
export function positionAt(scroll: number) {
  if (scroll <= 0) return 0;
  for (let i = count - 1; i >= 0; i--) {
    const start = offsets[i]!;
    if (scroll >= start) {
      if (i === count - 1) return i;
      return i + (scroll - start) / lengths[i]!;
    }
  }
  return 0;
}

/** Where the page is right now, in screens. Safe to read in a frame. */
export const getPosition = () => clamp(positionAt(getScroll()), 0, count - 1);

/** The closest story beat to the current position. */
export const getIndex = () => Math.round(getPosition());

export const getCount = () => count;

/** True while a button-started move is still travelling. */
export const isMoving = () => !!lenis && lenis.isScrolling === "smooth";

export const isReducedMotion = () => reduced;

export const getViewportHeight = () => viewportHeight;

export function setViewportHeight(height: number) {
  viewportHeight = Math.max(1, height);
}

export function setScroller(instance: Lenis | null) {
  lenis = instance;
}

export function configure(options: { lengths: number[]; reducedMotion: boolean }) {
  lengths = options.lengths.length ? options.lengths.map((l) => Math.max(0.25, l)) : [1];
  count = lengths.length;
  offsets = [];
  let total = 0;
  for (const length of lengths) {
    offsets.push(total);
    total += length;
  }
  reduced = options.reducedMotion;
}

/** Move to a beat. Scrolling stays interruptible by the visitor. */
export function goTo(next: number) {
  if (typeof window === "undefined") return false;
  const target = getOffset(next) * viewportHeight;
  if (Math.abs(nativeScroll() - target) <= 2) return false;
  if (lenis) lenis.scrollTo(target, { duration: 1.6 });
  else window.scrollTo({ top: target, behavior: reduced ? "instant" : "smooth" });
  return true;
}

/** Move directly, for an explicit skip or restoration. */
export function jumpTo(next: number) {
  if (typeof window === "undefined") return;
  const target = getOffset(next) * viewportHeight;
  if (lenis) lenis.scrollTo(target, { immediate: true, force: true });
  else window.scrollTo({ top: target, behavior: "instant" });
}

/** Advance to the next beat boundary in the requested direction. */
export const step = (direction: number) => {
  if (direction === 0) return false;
  const position = getPosition();
  return goTo(direction > 0
    ? Math.floor(position + 0.001) + 1
    : Math.ceil(position - 0.001) - 1);
};
