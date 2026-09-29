import { useState, type JSX, type ReactNode } from "react";
import { goTo } from "@/lib/stepper";
import { openGetApp } from "@/lib/getApp";
import {PRODUCT_AVAILABILITY} from '../story/availability';
import "./phone-app.css";

/**
 * The app's pages at the phone's own size, 390 x 844 CSS px, in the live app's
 * look (apps/mobile/lib/product/design/product_theme.dart). PhoneStory lays one
 * under the rendered phone's see-through display, mapped onto its corners each
 * frame, so the phone shows the app sharp and live: the stocks and the trim can
 * be tried on it.
 *
 * Prices are examples, not a feed, and the trim places no trade.
 */

export type PageName = "money" | "prices" | "sal" | "trim" | "ranks" | "status" | "close";

type Tab = "desk" | "market" | "career" | "profile";

const TABS: { id: Tab; label: string }[] = [
  { id: "desk", label: "Desk" },
  { id: "market", label: "Market" },
  { id: "career", label: "Career" },
  { id: "profile", label: "Profile" },
];

const STOCKS = [
  { name: "Apple", ticker: "AAPL", image: "apple", price: "225.00", change: "+1.24%", path: "M0 92 26 88 48 97 72 71 94 76 120 55 142 62 166 36 194 44 218 21 240 30 264 10 300 16" },
  { name: "Nvidia", ticker: "NVDA", image: "nvidia", price: "125.00", change: "+2.18%", path: "M0 104 22 94 48 101 70 83 88 87 114 46 138 55 158 27 184 34 208 12 234 21 262 4 300 9" },
  { name: "Meta", ticker: "META", image: "meta", price: "510.00", change: "+0.86%", path: "M0 88 28 92 48 74 72 82 98 58 122 67 150 54 176 62 200 39 230 46 256 30 280 33 300 22" },
];

const RANKS = ["Rookie", "Analyst", "Trader", "Senior Trader", "Partner", "Legend"];

function StatusBar() {
  return <div className="app-status" aria-hidden="true">
    <span>9:41</span>
    <span className="app-status-icons">
      <svg viewBox="0 0 18 12" width="18" height="12"><rect x="0" y="8" width="3" height="4" rx="1" /><rect x="5" y="5.5" width="3" height="6.5" rx="1" /><rect x="10" y="3" width="3" height="9" rx="1" /><rect x="15" y="0" width="3" height="12" rx="1" /></svg>
      <svg viewBox="0 0 16 12" width="16" height="12" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M1.5 4.6a9.2 9.2 0 0 1 13 0" /><path d="M4.3 7.4a5.3 5.3 0 0 1 7.4 0" /><circle cx="8" cy="10.3" r="1.4" fill="currentColor" stroke="none" /></svg>
      <svg viewBox="0 0 27 13" width="27" height="13"><rect x=".5" y=".5" width="23" height="12" rx="3.8" fill="none" stroke="currentColor" opacity=".4" /><rect x="2.5" y="2.5" width="16" height="8" rx="2.2" /><path d="M25 4.4v4.2a2.2 2.2 0 0 0 0-4.2Z" opacity=".45" /></svg>
    </span>
  </div>;
}

function TabBar({ active }: { active: Tab }) {
  return <nav className="app-tabs" aria-label="App sections">
    {TABS.map((tab) => <span key={tab.id} className={tab.id === active ? "is-active" : undefined} aria-current={tab.id === active ? "page" : undefined}>
      <img src={`/app/nav-${tab.id}.png`} alt="" />{tab.label}
    </span>)}
  </nav>;
}

function Shell({ tab, children, className }: { tab?: Tab; children: ReactNode; className?: string }) {
  return <div className={`app-page ${tab ? "app-page--tabs" : ""} ${className ?? ""}`}>
    <StatusBar />
    <div className="app-body">{children}</div>
    {tab && <TabBar active={tab} />}
    <span className="app-home" aria-hidden="true" />
  </div>;
}

function Chart({ path }: { path: string }) {
  return <svg className="app-chart" viewBox="0 0 300 110" preserveAspectRatio="none" aria-hidden="true">
    <defs><linearGradient id="app-chart-wash" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stopColor="#087957" stopOpacity=".2" /><stop offset="1" stopColor="#087957" stopOpacity="0" /></linearGradient></defs>
    <path className="app-chart-rule" d="M0 27.5H300M0 55H300M0 82.5H300" />
    <path className="app-chart-wash" d={`${path} L300 110 L0 110Z`} />
    <path className="app-chart-line" d={path} />
  </svg>;
}

