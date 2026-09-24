import { useRef } from "react";
import { useFrame } from "@/lib/useFrame";
import { getCount, getPosition } from "@/lib/stepper";
import { clamp01 } from "@/lib/math";

/**
 * Rail ends, both Icons8 (iOS line style, same family as the capsule arrow),
 * drawn as masks so they take the rail's colour. Top is where the story starts:
 * Wall Street, as its bull. Bottom is where it ends: in your hand.
 */
const RailIcon = ({ src }: { src: string }) => (
  <span
    aria-hidden="true"
    className="block h-[22px] w-[22px] bg-current"
    style={{
      WebkitMask: `url(${src}) center / contain no-repeat`,
      mask: `url(${src}) center / contain no-repeat`,
    }}
  />
);

/**
 * The page's own scroll bar, after the reference's: a short 2px track with a
 * solid thumb a fifth of its height that slides from Wall Street (the bull) to
 * the phone in your hand as the story goes by. It replaces the browser's, which
 * is hidden. On phones the icons drop away and the track sits at the edge.
 *
 * Decorative: the screens carry the meaning, so it is hidden from a reader.
 */
export function ProgressRail() {
  const thumb = useRef<HTMLDivElement>(null);

  useFrame(() => {
    const el = thumb.current;
    if (!el) return;
    const last = getCount() - 1;
    // The thumb is 20% of the track, so 400% of its own height is the whole run.
    el.style.transform = `translate3d(0, ${(last > 0 ? clamp01(getPosition() / last) : 0) * 400}%, 0)`;
  });

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none fixed left-2.5 top-1/2 z-20 flex -translate-y-1/2 flex-col items-center gap-2.5 text-white drop-shadow-[0_0_3px_rgba(0,0,0,0.45)] md:left-8"
    >
      <span className="hidden md:block"><RailIcon src="/icons8-bull.png" /></span>
      <div className="relative h-[140px] w-[2px] overflow-hidden rounded-full bg-white/25">
        <div
          ref={thumb}
          className="absolute inset-x-0 top-0 h-1/5 rounded-full bg-white will-change-transform"
          style={{ transform: "translate3d(0, 0, 0)" }}
        />
      </div>
      <span className="hidden md:block"><RailIcon src="/icons8-smartphone.png" /></span>
    </div>
  );
}
