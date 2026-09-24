import { useRef, type PointerEvent } from "react";
import { useFrame } from "@/lib/useFrame";
import { getPosition, isReducedMotion } from "@/lib/stepper";
import { clamp01, smoothstep } from "@/lib/math";
import { PhoneArrival, VirtualBalance, StockOrbit, SalMission, SplitHolding, RankAscent, BuildAssembly, BrandReturn } from "./ProductScenes";
import "./product.css";

const scenes = [PhoneArrival, VirtualBalance, StockOrbit, SalMission, SplitHolding, RankAscent, BuildAssembly, BrandReturn];
// Each object has a different physical arrival/departure, in a single perspective stage.
const motion = [
  { enter: [-160, 40, -300, -48, 8], leave: [75, -170, -420, 75, 25] },
  { enter: [35, 190, -220, -18, 30], leave: [-180, 65, -400, -45, 45] },
  { enter: [180, -45, -160, 45, -10], leave: [70, -160, -280, -35, 25] },
  { enter: [-150, 90, -190, -25, 12], leave: [180, 20, -370, 40, -12] },
  { enter: [50, 140, -220, 20, 30], leave: [-70, -180, -370, -35, 25] },
  { enter: [-100, 180, -340, -35, 12], leave: [110, -180, -300, 40, -15] },
  { enter: [180, 15, -250, 38, 18], leave: [-150, 70, -390, -55, 30] },
  { enter: [90, 140, -270, -40, 15], leave: [0, 0, 0, 0, 0] },
];

/** Distinct objects occupy the same space; scroll moves through their depth. */
export function ProductShowcase() {
  const host = useRef<HTMLDivElement>(null);
  const objects = useRef<(HTMLDivElement | null)[]>([]);
  const pointer = useRef({ x: 0, y: 0 });
  const active = useRef(-1);
  const shown = useRef(false);

  useFrame((time) => {
    const el = host.current;
    if (!el) return;
    const position = getPosition();
    const reduced = isReducedMotion();
    el.style.setProperty("--idle", reduced ? "0" : String(Math.sin(time / 1450)));
    el.style.setProperty("--idle-depth", reduced ? "0" : String(Math.sin(time / 1900 + .7)));
    const visible = position > 8.05;
    if (visible !== shown.current) {
      shown.current = visible;
      el.style.visibility = visible ? "visible" : "hidden";
      el.setAttribute("aria-hidden", String(!visible));
      el.inert = !visible;
    }
    const selected = Math.max(0, Math.min(7, Math.round(position - 9)));
    el.style.setProperty("--pointer-x", reduced ? "0" : String(pointer.current.x));
    el.style.setProperty("--pointer-y", reduced ? "0" : String(pointer.current.y));
    objects.current.forEach((node, i) => {
      if (!node) return;
      const local = position - (i + 9);
      const distance = Math.abs(local);
      const opacity = smoothstep(clamp01(1 - distance));
      node.style.opacity = String(opacity);
      node.style.visibility = opacity > .002 ? "visible" : "hidden";
      const amount = reduced ? 0 : clamp01(distance);
      const vector = local < 0 ? motion[i]!.enter : motion[i]!.leave;
      node.style.transform = `translate3d(${vector[0]! * amount}px, ${vector[1]! * amount}px, ${vector[2]! * amount}px) rotateY(${vector[3]! * amount}deg) rotateX(${vector[4]! * amount}deg)`;
      node.style.setProperty("--phase", reduced ? "0" : String(Math.max(-1, Math.min(1, local))));
      if (selected !== active.current) {
        node.inert = i !== selected;
        node.setAttribute("aria-hidden", String(i !== selected));
      }
    });
    active.current = selected;
  });

  const movePointer = (event: PointerEvent<HTMLDivElement>) => {
    if (event.pointerType !== "mouse") return;
    const rect = event.currentTarget.getBoundingClientRect();
    pointer.current = { x: (event.clientX - rect.left) / rect.width * 2 - 1, y: (event.clientY - rect.top) / rect.height * 2 - 1 };
  };

  return <div className="product-spatial-world" ref={host} aria-label="Explore the Trimmy game" aria-hidden="true" inert style={{ visibility: "hidden" }} onPointerMove={movePointer} onPointerLeave={() => { pointer.current = { x: 0, y: 0 }; }}><div className="product-spatial-camera">{scenes.map((Scene, i) => <div className={`product-spatial-scene product-spatial-scene--${i + 9}`} key={i} ref={(node) => { objects.current[i] = node; }} inert={i !== 0} aria-hidden={i !== 0} style={{ opacity: 0, visibility: "hidden" }}><Scene /></div>)}</div></div>;
}
