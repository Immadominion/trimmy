import {useEffect, useMemo, useRef, useState} from 'react';
import type {ProductMarketClient, StockCard, StockFacts, StockInsight, StockInsightPeriod, StockVariant} from './market-client';
import type {PracticeSession} from './practice-session';
import type {PaperPortfolio, PaperPreview, PaperReceipt} from './practice-client';
import {CompanyLogo, Failure, Loading, change, compactUsd, errorCopy, micros, paperPlain, shares, toPaperMicros, usd} from './ui';
import * as fmt from '../i18n/format';
import {useT} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';
import {useMoney} from './money/money-api';
import {discoveryRefs} from './money/market-tradeable';
import {LiveOrderPanel} from './money/live-order-panel';
import {marketLabel, type VariantOption} from './money/live-trading';
import {CompanyFollow, CompanySections, type CompanySocial} from './company-social';
import {shareCount} from './market-social';

const ranges: readonly [StockInsightPeriod, MessageKey][] = [['day', 'market.stock.period.day'], ['week', 'market.stock.period.week'],
  ['month', 'market.stock.period.month'], ['year', 'market.stock.period.year']];

function TokenChart({insight}: {insight: StockInsight}) {
  const tr = useT();
  const [active, setActive] = useState<number | null>(null);
  const points = insight.points;
  useEffect(() => setActive(null), [insight]);
  if (points.length < 2) return <div className="chart-empty"><p>{tr(insight.chartStatus === 'unavailable' ? 'market.stock.chartUnavailable' : 'market.stock.chartTooShort')}</p></div>;
  const values = points.map(point => point.close), low = Math.min(...values), high = Math.max(...values);
  const span = high === low ? Math.max(high * .02, .01) : high - low;
  const coords = points.map((point, index) => ({x: index / (points.length - 1) * 600, y: 192 - (point.close - low) / span * 165}));
  const path = coords.map((point, index) => `${index ? 'L' : 'M'}${point.x.toFixed(2)},${point.y.toFixed(2)}`).join(' ');
  const selected = Math.min(active ?? points.length - 1, points.length - 1);
  const point = points[selected]!, xy = coords[selected]!;
  const label = (seconds: number) => fmt.date(seconds * 1000, 'en-US', {month: 'short', day: 'numeric'});
  return <>
    <div className="chart-selected" aria-live="polite">{active === null ? tr('market.stock.chartHint') : tr('market.stock.chartPoint', {price: usd(point.close), time: fmt.dateTime(point.unixSeconds * 1000, undefined)})}</div>
    <div className="token-chart" tabIndex={0} role="slider" aria-label={tr('market.stock.chartLabel')} aria-valuemin={0} aria-valuemax={points.length - 1} aria-valuenow={selected} aria-valuetext={tr('market.stock.chartValue', {price: usd(point.close), date: label(point.unixSeconds)})}
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
  /** Mobile's Follow, Holders and Comments (company-social.tsx). */
  readonly social?: CompanySocial;
  /** Real mode: leave for Paper when this company has no token to trade with real money. */
  readonly onPracticeInPaper?: () => void;
}

/** Every Market version of the company in Real mode: tradeable ones first, the rest with the reason. */
function LiveVersions({options, selected, onSelect}: {options: readonly VariantOption[]; selected: string | null; onSelect(mint: string): void}) {
  const tr = useT();
  return <fieldset className="live-versions"><legend>{tr('market.stock.versions')}</legend>{options.map(option => <label key={option.mint} className={`live-version${option.asset ? '' : ' refused'}`}>
    <input type="radio" name="live-version" value={option.mint} checked={selected === option.mint} disabled={!option.asset} onChange={() => onSelect(option.mint)}/>
    <span><strong>{option.label}</strong><small className={option.tradeable ? 'tradeable' : ''}>{option.tradeable
      ? option.asset?.market?.usSessions ? marketLabel(option.asset.market) : tr('market.stock.versionTradeable') : option.reason ?? tr('market.stock.versionUnavailable')}</small></span>
  </label>)}</fieldset>;
}

