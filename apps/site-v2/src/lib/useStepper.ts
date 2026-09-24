import { useEffect } from "react";
import Lenis from "lenis";
import { setFrameDriver } from "./useFrame";
import {
  configure,
  getOffset,
  getPosition,
  getViewportHeight,
  positionAt,
  setScroller,
  setViewportHeight,
} from "./stepper";

/**
 * Smooth scrolling, set up the way the reference does it: Lenis with its default
 * lerp of 0.1 on the wheel, touch synced to the same easing, no automatic
 * requestAnimationFrame. The shared frame loop steps it first on every frame, so
 * scroll and every animated layer advance together and never drift apart.
 *
 * Under a reduced motion preference Lenis is never created: the browser scrolls
 * natively and every beat still arrives, only without the easing.
 */
export function useStepper(lengths: number[]) {
  const key = lengths.join(",");

  useEffect(() => {
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const root = document.documentElement;
    let lenis: Lenis | null = null;

    const start = () => {
      configure({ lengths, reducedMotion: motion.matches });
      if (motion.matches) return;
      lenis = new Lenis({
        autoRaf: false,
        lerp: 0.1,
        smoothWheel: true,
        syncTouch: true,
        wheelMultiplier: 1,
      });
      setScroller(lenis);
      setFrameDriver((time) => lenis?.raf(time));
    };

    const stop = () => {
      setFrameDriver(null);
      setScroller(null);
      lenis?.destroy();
      lenis = null;
    };

    const onMotion = () => {
      const position = getPosition();
      stop();
      start();
      restore(position);
    };

    // Keep the same story moment in view when the browser is resized or rotated.
    const restore = (position: number) => {
      const i = Math.floor(position);
      const within = position - i;
      const next = lengths[i] ?? 1;
      const top = (getOffset(i) + within * next) * getViewportHeight();
      if (lenis) lenis.scrollTo(top, { immediate: true, force: true });
      else window.scrollTo({ top, behavior: "instant" });
    };

    const syncViewport = () => {
      const next = Math.max(1, window.innerHeight);
      const previous = getViewportHeight();
      const position = positionAt((document.scrollingElement?.scrollTop ?? window.scrollY) / previous);
      setViewportHeight(next);
      root.style.setProperty("--story-viewport-height", `${next}px`);
      if (Math.abs(next - previous) > 1) {
        lenis?.resize();
        restore(position);
      }
    };

    setViewportHeight(Math.max(1, window.innerHeight));
    root.style.setProperty("--story-viewport-height", `${getViewportHeight()}px`);
    start();

    window.addEventListener("resize", syncViewport, { passive: true });
    motion.addEventListener("change", onMotion);

    return () => {
      window.removeEventListener("resize", syncViewport);
      motion.removeEventListener("change", onMotion);
      stop();
      root.style.removeProperty("--story-viewport-height");
    };
    // `key` stands in for the array's contents.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
}
