import {useEffect, useRef, useState} from 'react';
import type {ProductMarketClient, StockCard} from './market-client';
import {CompanyLogo, Failure, Loading, change, errorCopy, usd} from './ui';
import {FollowButton, MarketControls, RecentsStrip, availableSorts, followNoticeText, marketFigures, sortCards, useFollowedCards} from './market-social';
import type {FollowNotice, FollowingState, MarketList, MarketSort, SearchRecents} from './market-social';
import {useT} from '../i18n/react';
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
  const [moreError, setMoreError] = useState<unknown>(null);
  const sentinel = useRef<HTMLDivElement>(null), results = useRef<HTMLDivElement>(null);
  const [error, setError] = useState<unknown>(null);
  const [revision, setRevision] = useState(0);
  const [freshness, setFreshness] = useState<{observedAt: string; refreshAfter: string} | null>(null);
  const [clock, setClock] = useState(Date.now);
  const [online, setOnline] = useState(() => navigator.onLine);
  const generation = useRef(0), loadedOffsets = useRef([0]);
  const moreController = useRef<AbortController | null>(null);
  const status = useRef({busy, query}); status.current = {busy, query};
  const [list, setList] = useState<MarketList>('all'), [sort, setSort] = useState<MarketSort>('featured');
  const [notice, setNotice] = useState<{notice: FollowNotice; signIn: boolean} | null>(null);
  const tr = useT();
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
    setBusy(true); setError(null); setMoreError(null); setCards([]); setOffset(null); setFreshness(null);
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
    setBusy(true); setMoreError(null);
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
    } catch (reason) {if (!controller.signal.aborted && turn === generation.current) setMoreError(reason);}
    finally {if (moreController.current === controller) moreController.current = null; if (!controller.signal.aborted && turn === generation.current) setBusy(false);}
  }
  useEffect(() => {
    if (!sentinel.current || typeof window.IntersectionObserver !== 'function' ||
        offset === null || busy || error || moreError || query || list !== 'all' || !online) return;
    let active = true;
    const observer = new window.IntersectionObserver(entries => {
      if (active && entries.some(entry => entry.isIntersecting) && document.visibilityState !== 'hidden') void more();
    }, {root: results.current, rootMargin: '0px 0px 500px 0px'});
    observer.observe(sentinel.current);
    return () => {active = false; observer.disconnect();};
  }, [offset, busy, error, moreError, query, list, online, client]);
  const stale = freshness !== null && clock >= Date.parse(freshness.refreshAfter);
  return <section className={`market-screen${social ? ' has-follow' : ''}`} aria-label={tr('market.screen.title')}>
    <header className="market-heading">
      <div className="page-intro"><h1>{tr('market.screen.title')}</h1>{(!online || stale) && <span className="market-status" role="status">{tr(!online ? 'market.screen.offline' : 'market.screen.updating')}</span>}</div>
      <div className="market-tools"><div className="market-search">
        <svg className="market-search-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/></svg>
        <label className="sr-only" htmlFor="company-search">{tr('market.screen.searchLabel')}</label><input id="company-search" type="search" autoComplete="off" autoCorrect="off" autoCapitalize="none" spellCheck={false} placeholder={tr('market.screen.searchPlaceholder')} maxLength={80} value={query} onChange={event => setQuery(event.target.value)}/>{query && <button aria-label={tr('market.screen.clearSearch')} onClick={() => setQuery('')}>×</button>}
      </div></div>
    </header>
    {/* No separate Tradeable list: every listed company can be bought, and each row says when its market is closed. */}
    {social && <MarketControls list={list} lists={['all', 'following']} onList={next => {setList(next); setNotice(null);}} sort={sort} sorts={availableSorts(cards)} onSort={setSort}/>}
    {notice && <div className="notice market-notice" role="status">{followNoticeText(tr, notice.notice)}{notice.signIn && social && <button className="text-button" onClick={social.onSignIn}>{tr('common.signIn')}</button>}<button className="text-button" onClick={() => setNotice(null)}>{tr('common.dismiss')}</button></div>}
    {social && !query && list === 'all' && <RecentsStrip recents={social.recents} onOpen={company => onSelect({assetId: company.assetId, name: company.name, symbol: company.symbol,
      imageUrl: company.imageUrl, stock: null, primaryVariant: null})}/>}
    <div className="stock-list-head" aria-hidden="true"><span>{tr('market.screen.headCompany')}</span><span>{tr('market.screen.headPrice')}</span><span>{tr('market.screen.headChange')}</span><span/></div>
    <div ref={results} className="market-results" role="region" aria-label={tr('market.screen.resultsLabel')} tabIndex={0}>
      {error !== null && <Failure title={tr('market.screen.failureTitle')} message={errorCopy(error)} onRetry={() => setRevision(n => n + 1)}/>}
      {rows.length > 0 && <div className="stock-list">{rows.map(card => <div key={card.assetId} className={social ? 'stock-row-shell' : 'stock-row-plain'}><button className="stock-row" onClick={() => choose(card)} aria-label={tr('market.screen.openCompany', {name: card.name ?? card.assetId})} aria-describedby={`market-price-${card.assetId} market-change-${card.assetId}`}>
        <span className="stock-company"><CompanyLogo name={card.name ?? card.assetId} url={card.imageUrl}/><span className="stock-company-text"><strong>{card.name ?? card.assetId}</strong><small>{card.symbol ?? tr('market.category.stock')}{tradeable(card) ? <span className="market-tradeable" data-testid={`market-tradeable-${card.assetId}`}>{tr('market.screen.tradeable')}</span>
          : marks && companyMarketNote(capabilities, card.assetId, known) && <span className="market-tradeable waiting">{companyMarketNote(capabilities, card.assetId, known)}</span>}</small></span></span>
        <span className="stock-price" id={`market-price-${card.assetId}`}><span className="sr-only">{tr('market.screen.srPrice')} </span>{usd(marketFigures(card).price)}</span><span id={`market-change-${card.assetId}`} className={`stock-change ${!marketFigures(card).change ? 'neutral' : marketFigures(card).change! < 0 ? 'negative' : 'positive'}`}><span className="sr-only">{tr('market.screen.srChange')} </span>{marketFigures(card).change === null ? <><span aria-hidden="true">{change(null)}</span><span className="sr-only">{tr('market.screen.srChangeUnavailable')}</span></> : change(marketFigures(card).change!)}</span><span className="stock-open" aria-hidden="true"><svg viewBox="0 0 20 20" fill="none"><path d="m8 5 5 5-5 5"/></svg></span>
      </button>{social && <FollowButton card={card} following={social.following} onNotice={(next, signIn) => setNotice({notice: next, signIn})}/>}</div>)}</div>}
      {social && list === 'following' && !followed.loading && !rows.length && <div className="empty-page"><h2>{tr('market.screen.followingEmptyTitle')}</h2><p>{tr('market.screen.followingEmptyBody')}</p><button className="text-button" onClick={() => setList('all')}>{tr('market.screen.findCompany')}</button></div>}
      {busy && <Loading>{tr('market.screen.finding')}</Loading>}
      {marks && list === 'tradeable' && !rows.length && !busy && <div className="empty-page"><h2>{tr('market.screen.noTradeableTitle')}</h2><p>{tr('market.screen.noTradeableBody')}</p></div>}
      {!busy && !error && !cards.length && list === 'all' && <div className="empty-page"><h2>{tr('market.screen.noResultsTitle')}</h2><p>{tr('market.screen.noResultsBody')}</p><button className="text-button" onClick={() => setQuery('')}>{tr('market.screen.browse')}</button></div>}
      {offset !== null && !query && list === 'all' && <div ref={sentinel} style={{minHeight: 1}}>
        {moreError !== null && <p role="status">{tr('market.screen.moreFailed')}</p>}
        {!busy && (moreError !== null || typeof window.IntersectionObserver !== 'function') &&
          <button className="secondary load-more" onClick={() => void more()}>{tr(moreError ? 'common.tryAgain' : 'market.screen.more')}</button>}
      </div>}
    </div>
  </section>;
}
