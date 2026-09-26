import { useEffect, useMemo, useRef, useState } from "react";
import { useFrame } from "@/lib/useFrame";
import { getOffset, getScroll, isReducedMotion } from "@/lib/stepper";
import { clamp01, smoothstep } from "@/lib/math";
import { setTextPlans, type TextPlan } from "@/lib/storyText";
import { LENGTHS } from "@/story/screens";
import { FrameCanvas, FrameSequence, handoff, loadManifest, measure, PORTRAIT_QUERY, type Layout, type Quad, type RiseManifest, type SequenceSet } from "./risePlayer";
import { PAGES, PAGE_ORDER, type PageName } from "./PhoneApp";
import "./frame-story.css";

/**
 * Screens 6 to 16, one continuous take rendered in Blender and played in step
 * with the scroll (art/tmp/blender-opening/exchange/SHOTS.md, phone/SHOTS.md).
 * From the market's facade the camera flies through the doors onto the 1930s
 * trading floor, follows the ticker tape, climbs to the bell, and a storm of
 * paper turns the room into today's; it pulls back and the floor becomes the
 * picture on a phone in a hand, and the phone then turns from one screen's
 * object to the next. Every shot starts on the frame the one before ended on,
 * so nothing fades between them.
 *
 * Each shot plays on the way to its screen and comes to rest as that screen's
 * copy arrives. The phone's display is see-through in the frames: the app's
 * page lies under them, mapped onto the display's four corners in the frame on
 * screen, so it is sharp, live HTML, and the glass's reflection, the punch hole
 * and anything in front of the display cover it as they would a phone's own.
 */

type Shot = {
  name: string;
  /** Screen at which the shot comes to rest. */
  arrive: number;
  /** Viewports of scroll the shot takes; it ends as its screen arrives. */
  move: number;
  /** How long before arrival the copy may start to show, in viewports. */
  lead: number;
  /** Phone shots: the app page the display shows from the shot's `page` frame. */
  page?: PageName | null;
};

const SHOTS: Shot[] = [
  { name: "exchange-ticker", arrive: 6, move: 1, lead: 0.5 },
  { name: "exchange-floor", arrive: 7, move: 0.8, lead: 0.5 },
  { name: "exchange-performance", arrive: 8, move: 0.9, lead: 0.5 },
  { name: "phone-hand", arrive: 9, move: 0.7, lead: 0.3, page: null },
  { name: "phone-money", arrive: 10, move: 0.6, lead: 0.3, page: "money" },
  { name: "phone-prices", arrive: 11, move: 0.6, lead: 0.3, page: "prices" },
  { name: "phone-sal", arrive: 12, move: 0.6, lead: 0.3, page: "sal" },
  { name: "phone-trim", arrive: 13, move: 0.6, lead: 0.3, page: "trim" },
  { name: "phone-ranks", arrive: 14, move: 0.6, lead: 0.3, page: "ranks" },
  { name: "phone-status", arrive: 15, move: 0.6, lead: 0.3, page: "status" },
  { name: "phone-close", arrive: 16, move: 0.6, lead: 0.3, page: "close" },
];
/** Frames over which one page gives way to the next while the display is in view. */
const SWAP = 8;
/** How close, in pixels, the display must be to where it rests to be used. */
const SETTLED = 1.5;
/** The app's page size, in CSS pixels. */
const UI: [number, number] = [390, 844];

/** Where each shot plays, in viewports of scroll. */
const windows = () => SHOTS.map((shot) => {
  const end = getOffset(shot.arrive);
  return [end - shot.move, end] as [number, number];
});

/** CSS matrix3d that maps a w x h box onto a quad (TL, TR, BR, BL) in pixels. */
function quadTransform(q: number[], w: number, h: number) {
  const [x0, y0, x1, y1, x2, y2, x3, y3] = q as Quad;
  const dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
  const dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
  const det = dx1 * dy2 - dx2 * dy1;
  const g = (dx3 * dy2 - dx2 * dy3) / det;
  const k = (dx1 * dy3 - dx3 * dy1) / det;
  const a = x1 - x0 + g * x1, b = x3 - x0 + k * x3;
  const d = y1 - y0 + g * y1, e = y3 - y0 + k * y3;
  return `matrix3d(${a / w},${d / w},0,${g / w},${b / h},${e / h},0,${k / h},0,0,1,0,${x0},${y0},0,1)`;
}

/**
 * When each screen's copy shows and, for the exchange, where: it arrives from
 * the frame its picture leaves room for it and leaves as the next shot starts.
 * The phone screens keep their column (desktop) or top band (portrait) from
 * product.css, which is where the phone renders leave room.
 */
