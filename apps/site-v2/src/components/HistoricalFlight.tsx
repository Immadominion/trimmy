import { useEffect, useRef, useState } from "react";
import { useFrame } from "@/lib/useFrame";
import { getOffset, getScroll, isReducedMotion } from "@/lib/stepper";
import { clamp01, smoothstep } from "@/lib/math";
import { SCREENS } from "@/story/screens";
import { PaintTitle, type SkyTitleState } from "./PaintTitle";
import { FrameCanvas, FrameSequence, IDENTITY, invert, multiply, type RiseManifest, type RiseSet, type SequenceSet } from "./risePlayer";
import { drawTitle, TITLE_FONTS, tokens } from "./wallTitle";
import "./historical-flight.css";

/**
 * 1653 to 1792 as one continuous camera move, rendered in Blender from a 3D
 * rebuild of Wall Street at Federal Hall (trimmy/art/tmp/blender-opening) and
 * played here as frames in step with the scroll:
 *
 * 1. The sky comes up out of the black and "A WALL gave a STREET its name"
 *    paints on over it.
 * 2. Rise: the buildings come up from below in front of the title, each at its
 *    own depth, and settle into the upward view.
 * 3. Tilt: the buildings went up, so the camera comes down. It tilts and moves
 *    down Wall Street to eye level at Federal Hall, while a 1790 bond, the thing
 *    the brokers came to trade, falls with it.
 * 4. Peel: the modern street lifts away upward and the 1792 street is
 *    underneath, where the brokers meet.
 * 5. Whip: a sharp camera turn out of 1792, a second jump in time, landing on
 *    today's New York Stock Exchange on Broad Street: "The street became the
 *    market." Then the three.js world takes over at the ticker.
 *
 * The sky and the title are the site's own layers under the frames. While the
 * camera turns, they move by the homography the render exported for each
 * frame, so they stay locked to the rendered buildings.
 */

const wall = SCREENS[2]!;
const bonds = SCREENS[3]!;
const agreement = SCREENS[4]!;
const market = SCREENS[5]!;
const WALL_PARTS = tokens(wall.heading ?? "", wall.emphasis ?? []);
/** Where the title's lowest line sits on screen at the hero pose, as a share of the height. */
let wallBottom = 0.76;
const drawWall = (context: CanvasRenderingContext2D, width: number, height: number, scale: number) => {
  wallBottom = drawTitle(context, width, height, scale, wall.stamp ?? "", WALL_PARTS) || wallBottom;
};

/** Where a hero-frame point lands through a homography, as frame v (0 top). */
const landV = (h: number[], u: number, v: number) => (h[3]! * u + h[4]! * v + h[5]!) / (h[6]! * u + h[7]! * v + h[8]!);

/**
 * How much of the title is left while the camera tilts down: it goes as it
 * slides out through the top, and on tall screens, where part of it would stay
 * in the sky above Federal Hall, it has gone by 40% of the tilt all the same.
 */
const titleLeft = (h: number[], bottom: number, tilt: number) =>
  Math.min(soft((landV(h, 0.5, bottom) + 0.01) / 0.14), 1 - soft((tilt - 0.18) / 0.22));

type Kind = "desktop" | "portrait";
type Plate = {
  /** Width over height of the Blender camera's frame. */
  aspect: number;
  /** Folder with the frames, stills and skies, under public/. */
  base: string;
  /** The 1792 street, revealed under the modern one. */
  photo: string;
};

const PLATES: Record<Kind, Plate> = {
  desktop: { aspect: 1.6, base: "/opening/rise/desktop", photo: "/history/brokers-desktop.webp" },
  portrait: { aspect: 9 / 16, base: "/opening/rise/portrait", photo: "/history/brokers-portrait.webp" },
};

let manifestLoad: Promise<RiseManifest | null> | null = null;
const loadManifest = () => (manifestLoad ??= fetch("/opening/rise/manifest.json")
  .then((response) => (response.ok ? response.json() as Promise<RiseManifest> : null))
  .catch(() => null));

