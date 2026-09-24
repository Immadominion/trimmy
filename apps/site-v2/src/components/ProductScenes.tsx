import { useState, type CSSProperties } from "react";
import { goTo, jumpTo } from "@/lib/stepper";

const stocks = [
  { name: "Apple", ticker: "AAPL", image: "apple", price: "225.00", change: "+1.24%", path: "M0 132 34 125 60 140 92 101 122 108 155 75 184 86 214 49 250 60 282 28 310 41 340 12" },
  { name: "Nvidia", ticker: "NVDA", image: "nvidia", price: "125.00", change: "+2.18%", path: "M0 148 25 133 60 143 90 117 113 123 147 64 179 77 205 37 239 47 270 17 303 30 340 4" },
  { name: "Meta", ticker: "META", image: "meta", price: "510.00", change: "+0.86%", path: "M0 125 36 131 62 105 94 116 128 83 158 96 194 77 228 88 260 56 299 66 340 42" },
];
const variable = (values: Record<string, string | number>) => values as CSSProperties;

export function StockChart({ path = stocks[0]!.path, className = "" }: { path?: string; className?: string }) {
  return <svg className={`scene-chart ${className}`} viewBox="0 0 340 170" aria-hidden="true"><path className="scene-chart-grid" d="M0 10H340M0 60H340M0 110H340M0 160H340M40 0V170M110 0V170M180 0V170M250 0V170M320 0V170" /><path className="scene-chart-line scene-chart-glow" d={path} /><path className="scene-chart-line" d={path} /></svg>;
}

export function SpatialPhone({ closing = false }: { closing?: boolean }) {
  return <div className={`scene-phone ${closing ? "scene-phone--closing" : ""}`}>
    <div className="scene-phone-back"><img src="/mark.png" alt="" /></div>
    <div className="scene-phone-side scene-phone-side--left" /><div className="scene-phone-side scene-phone-side--right" />
    <div className="scene-phone-front"><div className="scene-phone-screen">
      <div className="scene-phone-status"><span>9:41</span><span>Demo</span><span aria-hidden="true">▮▮▮</span></div><div className="scene-phone-island" />
      <div className="scene-phone-brand"><img src="/mark.png" alt="" />trimmy</div>
      <img className="scene-phone-sal" src="/product/sal-teaching.png" alt="Sal, your guide" />
      <h3>Start your<br />Wall Street career.</h3>
      <div className="scene-phone-balance"><span>Virtual money</span><strong>10,000</strong></div>
      <button type="button" onClick={() => closing ? jumpTo(10) : goTo(10)}>Explore the demo</button>
      <div className="scene-phone-home" />
    </div></div>
  </div>;
}

export function PhoneArrival() {
  return <div className="phone-arrival scene-object"><div className="phone-arrival-shadow" /><div className="phone-arrival-tape" aria-hidden="true">A new way to learn the market.</div><SpatialPhone /><span className="scene-demo">Explore the game</span></div>;
}

export function VirtualBalance() {
  return <div className="balance-scene scene-object"><div className="balance-number" aria-label="10,000 in virtual money"><span>10,000</span><small>Virtual money</small></div><div className="practice-stack" aria-hidden="true">{Array.from({ length: 5 }, (_, i) => <div className="practice-sheet" key={i} style={variable({ "--sheet": i })}>{i === 4 && <><div className="practice-sheet-top"><img src="/mark.png" alt="" /><span>Your first trading balance</span></div><strong>10,000</strong><span className="practice-sheet-note">For practice. No deposit needed.</span><div className="practice-perforation" /></>}</div>)}</div><button className="scene-action balance-action" type="button" onClick={() => goTo(11)}>Choose your first stock <span aria-hidden="true">↗</span></button></div>;
}

export function StockOrbit() {
  const [selected, setSelected] = useState(0);
  const stock = stocks[selected] ?? stocks[0]!;
  return <div className="stocks-scene scene-object"><div className="stock-orbit-ring" aria-hidden="true" /><div className="stock-orbit">{stocks.map((item, index) => {
    const slot = (index - selected + 3) % 3;
    return <button key={item.name} className={`stock-orbit-coin stock-orbit-coin--${slot}`} type="button" onClick={() => setSelected(index)} aria-label={`See ${item.name} example`} aria-pressed={selected === index}><span className="stock-coin-rim" /><img src={`/product/${item.image}.webp`} alt="" /><span>{item.name}</span></button>;
  })}</div><div className="stock-quote" aria-live="polite"><span>{stock.name} <small>{stock.ticker}</small></span><strong>{stock.price}</strong><em>{stock.change}</em></div><div className="stock-chart-plane"><StockChart path={stock.path} /></div><p className="stock-example-note">Example prices · select a company</p></div>;
}