function textPlans(sets: (SequenceSet | undefined)[], L: Layout) {
  const plans = new Map<number, TextPlan>();
  const narrow = L.width < 700;
  SHOTS.forEach((shot, k) => {
    const set = sets[k];
    if (!set) return;
    const from = -shot.move + shot.move * ((set.textFrom ?? 0) / Math.max(1, set.frames - 1));
    const start = Math.min(-0.12, Math.max(from, -shot.lead));
    const next = SHOTS[k + 1];
    const leave = next ? (LENGTHS[shot.arrive] ?? 1) - next.move : Infinity;
    const plan: TextPlan = { fadeIn: [start, Math.min(-0.02, start + 0.24)], fadeOut: [leave - 0.04, leave + 0.12] };
    if (!shot.name.startsWith("phone") && set.textArea) {
      const [x0, y0, x1, y1] = set.textArea;
      const { frame, width: W, height: H } = L;
      const left = Math.max(narrow ? 24 : Math.max(100, W * 0.07), frame.x + x0 * frame.w);
      const right = Math.min(W - 24, frame.x + x1 * frame.w);
      const top = Math.max(24, frame.y + y0 * frame.h);
      // Clear of the Scroll capsule at the bottom centre when the box reaches it.
      const overCue = left < W / 2 + 90 && right > W / 2 - 90;
      const bottom = Math.min(frame.y + y1 * frame.h, H - (overCue ? 100 : 40));
      plan.box = {
        left, top, width: Math.max(200, right - left), height: Math.max(80, bottom - top),
        center: narrow || (x1 - x0) > 0.7,
        middle: (y1 - y0) > 0.4,
      };
    }
    plans.set(shot.arrive, plan);
  });
  return plans;
}

type Applied = { transform: string; interactive: boolean; front: PageName | null; back: PageName | null; mix: number };

