import { useRef } from "react";
import { useFrame } from "@/lib/useFrame";
import { getPosition, goTo } from "@/lib/stepper";
import { openGetApp } from "@/lib/getApp";
import { LINKS } from "@/story/links";

/**
 * A quiet text header, on every screen including the black opening. A soft
 * shade comes in behind it over the bright rendered pictures.
 */
export function SiteHeader() {
  const node = useRef<HTMLElement>(null);

  useFrame(() => {
    const p = getPosition();
    node.current?.classList.toggle("site-header--shade", p > 1.3 && p < 8.95);
  });

  return <header className="site-header" ref={node}>
    <a className="site-header__brand" href="/" onClick={(event) => { event.preventDefault(); goTo(0); }}>trimmy</a>
    <nav aria-label="Trimmy">
      {LINKS.web && <a href={LINKS.web}>Play on the web</a>}
      <button type="button" onClick={openGetApp}>Get the app</button>
    </nav>
  </header>;
}
