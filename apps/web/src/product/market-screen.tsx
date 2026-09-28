import {useEffect, useRef, useState} from 'react';
import type {ProductMarketClient, StockCard} from './market-client';
import {CompanyLogo, Failure, Loading, change, errorCopy, usd} from './ui';
import {FollowButton, MarketControls, RecentsStrip, availableSorts, sortCards, useFollowedCards} from './market-social';
import type {FollowingState, MarketList, MarketSort, SearchRecents} from './market-social';
import type {TradingCapabilities} from './money/live-trading';
import {companyMarketNote, companyTradeable, discoveryRefs, tradeableCompanies, type DiscoveryIndex} from './money/market-tradeable';

/** Mobile's Following, sort and recents (market-social.tsx). Omitted, the Market is read-only browsing. */
export interface MarketSocial {readonly following: FollowingState; readonly recents: SearchRecents; readonly onSignIn: () => void}
/** Real mode marks what can be traded and adds a Tradeable list; Paper shows the Market without them. */
export function MarketScreen({client, onSelect, social, real = false, capabilities = null}: {client: ProductMarketClient; onSelect: (card: StockCard) => void; social?: MarketSocial;
  real?: boolean; capabilities?: TradingCapabilities | null}) {
  const discovery = useRef(new Map<string, ReturnType<typeof discoveryRefs>>());
  const index = (pages: readonly {discovery: {results: readonly {assetId: string; variants: Parameters<typeof discoveryRefs>[0]}[]}}[]) => {
    for (const page of pages) for (const row of page.discovery.results) discovery.current.set(row.assetId, discoveryRefs(row.variants));
  };
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
  const [list, setList] = useState<MarketList>('all'), [sort, setSort] = useState<MarketSort>('featured');
  const [notice, setNotice] = useState<{message: string; signIn: boolean} | null>(null);
  useEffect(() => {if (list === 'tradeable' && !(real && capabilities?.enabled === true)) setList('all');}, [list, real, capabilities]);
  const followed = useFollowedCards(client, social?.following.assetIds ?? null, cards, Boolean(social) && list === 'following');
  // Nothing claims to be tradeable without a live capabilities read, or while trading is paused.
  const marks = real && capabilities?.enabled === true;
  const known: DiscoveryIndex = discovery.current;
  const tradeable = (card: StockCard) => marks && companyTradeable(capabilities, card.assetId, known);
  const text = query.trim().toLowerCase().replace(/^\$/, '');
  const listed = social && list === 'following' ? followed.cards
    : marks && list === 'tradeable' ? tradeableCompanies(capabilities!, new Map(cards.map(card => [card.assetId, card])), known)
      .filter(card => !text || [card.name ?? '', card.symbol ?? '', card.assetId].some(field => field.toLowerCase().includes(text)))
    : cards;
  const ordered = sortCards(listed, social ? sort : 'featured');
  const rows = marks && list === 'all' && (!social || sort === 'featured') ? [...ordered.filter(tradeable), ...ordered.filter(card => !tradeable(card))] : ordered;
  const choose = (card: StockCard) => {if (social && query.trim()) social.recents.record(card); onSelect(card);};
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
            if (turn === generation.current) {index([page]); setCards(page.cards); setOffset(page.nextOffset); setFreshness(page.discovery); setClock(Date.now());}
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
            index(pages);
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
        index([page]);
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
  return <section className={`market-screen${social ? ' has-follow' : ''}`} aria-label="Market">
    <header className="market-heading">
      <div className="page-intro"><h1>Market</h1>{(!online || stale) && <span className="market-status" role="status">{!online ? 'Offline' : 'Updating prices…'}</span>}</div>
      <div className="market-tools"><div className="market-search">
        <svg className="market-search-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/></svg>
        <label className="sr-only" htmlFor="company-search">Search companies</label><input id="company-search" type="search" autoComplete="off" placeholder="Search companies or symbols" maxLength={80} value={query} onChange={event => setQuery(event.target.value)}/>{query && <button aria-label="Clear search" onClick={() => setQuery('')}>×</button>}
      </div></div>
    </header>
    {social && <MarketControls list={list} lists={marks ? ['all', 'following', 'tradeable'] : ['all', 'following']} onList={next => {setList(next); setNotice(null);}} sort={sort} sorts={availableSorts(cards)} onSort={setSort}/>}
    {!social && marks && <MarketControls list={list} lists={['all', 'tradeable']} onList={setList} sort="featured" sorts={[]} onSort={() => undefined}/>}
    {notice && <div className="notice market-notice" role="status">{notice.message}{notice.signIn && social && <button className="text-button" onClick={social.onSignIn}>Sign in</button>}<button className="text-button" onClick={() => setNotice(null)}>Dismiss</button></div>}
    {social && !query && list === 'all' && <RecentsStrip recents={social.recents} onOpen={company => onSelect({assetId: company.assetId, name: company.name, symbol: company.symbol,
      imageUrl: company.imageUrl, stock: null, primaryVariant: null})}/>}
    <div className="stock-list-head" aria-hidden="true"><span>Company</span><span>Stock price</span><span>24h change</span><span/></div>
    <div className="market-results" role="region" aria-label="Companies" tabIndex={0}>
      {error !== null && <Failure title="Market is taking a moment." message={errorCopy(error)} onRetry={() => setRevision(n => n + 1)}/>}
      {rows.length > 0 && <div className="stock-list">{rows.map(card => <div key={card.assetId} className={social ? 'stock-row-shell' : 'stock-row-plain'}><button className="stock-row" onClick={() => choose(card)} aria-label={`Open ${card.name ?? card.assetId}`} aria-describedby={`market-price-${card.assetId} market-change-${card.assetId}`}>
        <span className="stock-company"><CompanyLogo name={card.name ?? card.assetId} url={card.imageUrl}/><span className="stock-company-text"><strong>{card.name ?? card.assetId}</strong><small>{card.symbol ?? 'Stock'}{tradeable(card) ? <span className="market-tradeable" data-testid={`market-tradeable-${card.assetId}`}>Tradeable</span>
          : marks && companyMarketNote(capabilities, card.assetId, known) && <span className="market-tradeable waiting">{companyMarketNote(capabilities, card.assetId, known)}</span>}</small></span></span>
        <span className="stock-price" id={`market-price-${card.assetId}`}><span className="sr-only">Stock price </span>{usd(card.stock?.priceUsd)}</span><span id={`market-change-${card.assetId}`} className={`stock-change ${!card.stock?.changePercent24h ? 'neutral' : card.stock.changePercent24h < 0 ? 'negative' : 'positive'}`}><span className="sr-only">24 hour change </span>{card.stock?.changePercent24h == null ? <><span aria-hidden="true">{change(null)}</span><span className="sr-only">unavailable</span></> : change(card.stock.changePercent24h)}</span><span className="stock-open" aria-hidden="true"><svg viewBox="0 0 20 20" fill="none"><path d="m8 5 5 5-5 5"/></svg></span>
      </button>{social && <FollowButton card={card} following={social.following} onNotice={(message, signIn) => setNotice({message, signIn})}/>}</div>)}</div>}
      {social && list === 'following' && !followed.loading && !rows.length && <div className="empty-page"><h2>Your watchlist starts here.</h2><p>Tap Follow on a company to keep it here.</p><button className="text-button" onClick={() => setList('all')}>Find a company</button></div>}
      {busy && <Loading>Finding companies…</Loading>}
      {marks && list === 'tradeable' && !rows.length && !busy && <div className="empty-page"><h2>No tradeable stocks here yet.</h2><p>Try searching for a company.</p></div>}
      {!busy && !error && !cards.length && list === 'all' && <div className="empty-page"><h2>No companies found.</h2><p>Try a company name or stock symbol.</p><button className="text-button" onClick={() => setQuery('')}>Browse the market</button></div>}
      {offset !== null && !query && !busy && list === 'all' && <button className="secondary load-more" onClick={() => void more()}>More companies</button>}
    </div>
  </section>;
}
