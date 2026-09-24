import {useEffect, useRef, useState} from 'react';
import type {ProductMarketClient, StockCard} from './market-client';
import {CompanyLogo, Failure, Loading, change, errorCopy, usd} from './ui';

export function MarketScreen({client, onSelect}: {client: ProductMarketClient; onSelect: (card: StockCard) => void}) {
  const [query, setQuery] = useState('');
  const [cards, setCards] = useState<readonly StockCard[]>([]);
  const [offset, setOffset] = useState<number | null>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<unknown>(null);
  const [revision, setRevision] = useState(0);
  const [freshness, setFreshness] = useState<{observedAt: string; refreshAfter: string} | null>(null);
  const [clock, setClock] = useState(Date.now);
  const [online, setOnline] = useState(() => navigator.onLine);
  const generation = useRef(0), loadedOffsets = useRef([0]);
  const moreController = useRef<AbortController | null>(null);
  const status = useRef({busy, query}); status.current = {busy, query};
  useEffect(() => {
    const tick = () => {setClock(Date.now()); setOnline(navigator.onLine);};
    const timer = window.setInterval(tick, 5000);
    window.addEventListener('online', tick); window.addEventListener('offline', tick);
    return () => {clearInterval(timer); window.removeEventListener('online', tick); window.removeEventListener('offline', tick);};
  }, []);
  useEffect(() => {
    const turn = ++generation.current;
    const controller = new AbortController(); moreController.current?.abort(); loadedOffsets.current = [0];
    setBusy(true); setError(null); setCards([]); setOffset(null); setFreshness(null);
    const timer = window.setTimeout(() => {
      void (async () => {
        try {
          if (query.trim()) {
            const page = await client.cards(query.trim(), {signal: controller.signal});
            if (turn === generation.current) {setCards(page.results); setFreshness(page); setClock(Date.now());}
          } else {
            const page = await client.catalog(0, {signal: controller.signal});
            if (turn === generation.current) {setCards(page.cards); setOffset(page.nextOffset); setFreshness(page.discovery); setClock(Date.now());}
          }
        } catch (reason) {if (!controller.signal.aborted && turn === generation.current) setError(reason);}
        finally {if (!controller.signal.aborted && turn === generation.current) setBusy(false);}
      })();
    }, query ? 350 : 0);
    return () => {clearTimeout(timer); ++generation.current; controller.abort(); moreController.current?.abort();};
  }, [client, query, revision]);
  // Refresh visible pages quietly. The search, list and scroll position stay in place.
  useEffect(() => {
    let active: AbortController | null = null;
    const update = async () => {
      if (document.visibilityState === 'hidden' || !navigator.onLine || status.current.busy || active) return;
      const turn = generation.current, controller = new AbortController(); active = controller;
      try {
        if (query.trim()) {
          const page = await client.cards(query.trim(), {signal: controller.signal});
          if (turn === generation.current && !controller.signal.aborted) {setCards(page.results); setFreshness(page); setError(null); setClock(Date.now());}
        } else {
          const starts = [...loadedOffsets.current];
          const pages = await Promise.all(starts.map(start => client.catalog(start, {signal: controller.signal})));
          if (turn === generation.current && !controller.signal.aborted && !status.current.busy && starts.join(',') === loadedOffsets.current.join(',')) {
            setCards(Array.from(new Map(pages.flatMap(page => page.cards).map(card => [card.assetId, card])).values()));
            setOffset(pages.at(-1)?.nextOffset ?? null);
            setFreshness(pages.reduce((oldest, page) => Date.parse(page.discovery.refreshAfter) < Date.parse(oldest.refreshAfter) ? page.discovery : oldest, pages[0]!.discovery));
            setClock(Date.now()); setError(null);
          }
        }
      } catch { /* Retained data ages visibly; the next focus/timer retries. */ }
      finally {if (active === controller) active = null;}
    };
    const resume = () => void update();
    const timer = window.setInterval(resume, 30000);
    window.addEventListener('focus', resume); window.addEventListener('online', resume); document.addEventListener('visibilitychange', resume);
    return () => {clearInterval(timer); active?.abort(); window.removeEventListener('focus', resume); window.removeEventListener('online', resume); document.removeEventListener('visibilitychange', resume);};
  }, [client, query]);
  async function more() {
    if (offset === null || busy || moreController.current) return;
    const turn = generation.current, start = offset;
    const controller = new AbortController(); moreController.current = controller;
    setBusy(true); setError(null);
    try {
      const page = await client.catalog(start, {signal: controller.signal});
      if (turn === generation.current && !controller.signal.aborted) {
        loadedOffsets.current = [...new Set([...loadedOffsets.current, start])];
        setCards(prior => Array.from(new Map([...prior, ...page.cards].map(card => [card.assetId, card])).values()));
        setOffset(page.nextOffset);
        setFreshness(prior => ({observedAt: prior && Date.parse(prior.observedAt) < Date.parse(page.discovery.observedAt) ? prior.observedAt : page.discovery.observedAt,
          refreshAfter: prior && Date.parse(prior.refreshAfter) < Date.parse(page.discovery.refreshAfter) ? prior.refreshAfter : page.discovery.refreshAfter}));
        setClock(Date.now());
      }
    } catch (reason) {if (!controller.signal.aborted && turn === generation.current) setError(reason);}
    finally {if (moreController.current === controller) moreController.current = null; if (!controller.signal.aborted && turn === generation.current) setBusy(false);}
  }
  const stale = freshness !== null && clock >= Date.parse(freshness.refreshAfter);
  return <section className="market-screen" aria-label="Market">
    <header className="market-heading">
      <div className="page-intro"><h1>Market</h1>{(!online || stale) && <span className="market-status" role="status">{!online ? 'Offline' : 'Updating prices…'}</span>}</div>
      <div className="market-tools"><div className="market-search">
        <svg className="market-search-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/></svg>
        <label className="sr-only" htmlFor="company-search">Search companies</label><input id="company-search" type="search" autoComplete="off" placeholder="Search companies or symbols" maxLength={80} value={query} onChange={event => setQuery(event.target.value)}/>{query && <button aria-label="Clear search" onClick={() => setQuery('')}>×</button>}
      </div></div>
    </header>
    <div className="stock-list-head" aria-hidden="true"><span>Company</span><span>Stock price</span><span>24h change</span><span/></div>
    <div className="market-results" role="region" aria-label="Companies" tabIndex={0}>
      {error !== null && <Failure title="Market is taking a moment." message={errorCopy(error)} onRetry={() => setRevision(n => n + 1)}/>}
      {cards.length > 0 && <div className="stock-list">{cards.map(card => <button key={card.assetId} className="stock-row" onClick={() => onSelect(card)} aria-label={`Open ${card.name ?? card.assetId}`} aria-describedby={`market-price-${card.assetId} market-change-${card.assetId}`}>
        <span className="stock-company"><CompanyLogo name={card.name ?? card.assetId} url={card.imageUrl}/><span className="stock-company-text"><strong>{card.name ?? card.assetId}</strong><small>{card.symbol ?? 'Stock'}</small></span></span>
        <span className="stock-price" id={`market-price-${card.assetId}`}><span className="sr-only">Stock price </span>{usd(card.stock?.priceUsd)}</span><span id={`market-change-${card.assetId}`} className={`stock-change ${!card.stock?.changePercent24h ? 'neutral' : card.stock.changePercent24h < 0 ? 'negative' : 'positive'}`}><span className="sr-only">24 hour change </span>{card.stock?.changePercent24h == null ? <><span aria-hidden="true">{change(null)}</span><span className="sr-only">unavailable</span></> : change(card.stock.changePercent24h)}</span><span className="stock-open" aria-hidden="true"><svg viewBox="0 0 20 20" fill="none"><path d="m8 5 5 5-5 5"/></svg></span>
      </button>)}</div>}
      {busy && <Loading>Finding companies…</Loading>}
      {!busy && !error && !cards.length && <div className="empty-page"><h2>No companies found.</h2><p>Try a company name or stock symbol.</p><button className="text-button" onClick={() => setQuery('')}>Browse the market</button></div>}
      {offset !== null && !query && !busy && <button className="secondary load-more" onClick={() => void more()}>More companies</button>}
    </div>
  </section>;
}
