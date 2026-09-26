import { useRef, type CSSProperties } from "react";
import { useFrame } from "@/lib/useFrame";
import { getOffset, getScroll, isReducedMotion } from "@/lib/stepper";
import { clamp01, smoothstep } from "@/lib/math";
import { getTextPlan, textPlanVersion, type TextBox } from "@/lib/storyText";
import { openGetApp } from "@/lib/getApp";
import { LINKS } from "@/story/links";
import { LENGTHS, type Screen as ScreenData } from "@/story/screens";
import "./product.css";

const RISE = 20;
/** Share of a screen's scroll over which its copy crosses with the next one's. */
const SHARE = 0.55;
const OPSZ: CSSProperties = { fontVariationSettings: "'opsz' 48" };

type Props = { screen: ScreenData; index: number };

function place(el: HTMLElement, box: TextBox | undefined) {
  el.classList.toggle("story-screen--placed", !!box);
  el.classList.toggle("story-screen--center", !!box?.center);
  el.classList.toggle("story-screen--middle", !!box?.middle);
  el.style.left = box ? `${box.left}px` : "";
  el.style.top = box ? `${box.top}px` : "";
  el.style.width = box ? `${box.width}px` : "";
  el.style.height = box ? `${box.height}px` : "";
}

/**
 * Copy follows the scroll, including when going back. By default it crosses
 * with its neighbours around the moment its screen arrives; a screen whose
 * picture is rendered frames gets its timing and place from the section that
 * plays them (see storyText).
 */
export function Screen({ screen, index }: Props) {
  const node = useRef<HTMLElement>(null);
  const shown = useRef(index === 0);
  const placed = useRef(-1);

  useFrame(() => {
    const el = node.current;
    if (!el) return;
    const plan = getTextPlan(index);
    if (placed.current !== textPlanVersion()) {
      placed.current = textPlanVersion();
      place(el, plan?.box);
    }
    const t = getScroll() - getOffset(index);
    const [in0, in1] = plan?.fadeIn ?? [-SHARE * (LENGTHS[index - 1] ?? 1), 0];
    const [out0, out1] = plan?.fadeOut ?? [0, SHARE * (LENGTHS[index] ?? 1)];
    let opacity = 0;
    let drift = 0;
    if (t >= in1 && t <= out0) {
      opacity = 1;
    } else if (t > in0 && t < in1) {
      const k = smoothstep(clamp01((t - in0) / (in1 - in0)));
      opacity = k;
      drift = 1 - k;
    } else if (t > out0 && t < out1) {
      const k = smoothstep(clamp01((t - out0) / (out1 - out0)));
      opacity = 1 - k;
      drift = -k;
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
      className={`story-screen story-screen--${placement}${screen.large ? " story-screen--large" : ""}`}
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
      {screen.cta && (
        <div className="story-cta">
          <button type="button" className="capsule capsule--primary" onClick={openGetApp}>
            Get the app<span className="capsule__disc" aria-hidden="true"><span className="icon icon--download" /></span>
          </button>
          {LINKS.web && (
            <a className="capsule" href={LINKS.web}>
              Play on the web<span className="capsule__disc" aria-hidden="true"><span className="icon icon--web" /></span>
            </a>
          )}
        </div>
      )}
      {screen.note && <p className="story-note">{screen.note}</p>}
      {screen.status && (
        <dl className="story-status">
          {screen.status.map(({ label, text }) => <div key={label}><dt>{label}</dt><dd>{text}</dd></div>)}
        </dl>
      )}
      {screen.footer && (
        <>
          <p className="story-footer">{screen.footer}</p>
          <nav className="story-links" aria-label="More from Trimmy">
            <a href={LINKS.x} target="_blank" rel="noopener noreferrer"><span className="icon icon--x" aria-hidden="true" />@trimmyhq</a>
            <a href="/privacy">Privacy</a>
            <a href="/terms">Terms</a>
          </nav>
        </>
      )}
    </section>
  );
}
