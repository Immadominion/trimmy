import { useRef } from "react";
import { useFrame } from "@/lib/useFrame";
import { getPosition, getIndex, getCount, goTo } from "@/lib/stepper";
import { clamp01, smoothstep } from "@/lib/math";

/** The original scroll capsule remains the only chapter control. */
export function ScrollCue() {
  const node = useRef<HTMLButtonElement>(null);
  const hidden = useRef(false);

  useFrame(() => {
    const el = node.current;
    if (!el) return;
    const k = smoothstep(clamp01((getPosition() - (getCount() - 1.5)) / 0.5));
    el.style.opacity = String(1 - k);
    // Darker behind the capsule while the rendered opening (sky, streets, the market) is up.
    el.style.backgroundColor = getPosition() > 1.3 && getPosition() < 5.95 ? "rgba(0,0,0,.28)" : "";
    el.dataset.chapter = String(getIndex());
    el.style.transform = `translate3d(-50%, ${k * 10}px, 0)`;

    const nowHidden = k > 0.98;
    if (nowHidden !== hidden.current) {
      hidden.current = nowHidden;
      el.style.visibility = nowHidden ? "hidden" : "visible";
    }
  });

  return (
    <button
      ref={node}
      type="button"
      onClick={() => goTo(Math.floor(getPosition() + 0.001) + 1)}
      className="fixed bottom-[calc(env(safe-area-inset-bottom)+2rem)] left-1/2 z-20 flex items-center gap-3 rounded-full border border-white/20 bg-white/[0.05] py-1.5 pl-5 pr-1.5 text-white/75 transition-colors duration-200 hover:border-white/35 hover:bg-white/10 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white"
      style={{ transform: "translate3d(-50%, 0, 0)" }}
    >
      <span className="text-[11px] font-semibold uppercase tracking-[0.24em]">
        Scroll
      </span>
      <span className="relative grid h-8 w-8 place-items-center overflow-hidden rounded-full bg-white text-black">
        <span aria-hidden="true" className="cue-arrow" />
        <span aria-hidden="true" className="cue-arrow cue-arrow-next" />
      </span>
    </button>
  );
}