export function StockScreen(props: StockScreenProps) {
  const {assetId, card, selectedMint, market} = props;
  const tr = useT();
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
  const money = useMoney();
  // Opening a company reads the token list again, as mobile does, so a list that was stale corrects itself.
  useEffect(() => {if (money.real) void money.refreshCapabilities(true);}, [money.real, money.refreshCapabilities, assetId]);
  const discovery = busy && !variants.length ? null : discoveryRefs(variants);
  const liveOptions = money.real && money.capabilities?.enabled && discovery ? money.capabilities.optionsFor(assetId, discovery, facts?.symbol ?? card?.symbol ?? assetId) : null;
  // The token chosen here, else the most liquid tradeable one; never another issuer's token by accident.
  const liveMint = liveOptions ? liveOptions.find(option => option.asset && option.mint === mint)?.mint ??
    liveOptions.find(option => option.tradeable)?.mint ?? liveOptions.find(option => option.asset)?.mint ?? null : null;
  useEffect(() => {if (liveMint && liveMint !== mint) setMint(liveMint);}, [liveMint]);
  return <>
    <button className="company-back" onClick={props.onBack}>{tr('market.stock.back')}</button>
    <div className="company-layout"><section className="company-reading">
      <div className="company-heading"><CompanyLogo name={name} url={facts?.imageUrl ?? card?.imageUrl ?? null} large/><div><h1>{name}</h1><p>{facts?.symbol ?? card?.symbol ?? tr('market.stock.symbolFallback')}{variant ? ` / ${variant.label ?? variant.symbol ?? tr('market.stock.tokenFallback')}` : ''}</p></div>
        {props.social && <CompanyFollow card={card ?? {assetId, name, symbol: facts?.symbol ?? null, imageUrl: facts?.imageUrl ?? null, stock: facts?.stock ?? null, primaryVariant: null}} social={props.social}/>}</div>
      <div className="company-price">{chartBusy ? '…' : usd(insight?.priceUsd)}</div>
      <p className="company-price-caption">{insight?.changePercent24h != null && <span className={insight.changePercent24h < 0 ? 'negative' : 'positive'}>{tr('market.stock.changeToday', {change: change(insight.changePercent24h)})}</span>}{tr('market.stock.priceCaption')}</p>
      <div className="range-picker" aria-label={tr('market.stock.periodLabel')}>{ranges.map(([value, label]) => <button key={value} aria-pressed={period === value} onClick={() => setPeriod(value)}>{tr(label)}</button>)}<button aria-label={tr('market.stock.refreshChart')} onClick={() => setChartRevision(n => n + 1)}>↻</button></div>
      {chartBusy ? <div className="chart-empty"><Loading>{tr('market.stock.chartLoading')}</Loading></div> : insight ? <TokenChart insight={insight}/> : <div className="chart-empty"><p>{tr('market.stock.chartUnavailable')}</p>{chartError !== null && <button className="text-button" onClick={() => setChartRevision(n => n + 1)}>{tr('common.tryAgain')}</button>}</div>}
      {busy && <Loading>{tr('market.stock.detailsLoading')}</Loading>}
      {error !== null && <Failure message={errorCopy(error)} onRetry={() => setRevision(n => n + 1)}/>}
      {liveOptions && liveOptions.length > 0 ? <LiveVersions options={liveOptions} selected={liveMint} onSelect={setMint}/>
      : variants.length > 0 && <><label className="sr-only" htmlFor="token-version">{tr('market.stock.versionLabel')}</label><select id="token-version" className="token-select" value={mint ?? ''} onChange={event => setMint(event.target.value)}>{variants.map(v => <option key={v.mint} value={v.mint}>{v.symbol ?? v.name ?? v.variantId} · {v.label ?? v.issuer ?? tr('market.stock.versionFallback')}</option>)}</select></>}
      {variant?.advisory && <div className="notice warning"><strong>{tr('market.stock.cautionTitle')}</strong><p>{variant.advisory.reason}</p></div>}
      <div className="company-section"><h2>{tr('market.stock.about', {name})}</h2><p>{facts?.description ?? insight?.description ?? tr('market.stock.noDescription')}</p></div>
      {insight && <dl className="company-metrics"><div><dt>{tr('market.stock.volume')}</dt><dd>{compactUsd(insight.volume24hUsd)}</dd></div><div><dt>{tr('market.stock.liquidity')}</dt><dd>{compactUsd(insight.liquidityUsd)}</dd></div><div><dt>{tr('market.stock.holders')}</dt><dd>{insight.holders === null ? tr('common.unavailable') : fmt.integer(insight.holders)}</dd></div><div><dt>{tr('market.stock.marketCap')}</dt><dd>{compactUsd(insight.stockMarketCapUsd)}</dd></div></dl>}
      {props.social && mint && <CompanySections assetId={assetId} mint={mint} social={props.social}/>}
      <p className="source-note">{[tr('market.stock.source'),
        ...(insight ? [tr('market.stock.checked', {time: fmt.time(insight.observedAt, [], {hour: '2-digit', minute: '2-digit'})}),
          ...(Date.parse(insight.refreshAfter) <= clock ? [tr('market.stock.stale')] : [])] : []),
        tr('market.stock.reference'), tr(money.real ? 'market.stock.realQuote' : 'market.stock.paperQuote')].join(' ')}{mint ? <><br/>{tr('market.stock.selectedToken', {mint})}</> : null}</p>
    </section>
    {money.real ? liveOptions && !liveOptions.some(option => option.asset)
      ? <aside className="trade-panel live"><p className="money-badge real">{tr('market.stock.realBadge')}</p><h2>{tr('market.stock.realUnavailableTitle')}</h2>
        <p className="trade-caption">{liveOptions.length === 1 ? liveOptions[0]!.reason : tr('market.stock.realUnavailableBody')}</p>
        {props.onPracticeInPaper && <button className="secondary full" onClick={props.onPracticeInPaper}>{tr('market.stock.practiceInPaper')}</button>}</aside>
      : <LiveOrderPanel key={`${assetId}:${liveMint ?? ''}`} assetId={assetId} mint={liveMint} companyName={name} discovery={discovery}
        {...(props.onPracticeInPaper ? {onPracticeInPaper: props.onPracticeInPaper} : {})}/>
    : variant ? <TradePanel key={`${assetId}:${variant.mint}`} {...props} variant={variant} name={name}/> : <aside className="trade-panel"><h2>{tr('market.stock.noTokenTitle')}</h2><p className="trade-caption">{tr('market.stock.noTokenBody')}</p></aside>}
    </div>
  </>;
}

