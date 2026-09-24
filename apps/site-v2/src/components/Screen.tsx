import { useRef, type CSSProperties } from "react";
import { useFrame } from "@/lib/useFrame";
import { getPosition, isReducedMotion } from "@/lib/stepper";
import { clamp01, smoothstep } from "@/lib/math";
import type { Screen as ScreenData } from "@/story/screens";
import "./product.css";

const RISE = 20;
const SHARE = 0.55;
const OPSZ: CSSProperties = { fontVariationSettings: "'opsz' 48" };

type Props = { screen: ScreenData; index: number };

/** Copy and the world follow the same position, including when going back. */
export function Screen({ screen, index }: Props) {
  const node = useRef<HTMLElement>(null);
  const shown = useRef(index === 0);

  useFrame(() => {
    const el = node.current;
    if (!el) return;
    const t = getPosition() - index;
    let opacity = 0;
    let drift = 0;
    if (t >= 0 && t < 1) {
      const k = smoothstep(clamp01(t / SHARE));
      opacity = 1 - k;
      drift = -k;
    } else if (t < 0 && t > -1) {
      const k = smoothstep(clamp01((t + SHARE) / SHARE));
      opacity = k;
      drift = 1 - k;
    }
    el.style.opacity = String(opacity);
    el.style.setProperty("--story-drift", `${drift * (isReducedMotion() ? 0 : RISE)}px`);
    const visible = opacity > 0.01;
    if (visible !== shown.current) {
      shown.current = visible;
      el.style.visibility = visible ? "visible" : "hidden";
      el.setAttribute("aria-hidden", visible ? "false" : "true");
      el.inert = !visible;
    }
  });

  const Heading = index === 0 ? "h1" : "h2";
  const placement = index < 2 ? "intro" : index < 9 ? "scene" : "product";

  return (
    <section
      ref={node}
      aria-hidden={index !== 0}
      inert={index !== 0}
      className={`story-screen story-screen--${placement}`}
      style={{ opacity: index === 0 ? 1 : 0, visibility: index === 0 ? "visible" : "hidden" }}
    >
      {screen.stamp && <p className="story-stamp">{screen.stamp}</p>}
      {screen.heading && <Heading className="story-title" style={OPSZ}>{screen.heading}</Heading>}
      {screen.large && <p className="story-title" style={OPSZ}>{screen.large}</p>}
      {screen.body && (
        <p className={screen.heading ? "story-body" : "story-title story-title--body"} style={screen.heading ? undefined : OPSZ}>
          {screen.body.map((line) => <span key={line}>{line}</span>)}
        </p>
      )}
      {screen.signature && (
        <div className="story-signature">
          <p className="story-lockup"><span>with</span><span className="story-wordmark"><img src="/mark.png" alt="" width={34} height={34} />trimmy</span></p>
          <p className="story-powered">Proudly powered by Solana</p>
        </div>
      )}
      {screen.note && <p className="story-note">{screen.note}</p>}
      {screen.status && (
        <dl className="story-status">
          {screen.status.map(({ label, text }) => <div key={label}><dt>{label}</dt><dd>{text}</dd></div>)}
        </dl>
      )}
      {screen.action && (
        <a className="story-action" href={screen.action.href} target="_blank" rel="noopener noreferrer">
          {screen.action.label}<span aria-hidden="true">↗</span>
        </a>
      )}
      {screen.footer && <p className="story-footer">{screen.footer}</p>}
    </section>
  );
}