export function SalMission() {
  return <div className="sal-scene scene-object"><div className="mission-ticket"><div className="mission-ticket-hole" /><span className="mission-ticket-label">Your first mission</span><h3>Buy your first stock.</h3><p>Pick a company you know.<br />Make a practice purchase.</p><div className="mission-ticket-rule" /><div className="mission-ticket-reward"><strong>+20</strong><span>Trims<br /><small>points for learning</small></span></div><button type="button" onClick={() => goTo(11)}>Find a stock <span aria-hidden="true">↗</span></button><span className="mission-ticket-signature">Sal</span></div><img className="sal-foreground" src="/product/sal-teaching.png" alt="Sal, your boss, presenting your first mission" /><div className="sal-quote">“Start with one stock.<br />We’ll take it from there.”</div></div>;
}

export function SplitHolding() {
  const [sold, setSold] = useState(false);
  return <div className={`trim-scene scene-object ${sold ? "trim-scene--sold" : ""}`}><div className="holding-explanation"><img src="/product/nvidia.webp" alt="" /><div><strong>An example investment</strong><span>Bought at 100 · now worth 125 per share</span></div></div><div className="holding-field"><div className="holding-base holding-base--keep" /><div className="holding-base holding-base--sold" /><div className="holding-tokens" aria-hidden="true">{Array.from({ length: 8 }, (_, i) => <span className={`holding-token ${i > 5 ? "holding-token--sell" : ""}`} key={i} style={variable({ "--home-x": (i % 4 - 1.5) * 62, "--home-y": (Math.floor(i / 4) - .5) * 67, "--split-x": i < 6 ? (i % 3 - 1) * 55 - 62 : 136, "--split-y": i < 6 ? (Math.floor(i / 3) - .5) * 67 : (i - 6.5) * 67, "--order": i })}><img src="/product/nvidia.webp" alt="" /></span>)}</div><div className="holding-label holding-label--keep"><strong>{sold ? "6" : "8"}</strong><span>shares {sold ? "kept" : "owned"}</span></div><div className="holding-label holding-label--sold"><strong>2</strong><span>shares sold</span></div></div><div className="trim-result" aria-live="polite">{sold ? <><div><strong>250</strong><span>virtual money received</span></div><div><strong>50</strong><span>gain you’ve taken</span></div></> : <p>Sell 2 of your 8 shares.<br />Keep the other 6 invested.</p>}</div><button className="scene-action trim-action" type="button" onClick={() => setSold(!sold)}>{sold ? "Try again" : "Try selling 25%"}<span aria-hidden="true">{sold ? "↺" : "↗"}</span></button><p className="scene-demo trim-demo-note">Example only. No trade is placed.</p></div>;
}

const rankNames = ["Rookie", "Analyst", "Trader", "Senior Trader", "Partner", "Legend"];
export function RankAscent() {
  return <div className="rank-scene scene-object"><div className="rank-ladder">{rankNames.map((rank, i) => <div className={`rank-step ${i === 0 ? "rank-step--current" : ""} ${i === 5 ? "rank-step--legend" : ""}`} key={rank} style={variable({ "--rank": i })}><div className="rank-step-face"><span>{i === 5 ? "✦" : i + 1}</span><strong>{rank}</strong></div><div className="rank-step-tread" /><div className="rank-step-side rank-step-side--left" /><div className="rank-step-side rank-step-side--right" /></div>)}</div><p className="rank-caption">One mission at a time.</p></div>;
}

export function BuildAssembly() {
  return <div className="build-scene scene-object"><div className="build-plane"><div className="build-order"><img src="/mark.png" alt="" /><span>Practice purchase</span><strong>Apple</strong><div><span>Stock</span><b>AAPL</b></div><div><span>Mode</span><b>Virtual money</b></div><span className="build-order-confirmed">✓ Practice trading</span></div><div className="build-chart-object"><StockChart /><span>Stock prices</span></div><img className="build-sal" src="/product/sal-teaching.png" alt="" /><span className="build-sal-label">Sal’s first missions</span></div><div className="build-next"><span>Still building</span><div><span>Friends</span><span>Leagues</span><span>Money trading</span></div></div></div>;
}

export function BrandReturn() {
  return <div className="brand-return scene-object"><div className="closing-phone"><SpatialPhone closing /></div><img className="closing-mark" src="/mark.png" alt="Trimmy" /><span className="closing-wordmark" aria-hidden="true">trimmy</span></div>;
}