function TradePanel({assetId, variant, name, session, portfolio, ensureDesk, onCommitted, onPending, onDesk}: StockScreenProps & {variant: StockVariant; name: string}) {
  const tr = useT();
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
    const typed = fmt.normalizeDecimalInput(amount);
    if (!/^(?:0|[1-9]\d{0,8})(?:\.\d{1,6})?$/.test(typed)) return null;
    const [whole, fraction = ''] = typed.split('.');
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
  function mode(next: 'buy' | 'sell') {if (busy) return; setAction(next); setAmount(next === 'buy' ? '100' : position ? fmt.decimalInput(paperPlain(position.quantityMicros, 6).replaceAll(',', '')) : ''); setPreview(null); setError(null);}
  const unavailable = variant.advisory !== null;
  return <aside className="trade-panel" aria-label={tr('market.trade.panelLabel')}>
    {receipt ? <><div className="receipt-mark" aria-hidden="true">✓</div><h2>{tr(receipt.action === 'buy' ? 'market.trade.receiptBuyTitle' : 'market.trade.receiptSellTitle')}</h2><p className="receipt-text">{tr('market.trade.receiptShares', {action: receipt.action, shares: shareCount(receipt.quantityMicros), name})}</p><dl className="review-summary"><div><dt>{tr(receipt.action === 'buy' ? 'market.trade.paperSpent' : 'market.trade.paperReceived')}</dt><dd>{micros(receipt.action === 'buy' ? receipt.cashDebitPaperMicros : receipt.cashCreditPaperMicros)}</dd></div><div><dt>{tr('market.trade.cashLeft')}</dt><dd>{micros(receipt.cashAfterPaperMicros)}</dd></div></dl><button className="primary full" onClick={onDesk}>{tr('market.trade.backToDesk')}</button><button className="text-button full" onClick={() => {setReceipt(null); setError(null);}}>{tr('market.trade.another')}</button><p className="trade-disclosure">{tr('market.trade.disclosure')}</p></>
    : preview ? <><h2>{tr('market.trade.reviewTitle', {action: preview.action})}</h2><p className="trade-caption">{name} · {variant.symbol ?? preview.symbol}</p><dl className="review-summary"><div><dt>{tr('market.trade.shares')}</dt><dd>{shares(preview.quantityMicros)}</dd></div><div><dt>{tr('market.trade.pricePerShare')}</dt><dd>{tr('common.paperAmount', {amount: micros(preview.pricePaperMicros)})}</dd></div><div><dt>{tr('market.trade.fees')}</dt><dd>{tr('common.paperAmount', {amount: fmt.number('0.00')})}</dd></div><div className="review-total"><dt>{tr(action === 'buy' ? 'market.trade.toSpend' : 'market.trade.toReceive')}</dt><dd>{micros(action === 'buy' ? preview.cashDebitPaperMicros : preview.cashCreditPaperMicros)}</dd></div><div><dt>{tr('market.trade.cashAfter')}</dt><dd>{micros(preview.cashAfterPaperMicros)}</dd></div></dl>
      <button className="primary full" disabled={busy || remaining === 0 || session.pendingCommit !== null} onClick={() => void confirm()}>{busy ? tr('market.trade.confirming') : tr('market.trade.confirm', {action})}</button><p className="quote-clock">{remaining > 0 ? tr('market.trade.expiresIn', {seconds: remaining}) : tr('market.trade.expired')}</p><button className="text-button full" disabled={busy} onClick={() => {setPreview(null); setError(null);}}>{tr(remaining ? 'market.trade.editAmount' : 'market.trade.newQuote')}</button></>
    : <><div className="trade-mode"><button aria-pressed={action === 'buy'} disabled={busy} onClick={() => mode('buy')}>{tr('market.trade.buy')}</button><button aria-pressed={action === 'sell'} disabled={busy || !position} onClick={() => mode('sell')}>{tr('market.trade.sell')}</button></div><h2>{tr(action === 'buy' ? 'market.trade.buyTitle' : 'market.trade.sellTitle')}</h2><p className="trade-caption">{action === 'buy' ? tr('market.trade.buyCaption', {name}) : tr('market.trade.sellCaption', {shares: shareCount(position?.quantityMicros ?? '0')})}</p>
      <label className="amount-label" htmlFor="order-amount">{tr(action === 'buy' ? 'market.trade.amountToSpend' : 'market.trade.sharesToSell')}</label><div className="amount-field"><input id="order-amount" inputMode="decimal" autoComplete="off" value={amount} maxLength={18} disabled={busy} onChange={event => setAmount(event.target.value)} aria-describedby="order-unit"/><span id="order-unit">{tr(action === 'buy' ? 'common.paperUnit' : 'market.trade.sharesUnit')}</span></div>
      <div className="amount-options">{action === 'buy' ? ['50', '100', '500'].map(value => <button key={value} disabled={busy} onClick={() => setAmount(value)}>{value}</button>) : <>{[25, 50].map(percent => <button key={percent} disabled={busy || !position} onClick={() => setAmount(fmt.decimalInput(paperPlain((BigInt(position!.quantityMicros) * BigInt(percent) / 100n).toString(), 6).replaceAll(',', '')))}>{fmt.percent(`${percent}%`)}</button>)}<button disabled={busy || !position} onClick={() => setAmount(fmt.decimalInput(paperPlain(position!.quantityMicros, 6).replaceAll(',', '')))}>{tr('market.trade.max')}</button></>}</div>
      {unavailable ? <p className="trade-error">{tr('market.trade.caution')}</p> : <button className="primary full" disabled={busy || !quantity || session.pendingCommit !== null} onClick={() => void review()}>{busy ? tr('market.trade.quoting') : tr('market.trade.review', {action})}</button>}
      <p className="trade-available">{portfolio ? tr('market.trade.available', {amount: micros(portfolio.cashPaperMicros)}) : session.hasIdentity ? tr('market.trade.balanceUnavailable') : tr('market.trade.start', {amount: fmt.number('10,000')})}</p></>}
    {error !== null && <p className="trade-error" role="alert">{errorCopy(error)}</p>}
    {session.pendingCommit !== null && !busy && <div className="trade-error">{tr('market.trade.pending')}<button className="text-button full" onClick={onDesk}>{tr('market.trade.pendingCheck')}</button></div>}
  </aside>;
}
