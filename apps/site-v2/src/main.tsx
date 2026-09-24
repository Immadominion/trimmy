import { StrictMode, Suspense, lazy } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "lenis/dist/lenis.css";
import "./styles.css";

// The art-direction review is isolated from the approved landing-page opening.
// Its model and Three.js bundle load only when the review URL is visited.
const WorldStudy = lazy(() => import("./study/WorldStudy"));
const isStudy = window.location.pathname.replace(/\/$/, "") === "/world-study";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Suspense fallback={<p className="study-loading">Opening the study…</p>}>
      {isStudy ? <WorldStudy /> : <App />}
    </Suspense>
  </StrictMode>,
);