const soft = (t: number) => smoothstep(clamp01(t));
const range = (s: number, [from, to]: [number, number]) => (s - from) / (to - from);

/** Scroll positions, in viewports, for each part of the move. */
function beats() {
  const start = getOffset(2);
  const middle = getOffset(3);
  const end = getOffset(4);
  const street = getOffset(5);
  const tilt: [number, number] = [start + 1.4, end - 1.1];
  const tiltLength = tilt[1] - tilt[0];
  return {
    dawn: [start - 0.62, start - 0.12] as [number, number],
    paint: [start - 0.46, start + 0.02] as [number, number],
    rise: [start + 0.1, start + 1.2] as [number, number],
    tilt,
    /** The bond is in view through the middle of the tilt; 1790 sits beside it. */
    bonds: [Math.min(middle - 0.3, tilt[0] + tiltLength * 0.24), tilt[0] + tiltLength * 0.8] as [number, number],
    peel: [end - 0.9, end - 0.02] as [number, number],
    agreement: [end - 0.1, street - 0.62] as [number, number],
    /** A sharp turn: short in scroll, so a normal flick carries straight through it. */
    whip: [street - 0.56, street + 0.02] as [number, number],
    market: [street + 0.02, street + 1.3] as [number, number],
    marketLine: [street + 0.1, street + 1.2] as [number, number],
    exit: [street + 1.25, street + 1.55] as [number, number],
  };
}

type Layout = { width: number; height: number; frame: { w: number; h: number; x: number; y: number } };

function measure(width: number, height: number, plate: Plate): Layout {
  // The rendered frame covers the screen, centred, like the Blender camera.
  const h = Math.max(height, width / plate.aspect);
  const w = h * plate.aspect;
  return { width, height, frame: { w, h, x: (width - w) / 2, y: (height - h) / 2 } };
}

function setVisible(node: HTMLElement | null, visible: boolean) {
  if (!node) return;
  const value = visible ? "visible" : "hidden";
  if (node.style.visibility !== value) node.style.visibility = value;
}

function setShown(node: HTMLElement | null, shown: boolean) {
  if (!node || node.classList.contains("is-shown") === shown) return;
  node.classList.toggle("is-shown", shown);
  node.setAttribute("aria-hidden", String(!shown));
  node.inert = !shown;
}

const portraitQuery = "(max-aspect-ratio: 4/5)";

type Sequences = {
  rise: FrameSequence;
  tilt: FrameSequence | null;
  peel: FrameSequence | null;
  whip: FrameSequence | null;
  market: FrameSequence | null;
};

