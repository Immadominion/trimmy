import {useEffect, useMemo, useRef, useState} from 'react';
import type {ProductMarketClient, StockCard, StockFacts, StockInsight, StockInsightPeriod, StockVariant} from './market-client';
import type {PracticeSession} from './practice-session';
import type {PaperPortfolio, PaperPreview, PaperReceipt} from './practice-client';
import {CompanyLogo, Failure, Loading, change, compactUsd, errorCopy, micros, shares, toPaperMicros, usd} from './ui';

const ranges: readonly [StockInsightPeriod, string][] = [['day', '1D'], ['week', '1W'], ['month', '1M'], ['year', '1Y']];

function TokenChart({insight}: {insight: StockInsight}) {
  const [active, setActive] = useState<number | null>(null);
  const points = insight.points;
  useEffect(() => setActive(null), [insight]);
  if (points.length < 2) return <div className="chart-empty"><p>{insight.chartStatus === 'unavailable' ? 'Price history is unavailable right now.' : 'There isn’t enough price history for this period yet.'}</p></div>;
  const values = points.map(point => point.close), low = Math.min(...values), high = Math.max(...values);
  const span = high === low ? Math.max(high * .02, .01) : high - low;
  const coords = points.map((point, index) => ({x: index / (points.length - 1) * 600, y: 192 - (point.close - low) / span * 165}));
  const path = coords.map((point, index) => `${index ? 'L' : 'M'}${point.x.toFixed(2)},${point.y.toFixed(2)}`).join(' ');
  const selected = Math.min(active ?? points.length - 1, points.length - 1);
  const point = points[selected]!, xy = coords[selected]!;
  const label = (seconds: number) => new Date(seconds * 1000).toLocaleDateString('en-US', {month: 'short', day: 'numeric'});
  return <>
    <div className="chart-selected" aria-live="polite">{active === null ? 'Selected token price in USD' : `${usd(point.close)} · ${new Date(point.unixSeconds * 1000).toLocaleString()}`}</div>
    <div className="token-chart" tabIndex={0} role="slider" aria-label="Token price history" aria-valuemin={0} aria-valuemax={points.length - 1} aria-valuenow={selected} aria-valuetext={`${usd(point.close)}, ${label(point.unixSeconds)}`}
      onPointerMove={event => {const rect = event.currentTarget.getBoundingClientRect(); setActive(Math.max(0, Math.min(points.length - 1, Math.round((event.clientX - rect.left) / rect.width * (points.length - 1)))));}}
      onPointerLeave={() => setActive(null)} onBlur={() => setActive(null)} onKeyDown={event => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault(); setActive(event.key === 'Home' ? 0 : event.key === 'End' ? points.length - 1 : Math.max(0, Math.min(points.length - 1, selected + (event.key === 'ArrowRight' ? 1 : -1))));
      }}>
      <svg viewBox="0 0 600 220" preserveAspectRatio="none" aria-hidden="true">
        {[35, 110, 190].map(y => <line key={y} x1="0" x2="600" y1={y} y2={y} stroke="#f0ecf6" strokeDasharray="3 5"/>)}
        <path d={path} fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinejoin="round" vectorEffect="non-scaling-stroke"/>
        {active !== null && <><line x1={xy.x} x2={xy.x} y1="10" y2="210" stroke="#cdbde9" strokeDasharray="3 4"/><circle cx={xy.x} cy={xy.y} r="4" fill="currentColor" stroke="#fff" strokeWidth="2"/></>}
      </svg>
    </div><div className="chart-dates"><span>{label(points[0]!.unixSeconds)}</span><span>{label(points.at(-1)!.unixSeconds)}</span></div>
  </>;
}

export interface StockScreenProps {
  readonly assetId: string; readonly card?: StockCard; readonly selectedMint?: string;
  readonly market: ProductMarketClient; readonly session: PracticeSession;
  readonly portfolio: PaperPortfolio | null; readonly onBack: () => void; readonly onDesk: () => void;
  readonly ensureDesk: () => Promise<void>; readonly onCommitted: (receipt: PaperReceipt) => Promise<void>;
  readonly onPending: () => void;
}

