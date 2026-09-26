import { useRef } from "react";
import { useFrame } from "@/lib/useFrame";
import { getPosition, getIndex, getCount, goTo } from "@/lib/stepper";
import { openGetApp } from "@/lib/getApp";

/**
 * The page's one control. It moves to the next beat; on the last screen,
 * where there is nothing left to scroll, it becomes Get the app.
 */
export function ScrollCue() {
  const node = useRef<HTMLButtonElement>(null);
  const label = useRef<HTMLSpanElement>(null);
  const mode = useRef<"scroll" | "cta">("scroll");
  const timer = useRef(0);

  useFrame(() => {
    const el = node.current;
    if (!el) return;
    const position = getPosition();
    const end = getCount() - 1;
    // A little hysteresis, so resting near the edge does not flicker.
    const next = position > end - (mode.current === "cta" ? 0.5 : 0.4) ? "cta" : "scroll";
    if (next !== mode.current) {
      mode.current = next;
      el.classList.add("is-switching");
      window.clearTimeout(timer.current);
      timer.current = window.setTimeout(() => {
        el.dataset.mode = next;
        if (label.current) label.current.textContent = next === "cta" ? "Get the app" : "Scroll";
        el.setAttribute("aria-label", next === "cta" ? "Get the app" : "Scroll to the next part");
        el.classList.remove("is-switching");
      }, 180);
    }
    // Darker behind the capsule over the rendered pictures (sky, streets, the market, the exchange floor).
    el.style.backgroundColor = position > 1.3 && position < 8.95 ? "rgba(0,0,0,.28)" : "";
    el.dataset.chapter = String(getIndex());
  });

  return (
    <button
      ref={node}
      type="button"
      data-mode="scroll"
      aria-label="Scroll to the next part"
      onClick={() => (mode.current === "cta" ? openGetApp() : goTo(Math.floor(getPosition() + 0.001) + 1))}
      className="scroll-cue fixed bottom-[calc(env(safe-area-inset-bottom)+2rem)] left-1/2 z-20 flex items-center gap-3 rounded-full border border-white/20 bg-white/[0.05] py-1.5 pl-5 pr-1.5 text-white/75 hover:border-white/35 hover:bg-white/10 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white"
      style={{ transform: "translate3d(-50%, 0, 0)" }}
    >
      <span ref={label} className="text-[11px] font-semibold uppercase tracking-[0.24em]">
        Scroll
      </span>
      <span className="scroll-cue__disc relative grid h-8 w-8 place-items-center overflow-hidden rounded-full bg-white text-black">
        <span aria-hidden="true" className="cue-arrow" />
        <span aria-hidden="true" className="cue-arrow cue-arrow-next" />
        <span aria-hidden="true" className="icon icon--download scroll-cue__download" />
      </span>
    </button>
  );
}
