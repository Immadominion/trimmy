import { useEffect, useRef, useState } from "react";
import { useFrame } from "@/lib/useFrame";
import { getPosition, isReducedMotion } from "@/lib/stepper";
import { clamp01, smoothstep } from "@/lib/math";
import { createWorld, type WorldEngine } from "./engine";
import "./world.css";

export default function WorldStage() {
  const host = useRef<HTMLDivElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const poster = useRef<HTMLImageElement>(null);
  const loader = useRef<HTMLParagraphElement>(null);
  const engine = useRef<WorldEngine | null>(null);
  const pointer = useRef({ x: 0, y: 0 });
  const [state, setState] = useState<"loading" | "ready" | "fallback">("loading");

  useEffect(() => {
    let disposed = false;
    const onPointer = (event: PointerEvent) => {
      if (event.pointerType !== "mouse") return;
      pointer.current.x = event.clientX / window.innerWidth * 2 - 1;
      pointer.current.y = event.clientY / window.innerHeight * 2 - 1;
    };
    const leave = () => { pointer.current.x = 0; pointer.current.y = 0; };
    window.addEventListener("pointermove", onPointer, { passive: true });
    document.addEventListener("pointerleave", leave);
    try {
      engine.current = createWorld(host.current!, (next) => { if (!disposed) setState(next); });
    } catch { setState("fallback"); }
    return () => {
      disposed = true;
      window.removeEventListener("pointermove", onPointer);
      document.removeEventListener("pointerleave", leave);
      engine.current?.dispose(); engine.current = null;
    };
  }, []);

  useFrame((time) => {
    const p = getPosition();
    // The opening's rendered move runs through the market line (screen 5); the world takes over at the ticker.
    const reveal = smoothstep(clamp01((p - 5.84) / .16));
    const finish = 1 - smoothstep(clamp01((p - 8.35) / .65));
    if (stage.current) {
      stage.current.style.opacity = String(reveal * finish);
      stage.current.style.visibility = reveal * finish > .001 ? "visible" : "hidden";
    }
    if (loader.current) { loader.current.style.opacity = p > 5.5 && p < 9 ? "1" : "0"; loader.current.style.visibility = p > 5.5 && p < 9 ? "visible" : "hidden"; }
    if (poster.current) {
      const path = p < 6.6 ? "/world/poster-street.webp" : "/world/poster-floor.webp";
      if (!poster.current.src.endsWith(path)) poster.current.src = path;
    }
    engine.current?.update(p, time, isReducedMotion(), pointer.current);
  });

  return <>
    <div className="world-stage" ref={stage} aria-hidden="true" data-world-state={state} style={{ opacity: 0, visibility: "hidden" }}>
      {state !== "ready" && <img className="world-poster" ref={poster} src="/world/poster-street.webp" alt="" onError={(event) => { event.currentTarget.style.visibility = "hidden"; }} onLoad={(event) => { event.currentTarget.style.visibility = "visible"; }} />}
      <div className="world-canvas" ref={host} style={{ opacity: state === "ready" ? 1 : 0 }} />
      <div className="world-readability" />
      <div className="world-grain" />
    </div>
    {state === "loading" && <p ref={loader} className="world-loading" role="status">Opening Wall Street…</p>}
  </>;
}