export function StockScreen(props: StockScreenProps) {
  const {assetId, card, selectedMint, market} = props;
  const [facts, setFacts] = useState<StockFacts | null>(null);
  const [variants, setVariants] = useState<readonly StockVariant[]>([]);
  const [mint, setMint] = useState<string | null>(selectedMint ?? card?.primaryVariant?.mint ?? null);
  const [period, setPeriod] = useState<StockInsightPeriod>('day');
  const [insight, setInsight] = useState<StockInsight | null>(null);
  const [busy, setBusy] = useState(true), [chartBusy, setChartBusy] = useState(false);
  const [error, setError] = useState<unknown>(null), [chartError, setChartError] = useState<unknown>(null);
  const [revision, setRevision] = useState(0), [chartRevision, setChartRevision] = useState(0);
  const [clock, setClock] = useState(Date.now());
  useEffect(() => {const timer = window.setInterval(() => setClock(Date.now()), 5000); return () => clearInterval(timer);}, []);
  useEffect(() => {
    const controller = new AbortController(); setBusy(true); setError(null);
    void Promise.allSettled([market.facts(assetId, {signal: controller.signal}), market.variants(assetId, {signal: controller.signal})]).then(([company, token]) => {
      if (controller.signal.aborted) return;
      if (company.status === 'fulfilled') setFacts(company.value);
      if (token.status === 'fulfilled') {
        setVariants(token.value.variants);
        setMint(previous => token.value.variants.some(v => v.mint === previous) ? previous : token.value.variants.find(v => v.advisory === null)?.mint ?? token.value.variants[0]?.mint ?? null);
      } else setError(token.reason);
      if (company.status === 'rejected' && token.status === 'rejected') setError(company.reason);
      setBusy(false);
    });
    return () => controller.abort();
  }, [market, assetId, revision]);
  useEffect(() => {
    setInsight(null); setChartError(null);
    if (!mint) return;
    const controller = new AbortController(); setChartBusy(true);
    void market.insight({assetId, mint, period}, {signal: controller.signal}).then(value => {
      if (!controller.signal.aborted) setInsight(value);
    }).catch(reason => {if (!controller.signal.aborted) setChartError(reason);}).finally(() => {if (!controller.signal.aborted) setChartBusy(false);});
    return () => controller.abort();
  }, [market, assetId, mint, period, chartRevision]);
  const variant = variants.find(v => v.mint === mint) ?? null;
  const name = facts?.name ?? card?.name ?? assetId.replaceAll('-', ' ');
  return <>
    <button className="company-back" onClick={props.onBack}>← Back to Market</button>
    <div className="company-layout"><section className="company-reading">
      <div className="company-heading"><CompanyLogo name={name} url={facts?.imageUrl ?? card?.imageUrl ?? null} large/><div><h1>{name}</h1><p>{facts?.symbol ?? card?.symbol ?? 'Company'}{variant ? ` / ${variant.label ?? variant.symbol ?? 'Selected token'}` : ''}</p></div></div>
      <div className="company-price">{chartBusy ? '…' : usd(insight?.priceUsd)}</div>
      <p className="company-price-caption">{insight?.changePercent24h != null && <span className={insight.changePercent24h < 0 ? 'negative' : 'positive'}>{change(insight.changePercent24h)} today</span>}Selected token · USD reference</p>
      <div className="range-picker" aria-label="Chart period">{ranges.map(([value, label]) => <button key={value} aria-pressed={period === value} onClick={() => setPeriod(value)}>{label}</button>)}<button aria-label="Refresh chart" onClick={() => setChartRevision(n => n + 1)}>↻</button></div>
      {chartBusy ? <div className="chart-empty"><Loading>Getting price history…</Loading></div> : insight ? <TokenChart insight={insight}/> : <div className="chart-empty"><p>Price history is unavailable right now.</p>{chartError !== null && <button className="text-button" onClick={() => setChartRevision(n => n + 1)}>Try again</button>}</div>}
      {busy && <Loading>Getting company details…</Loading>}
      {error !== null && <Failure message={errorCopy(error)} onRetry={() => setRevision(n => n + 1)}/>}
      {variants.length > 0 && <><label className="sr-only" htmlFor="token-version">Token version</label><select id="token-version" className="token-select" value={mint ?? ''} onChange={event => setMint(event.target.value)}>{variants.map(v => <option key={v.mint} value={v.mint}>{v.symbol ?? v.name ?? v.variantId} · {v.label ?? v.issuer ?? 'Token'}</option>)}</select></>}
      {variant?.advisory && <div className="notice warning"><strong>Token caution</strong><p>{variant.advisory.reason}</p></div>}
      <div className="company-section"><h2>About {name}</h2><p>{facts?.description ?? insight?.description ?? 'A company description is not available right now.'}</p></div>
      {insight && <dl className="company-metrics"><div><dt>Token trading volume · 24h</dt><dd>{compactUsd(insight.volume24hUsd)}</dd></div><div><dt>Token liquidity</dt><dd>{compactUsd(insight.liquidityUsd)}</dd></div><div><dt>Token holders</dt><dd>{insight.holders?.toLocaleString() ?? 'Unavailable'}</dd></div><div><dt>Company market cap</dt><dd>{compactUsd(insight.stockMarketCapUsd)}</dd></div></dl>}
      <p className="source-note">Data from Tokens.xyz. {insight ? `Checked ${new Date(insight.observedAt).toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})}. ${Date.parse(insight.refreshAfter) <= clock ? 'Prices may have changed; refresh for a new read. ' : ''}` : ''}Reference prices are for research. Your paper order gets its own current quote.{mint ? <><br/>Selected token: {mint}</> : null}</p>
    </section>
    {variant ? <TradePanel key={`${assetId}:${variant.mint}`} {...props} variant={variant} name={name}/> : <aside className="trade-panel"><h2>Practice a move.</h2><p className="trade-caption">A supported token and a current quote are needed to review a paper order.</p></aside>}
    </div>
  </>;
}

