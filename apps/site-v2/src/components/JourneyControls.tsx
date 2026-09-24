import { useRef } from "react";
import { useFrame } from "@/lib/useFrame";
import { getCount, getIndex, getPosition, goTo, jumpTo, isMoving } from "@/lib/stepper";

export function JourneyControls() {
  const nav = useRef<HTMLElement>(null);
  const skip = useRef<HTMLButtonElement>(null);
  const previous = useRef<HTMLButtonElement>(null);
  const next = useRef<HTMLButtonElement>(null);
  const label = useRef<HTMLSpanElement>(null);
  useFrame(() => {
    const p = getPosition(), index = getIndex();
    nav.current?.setAttribute("aria-busy", String(isMoving()));
    if (nav.current) { nav.current.style.opacity = p > .7 ? "1" : "0"; nav.current.style.visibility = p > .7 ? "visible" : "hidden"; }
    if (skip.current) { skip.current.style.visibility = p > 1.4 && p < 8.8 ? "visible" : "hidden"; }
    if (previous.current) previous.current.disabled = index === 0;
    if (next.current) next.current.disabled = index === getCount() - 1;
    if (label.current) label.current.textContent = `${String(index + 1).padStart(2, "0")} / ${String(getCount()).padStart(2, "0")}`;
  });
  const move = (direction: number) => { if (!isMoving()) goTo(getIndex() + direction); };
  return <>
    <button ref={skip} type="button" className="journey-skip" style={{ visibility: "hidden" }} onClick={() => jumpTo(9)}>Skip to the game</button>
    <nav ref={nav} className="journey-controls" style={{ opacity: 0, visibility: "hidden" }} aria-label="Move through the story">
      <button ref={previous} type="button" aria-label="Previous scene" onClick={() => move(-1)}>↑</button>
      <span ref={label} aria-hidden="true">01 / 17</span>
      <button ref={next} type="button" aria-label="Next scene" onClick={() => move(1)}>↓</button>
    </nav>
  </>;
}