export function FrameStory() {
  const [portrait, setPortrait] = useState(() => typeof window !== "undefined" && window.matchMedia(PORTRAIT_QUERY).matches);
  const kind = portrait ? "portrait" : "desktop";
  const [manifest, setManifest] = useState<RiseManifest | null>(null);
  const sets = useMemo(() => SHOTS.map((shot) => manifest?.[kind]?.sequences?.[shot.name]), [manifest, kind]);
  const host = useRef<HTMLElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const display = useRef<HTMLDivElement>(null);
  const pages = useRef(new Map<PageName, HTMLDivElement>());
  const stage = useRef<FrameCanvas | null>(null);
  const players = useRef<(FrameSequence | null)[]>([]);
  const loading = useRef<(FrameSequence | null)[] | null>(null);
  const layout = useRef<Layout | null>(null);
  const applied = useRef<Applied>({ transform: "", interactive: false, front: null, back: null, mix: -1 });

  useEffect(() => { void loadManifest().then(setManifest); }, []);

  useEffect(() => {
    const query = window.matchMedia(PORTRAIT_QUERY);
    const change = () => setPortrait(query.matches);
    query.addEventListener("change", change);
    return () => query.removeEventListener("change", change);
  }, []);

  useEffect(() => {
    const base = `/opening/rise/${kind}`;
    const next = sets.map((set) => set ? new FrameSequence(`${base}/${set.dir}`, set.frames, set.final ? `../${set.final}` : undefined, false) : null);
    players.current = next;
    return () => {
      for (const player of next) player?.dispose();
      if (players.current === next) players.current = [];
    };
  }, [sets, kind]);

  useEffect(() => {
    const size = sets.find(Boolean);
    const apply = () => {
      const node = host.current;
      if (!node || !size) return;
      const L = measure(node.clientWidth, node.clientHeight, size.size[0] / size.size[1]);
      layout.current = L;
      applied.current.transform = "";
      setTextPlans(textPlans(sets, L));
      const { frame } = L;
      const el = canvas.current;
      if (!el) return;
      el.style.left = `${frame.x}px`;
      el.style.top = `${frame.y}px`;
      el.style.width = `${frame.w}px`;
      el.style.height = `${frame.h}px`;
      stage.current ??= new FrameCanvas(el);
      // Screen resolution, never above the stills' own size.
      const widest = Math.max(...sets.map((set) => set?.finalSize?.[0] ?? set?.size[0] ?? 0));
      const scale = Math.min(Math.min(window.devicePixelRatio || 1, 2), widest / frame.w);
      stage.current.resize(Math.round(frame.w * scale), Math.round(frame.h * scale));
    };
    apply();
    const observer = new ResizeObserver(apply);
    if (host.current) observer.observe(host.current);
    return () => {
      observer.disconnect();
      setTextPlans(new Map());
    };
  }, [sets]);

  useFrame(() => {
    const root = host.current;
    const L = layout.current;
    if (!root || !L) return;
    const s = getScroll();
    const all = players.current;
    const spans = windows();

    // Fetch in the order the shots play, once the visitor is on the way.
    if (s > getOffset(2) && loading.current !== all) {
      loading.current = all;
      void all.reduce<Promise<void>>((ready, player) => ready.then(() => { player?.start(); return player?.coarse; }), Promise.resolve());
    }

    const active = s > spans[0]![0] - 0.01;
    if (root.style.visibility !== (active ? "visible" : "hidden")) root.style.visibility = active ? "visible" : "hidden";
    if (!active) {
      handoff.later = false;
      for (const player of all) player?.rest(true);
      return;
    }

    let k = 0;
    while (k < SHOTS.length - 1 && s >= spans[k + 1]![0]) k++;
    let t = clamp01((s - spans[k]![0]) / (spans[k]![1] - spans[k]![0]));
    if (isReducedMotion()) t = t < 0.5 ? 0 : 1;
    // Shots next to this one keep their ends ready; the rest let go.
    all.forEach((player, i) => { if (player && i !== k) player.rest(Math.abs(i - k) > 1); });

    // Until a shot's frames are in, hold the one before at rest.
    let used = k;
    let image = all[k]?.pick(t) ?? null;
    if (!image && k > 0) { used = k - 1; image = all[used]?.pick(1) ?? null; }
    stage.current?.show(image);
    handoff.later = !!image;

    const set = sets[used];
    const index = image ? all[used]?.picked ?? -1 : -1;
    const quad = set?.screen?.[index] ?? null;
    const shot = SHOTS[used]!;

    // Which page is on the display. After a turn the new page is simply there;
    // a change while the display faces the camera fades through a few frames.
    let front: PageName | null = null;
    let back: PageName | null = null;
    let mix = 1;
    if (quad && set && shot.page !== undefined) {
      const change = set.page ?? 0;
      const last = set.frames - 1;
      const f = used === k ? t * last : last;
      const inView = change > 0 && !!set.screen?.[change - 1];
      mix = inView ? smoothstep(clamp01((f - (change - SWAP / 2)) / SWAP)) : index >= change ? 1 : 0;
      front = mix > 0 ? shot.page : null;
      back = mix < 1 ? SHOTS[used - 1]?.page ?? null : null;
      if (!front && !back) mix = 1;
    }

    const state = applied.current;
    const face = display.current;
    if (!face) return;
    let transform = "";
    let interactive = false;
    if (quad && (front || back)) {
      const { frame } = L;
      const points = quad.map((v, i) => (i % 2 ? frame.y + v * frame.h : frame.x + v * frame.w));
      transform = quadTransform(points, UI[0], UI[1]);
      // Usable only once the phone is still, as in its resting pose.
      const rest = set?.screen?.[set.frames - 1];
      interactive = mix === 1 && !!rest && rest.every((v, i) => Math.abs(v - quad[i]!) * (i % 2 ? frame.h : frame.w) < SETTLED);
    }
    if (transform !== state.transform) {
      state.transform = transform;
      face.style.visibility = transform ? "visible" : "hidden";
      if (transform) face.style.transform = transform;
    }
    if (front !== state.front || back !== state.back || mix !== state.mix || interactive !== state.interactive) {
      for (const [name, node] of pages.current) {
        const role = name === front ? "front" : name === back ? "back" : null;
        node.style.display = role ? "block" : "none";
        node.style.opacity = role === "front" ? String(mix) : "1";
        node.style.zIndex = role === "front" ? "2" : "1";
        const live = interactive && role === "front";
        node.inert = !live;
        node.setAttribute("aria-hidden", String(!live));
      }
      face.style.pointerEvents = interactive ? "auto" : "none";
      Object.assign(state, { front, back, mix, interactive });
    }
  });

  return <section ref={host} className="frame-story" aria-label="Inside the exchange, then the Trimmy app on a phone" style={{ visibility: "hidden" }}>
    <div className="frame-story__display" ref={display} style={{ visibility: "hidden" }}>
      {PAGE_ORDER.map((name) => {
        const Page = PAGES[name];
        return <div key={name} className="frame-story__page" ref={(node) => { if (node) pages.current.set(name, node); else pages.current.delete(name); }} style={{ display: "none" }} inert aria-hidden="true"><Page /></div>;
      })}
    </div>
    <canvas className="frame-story__frames" ref={canvas} />
  </section>;
}