function TradePanel({assetId, variant, name, session, portfolio, ensureDesk, onCommitted, onPending, onDesk}: StockScreenProps & {variant: StockVariant; name: string}) {
  const position = portfolio?.positions.find(p => p.assetId === assetId && p.variantMint === variant.mint && BigInt(p.quantityMicros) > 0n);
  const [action, setAction] = useState<'buy' | 'sell'>('buy');
  const [amount, setAmount] = useState('100');
  const [preview, setPreview] = useState<PaperPreview | null>(null);
  const [receipt, setReceipt] = useState<PaperReceipt | null>(null);
  const [busy, setBusy] = useState(false), [error, setError] = useState<unknown>(null);
  const [clock, setClock] = useState(Date.now());
  const locked = useRef(false), mounted = useRef(true);
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  useEffect(() => {if (!preview) return; const id = window.setInterval(() => setClock(Date.now()), 1000); return () => clearInterval(id);}, [preview]);
  const remaining = preview ? Math.max(0, Math.ceil((Date.parse(preview.expiresAt) - clock) / 1000)) : 0;
  const quantity = useMemo(() => {
    if (action === 'buy') return toPaperMicros(amount);
    if (!/^(?:0|[1-9]\d{0,8})(?:\.\d{1,6})?$/.test(amount)) return null;
    const [whole, fraction = ''] = amount.split('.');
    const value = BigInt(whole!) * 1_000_000n + BigInt(fraction.padEnd(6, '0'));
    return value > 0n ? value.toString() : null;
  }, [action, amount]);
  async function review() {
    if (locked.current || !quantity) return; locked.current = true; setBusy(true); setError(null);
    try {
      await ensureDesk();
      if (!mounted.current) return;
      const result = await session.previewOrder({action, assetId, variantMint: variant.mint,
        amount: action === 'buy' ? {kind: 'paper_amount', paperMicros: quantity} : {kind: 'share_quantity', quantityMicros: quantity}});
      if (mounted.current) {setPreview(result); setClock(Date.now());}
    } catch (reason) {if (mounted.current) setError(reason);}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  async function confirm() {
    if (locked.current || !preview || Date.parse(preview.expiresAt) <= Date.now()) return;
    locked.current = true; setBusy(true); setError(null);
    try {
      const result = await session.commitOrder(preview);
      if (mounted.current) {setReceipt(result); setPreview(null);}
      await onCommitted(result);
    } catch (reason) {if (mounted.current) setError(reason); onPending();}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  function mode(next: 'buy' | 'sell') {if (busy) return; setAction(next); setAmount(next === 'buy' ? '100' : position ? micros(position.quantityMicros, 6).replaceAll(',', '') : ''); setPreview(null); setError(null);}
  const unavailable = variant.advisory !== null;
  return <aside className="trade-panel" aria-label="Paper order">
    {receipt ? <><div className="receipt-mark" aria-hidden="true">✓</div><h2>{receipt.action === 'buy' ? 'Your move is made.' : 'Sale confirmed.'}</h2><p className="receipt-text">{receipt.action === 'buy' ? 'Bought' : 'Sold'} {shares(receipt.quantityMicros)} shares of {name}.</p><dl className="review-summary"><div><dt>Paper {receipt.action === 'buy' ? 'spent' : 'received'}</dt><dd>{micros(receipt.action === 'buy' ? receipt.cashDebitPaperMicros : receipt.cashCreditPaperMicros)}</dd></div><div><dt>Paper cash left</dt><dd>{micros(receipt.cashAfterPaperMicros)}</dd></div></dl><button className="primary full" onClick={onDesk}>Back to your desk</button><button className="text-button full" onClick={() => {setReceipt(null); setError(null);}}>Make another move</button><p className="trade-disclosure">Confirmed paper order. No real money was moved.</p></>
    : preview ? <><h2>Review your {preview.action}.</h2><p className="trade-caption">{name} · {variant.symbol ?? preview.symbol}</p><dl className="review-summary"><div><dt>Shares</dt><dd>{shares(preview.quantityMicros)}</dd></div><div><dt>Price per share</dt><dd>{micros(preview.pricePaperMicros)} paper</dd></div><div><dt>Fees</dt><dd>0.00 paper</dd></div><div className="review-total"><dt>Paper {action === 'buy' ? 'to spend' : 'to receive'}</dt><dd>{micros(action === 'buy' ? preview.cashDebitPaperMicros : preview.cashCreditPaperMicros)}</dd></div><div><dt>Paper cash after</dt><dd>{micros(preview.cashAfterPaperMicros)}</dd></div></dl>
      <button className="primary full" disabled={busy || remaining === 0 || session.pendingCommit !== null} onClick={() => void confirm()}>{busy ? 'Confirming…' : `Confirm paper ${action}`}</button><p className="quote-clock">{remaining > 0 ? `Quote expires in ${remaining}s` : 'Quote expired. Get a new review.'}</p><button className="text-button full" disabled={busy} onClick={() => {setPreview(null); setError(null);}}>{remaining ? 'Edit amount' : 'Get a new quote'}</button></>
    : <><div className="trade-mode"><button aria-pressed={action === 'buy'} disabled={busy} onClick={() => mode('buy')}>Buy</button><button aria-pressed={action === 'sell'} disabled={busy || !position} onClick={() => mode('sell')}>Sell</button></div><h2>{action === 'buy' ? 'Make your move.' : 'Take a little back.'}</h2><p className="trade-caption">{action === 'buy' ? `Practice buying ${name}.` : `You hold ${shares(position?.quantityMicros ?? '0')} shares.`}</p>
      <label className="amount-label" htmlFor="order-amount">{action === 'buy' ? 'Amount to spend' : 'Shares to sell'}</label><div className="amount-field"><input id="order-amount" inputMode="decimal" autoComplete="off" value={amount} maxLength={18} disabled={busy} onChange={event => setAmount(event.target.value)} aria-describedby="order-unit"/><span id="order-unit">{action === 'buy' ? 'paper' : 'shares'}</span></div>
      <div className="amount-options">{action === 'buy' ? ['50', '100', '500'].map(value => <button key={value} disabled={busy} onClick={() => setAmount(value)}>{value}</button>) : <>{[25, 50].map(percent => <button key={percent} disabled={busy || !position} onClick={() => setAmount(micros((BigInt(position!.quantityMicros) * BigInt(percent) / 100n).toString(), 6).replaceAll(',', ''))}>{percent}%</button>)}<button disabled={busy || !position} onClick={() => setAmount(micros(position!.quantityMicros, 6).replaceAll(',', ''))}>Max</button></>}</div>
      {unavailable ? <p className="trade-error">Paper orders are unavailable while this token has a provider caution.</p> : <button className="primary full" disabled={busy || !quantity || session.pendingCommit !== null} onClick={() => void review()}>{busy ? 'Getting your quote…' : `Review paper ${action}`}</button>}
      <p className="trade-available">{portfolio ? `${micros(portfolio.cashPaperMicros)} paper available` : session.hasIdentity ? 'Paper balance unavailable. Refresh your desk.' : 'Start with 10,000 paper. No sign-in needed.'}</p></>}
    {error !== null && <p className="trade-error" role="alert">{errorCopy(error)}</p>}
    {session.pendingCommit !== null && <div className="trade-error">An order still needs checking.<button className="text-button full" onClick={onDesk}>Check it from your desk</button></div>}
  </aside>;
}
