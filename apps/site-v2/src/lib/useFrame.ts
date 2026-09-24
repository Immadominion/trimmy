import { useEffect, useRef } from "react";

type FrameCallback = (time: number) => void;

const callbacks = new Set<FrameCallback>();
let raf = 0;
let now = typeof performance === "undefined" ? 0 : performance.now();
let driver: FrameCallback | null = null;

/**
 * The timestamp of the frame being drawn. Read this rather than performance.now()
 * inside a frame callback, so everything drawn in one frame agrees on the time.
 */
export const frameTime = () => now;

/**
 * Runs once at the start of every frame, before any animated element reads the
 * page position. The smooth scroller registers here, so it advances first and
 * every layer in the frame reads the same smoothed value, the way the reference
 * steps Lenis ahead of its whole render loop.
 */
export function setFrameDriver(fn: FrameCallback | null) {
  driver = fn;
  if (driver && !raf) raf = requestAnimationFrame(tick);
}

function tick(time: number) {
  now = time;
  driver?.(time);
  for (const cb of callbacks) cb(time);
  raf = callbacks.size || driver ? requestAnimationFrame(tick) : 0;
}

/**
 * One shared frame loop for the whole page. Every animated element reads the
 * page position here and writes to its own node, so N elements still cost one
 * requestAnimationFrame and nothing animated ever goes through React state.
 */
export function useFrame(callback: FrameCallback) {
  const ref = useRef(callback);
  ref.current = callback;

  useEffect(() => {
    const run: FrameCallback = (time) => ref.current(time);
    callbacks.add(run);
    if (!raf) raf = requestAnimationFrame(tick);
    return () => {
      callbacks.delete(run);
      if (!callbacks.size && !driver && raf) {
        cancelAnimationFrame(raf);
        raf = 0;
      }
    };
  }, []);
}
