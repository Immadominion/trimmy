import { isStorableAssetId } from '../account/followed-stocks';
import type { FollowedStocksWorkspace } from '../account/use-followed-stocks';
import {useEffect, useMemo, useRef, useState, useSyncExternalStore} from 'react';
import type {StockResearchClient} from './client.js';
import type {StockResearchConfig} from './config.js';
import type {StockAdvisory, StockDiscoveryAsset, StockVariant} from './discovery.js';
import type {StockHistoryPage} from './history.js';
import {LiveResearchStore, RESEARCH_AMOUNT_RAW, researchIsStale, researchIssueMessage, type ResearchSlice} from './live-research.js';
import {formatRawTokenUnits} from './validation.js';

export interface LiveResearchPanelProps {
  readonly config: StockResearchConfig;
  /** Present only when the configuration is enabled; the panel owns its store. */
  readonly client: StockResearchClient | null;
  readonly now?: () => number;
  readonly online?: () => boolean;
  /** Absent for a guest, so keeping is simply not offered. */
  readonly following?: FollowedStocksWorkspace;
}

function clock(iso: string): string {
  const value = new Date(iso);
  if (Number.isNaN(value.getTime())) return 'an unknown time';
  const two = (n: number) => String(n).padStart(2, '0');
  return `${two(value.getHours())}:${two(value.getMinutes())}:${two(value.getSeconds())}`;
}

function shortMint(mint: string): string { return mint.length <= 12 ? mint : `${mint.slice(0, 4)}…${mint.slice(-4)}`; }

function advisoryLabel(advisory: StockAdvisory | null): string | null {
  if (!advisory) return null;
  const status = advisory.status === 'caution' ? 'Caution' : advisory.status === 'compromised' ? 'Compromised'
    : advisory.status === 'blocked' ? 'Blocked' : 'Unknown status';
  return `${status}: ${advisory.reason}`;
}

function Status({slice, stale, verb}: {slice: ResearchSlice<unknown>; stale: boolean; verb: string}) {
  const text = slice.phase === 'loading' ? `${verb}…`
    : slice.phase === 'idle' ? ''
    : slice.phase === 'offline' ? researchIssueMessage('STOCK_OFFLINE')
    : slice.phase === 'error' ? `${researchIssueMessage(slice.code)}${slice.retained ? ' Showing the last result.' : ''}`
    : stale ? 'Out of date. Check again.' : '';
  return text ? <p role="status" className="research-status">{text}</p> : null;
}

function VariantRow({variant}: {variant: StockVariant}) {
  const advisory = advisoryLabel(variant.advisory);
  const figure = variant.market?.priceUsd;
  return <li className="research-variant">
    <div><strong>{variant.symbol ?? variant.label ?? variant.variantId}</strong><span>{variant.issuer ?? 'Issuer not listed'} · {variant.kind}</span></div>
    <div><span aria-label={`Mint ${variant.mint}`}>{shortMint(variant.mint)}</span>
      {figure !== null && figure !== undefined && <span>Provider figure {figure} (display only, no timestamp)</span>}</div>
    {advisory && <em className={`research-advisory research-advisory-${variant.advisory?.status}`}>{advisory}</em>}
  </li>;
}

const IDLE_FOLLOWING: FollowedStocksWorkspace = Object.freeze({
  view: null, isFollowing: () => false, follow: () => {}, unfollow: () => {}, refresh: () => {},
});

function keepMessage(code: string): string {
  switch (code) {
    case 'FOLLOWING_LIST_FULL': return 'Your list is full. Remove one to keep another.';
    case 'WATCHLIST_UNAUTHENTICATED': case 'WATCHLIST_TOKEN_UNAVAILABLE': return 'Sign in again to keep this.';
    case 'WATCHLIST_REVISION_CONFLICT': return 'Your list changed while you were looking. Try again.';
    case 'WATCHLIST_TIMEOUT': return 'That took too long. Try again.';
    default: return 'Your list is unavailable right now.';
  }
}

