import { lazy, Suspense, useState } from "react";
import "./study.css";

const RoutePreview = lazy(() => import("./RoutePreview"));
type View = "look" | "route" | "story";
const stops = [
  ["The invitation", "It’s your first day on Wall Street, intern.", "Black. White type. Room to breathe."],
  ["The pause", "So let’s get you up to speed.", "The current quiet opening stays."],
  ["The street", "The street became the market.", "1653, 1790 and 1792 share one concise chapter. The street changes with time."],
  ["The first turn", "Then the numbers learned to run.", "Follow the street around a visible corner. Paper tape leads toward the exchange."],
  ["The floor", "Then the floor found its voice.", "A second real turn takes us through a doorway into the trading room."],
  ["The reveal", "Now the floor fits in your hand.", "A trading screen becomes the Trimmy phone. The product takes over at 38.5%."],
  ["Your starting money", "Start with 10,000 in virtual money.", "Practice buying and selling stocks without spending your own money."],
  ["Market", "Find a stock. Make the call.", "Follow stock prices and practice a purchase. Keep the same phone in view."],
  ["The trim", "Buy. Hold. Trim.", "Sell part of a winner. Lock the gain. Stay in the trade."],
  ["The career", "Start as a Rookie.", "Sal, missions, Trims and the climb to Legend."],
  ["The people", "See what your friends bought and why.", "Preview the social Floor with its “In build” status visible."],
  ["Beyond the bell", "Wall Street closes. Trimmy keeps moving.", "The Solana connection, with money trading clearly marked “In build”."],
  ["The build", "What works today.", "A clear distinction between working features and what comes next."],
  ["Your desk", "Take your desk.", "One closing action. Trimmy is a Wall Street simulation game."],
];

export default function WorldStudy() {
  const [view, setView] = useState<View>("look");
  const [showCopy, setShowCopy] = useState(true);
  return (
    <main className={`world-study world-study--${view}`}>
      <header className="study-header">
        <a href="/" className="study-brand" aria-label="Back to Trimmy landing page">
          <img src="/mark.png" alt="" width="30" height="30" />
          <span>trimmy</span>
          <span className="study-brand-note">World study</span>
        </a>
        <nav className="study-tabs" aria-label="Design study views">
          <button type="button" aria-pressed={view === "look"} onClick={() => setView("look")}>The look</button>
          <button type="button" aria-pressed={view === "route"} onClick={() => setView("route")}>The turns</button>
          <button type="button" aria-pressed={view === "story"} onClick={() => setView("story")}>The story</button>
        </nav>
        <span className="study-date">23 September 2026</span>
      </header>

      {view === "look" && (
        <section className="study-look" aria-label="Blue-hour art direction">
          <img className="study-look-image" src="/studies/wall-street/look-v1.png" alt="A proposed Wall Street environment at blue hour, with limestone columns, hanging flags, warm lamps and damp stone paving." />
          <div className="study-look-shade" />
          <div className="study-look-note">
            <p>Broad Street, blue hour</p>
            <span>Generated look frame · proposed materials and light</span>
          </div>
          {showCopy && <h1 className="study-scene-copy">The street became<br />the market.</h1>}
          <div className="study-look-footer">
            <div><h2>A place you can believe in.</h2><p>Stone, bronze, cloth. Warm windows. A little light on the wet pavement.</p></div>
            <button className="study-outline" type="button" aria-pressed={showCopy} onClick={() => setShowCopy(!showCopy)}>{showCopy ? "Hide scene copy" : "Show scene copy"}</button>
          </div>
        </section>
      )}

      {view === "route" && (
        <Suspense fallback={<div className="study-loading" role="status">Loading the street model…</div>}>
          <RoutePreview />
        </Suspense>
      )}

      {view === "story" && (
        <section className="study-story" aria-label="Proposed narrative journey">
          <div className="study-story-intro">
            <p className="study-small">Earlier proposal · 14 stops</p>
            <h1>The street leads<br />to your desk.</h1>
            <p>The opening stays minimal. History sets the scene, then the game gets the space it needs.</p>
            <div className="study-story-ratio"><span>Street & history</span><span>The game</span></div>
            <p className="study-footnote">This earlier proposal grouped the dates and revealed the phone at 38.5%. The implemented landing page preserves the original historical screens and now has 17 stops.</p>
          </div>
          <ol className="study-story-stops">
            {stops.map(([name, copy, note], i) => (
              <li key={name} className={i === 5 ? "study-reveal" : ""}>
                <span className="study-stop-number">{String(i + 1).padStart(2, "0")}</span>
                <div><span className="study-stop-name">{name}</span><h2>{copy}</h2><p>{note}</p></div>
              </li>
            ))}
          </ol>
        </section>
      )}
    </main>
  );
}