/** Screen 10: the desk, with the practice balance the visitor starts with. */
function Money() {
  return <Shell tab="desk" className="app-money">
    <header className="app-top">
      <span className="app-brand"><img src="/mark.png" alt="" />trimmy</span>
      <span className="app-bell"><img src="/app/bell.png" alt="" /><i /></span>
    </header>
    <h2 className="app-title">Your desk</h2>
    <section className="app-balance">
      <div className="app-balance-top"><span className="app-kicker">Virtual money</span><span className="app-tag">Demo</span></div>
      <strong>10,000</strong>
      <p>For practice. No deposit needed.</p>
    </section>
    <div className="app-section-head"><h3>Holdings</h3><span>0 stocks</span></div>
    <section className="app-empty">
      <span className="app-logos" aria-hidden="true"><img src="/product/apple.webp" alt="" /><img src="/product/nvidia.webp" alt="" /><img src="/product/meta.webp" alt="" /></span>
      <div><strong>No stocks yet</strong><span>Pick a company to begin.</span></div>
    </section>
    <button type="button" className="app-button" onClick={() => goTo(11)}>Explore stocks</button>
    <div className="app-career-strip">
      <img src="/app/briefcase.webp" alt="" />
      <div><strong>Rookie</strong><span>0 Trims · Day 1</span></div>
      <span className="app-chevron" aria-hidden="true" />
    </div>
  </Shell>;
}

/** Screen 11: the market. Pick a company and its price and chart follow. */
function Prices() {
  const [selected, setSelected] = useState(0);
  const stock = STOCKS[selected]!;
  return <Shell tab="market" className="app-prices">
    <header className="app-top"><h2 className="app-title app-title--top">Market</h2><img className="app-icon" src="/app/search.png" alt="" /></header>
    <div className="app-chips" aria-hidden="true"><span className="is-on">For you</span><span>Trending</span><span>Movers</span><span>Tech</span></div>
    <section className="app-quote" aria-live="polite">
      <div className="app-quote-name">
        <img src={`/product/${stock.image}.webp`} alt="" />
        <div><strong>{stock.name}</strong><span>{stock.ticker}</span></div>
        <span className="app-tag">Example</span>
      </div>
      <strong className="app-quote-price">{stock.price}</strong>
      <span className="app-gain">{stock.change} today</span>
      <Chart path={stock.path} />
      <div className="app-periods" aria-hidden="true"><span>1D</span><span>1W</span><span className="is-on">1M</span><span>1Y</span></div>
    </section>
    <ul className="app-list">
      {STOCKS.map((item, index) => <li key={item.ticker}>
        <button type="button" className={index === selected ? "is-on" : undefined} aria-pressed={index === selected} onClick={() => setSelected(index)}>
          <img src={`/product/${item.image}.webp`} alt="" />
          <span className="app-list-name"><strong>{item.name}</strong><small>{item.ticker}</small></span>
          <span className="app-list-price"><strong>{item.price}</strong><small>{item.change}</small></span>
        </button>
      </li>)}
    </ul>
    <div className="app-pair"><button type="button" className="app-button">Buy</button><button type="button" className="app-button app-button--line">Sell</button></div>
  </Shell>;
}

/** Screen 12: Sal hands out the first mission. */
function Sal() {
  return <Shell tab="career" className="app-sal">
    <span className="app-kicker app-kicker--violet">Career · Day 1</span>
    <h2 className="app-title">Your first mission</h2>
    <div className="app-sal-scene">
      <img src="/app/sal-teaching.webp" alt="Sal, your boss" />
      <p className="app-bubble">Start with a company you know.</p>
    </div>
    <section className="app-mission">
      <span className="app-kicker">Mission 01</span>
      <h3>Buy your first stock.</h3>
      <p>Pick a company you know. Tell Sal what made you choose it.</p>
      <div className="app-mission-reward"><strong>+20</strong><span>Trims<small>for learning</small></span></div>
    </section>
    <button type="button" className="app-button" onClick={() => goTo(11)}>Start mission</button>
  </Shell>;
}

