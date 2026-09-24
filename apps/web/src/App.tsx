import { useEffect, useId, useMemo, useRef, useState } from 'react';
import type { CSSProperties, KeyboardEvent, ReactNode } from 'react';
import { CHART_RANGES, DEFAULT_WATCHLIST, SECTORS, STOCKS, chartSeries, holdingValueCents, money, percent, portfolioSeries } from './fixtures';
import type { ChartPoint, ChartRange, Sector, Stock, WorkspaceView } from './fixtures';
import { STORAGE_KEY, decodeWorkspace, loadWorkspace, saveWorkspace, toggleWatchlist, visibleStocks } from './state';
import type { SortOrder, StoragePort } from './state';
import { useAccountWatchlist } from './account/use-account-watchlist';
import { useFollowedStocks } from './account/use-followed-stocks';
import { AccountBar } from './account/account-bar';
import { AccountPortfolioPanel } from './account/account-portfolio-panel';
import { StockResearchClient } from './markets/client';
import { readStockResearchConfig } from './markets/config';
import type { StockResearchConfig } from './markets/config';
import { LiveResearchPanel } from './markets/live-research-panel';
import { PreStocksPanel } from './markets/prestocks-panel';

type IconName = 'portfolio' | 'star' | 'compass' | 'search' | 'chevron' | 'arrow' | 'close' | 'info' | 'plus' | 'check' | 'external';
function Icon({name, size = 20, filled = false}: {name: IconName; size?: number; filled?: boolean}) {
  const paths: Record<IconName, string> = {
    portfolio: 'M4 10h16v10H4z M8 10V5h8v5 M4 14h16 M10 14v3h4v-3',
    star: 'm12 3 2.78 5.63L21 9.54l-4.5 4.39L17.56 20 12 17.08 6.44 20l1.06-6.07L3 9.54l6.22-.91z',
    compass: 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M15.5 8.5l-2 5-5 2 2-5z',
    search: 'M16.5 16.5 21 21 M18 10.5a7.5 7.5 0 1 1-15 0 7.5 7.5 0 0 1 15 0',
    chevron: 'm9 5 7 7-7 7',
    arrow: 'M6 17 17 6 M6 6h11v11',
    close: 'm6 6 12 12 M6 18 18 6',
    info: 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M12 11v6 M12 7v.2',
    plus: 'M12 5v14 M5 12h14',
    check: 'm5 12 4 4L19 6',
    external: 'M14 4h6v6 M20 4l-9 9 M10 5H5v14h14v-5',
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" fill={filled ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={paths[name]} /></svg>;
}

function StockMark({stock, large = false}: {stock: Stock; large?: boolean}) {
  const marks: Record<Stock['mark'], ReactNode> = {
    diamond: <><path d="m16 5 11 11-11 11L5 16z" fill="currentColor"/><path d="m16 12 4 4-4 4-4-4z" fill={stock.color}/></>,
    orbit: <><circle cx="16" cy="16" r="8"/><ellipse cx="16" cy="16" rx="13" ry="5" transform="rotate(-40 16 16)"/><circle cx="25" cy="8" r="2" fill="currentColor" stroke="none"/></>,
    leaf: <><path d="M8 24C5 12 15 6 25 7c0 11-6 20-17 17Z" fill="currentColor"/><path d="m9 23 12-12" stroke={stock.color}/></>,
    arch: <><path d="M7 26V15a9 9 0 0 1 18 0v11h-6V15a3 3 0 0 0-6 0v11Z" fill="currentColor" stroke="none"/></>,
    steps: <path d="M5 24V18h7v-6h7V6h8v18Z" fill="currentColor" stroke="none"/>,
    wave: <><path d="M5 11c5-6 8 6 13 0s8 0 9 0 M5 17c5-6 8 6 13 0s8 0 9 0 M5 23c5-6 8 6 13 0s8 0 9 0" strokeWidth="3"/></>,
    grid: <><rect x="6" y="6" width="8" height="8" rx="2" fill="currentColor"/><rect x="18" y="6" width="8" height="8" rx="2" fill="currentColor"/><rect x="6" y="18" width="8" height="8" rx="2" fill="currentColor"/><circle cx="22" cy="22" r="4" fill="currentColor"/></>,
    sun: <><circle cx="16" cy="16" r="6" fill="currentColor"/><path d="M16 3v4 M16 25v4 M3 16h4 M25 16h4 M7 7l3 3 M22 22l3 3 M7 25l3-3 M22 10l3-3"/></>,
  };
  return <span className={`stock-mark ${large ? 'stock-mark-large' : ''}`} style={{background: stock.color, color: stock.ink}}><svg width="30" height="30" viewBox="0 0 32 32" stroke="currentColor" strokeWidth="1.8" fill="none" aria-hidden="true">{marks[stock.mark]}</svg></span>;
}

function Sparkline({stock}: {stock: Stock}) {
  const series = chartSeries(stock, '1D');
  const values = series.map(point => point.valueCents);
  const minimum = Math.min(...values);
  const span = Math.max(1, Math.max(...values) - minimum);
  const points = values.map((value, index) => `${index / (values.length - 1) * 88},${28 - (value - minimum) / span * 24}`).join(' ');
  return <svg className={`sparkline ${stock.dayChangeBps < 0 ? 'negative' : ''}`} width="88" height="32" viewBox="0 0 88 32" aria-hidden="true"><polyline points={points} stroke="currentColor" strokeWidth="1.7" fill="none" strokeLinejoin="round" /></svg>;
}

function PriceChart({points, title, compact = false}: {points: readonly ChartPoint[]; title: string; compact?: boolean}) {
  const [activeIndex, setActiveIndex] = useState<number | null>(null);
  const gradientId = useId().replace(/:/g, '');
  const values = points.map(point => point.valueCents);
  const minimum = Math.min(...values);
  const maximum = Math.max(...values);
  const span = Math.max(1, maximum - minimum);
  const coordinates = values.map((value, index) => ({x: 8 + index / (values.length - 1) * 744, y: 224 - (value - minimum) / span * 170}));
  const path = coordinates.map((point, index) => `${index === 0 ? 'M' : 'L'}${point.x.toFixed(2)},${point.y.toFixed(2)}`).join(' ');
  const displayedIndex = Math.min(activeIndex ?? points.length - 1, points.length - 1);
  const activePoint = points[displayedIndex]!;
  const position = coordinates[displayedIndex]!;
  const negative = (points.at(-1)?.valueCents ?? 0) < (points[0]?.valueCents ?? 0);
  function keyboard(event: KeyboardEvent<HTMLDivElement>) {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    setActiveIndex(event.key === 'Home' ? 0 : event.key === 'End' ? points.length - 1 : Math.max(0, Math.min(points.length - 1, displayedIndex + (event.key === 'ArrowLeft' ? -1 : 1))));
  }
  return <div className={`chart-shell ${compact ? 'chart-compact' : ''}`}>
    <div className={`price-chart ${negative ? 'negative' : ''}`} role="slider" tabIndex={0} aria-label={title} aria-valuemin={0} aria-valuemax={points.length - 1} aria-valuenow={displayedIndex} aria-valuetext={`${activePoint.label}, ${money(activePoint.valueCents)}, fictional data`} onKeyDown={keyboard} onBlur={() => setActiveIndex(null)} onPointerLeave={() => setActiveIndex(null)} onPointerMove={event => {
      const rect = event.currentTarget.getBoundingClientRect();
      setActiveIndex(Math.max(0, Math.min(points.length - 1, Math.round((event.clientX - rect.left) / rect.width * (points.length - 1)))));
    }}>
      <svg viewBox="0 0 760 260" preserveAspectRatio="none" aria-hidden="true">
        <defs><linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="currentColor" stopOpacity=".095"/><stop offset="100%" stopColor="currentColor" stopOpacity="0"/></linearGradient></defs>
        {[54, 111, 168, 225].map(y => <line key={y} x1="0" y1={y} x2="760" y2={y} stroke="#EBECE7" strokeWidth="1" strokeDasharray="3 5"/>)}
        <path d={`${path} L752,260 L8,260Z`} fill={`url(#${gradientId})`} />
        <path d={path} fill="none" stroke="currentColor" strokeWidth={compact ? 3 : 2.5} strokeLinejoin="round" vectorEffect="non-scaling-stroke"/>
        {activeIndex !== null && <><line x1={position.x} y1="25" x2={position.x} y2="250" stroke="currentColor" strokeOpacity=".22" strokeDasharray="3 4"/><circle cx={position.x} cy={position.y} r="5" fill="currentColor" stroke="white" strokeWidth="3"/></>}
      </svg>
      {activeIndex !== null && <div className="chart-tooltip" style={{left: `${Math.max(12, Math.min(88, position.x / 760 * 100))}%`}}><strong>{money(activePoint.valueCents)}</strong><span>{activePoint.label}</span></div>}
      {!compact && <div className="chart-scale" aria-hidden="true"><span>{money(maximum)}</span><span>{money(Math.round((minimum + maximum) / 2))}</span><span>{money(minimum)}</span></div>}
    </div>
    {!compact && <div className="chart-axis" aria-hidden="true">{[0, 6, 12, 18, points.length - 1].map(index => <span key={index}>{points[index]?.label}</span>)}</div>}
  </div>;
}

function getStorage(): StoragePort | null {try {return window.localStorage;} catch {return null;}}
const sectionNames: Record<WorkspaceView, string> = {portfolio: 'Portfolio', watchlist: 'Watchlist', explore: 'Explore'};
const rangeNames: Record<ChartRange, string> = {'1D': 'today', '1W': 'this week', '1M': 'this month', '3M': 'in 3 months', '1Y': 'this year'};

type AccountWorkspace = ReturnType<typeof useAccountWatchlist>;

/** The normal workspace contains only actual account state and provider reads.
 * Fictional asset IDs stay inside the explicitly selected sample workspace. */
export interface AppProps {readonly researchConfiguration?: StockResearchConfig}
export function App({researchConfiguration}: AppProps) {
  const account = useAccountWatchlist();
  const [sample, setSample] = useState(false);
  const researchConfig = useMemo(() => researchConfiguration ?? readStockResearchConfig(), [researchConfiguration]);
  return sample
    ? <SampleWorkspace account={account} onExit={() => setSample(false)}/>
    : <LiveWorkspace account={account} config={researchConfig} onSample={() => setSample(true)}/>;
}

function LiveWorkspace({account, config, onSample}: {
  account: AccountWorkspace; config: StockResearchConfig; onSample: () => void;
}) {
  const [view, setView] = useState<'portfolio' | 'explore'>('portfolio');
  const headingRef = useRef<HTMLHeadingElement>(null);
  function changeView(next: 'portfolio' | 'explore') {
    setView(next);
    window.requestAnimationFrame(() => headingRef.current?.focus());
  }
  return <div className="workspace live-workspace">
    <a className="skip-link" href="#main">Skip to content</a>
    <aside className="sidebar">
      <button className="brand" aria-label="Trimmy portfolio" onClick={() => changeView('portfolio')}>
        <span className="brand-mark" aria-hidden="true"><span/></span>trimmy<span className="brand-period">.</span>
      </button>
      <p className="workspace-label">Your workspace</p>
      <nav className="navigation" aria-label="Workspace">
        <button className={`nav-item ${view === 'portfolio' ? 'active' : ''}`} aria-current={view === 'portfolio' ? 'page' : undefined} onClick={() => changeView('portfolio')}><Icon name="portfolio"/><span>Portfolio</span></button>
        <button className={`nav-item ${view === 'explore' ? 'active' : ''}`} aria-current={view === 'explore' ? 'page' : undefined} onClick={() => changeView('explore')}><Icon name="compass"/><span>Explore</span></button>
      </nav>
      <div className="sidebar-bottom"><div className="practice-note"><span className="practice-symbol">↗</span><strong>See what you own.</strong><p>Check your linked wallet and look into stocks.</p></div><div className="sidebar-footer"><span className="small-dot"/>Read-only for now</div></div>
    </aside>
    <div className="workspace-body">
      <header className="topbar live-topbar"><div className="breadcrumb">Workspace <Icon name="chevron" size={12}/><span>{sectionNames[view]}</span></div><button className="workspace-switch" aria-label="Sample workspace" onClick={onSample}>Sample workspace <Icon name="arrow" size={16}/></button></header>
      <AccountBar account={account} guestIds={[]} scope="account"/>
      <main id="main" className="main-content live-content">
        <div className="page-heading"><div><h1 ref={headingRef} tabIndex={-1}>{sectionNames[view]}</h1><p>{view === 'portfolio' ? 'The balances in your linked wallet.' : 'Look up a company. See the details behind its token.'}</p></div><span className="read-only-pill">Read-only</span></div>
        {view === 'portfolio' ? <>
          {account.auth.enabled ? <AccountPortfolioPanel auth={account.auth} portfolio={account.portfolio}/> :
            <section className="workspace-empty" aria-labelledby="account-unavailable-title"><span className="workspace-empty-icon"><Icon name="portfolio" size={30}/></span><h2 id="account-unavailable-title">Your portfolio starts with your account.</h2><p>{account.auth.errorCode ? 'Sign-in is unavailable in this build. Your saved account data is unchanged.' : 'Account sign-in is not available in this build yet.'}</p><p>When connected, your wallet balances appear here.</p></section>}
          <section className="workspace-next" aria-labelledby="explore-next-title"><div><h2 id="explore-next-title">Get to know a stock.</h2><p>Find listed companies, issuer versions and available market history.</p></div><button className="primary-button" onClick={() => changeView('explore')}>Explore stocks <Icon name="arrow" size={16}/></button></section>
        </> : <ExploreResearch config={config} onSample={onSample}/>}
        <p className="workspace-footnote">Buying, selling and stock gifts are not available yet.</p>
      </main>
    </div>
  </div>;
}

/** A mounted Explore view owns its read client. Leaving it cancels reads;
 * returning creates a new client rather than reusing a closed store's client. */
function ExploreResearch({config, onSample}: {config: StockResearchConfig; onSample: () => void}) {
  // Null for a guest, so Explore offers no way to keep anything until signed in.
  const following = useFollowedStocks();
  const client = useMemo(() => config.kind === 'enabled' ? new StockResearchClient({apiOrigin: config.apiOrigin}) : null, [config]);
  useEffect(() => () => { client?.close(); }, [client]);
  return <>
    {config.kind === 'disabled' ? <section className="workspace-empty" aria-labelledby="research-unavailable-title"><span className="workspace-empty-icon"><Icon name="compass" size={30}/></span><h2 id="research-unavailable-title">Stock research is unavailable in this build.</h2><p>Live results will appear here when research is connected.</p><button className="primary-button" onClick={onSample}>Try the sample workspace</button></section> : <LiveResearchPanel config={config} client={client} following={following}/>}
    <PreStocksPanel config={config} client={client}/>
  </>;
}

function SampleWorkspace({account, onExit}: {account: AccountWorkspace; onExit: () => void}) {
  const [saved] = useState(() => loadWorkspace(getStorage()));
  const [guestWatchlist, setGuestWatchlist] = useState<readonly string[]>(saved.workspace.watchlist);
  const watchlist = account.auth.authenticated ? account.snapshot?.assetIds ?? [] : guestWatchlist;
  const canEditWatchlist = !account.auth.authenticated || account.canEdit;
  const [storageWarning, setStorageWarning] = useState<string | null>(saved.warning);
  const [view, setView] = useState<WorkspaceView>('portfolio');
  const [query, setQuery] = useState('');
  const [sector, setSector] = useState<Sector | 'All sectors'>('All sectors');
  const [sort, setSort] = useState<SortOrder>('value');
  const [selectedId, setSelectedId] = useState('forma');
  const [range, setRange] = useState<ChartRange>('1M');
  const [announcement, setAnnouncement] = useState('');
  const searchRef = useRef<HTMLInputElement>(null);
  const dialogRef = useRef<HTMLDialogElement>(null);
  const detailRef = useRef<HTMLElement>(null);
  const selected = STOCKS.find(stock => stock.id === selectedId) ?? STOCKS[0]!;
  const rows = visibleStocks({view, watchlist, query, sector, sort});
  const totalValue = STOCKS.reduce((total, stock) => total + holdingValueCents(stock), 0);
  const totalCost = STOCKS.reduce((total, stock) => total + stock.costBasisCents, 0);
  const points = view === 'portfolio' ? portfolioSeries(range) : chartSeries(selected, range);
  const firstValue = points[0]!.valueCents;
  const endValue = points.at(-1)!.valueCents;
  const delta = endValue - firstValue;
  const changeBps = Math.round(delta / firstValue * 10000);
  const isWatched = watchlist.includes(selected.id);
  const sectorValues = SECTORS.map(name => ({name, value: STOCKS.filter(stock => stock.sector === name).reduce((total, stock) => total + holdingValueCents(stock), 0)}));

  useEffect(() => {
    const shortcut = (event: globalThis.KeyboardEvent) => {
      const tag = (event.target as HTMLElement | null)?.tagName;
      if (event.key === '/' && tag !== 'INPUT' && tag !== 'TEXTAREA' && !(event.target as HTMLElement | null)?.isContentEditable && !dialogRef.current?.open) {
        event.preventDefault(); searchRef.current?.focus();
      }
    };
    const storageEvent = (event: StorageEvent) => {
      if (event.key === STORAGE_KEY) {
        const decoded = decodeWorkspace(event.newValue);
        setGuestWatchlist(decoded.workspace.watchlist);
        if (decoded.recovered) setStorageWarning('Some saved preferences could not be loaded. Your watchlist has been repaired.');
      }
    };
    window.addEventListener('keydown', shortcut);
    window.addEventListener('storage', storageEvent);
    return () => {window.removeEventListener('keydown', shortcut); window.removeEventListener('storage', storageEvent);};
  }, []);

  function changeView(next: WorkspaceView) {setView(next); setQuery(''); setSector('All sectors'); setSort(next === 'portfolio' ? 'value' : 'name');}
  function updateWatchlist(next: readonly string[]) {
    if (account.auth.authenticated) {
      const saved = account.setAssetIds(next);
      if (!saved) setStorageWarning('That watchlist change could not be saved. Your previous list is still here.');
      else setStorageWarning(null);
      return saved;
    }
    setGuestWatchlist(next);
    if (!saveWorkspace(getStorage(), next)) setStorageWarning('Watchlist updated for this session. Browser storage is unavailable.');
    else setStorageWarning(null);
    return true;
  }
  function toggle(stock: Stock) {
    const removing = watchlist.includes(stock.id);
    if (updateWatchlist(toggleWatchlist(watchlist, stock.id))) setAnnouncement(`${stock.name} ${removing ? 'removed from' : 'added to'} your watchlist.`);
  }
  function select(stock: Stock) {
    setSelectedId(stock.id);
    if (window.matchMedia('(max-width: 1100px)').matches) {
      detailRef.current?.scrollIntoView({behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth', block: 'start'});
      detailRef.current?.focus({preventScroll: true});
    }
  }

  return <div className="workspace sample-workspace">
    <a className="skip-link" href="#main">Skip to workspace</a>
    <aside className="sidebar" aria-label="Workspace navigation">
      <a className="brand" href="#" onClick={event => {event.preventDefault(); changeView('portfolio');}} aria-label="Trimmy portfolio"><span className="brand-mark"><span/></span>trimmy<span className="brand-period">.</span></a>
      <div className="workspace-label"><span className="workspace-avatar">Y</span><span>Your workspace<small>Practice portfolio</small></span></div>
      <nav className="navigation" aria-label="Main">{(['portfolio', 'watchlist', 'explore'] as const).map(item => <button key={item} className={`nav-item ${view === item ? 'active' : ''}`} aria-current={view === item ? 'page' : undefined} onClick={() => changeView(item)}><Icon name={item === 'portfolio' ? 'portfolio' : item === 'watchlist' ? 'star' : 'compass'}/><span>{sectionNames[item]}</span>{item === 'watchlist' && <span className="nav-count">{watchlist.length}</span>}</button>)}</nav>
      <div className="sidebar-bottom"><div className="practice-note"><span className="practice-symbol">↗</span><strong>Room to get familiar.</strong><p>Explore companies and follow your interests in a practice workspace.</p><button onClick={() => dialogRef.current?.showModal()}>About practice <Icon name="arrow" size={16}/></button></div><div className="sidebar-footer"><span className="small-dot"/>{account.auth.authenticated ? 'Account workspace' : 'Local workspace'}</div></div>
    </aside>

    <div className="workspace-body">
      <header className="topbar"><div className="breadcrumb">Sample <Icon name="chevron" size={12}/><span>{sectionNames[view]}</span></div><label className="search-field"><Icon name="search" size={18}/><input ref={searchRef} type="search" value={query} onChange={event => setQuery(event.target.value)} onKeyDown={event => {if (event.key === 'Escape') setQuery('');}} placeholder={view === 'portfolio' ? 'Search your holdings' : 'Search companies or symbols'} aria-label="Search companies or symbols"/><kbd>/</kbd></label><button className="practice-badge" onClick={() => dialogRef.current?.showModal()}><span className="practice-dot"/>Sample workspace<Icon name="info" size={15}/></button><button className="workspace-switch" onClick={onExit}>Back to stocks</button></header>
      <div className="disclosure">Fictional companies and sample prices. No real assets or money.<button onClick={() => dialogRef.current?.showModal()}>Learn more</button></div>
      <AccountBar account={account} guestIds={guestWatchlist} scope="sample"/>
      {storageWarning && <div className="storage-warning" role="status">{storageWarning}<button aria-label="Dismiss storage notice" onClick={() => setStorageWarning(null)}><Icon name="close" size={16}/></button></div>}

      <div className="content-grid">
        <main id="main" className="main-content">
          <div className="page-heading"><div><h1>Sample {sectionNames[view].toLowerCase()}</h1><p>{view === 'portfolio' ? 'Your investments, at a glance.' : view === 'watchlist' ? `${watchlist.length} companies you’re keeping an eye on.` : 'Get to know the companies in this practice market.'}</p></div><span className="sample-date">Sample snapshot <strong>Sep 11, 2026</strong></span></div>
          <section className="portfolio-overview" aria-labelledby="overview-title">
            <div className="overview-top"><div><h2 id="overview-title" className="value-label">{view === 'portfolio' ? 'Portfolio value' : `${selected.name} · ${selected.symbol}`}</h2><div className="big-value">{money(endValue)}<span>USD</span></div><div className={`value-change ${delta < 0 ? 'negative' : ''}`}><Icon name="arrow" size={16}/><strong>{delta >= 0 ? '+' : '−'}{money(Math.abs(delta))} ({percent(changeBps)})</strong><span>{rangeNames[range]}</span></div></div>{view === 'portfolio' && <div className="overview-note"><span>Total return</span><strong>+{money(totalValue - totalCost)}</strong><small>Across all practice holdings</small></div>}</div>
            <div className="range-toolbar"><div className="chart-legend"><span className="small-dot"/>{view === 'portfolio' ? 'Your portfolio' : selected.symbol}</div><div className="range-buttons" aria-label="Chart time range">{CHART_RANGES.map(item => <button key={item} aria-pressed={range === item} onClick={() => setRange(item)}>{item}</button>)}</div></div>
            <PriceChart key={`${view}-${view === 'portfolio' ? 'all' : selected.id}-${range}`} points={points} title={`${view === 'portfolio' ? 'Portfolio' : selected.name} sample value chart. Use left and right arrow keys to inspect values.`}/>
          </section>

          {view === 'portfolio' && <section className="allocation" aria-label="Portfolio allocation"><div className="allocation-title"><h2>Where you’re invested</h2><span>4 sectors</span></div><div className="allocation-bar">{sectorValues.map((item, index) => <button key={item.name} style={{width: `${item.value / totalValue * 100}%`, background: ['#006344', '#B7CAA6', '#D7D6E9', '#F3BB2C'][index]}} aria-label={`Filter ${item.name}, ${(item.value / totalValue * 100).toFixed(1)} percent`} onClick={() => setSector(sector === item.name ? 'All sectors' : item.name)}/>)}</div><div className="allocation-legend">{sectorValues.map((item, index) => <button key={item.name} aria-pressed={sector === item.name} onClick={() => setSector(sector === item.name ? 'All sectors' : item.name)}><span style={{background: ['#006344', '#B7CAA6', '#D7D6E9', '#F3BB2C'][index]}}/>{item.name}<strong>{Math.round(item.value / totalValue * 100)}%</strong></button>)}</div></section>}

          <section className="holdings" aria-labelledby="holdings-heading"><div className="holdings-heading"><h2 id="holdings-heading">{view === 'portfolio' ? 'Your holdings' : view === 'watchlist' ? 'Following' : 'All companies'}<span>{rows.length}</span></h2><div className="table-controls"><label><span className="sr-only">Filter by sector</span><select aria-label="Filter by sector" value={sector} onChange={event => setSector(event.target.value as Sector | 'All sectors')}><option>All sectors</option>{SECTORS.map(item => <option key={item}>{item}</option>)}</select></label><label><span className="sr-only">Sort companies</span><select aria-label="Sort companies" value={sort} onChange={event => setSort(event.target.value as SortOrder)}><option value="value">Market value</option><option value="name">Name</option><option value="gainers">Top movers</option><option value="price">Share price</option></select></label></div></div>
            {rows.length > 0 ? <div className="table-scroll"><table><thead><tr><th scope="col">Company</th><th scope="col">Price</th><th scope="col">Today</th><th scope="col" className="trend-column">Price trend</th><th scope="col">{view === 'portfolio' ? 'Market value' : 'Sector'}</th><th scope="col"><span className="sr-only">Watchlist</span></th></tr></thead><tbody>{rows.map(stock => <tr key={stock.id} className={selected.id === stock.id ? 'selected-row' : ''}><td><button className="asset-link" onClick={() => select(stock)} aria-label={`View ${stock.name}`} aria-pressed={selected.id === stock.id}><StockMark stock={stock}/><span><strong>{stock.name}</strong><small>{stock.symbol}</small></span></button></td><td><strong>{money(stock.priceCents)}</strong></td><td className={stock.dayChangeBps < 0 ? 'negative' : 'positive'}>{percent(stock.dayChangeBps)}</td><td className="trend-column"><Sparkline stock={stock}/></td><td>{view === 'portfolio' ? <><strong>{money(holdingValueCents(stock))}</strong><small className="quantity">{stock.quantityMilli / 1000} shares</small></> : <span className="table-sector">{stock.sector}</span>}</td><td><button className={`watch-button ${watchlist.includes(stock.id) ? 'watched' : ''}`} aria-label={`${watchlist.includes(stock.id) ? 'Remove' : 'Add'} ${stock.name} ${watchlist.includes(stock.id) ? 'from' : 'to'} watchlist`} aria-pressed={watchlist.includes(stock.id)} disabled={!canEditWatchlist} onClick={() => toggle(stock)}><Icon name="star" size={19} filled={watchlist.includes(stock.id)}/></button></td></tr>)}</tbody></table></div> : <div className="empty-state"><span><Icon name={view === 'watchlist' && watchlist.length === 0 ? 'star' : 'search'} size={26}/></span><h3>{view === 'watchlist' && watchlist.length === 0 ? 'A little space for your next idea.' : 'No matching companies'}</h3><p>{view === 'watchlist' && watchlist.length === 0 ? 'Save a company to follow its sample price and find it here.' : 'Try a different name, symbol or sector.'}</p><button className="primary-button" onClick={() => {if (view === 'watchlist' && watchlist.length === 0) changeView('explore'); else {setQuery(''); setSector('All sectors');}}}>{view === 'watchlist' && watchlist.length === 0 ? 'Explore companies' : 'Clear filters'}</button></div>}
            <div className="table-footnote"><span>All prices in USD. This is fictional sample data.</span>{view === 'watchlist' && <button disabled={!canEditWatchlist} onClick={() => {if (updateWatchlist([...DEFAULT_WATCHLIST])) setAnnouncement('Sample watchlist restored.');}}>Reset watchlist</button>}</div>
          </section>
        </main>

        <aside ref={detailRef} className="security-detail" tabIndex={-1} aria-label={`${selected.name} details`}><div className="detail-topline"><span>In focus</span><span className="sample-pill">Sample stock</span></div><div className="detail-company"><StockMark stock={selected} large/><button className={`watch-button ${isWatched ? 'watched' : ''}`} aria-label={`${isWatched ? 'Remove' : 'Add'} focused ${selected.name} ${isWatched ? 'from' : 'to'} watchlist`} aria-pressed={isWatched} disabled={!canEditWatchlist} onClick={() => toggle(selected)}><Icon name="star" filled={isWatched}/></button></div><h2>{selected.name}</h2><div className="security-meta">{selected.symbol}<span/>{selected.sector}</div><div className="detail-value">{money(selected.priceCents)}</div><p className={`detail-change ${selected.dayChangeBps < 0 ? 'negative' : 'positive'}`}>{percent(selected.dayChangeBps)} <span>today</span></p><PriceChart key={`${selected.id}-${range}`} compact points={chartSeries(selected, range)} title={`${selected.name} ${range} sample price chart`}/><button className={`watchlist-action ${isWatched ? 'is-watched' : ''}`} disabled={!canEditWatchlist} onClick={() => toggle(selected)}><Icon name={isWatched ? 'check' : 'plus'} size={18}/>{isWatched ? 'On your watchlist' : 'Add to watchlist'}</button>
          {selected.quantityMilli > 0 ? <section className="position"><h3>Your position</h3><div><span>Market value</span><strong>{money(holdingValueCents(selected))}</strong></div><div><span>Shares</span><strong>{selected.quantityMilli / 1000}</strong></div><div><span>Total return</span><strong className={holdingValueCents(selected) >= selected.costBasisCents ? 'positive' : 'negative'}>{holdingValueCents(selected) >= selected.costBasisCents ? '+' : '−'}{money(Math.abs(holdingValueCents(selected) - selected.costBasisCents))}</strong></div></section> : <div className="no-position">You don’t hold this sample stock. Add it to your watchlist to keep it close.</div>}
          <section className="key-stats"><h3>Key stats</h3><dl><div><dt>Market cap</dt><dd>{selected.marketCap}</dd></div><div><dt>Daily volume</dt><dd>{selected.volume}</dd></div><div><dt>52-week low</dt><dd>{money(selected.yearLowCents)}</dd></div><div><dt>52-week high</dt><dd>{money(selected.yearHighCents)}</dd></div></dl><div className="year-range"><span style={{'--position': `${Math.max(0, Math.min(100, (selected.priceCents - selected.yearLowCents) / (selected.yearHighCents - selected.yearLowCents) * 100))}%`} as CSSProperties}/></div></section>
          <section className="about-company"><h3>About {selected.name.split(' ')[0]}</h3><p>{selected.description}</p><span>Fictional company profile</span></section>
        </aside>
      </div>
    </div>
    <div className="sr-only" role="status" aria-live="polite">{announcement}</div>
    <dialog ref={dialogRef} className="practice-dialog" aria-labelledby="practice-title"><button className="dialog-close" aria-label="Close practice information" onClick={() => dialogRef.current?.close()} autoFocus><Icon name="close"/></button><span className="dialog-mark"><Icon name="compass" size={30}/></span><h2 id="practice-title">A space to explore.</h2><p>This workspace uses invented companies, sample holdings and fictional prices. Your portfolio is an example, and no real assets or money are involved.</p><p>Search companies, explore price ranges and build a watchlist. {account.auth.authenticated ? 'Your account watchlist saves in this browser and syncs across devices. Its save status is shown above.' : 'Your local watchlist is saved in this browser.'}</p><button className="primary-button" onClick={() => dialogRef.current?.close()}>Back to workspace</button></dialog>
  </div>;
}
