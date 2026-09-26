import { useEffect, useRef, useSyncExternalStore } from "react";
import { closeGetApp, isGetAppOpen, subscribeGetApp } from "@/lib/getApp";
import { holdScroll } from "@/lib/stepper";
import { LINKS } from "@/story/links";

/**
 * The Get the app panel. The Android build downloads today; the stores and the
 * web app are listed as coming soon until they exist (see story/links.ts).
 */
export function GetApp() {
  const open = useSyncExternalStore(subscribeGetApp, isGetAppOpen, () => false);
  const panel = useRef<HTMLElement>(null);
  const close = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    holdScroll(true);
    close.current?.focus({ preventScroll: true });
    const key = (event: KeyboardEvent) => {
      if (event.key === "Escape") closeGetApp();
      if (event.key !== "Tab" || !panel.current) return;
      // Keep focus inside the panel while it is open.
      const items = [...panel.current.querySelectorAll<HTMLElement>("a[href], button")];
      const first = items[0], last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    };
    window.addEventListener("keydown", key);
    return () => {
      window.removeEventListener("keydown", key);
      holdScroll(false);
    };
  }, [open]);

  if (!open) return null;
  return <div className="get-app" onClick={(event) => { if (event.target === event.currentTarget) closeGetApp(); }}>
    <section className="get-app__panel" ref={panel} role="dialog" aria-modal="true" aria-labelledby="get-app-title">
      <div className="get-app__top">
        <h2 id="get-app-title">Get Trimmy</h2>
        <button type="button" className="get-app__close" ref={close} onClick={closeGetApp} aria-label="Close"><span className="icon icon--close" aria-hidden="true" /></button>
      </div>
      <a className="get-app__apk" href={LINKS.apk} rel="noopener">
        <span className="icon icon--android" aria-hidden="true" />
        <span><strong>Download for Android</strong><small>APK · {LINKS.apkSize} · also installs on Solana Seeker</small></span>
        <span className="capsule__disc" aria-hidden="true"><span className="icon icon--download" /></span>
      </a>
      <p className="get-app__hint">Demo build. Android may ask you to allow installs from your browser.</p>
      {LINKS.web && <a className="get-app__web" href={LINKS.web}><span className="icon icon--web" aria-hidden="true" />Play on the web</a>}
      <p className="get-app__label">Coming soon</p>
      <ul className="get-app__soon">
        <li><span className="icon icon--play" aria-hidden="true" />Google Play<em>Soon</em></li>
        <li><span className="icon icon--seeker" aria-hidden="true" />Solana dApp Store<em>Soon</em></li>
        <li><span className="icon icon--apple" aria-hidden="true" />App Store (iPhone)<em>Soon</em></li>
        {!LINKS.web && <li><span className="icon icon--web" aria-hidden="true" />Web app<em>Soon</em></li>}
      </ul>
    </section>
  </div>;
}