export function HistoricalFlight() {
  const [portrait, setPortrait] = useState(() => typeof window !== "undefined" && window.matchMedia(portraitQuery).matches);
  const kind: Kind = portrait ? "portrait" : "desktop";
  const plate = PLATES[kind];
  const [manifest, setManifest] = useState<RiseManifest | null>(null);
  const set: RiseSet | undefined = manifest?.[kind];
  const host = useRef<HTMLElement>(null);
  const photo = useRef<HTMLDivElement>(null);
  const title = useRef<HTMLDivElement>(null);
  const skyTitle = useRef<SkyTitleState | null>(null);
  const wallHeading = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const stage = useRef<FrameCanvas | null>(null);
  const sequences = useRef<Sequences | null>(null);
  const bondStory = useRef<HTMLDivElement>(null);
  const brokerStory = useRef<HTMLDivElement>(null);
  const marketLine = useRef<HTMLDivElement>(null);
  const layout = useRef<Layout | null>(null);
  const [bondSide, setBondSide] = useState<"left" | "right" | "top" | "bottom">("left");
  /** Share of the tilt when 1790 shows: the bond in view and the title gone. */
  const bondWindow = useRef<[number, number] | null>(null);

  useEffect(() => { void loadManifest().then(setManifest); }, []);

  useEffect(() => {
    const query = window.matchMedia(portraitQuery);
    const change = () => setPortrait(query.matches);
    query.addEventListener("change", change);
    return () => query.removeEventListener("change", change);
  }, []);

  // One set of sequences per orientation, loaded in the order they are needed,
  // each once the one before has its coarse frames in.
  useEffect(() => {
    if (!set) return;
    const tiltSet = set.sequences?.tilt;
    const peelSet = set.sequences?.peel;
    const sequence = (seq?: SequenceSet) => seq
      ? new FrameSequence(`${plate.base}/${seq.dir}`, seq.frames, seq.final ? `../${seq.final}` : undefined)
      : null;
    const next: Sequences = {
      rise: new FrameSequence(plate.base, set.frames, set.hero),
      tilt: sequence(tiltSet),
      peel: sequence(peelSet),
      whip: sequence(set.sequences?.whip),
      market: sequence(set.sequences?.market),
    };
    next.rise.start();
    void [next.tilt, next.peel, next.whip, next.market]
      .reduce<Promise<void>>((ready, seq) => ready.then(() => { seq?.start(); return seq?.coarse; }), next.rise.coarse);
    sequences.current = next;
    // 1790 shows while the bond is in view and the title has gone, and sits on
    // the side of the screen the bond does not use while it shows.
    const bond = tiltSet?.bond;
    const skies = Array.isArray(tiltSet?.sky?.[0]) ? tiltSet!.sky as number[][] : null;
    bondWindow.current = null;
    if (bond?.length && skies?.length) {
      const last = bond.length - 1;
      const L = layout.current;
      const bottom = L ? (wallBottom * L.height - L.frame.y) / L.frame.h : 0.78;
      const gone = (i: number) => titleLeft(skies[Math.round(i / last * (skies.length - 1))]!, bottom, i / last) < 0.01;
      const first = bond.findIndex((box, i) => !!box && gone(i));
      const end = last - [...bond].reverse().findIndex(Boolean);
      if (first >= 0 && end > first) {
        bondWindow.current = [first / last, end / last];
        const shown = bond.slice(first, end + 1).filter((box): box is [number, number, number, number] => !!box);
        const cx = shown.reduce((sum, b) => sum + (b[0] + b[2]) / 2, 0) / shown.length;
        const cy = shown.reduce((sum, b) => sum + (b[1] + b[3]) / 2, 0) / shown.length;
        setBondSide(kind === "portrait" ? (cy > 0.5 ? "top" : "bottom") : (cx < 0.5 ? "right" : "left"));
      }
    }
    return () => {
      for (const seq of Object.values(next)) seq?.dispose();
      if (sequences.current === next) sequences.current = null;
    };
  }, [set, plate, kind]);

  // Size everything once per viewport; frames then only move it.
  useEffect(() => {
    const apply = () => {
      const node = host.current;
      if (!node) return;
      const L = measure(node.clientWidth, node.clientHeight, plate);
      layout.current = L;
      const place = (el: HTMLElement | null, x: number, y: number, w: number, h: number) => {
        if (!el) return;
        el.style.left = `${x}px`;
        el.style.top = `${y}px`;
        el.style.width = `${w}px`;
        el.style.height = `${h}px`;
      };
      const { frame } = L;
      place(canvas.current, frame.x, frame.y, frame.w, frame.h);
      place(photo.current, frame.x, frame.y, frame.w, frame.h);
      // The market line sits where the render left calm space for it, kept on screen.
      const area = set?.sequences?.market?.textArea;
      if (marketLine.current && area) {
        const [x0, y0, x1, y1] = area;
        const left = Math.max(24, frame.x + x0 * frame.w);
        const top = Math.max(24, frame.y + y0 * frame.h);
        const right = Math.min(L.width - 24, frame.x + x1 * frame.w);
        const bottom = Math.min(L.height - 24, frame.y + y1 * frame.h);
        place(marketLine.current, left, top, Math.max(160, right - left), Math.max(60, bottom - top));
        marketLine.current.dataset.placed = "true";
      }
      if (canvas.current) {
        stage.current ??= new FrameCanvas(canvas.current);
        // Draw at screen resolution, never above the sharpest still's own size.
        const widest = Math.max(set?.heroSize[0] ?? 2560, set?.sequences?.tilt?.finalSize?.[0] ?? 0);
        const scale = Math.min(Math.min(window.devicePixelRatio || 1, 2), widest / frame.w);
        stage.current.resize(Math.round(frame.w * scale), Math.round(frame.h * scale));
      }
    };
    apply();
    const observer = new ResizeObserver(apply);
    if (host.current) observer.observe(host.current);
    return () => observer.disconnect();
  }, [plate, set]);

  useFrame(() => {
    const L = layout.current;
    const root = host.current;
    if (!L || !root) return;
    const s = getScroll();
    const b = beats();
    const reduced = isReducedMotion();

    const active = s > b.dawn[0] - 0.02 && s < b.exit[1];
    root.style.opacity = String(1 - soft(range(s, b.exit)));
    setVisible(root, active);
    if (!active) { skyTitle.current = null; return; }

    const seq = sequences.current;
    const tiltSet = set?.sequences?.tilt;
    const peelSet = set?.sequences?.peel;

    // Which rendered frame is on screen, and the sky's homography for it.
    let image: ImageBitmap | null = null;
    let skyH = IDENTITY;
    const tilting = s >= b.tilt[0];
    const peeling = s >= b.peel[0];
    const whipping = s >= b.whip[0];
    const marketing = s >= b.market[0];
    if (!tilting) {
      image = seq?.rise.pick(reduced ? 1 : clamp01(range(s, b.rise))) ?? null;
    } else if (!peeling) {
      const t = reduced ? (s < (b.tilt[0] + b.tilt[1]) / 2 ? 0 : 1) : clamp01(range(s, b.tilt));
      if (seq?.tilt && tiltSet) {
        image = seq.tilt.pick(t);
        const skies = Array.isArray(tiltSet.sky?.[0]) ? tiltSet.sky as number[][] : null;
        if (skies) skyH = skies[Math.round(t * (skies.length - 1))] ?? IDENTITY;
      } else {
        image = seq?.rise.pick(1) ?? null;
      }
    } else if (!whipping) {
      const t = reduced ? 1 : clamp01(range(s, b.peel));
      if (seq?.peel && peelSet) {
        image = seq.peel.pick(t);
        skyH = (Array.isArray(peelSet.sky?.[0]) ? null : peelSet.sky as number[] | undefined) ?? IDENTITY;
      } else {
        image = t < 0.5 ? (seq?.tilt?.pick(1) ?? seq?.rise.pick(1) ?? null) : null;
      }
    } else if (!marketing) {
      // The whip's frames are opaque: the 1792 picture streaking away, the cut
      // at peak blur, then today's Broad Street coming out of the blur.
      image = seq?.whip?.pick(reduced ? 1 : clamp01(range(s, b.whip))) ?? null;
    } else {
      image = seq?.market?.pick(reduced ? 0 : clamp01(range(s, b.market))) ?? null;
    }
    // Sequences off screen let their decoded frames go.
    if (seq) {
      if (tilting) seq.rise.rest();
      if (!tilting || peeling) seq.tilt?.rest();
      if (!peeling || whipping) seq.peel?.rest();
      if (!whipping || marketing) seq.whip?.rest();
      if (!marketing) seq.market?.rest();
    }
    const hasWhip = !!seq?.whip;
    const showFrames = (s > b.rise[0] - 0.02 && s < b.peel[1] + 0.02) || (hasWhip && whipping);
    setVisible(canvas.current, showFrames);
    if (showFrames) stage.current?.show(image);

    // Sky and title stay locked to the camera: the layer maps every screen
    // pixel back to the hero frame through the inverse of the homography.
    const { frame } = L;
    const toFrame = [L.width / frame.w, 0, -frame.x / frame.w, 0, L.height / frame.h, -frame.y / frame.h, 0, 0, 1];
    const titleBottom = (wallBottom * L.height - frame.y) / frame.h;
    // The title leaves through the top as the camera tilts down.
    const titleExit = s < b.tilt[0] ? 1 : titleLeft(skyH, titleBottom, clamp01(range(s, b.tilt)));
    const titleShown = s < b.tilt[1] && titleExit > 0.001;
    setVisible(title.current, s < b.peel[1]);
    skyTitle.current = {
      progress: clamp01(range(s, b.paint)),
      titleOpacity: titleShown ? titleExit : 0,
      // Before the peel the sky is the modern one; it gives way to 1792's own sky.
      skyOpacity: soft(range(s, b.dawn)) * (1 - soft((range(s, b.peel) - 0.2) / 0.55)),
      warp: multiply(invert(skyH), toFrame),
      frame: [frame.x / L.width, frame.y / L.height, frame.w / L.width, frame.h / L.height],
      skyBox: set?.skyBox ?? [0, 0, 1, 1],
    };
    setShown(wallHeading.current, s > b.paint[0] + 0.2 && s < b.tilt[0] + 0.3);

    // 1790 beside the falling bond; 1792 once the modern street has gone.
    // It stays through the pause at Federal Hall, so it can be read, and goes
    // as the modern street starts to lift.
    const bondRange: [number, number] = bondWindow.current
      ? [b.tilt[0] + bondWindow.current[0] * (b.tilt[1] - b.tilt[0]), b.peel[0] + 0.04]
      : b.bonds;
    setShown(bondStory.current, s > bondRange[0] && s < bondRange[1]);
    // The 1792 picture holds still: the whip starts from it exactly as it is.
    setVisible(photo.current, s > b.peel[0] - 0.02 && !(hasWhip && s > b.whip[0] + 0.05));
    setShown(brokerStory.current, s > b.agreement[0] && s < b.agreement[1]);
    setShown(marketLine.current, s > b.marketLine[0] && s < b.marketLine[1]);
  });

  const skySource = set ? `${plate.base}/${set.skyBox ? "skyWide.webp" : set.sky}` : undefined;

  return <section ref={host} className="historical-flight" aria-hidden="true" style={{ visibility: "hidden" }}>
    <div className="historical-flight__photo" ref={photo}>
      <img src={plate.photo} alt="" draggable={false} decoding="async" />
    </div>
    <div className="historical-flight__title" ref={title}>
      <PaintTitle
        className="historical-flight__paint"
        draw={drawWall}
        fonts={TITLE_FONTS}
        sky={skySource}
        state={() => skyTitle.current}
      />
    </div>
    <canvas className="historical-flight__rise" ref={canvas} />
    <div className="historical-flight__story historical-flight__wall" ref={wallHeading} aria-hidden="true" inert>
      <h2 className="sr-only">{wall.stamp}. {wall.heading}</h2>
    </div>
    <div className={`historical-flight__story historical-flight__bonds historical-flight__bonds--${bondSide}`} ref={bondStory} aria-hidden="true" inert>
      <p className="historical-flight__year">{bonds.stamp}</p>
      <h2>{bonds.heading}</h2>
      <p>{bonds.body?.[0]}</p>
    </div>
    <div className="historical-flight__story historical-flight__agreement" ref={brokerStory} aria-hidden="true" inert>
      <p className="historical-flight__year">{agreement.stamp}</p>
      <h2>{agreement.heading}</h2>
      <p>{agreement.body?.[0]}</p>
    </div>
    <div className="historical-flight__story historical-flight__market" ref={marketLine} aria-hidden="true" inert>
      <h2>{market.large}</h2>
    </div>
  </section>;
}