function AssetRow({asset, onVariants, expanded, following}: {asset: StockDiscoveryAsset; onVariants: () => void; expanded: boolean; following: FollowedStocksWorkspace}) {
  // Keeping needs a verified account, so a guest sees no control rather than one
  // that is offered and then refused. Keeping records a name, not a holding.
  const view = following.view;
  const kept = view !== null && following.isFollowing(asset.assetId);
  const busy = view?.status === 'saving' || view?.status === 'loading';
  return <div className="research-asset">
    <div className="research-asset-heading">
      <div><strong>{asset.name ?? asset.assetId}</strong><span>{asset.symbol ?? 'No symbol'} · {asset.variants.length} listed {asset.variants.length === 1 ? 'variant' : 'variants'}</span></div>
      <button onClick={onVariants} aria-expanded={expanded}>{expanded ? 'Hide variants' : 'See variants'}</button>
      {view !== null && isStorableAssetId(asset.assetId) && <button
        aria-pressed={kept}
        disabled={busy}
        onClick={() => (kept ? following.unfollow(asset.assetId) : following.follow(asset.assetId))}
      >{kept ? 'Kept' : 'Keep'}</button>}
    </div>
    {view?.errorCode && <p role="status" className="research-status">{keepMessage(view.errorCode)}</p>}
    {asset.advisories.length > 0 && <p className="research-note">{asset.advisories.length} issuer {asset.advisories.length === 1 ? 'advisory' : 'advisories'} on this company's variants.</p>}
  </div>;
}

function HistoryChart({page}: {page: StockHistoryPage}) {
  const closes = page.candles.map(candle => Number(candle.closeRaw)).filter(Number.isFinite);
  if (closes.length < 2) return null;
  const low = Math.min(...closes), high = Math.max(...closes), span = high - low || 1;
  const points = closes.map((value, index) => `${(index / (closes.length - 1) * 100).toFixed(2)},${(100 - (value - low) / span * 100).toFixed(2)}`).join(' ');
  return <svg className="research-chart" viewBox="0 0 100 100" preserveAspectRatio="none" role="img"
    aria-label={`${closes.length} hourly close values for the AAPLx mint, provider units not declared`}>
    <polyline fill="none" stroke="currentColor" strokeWidth="1.5" vectorEffect="non-scaling-stroke" points={points}/>
  </svg>;
}

/**
 * Read-only live research in the Explore view. Search asks the provider for
 * listed equities and their issuer variants; the pinned AAPLx section shows
 * hourly mint history and two separate indicative reads for a fixed 10 USDC
 * amount. Nothing here is a price you can trade at, and nothing loads until
 * asked. Sample workspace data stays outside this section.
 */
export function LiveResearchPanel({config, client, now, online, following}: LiveResearchPanelProps) {
  const keeping = following ?? IDLE_FOLLOWING;
  // Opening Explore is the request to see what is kept, so the list is read
  // once here. Nothing polls it.
  useEffect(() => { if (keeping.view !== null && keeping.view.status === 'idle') keeping.refresh(); }, [keeping]);
  const store = useMemo(() => client ? new LiveResearchStore({client, ...(now ? {now} : {}), ...(online ? {online} : {})}) : null, [client, now, online]);
  useEffect(() => () => { store?.close(); }, [store]);
  const state = useSyncExternalStore(
    listener => store ? store.subscribe(listener) : () => {},
    () => store?.getSnapshot() ?? null,
    () => store?.getSnapshot() ?? null,
  );
  const [expandedAsset, setExpandedAsset] = useState<string | null>(null);
  const [, tick] = useState(0);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Freshness deadlines are read at render; re-render when the earliest one passes.
  useEffect(() => {
    if (!store || !state) return;
    const deadlines = [state.history.value?.provenance.refreshAfter, state.jupiter.value?.refreshAfter,
      state.raydium.value?.refreshAfter, state.search.value?.refreshAfter].filter((value): value is string => typeof value === 'string')
      .map(value => Date.parse(value)).filter(value => Number.isFinite(value) && value > store.now());
    if (deadlines.length === 0) return;
    const timer = setTimeout(() => tick(value => value + 1), Math.min(...deadlines) - store.now() + 50);
    return () => clearTimeout(timer);
  }, [store, state]);
  useEffect(() => () => { if (debounce.current) clearTimeout(debounce.current); }, []);

  if (config.kind === 'disabled') return null;
  if (config.kind === 'invalid' || !store || !state) {
    return <section className="live-research" aria-labelledby="live-research-title">
      <div className="live-research-heading"><h2 id="live-research-title">Live research</h2><span className="read-only-pill">Read-only</span></div>
      <p role="status">Live research is not configured correctly for this workspace.</p>
    </section>;
  }
  const currentTime = store.now();
  const search = state.search, variants = state.variants, history = state.history, jupiter = state.jupiter, raydium = state.raydium;
  const searchStale = search.value !== null && researchIsStale(search.value.refreshAfter, currentTime);
  const historyStale = history.value !== null && researchIsStale(history.value.provenance.refreshAfter, currentTime);
  const jupiterStale = jupiter.value !== null && researchIsStale(jupiter.value.refreshAfter, currentTime);
  const raydiumStale = raydium.value !== null && researchIsStale(raydium.value.refreshAfter, currentTime);
  const submitSearch = (value: string) => {
    if (debounce.current) clearTimeout(debounce.current);
    debounce.current = setTimeout(() => { setExpandedAsset(null); void store.search(value); }, 400);
  };
  const toggleVariants = (assetId: string) => {
    if (expandedAsset === assetId) { setExpandedAsset(null); return; }
    setExpandedAsset(assetId);
    void store.variants(assetId);
  };
  const lastCandle = history.value?.candles.at(-1) ?? null;

  return <section className="live-research" aria-labelledby="live-research-title">
    <div className="live-research-heading">
      <div><h2 id="live-research-title">Live research</h2><p>Real provider data, checked only when you ask. Not a price you can trade at.</p></div>
      <span className="read-only-pill">Read-only</span>
    </div>

    <div className="research-block">
      <label className="research-search"><span>Search listed equities</span>
        <input type="search" defaultValue="" placeholder="Company name or symbol" aria-label="Search listed equities"
          onInput={event => submitSearch((event.target as HTMLInputElement).value)}/></label>
      <Status slice={search} stale={searchStale} verb="Searching"/>
      {search.value && search.value.results.length === 0 && <p className="research-note">No listed equity matched "{search.value.query}".</p>}
      {search.value && search.value.results.length > 0 && <ul className="research-assets">
        {search.value.results.map(asset => <li key={asset.assetId}>
          <AssetRow asset={asset} expanded={expandedAsset === asset.assetId} onVariants={() => toggleVariants(asset.assetId)} following={keeping}/>
          {expandedAsset === asset.assetId && <div className="research-variants">
            <Status slice={variants} stale={false} verb="Loading variants"/>
            {variants.value && variants.value.assetId === asset.assetId && <ul>{variants.value.variants.map(variant => <VariantRow key={variant.variantId} variant={variant}/>)}</ul>}
          </div>}
        </li>)}
      </ul>}
      {search.value && <p className="research-note">Listed by the provider at {clock(search.value.observedAt)}. Listing is not eligibility, ownership or a complete catalog.</p>}
    </div>

    <div className="research-block">
      <div className="research-block-heading"><h3>Apple xStock (AAPLx) on Solana</h3>
        <div className="account-actions">
          <button onClick={() => { void store.history(); }} disabled={history.phase === 'loading'}>{history.value ? 'Check history again' : 'Load hourly history'}</button>
          <button onClick={() => { void store.estimates(); }} disabled={jupiter.phase === 'loading' || raydium.phase === 'loading'}>{jupiter.value || raydium.value ? 'Check estimates again' : 'Load estimates'}</button>
        </div>
      </div>
      <Status slice={history} stale={historyStale} verb="Loading history"/>
      {history.value && <div className="research-history">
        <HistoryChart page={history.value}/>
        <p className="research-note">{history.value.candles.length} hourly candles for the AAPLx mint, observed at {clock(history.value.provenance.observedAt)}.
          {lastCandle ? ` Last close value ${lastCandle.closeRaw}.` : ''} Provider units are not declared, and this is the mint's trading history, not canonical Apple stock history.
          {history.value.dataStatus === 'empty_provider_cache_or_no_trades' ? ' The provider returned no trades for this range.' : ''}</p>
      </div>}
      <dl className="research-estimates">
        <div><dt>Jupiter (indicative)</dt><dd>
          <Status slice={jupiter} stale={jupiterStale} verb="Asking Jupiter"/>
          {jupiter.value && <span>10 USDC → about {formatRawTokenUnits(jupiter.value.output.estimatedAmountRaw, jupiter.value.output.decimals)} AAPLx, minimum {formatRawTokenUnits(jupiter.value.output.quotedMinimumAmountRaw, jupiter.value.output.decimals)}. Received {clock(jupiter.value.receivedAt)}.</span>}
        </dd></div>
        <div><dt>Raydium (comparison only)</dt><dd>
          <Status slice={raydium} stale={raydiumStale} verb="Asking Raydium"/>
          {raydium.value && <span>10 USDC → about {formatRawTokenUnits(raydium.value.output.estimatedAmountRaw, raydium.value.output.decimals)} AAPLx, minimum {formatRawTokenUnits(raydium.value.output.quotedMinimumAmountRaw, raydium.value.output.decimals)}. Received {clock(raydium.value.receivedAt)}.</span>}
        </dd></div>
      </dl>
      <p className="research-note">Both reads are for a fixed {formatRawTokenUnits(RESEARCH_AMOUNT_RAW, 6)} USDC amount, each from its own venue, neither chosen over the other, and neither executable. No wallet was checked and no order exists.</p>
    </div>
  </section>;
}