/** Screen 13: a trim, tried on the phone. Two of eight shares go; six stay. */
function Trim() {
  const [sold, setSold] = useState(false);
  const toggle = () => setSold((value) => !value);
  return <Shell className={`app-trim ${sold ? "is-sold" : ""}`}>
    <header className="app-top app-top--detail">
      <span className="app-back" aria-hidden="true" />
      <img src="/product/nvidia.webp" alt="" />
      <div><strong>Nvidia</strong><span>NVDA · 125.00</span></div>
      <span className="app-tag">Demo</span>
    </header>
    <button type="button" className="app-position" onClick={toggle} aria-label={sold ? "Undo the trim" : "Trim 25% of this position"}>
      <span className="app-kicker">Your position</span>
      <strong className="app-position-count">{sold ? 6 : 8} shares</strong>
      <span className="app-position-note">Bought at 100 · now 125 a share</span>
      <span className="app-shares" aria-hidden="true">
        {Array.from({ length: 8 }, (_, i) => <i key={i} className={i >= 6 ? "is-leaving" : undefined}><img src="/product/nvidia.webp" alt="" /></i>)}
      </span>
      <span className="app-position-values" aria-hidden="true">
        <span>Value<b>{sold ? "750" : "1,000"}</b></span>
        <span>{sold ? "Sold" : "Gain"}<b>{sold ? "2 shares" : "+200"}</b></span>
      </span>
    </button>
    <div className="app-trim-result" aria-live="polite">
      {sold
        ? <><div><strong>250</strong><span>virtual money received</span></div><div><strong>+50</strong><span>gain you’ve taken</span></div></>
        : <p>Sell 2 of your 8 shares. Keep the other 6 invested.</p>}
    </div>
    <button type="button" className={`app-button ${sold ? "app-button--line" : ""}`} onClick={toggle}>{sold ? "Undo trim" : "Trim 25%"}</button>
    {sold
      ? <button type="button" className="app-more" onClick={openGetApp}>Play the full game</button>
      : <p className="app-fine">Example only. No trade is placed.</p>}
  </Shell>;
}

/** Screen 14: the career, six ranks from Rookie to Legend. */
function Ranks() {
  return <Shell tab="career" className="app-ranks">
    <header className="app-top"><h2 className="app-title app-title--top">Career</h2><span className="app-streak"><img src="/app/streak.png" alt="" />3</span></header>
    <section className="app-rank-card">
      <img src="/app/briefcase.webp" alt="" />
      <div>
        <span className="app-kicker">Your rank</span>
        <strong>Rookie</strong>
        <span>120 Trims · 3-day streak</span>
      </div>
      <div className="app-rank-progress"><span>Analyst at 300 Trims</span><i><b /></i></div>
    </section>
    <ol className="app-ladder" reversed>
      {[...RANKS].reverse().map((rank) => {
        const step = RANKS.indexOf(rank);
        return <li key={rank} className={step === 0 ? "is-current" : step === 5 ? "is-legend" : undefined} style={{ marginLeft: step * 11 }}>
          <span className="app-ladder-step">{step + 1}</span>
          <strong>{rank}</strong>
          {step === 0 ? <span className="app-ladder-you">You</span> : <span className="app-lock" aria-label="Locked" />}
        </li>;
      })}
    </ol>
  </Shell>;
}

/** Screen 15: what works today and what is still being built. */
function Status() {
  return <Shell className="app-status-page">
    <span className="app-kicker app-kicker--violet">Build notes</span>
    <h2 className="app-title">Where we’re at</h2>
    {PRODUCT_AVAILABILITY.map((group, index) => <div key={group.label}>
      <div className="app-section-head"><h3><i className={`app-dot${index ? ' app-dot--violet' : ''}`} />{group.label}</h3></div>
      <ul className={`app-checks${index ? ' app-checks--next' : ''}`}>
        {group.items.map(item => <li key={item}><span aria-hidden="true" />{item}</li>)}
      </ul>
    </div>)}
  </Shell>;
}

/** Screen 16: the welcome, where the first day starts. */
function Close() {
  return <Shell className="app-close">
    <span className="app-close-mark"><img src="/mark.png" alt="" /></span>
    <strong className="app-close-word">trimmy</strong>
    <p className="app-close-line">It’s your first day on Wall Street, intern.</p>
    <img className="app-close-sal" src="/app/sal-celebrating.webp" alt="" />
    <button type="button" className="app-button app-close-button" onClick={openGetApp}>Start my first day</button>
  </Shell>;
}

export const PAGES: Record<PageName, () => JSX.Element> = { money: Money, prices: Prices, sal: Sal, trim: Trim, ranks: Ranks, status: Status, close: Close };
export const PAGE_ORDER: PageName[] = ["money", "prices", "sal", "trim", "ranks", "status", "close"];
