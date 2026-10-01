/**
 * Real-money order entry, review, signing and result for one company's chosen
 * token. Mirrors mobile's LiveOrderFlow: the issuer card and its warning come
 * before the eligibility tick, the review shows the warning, terms, fees and
 * expiry before Confirm, and a signed order is reconciled by its id.
 */
import {useEffect, useId, useMemo, useRef, useState, useSyncExternalStore, type ReactNode} from 'react';
import {amountRaw, percentFromBps, rawDecimal, ShareScale, signedLamports, solLabel, usdcLabel, USDC_DECIMALS} from './amounts.js';
import {explorerUrl, type LiveOrder, type MoneyCopy} from './live-order-client.js';
import {marketHours, marketLabel, uncapped, type DiscoveryVariantRef, type MarketState, type TradingAsset, type TradingCapabilities, type TradingIssuer} from './live-trading.js';
import {useMoney} from './money-api.js';
import type {LiveOrderSession, OrderSessionState} from './order-session.js';
import {coherentHoldings} from './wallet-controller.js';
import {useT} from '../../i18n/react.js';
import type {MessageKey} from '../../i18n/runtime.js';
import * as fmt from '../../i18n/format.js';
import {enterPresses} from '../ui.js';

const idle: OrderSessionState = Object.freeze({phase: 'checking', order: null, notice: null, noticeCopy: null, noticeCode: null, fundingNeeded: false, termsRequired: false});

/** The tradeable token this panel may trade, or why none: never another issuer's token by accident. */
export function resolveLiveAsset(caps: TradingCapabilities, assetId: string, mint: string | null, discovery: readonly DiscoveryVariantRef[] | null): TradingAsset | null {
  const variants = caps.variantsFor(assetId, discovery ?? undefined);
  return variants.find(asset => asset.mint === mint) ?? (mint === null ? variants[0] ?? null : null);
}

export function IssuerCard({issuer, transferFeeBps, accepted, onAccepted, disabled, highlight}: {
  issuer: TradingIssuer; transferFeeBps: number; accepted?: boolean; onAccepted?: (value: boolean) => void; disabled?: boolean; highlight?: boolean;
}) {
  const checkbox = useId();
  const tr = useT();
  const facts = [issuer.productType, issuer.holderRights, issuer.excludedRegions.length ? tr('money.issuer.excluded', {regions: issuer.excludedRegions.join(', ')}) : '']
    .filter(Boolean);
  return <section className={`issuer-card${highlight ? ' needs-tick' : ''}`} aria-label={tr('money.issuer.label', {issuer: issuer.name})}>
    <div className="issuer-face">
      <h3>{issuer.name}{issuer.legalName && <small>{issuer.legalName}</small>}</h3>
      {issuer.warning && <p className="issuer-warning" role="note"><span aria-hidden="true">!</span>{issuer.warning}</p>}
      {issuer.summary && <p className="issuer-summary">{issuer.summary}</p>}
      {facts.map(fact => <p key={fact} className="issuer-fact">{fact}</p>)}
      {transferFeeBps > 0 && <p className="issuer-fee">{tr('money.issuer.fee', {fee: percentFromBps(transferFeeBps)})}</p>}
    </div>
    {onAccepted && <label className="issuer-tick" htmlFor={checkbox}>
      <input id={checkbox} type="checkbox" checked={accepted === true} disabled={disabled} onChange={event => onAccepted(event.target.checked)}/>
      <span>{issuer.attestation.text}</span></label>}
    <a className="issuer-terms" href={issuer.termsUrl} target="_blank" rel="noreferrer noopener">{tr('money.issuer.terms')}</a>
  </section>;
}

/** When a token can trade: shown when its market is not open, and for tokens that follow US sessions even while open. */
export function MarketStateNote({state}: {state: MarketState}) {
  const hours = marketHours(state);
  return <div className={`market-state-note ${state.status === 'open' ? 'open' : 'closed'}`} data-testid="live-order-market-state">
    <strong>{marketLabel(state)}</strong>{hours && <p>{hours}</p>}</div>;
}

export interface LiveOrderPanelProps {
  readonly assetId: string; readonly mint: string | null; readonly companyName: string;
  /** Discovery's tokens for this company, or null while they load. */
  readonly discovery: readonly DiscoveryVariantRef[] | null;
  readonly initialSide?: 'buy' | 'sell';
  readonly onDone?: () => void;
  readonly onPracticeInPaper?: () => void;
}

export function LiveOrderPanel(props: LiveOrderPanelProps) {
  const money = useMoney();
  const tr = useT();
  // One session per mount (and per StrictMode re-mount), never reused after dispose.
  const [session, setSession] = useState<LiveOrderSession | null>(null);
  useEffect(() => {
    const created = money.createOrderSession();
    setSession(created);
    if (!created) return;
    void created.restore();
    const resume = () => {if (document.visibilityState !== 'hidden') created.resume();};
    document.addEventListener('visibilitychange', resume);
    return () => {document.removeEventListener('visibilitychange', resume); created.dispose(); setSession(current => current === created ? null : current);};
  }, [money.orders]);
  useEffect(() => {void money.refreshCapabilities();}, [money.refreshCapabilities]);
  const state = useSyncExternalStore(session?.subscribe ?? noSubscribe, session?.getState ?? idleState);
  if (!money.available) return <aside className="trade-panel live"><h2>{tr('money.order.signedOutTitle')}</h2><p className="trade-caption">{tr('money.order.signedOutBody')}</p></aside>;
  if (!session) return <aside className="trade-panel live"><div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>{tr('money.checkingLastOrder')}</div></aside>;
  return <LivePanelBody {...props} session={session} state={state}/>;
}
const noSubscribe = () => () => {};
const idleState = () => idle;

function LivePanelBody({assetId, mint, companyName, discovery, initialSide = 'buy', onDone, onPracticeInPaper, session, state}: LiveOrderPanelProps & {session: LiveOrderSession; state: OrderSessionState}) {
  const money = useMoney();
  const tr = useT();
  const caps = money.capabilities;
  const asset = caps && caps.enabled ? resolveLiveAsset(caps, assetId, mint, discovery) : null;
  const issuer = asset && caps ? caps.issuerFor(asset) : null;
  const [side, setSide] = useState<'buy' | 'sell'>(initialSide);
  const [amount, setAmount] = useState(initialSide === 'buy' ? '5' : '');
  const [preset, setPreset] = useState<{text: string; raw: string} | null>(null);
  /** The quick amount (a percent; 100 is Max) that the order limit capped, if any. */
  const [capped, setCapped] = useState<number | null>(null);
  const [notice, setNotice] = useState<MoneyCopy | null>(null);
  const [termsVersion, setTermsVersion] = useState(0);
  const touched = useRef(false), termsRef = useRef<HTMLDivElement>(null);
  const holdings = coherentHoldings(money.wallet);
  const holding = asset ? holdings?.stockTokens.find(token => token.mint === asset.mint) ?? null : null;
  const scale = useMemo(() => !asset ? ShareScale.plain(0) : holding && holding.decimals === asset.decimals
    ? ShareScale.fromDisplay(asset.decimals, holding.amountRaw, holding.displayAmount) : ShareScale.plain(asset.decimals), [asset, holding]);
  const balanceRaw = holdings === null ? null : side === 'sell' ? holding?.availableToTradeRaw ?? '0' : holdings.usdc.availableToTradeRaw;
  const limitRaw = asset ? side === 'sell' ? asset.maxSellInputRaw : asset.maxBuyInputRaw : '0';
  // Schema 3 sells have no per-token cap: holdings and the server's price check bound them.
  const limited = asset !== null && !uncapped(limitRaw);
  const maxRaw = balanceRaw === null || !asset ? null : BigInt(balanceRaw) < BigInt(limitRaw) ? balanceRaw : limitRaw;
  const symbol = asset?.symbol ?? companyName;
  const label = (raw: string) => side === 'sell' ? `${scale.label(raw)} ${symbol}` : usdcLabel(raw);
  const accepted = issuer !== null && money.terms?.accepted(issuer.issuerId, issuer.attestation.version) === true;
  void termsVersion;
  const enteredRaw = preset && preset.text === amount.trim() ? preset.raw : side === 'sell' ? scale.raw(amount) : amountRaw(amount, USDC_DECIMALS);

  const fill = (raw: string) => {
    const text = fmt.decimalInput(side === 'sell' ? scale.shares(raw) : rawDecimal(raw, USDC_DECIMALS));
    setAmount(text); setPreset({text, raw});
  };
  // A zero or unknown first balance may predate a deposit: keep the untouched field eligible for autofill.
  useEffect(() => {
    if (touched.current || !asset || maxRaw === null || BigInt(maxRaw) <= 0n) return;
    touched.current = true;
    if (side === 'sell') {fill(maxRaw); setCapped(balanceRaw !== null && BigInt(balanceRaw) > BigInt(limitRaw) ? 100 : null);}
    else if (BigInt(maxRaw) < 5_000_000n) fill(maxRaw);
  }, [asset?.mint, maxRaw, side]);
  // A token the API refused on the spot, or a stale list after an API restart: read the list again.
  useEffect(() => {if (state.noticeCode === 'MARKET_INPUT_INVALID') void money.refreshCapabilities(true);}, [state.noticeCode]);
  useEffect(() => {
    if (!state.termsRequired || !issuer) return;
    money.terms?.record(issuer.issuerId, issuer.attestation.version, false); setTermsVersion(value => value + 1);
    termsRef.current?.scrollIntoView?.({block: 'center', behavior: 'smooth'});
    void money.refreshCapabilities(true);
  }, [state.termsRequired]);
  useEffect(() => {
    if (!notice) return;
    const timer = window.setTimeout(() => setNotice(null), 6000);
    return () => clearTimeout(timer);
  }, [notice]);

  function percent(value: number) {
    if (balanceRaw === null) return;
    touched.current = true;
    const portion = BigInt(balanceRaw) * BigInt(value) / 100n, over = portion > BigInt(limitRaw);
    fill(over ? limitRaw : portion.toString());
    setCapped(over ? value : null);
  }
  function switchSide() {
    touched.current = false; setSide(side === 'buy' ? 'sell' : 'buy'); setPreset(null); setCapped(null);
    setAmount(side === 'buy' ? '' : '5'); setNotice(null);
  }
  function review() {
    if (!asset || !issuer || !caps || session.busy) return;
    // Amounts and times are written when the notice shows, so a language change rewrites them too.
    if (!accepted) {setNotice({key: 'money.order.confirmTermsFirst'}); termsRef.current?.scrollIntoView?.({block: 'center', behavior: 'smooth'}); return;}
    if (enteredRaw === null) {setNotice({key: 'money.order.invalidAmount', params: {side}}); return;}
    if (BigInt(enteredRaw) > BigInt(limitRaw)) {setNotice({key: 'money.order.overLimit', params: {get amount() {return label(limitRaw);}}}); return;}
    const minimum = asset.minBuyInputRaw, market = asset.market;
    if (side === 'buy' && BigInt(enteredRaw) < BigInt(minimum)) {setNotice({key: 'money.order.underMinimum', params: {get amount() {return label(minimum);}}}); return;}
    if (market && market.status !== 'open') {setNotice({key: 'money.market.sentence', params: {get status() {return marketLabel(market);}}}); return;}
    setNotice(null);
    void session.preview({asset, issuer, side, amountRaw: enteredRaw, legacy: caps.legacy,
      spendable: () => {
        const current = coherentHoldings(money.wallet);
        return {raw: current === null ? null : side === 'sell' ? current.stockTokens.find(token => token.mint === asset.mint)?.availableToTradeRaw ?? '0'
          : current.usdc.availableToTradeRaw, fresh: money.walletFresh};
      }});
  }

  const phase = state.phase, order = state.order;
  const shownNotice = notice ?? state.noticeCopy;
  const wrap = (content: ReactNode) => <aside className="trade-panel live" aria-label={tr('money.order.label')} aria-busy={phase === 'checking' || phase === 'previewing' || phase === 'signing' || phase === 'submitting'}>
    <p className="money-badge real">{tr('money.realMoney')}</p>{content}
    {shownNotice && <p className="trade-error" role="alert">{tr(shownNotice.key, shownNotice.params)}</p>}
  </aside>;
  const unavailable = (title: string, message: string, action?: {label: string; run: () => void}) => wrap(<>
    <h2>{title}</h2><p className="trade-caption">{message}</p>
    {action && <button className="primary full" onClick={action.run}>{action.label}</button>}
    {onPracticeInPaper && <button className="text-button full" onClick={onPracticeInPaper}>{tr('money.order.practice')}</button>}</>);
  const tryAgain = tr('common.tryAgain');

  if (phase === 'account-changed') return unavailable(tr('money.order.accountChangedTitle'), tr('money.order.accountChangedBody'));
  if (order && (phase === 'pending' || phase === 'confirmed' || phase === 'failed' || phase === 'expired')) {
    return wrap(<OrderResult order={order} phase={phase} caps={caps} onDone={() => {session.reset(); onDone?.();}}
      onRetry={() => {session.reset(); if (asset && issuer && caps?.enabled) review(); else void session.restore();}}/>);
  }
  if (phase === 'checking') return wrap(<div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>{tr('money.checkingLastOrder')}</div>);
  if (phase === 'recovery-failed') return unavailable(tr('money.order.recoveryTitle'), tr('money.order.whenConnected'), {label: tryAgain, run: () => void session.restore()});
  if (money.capabilitiesFailed && !caps) return unavailable(tr('money.order.connectFailedTitle'), tr('money.order.whenConnected'), {label: tryAgain, run: () => void money.refreshCapabilities(true)});
  if (!caps) return wrap(<div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>{tr('money.checkingTrading')}</div>);
  if (!caps.enabled) return unavailable(tr('money.order.pausedTitle'), tr('money.order.pausedBody'), {label: tryAgain, run: () => void money.refreshCapabilities(true)});
  if (!asset || !issuer) return unavailable(tr('money.order.notTradableTitle'), mint ? caps.reasonFor(mint) : tr('money.order.chooseAnother'));
  // Ordering is disabled whenever the token's market is not open; the entry still shows when it opens.
  const marketOpen = asset.market === null || asset.market.status === 'open';
  if (order && (phase === 'reviewed' || phase === 'signing' || phase === 'submitting')) {
    return wrap(<OrderReview order={order} asset={asset} issuer={issuer} busy={phase !== 'reviewed'} phase={phase}
      onConfirm={() => void session.confirm()} onEdit={() => session.edit()} onExpire={() => session.expireQuote()}/>);
  }
  const walletMissing = money.wallet.context?.embeddedSolanaWallet.status === 'missing';
  const busy = phase === 'previewing';
  const available = balanceRaw === null ? tr('money.order.checkingBalance') : tr('money.order.available', {amount: label(balanceRaw)});
  const unspendable = side === 'sell' && holding && holding.availableToTradeRaw !== holding.amountRaw;
  return wrap(<>
    <div className="live-heading"><div><h2>{tr('money.order.heading', {side, symbol})}</h2><p className="trade-caption">{caps.variantLabel(asset)} · Solana</p></div>
      <button className="text-button" disabled={busy} onClick={switchSide}>{side === 'sell' ? tr('money.order.buyInstead') : tr('money.order.sellInstead')}</button></div>
    <label className="amount-label" htmlFor="live-amount">{side === 'sell' ? tr('money.order.youSell') : tr('money.order.youPay')}</label>
    <div className="amount-field live-amount">{side === 'buy' && <span aria-hidden="true">{tr('money.order.dollarSign')}</span>}
      <input id="live-amount" inputMode="decimal" autoComplete="off" maxLength={40} value={amount} disabled={busy}
        onChange={event => {touched.current = true; const value = fmt.amountCharacters(event.target.value); setAmount(value); if (capped !== null && preset?.text !== value.trim()) setCapped(null);}}
        onKeyDown={enterPresses(!busy && !walletMissing, review)}
        aria-describedby={limited ? 'live-available live-limit' : 'live-available'}/>
      <span>{side === 'sell' ? symbol : 'USDC'}</span></div>
    <div className="live-available-row"><span id="live-available">{available}</span>
      <button className="text-button" disabled={busy || maxRaw === null || maxRaw === '0'} onClick={() => percent(100)}>{tr('money.max')}</button></div>
    {unspendable && <p className="trade-caption">{tr('money.order.partlyElsewhere', {symbol, amount: scale.label(holding.availableToTradeRaw)})}</p>}
    <div className="amount-options">{side === 'sell' ? [25, 50, 75].map(value => <button key={value} disabled={busy || maxRaw === null} onClick={() => percent(value)}>{fmt.percent(`${value}%`)}</button>)
      : [5, 10, 25, 50].map(value => <button key={value} disabled={busy} onClick={() => {touched.current = true; setPreset(null); setCapped(null); setAmount(String(value));}}>{fmt.usd(`$${value}`)}</button>)}</div>
    {limited && <p className="trade-caption" id="live-limit">{capped === null ? tr('money.order.limit', {amount: label(limitRaw)})
      : capped === 100 ? tr('money.order.maxCapped', {amount: label(limitRaw)}) : tr('money.order.percentCapped', {percent: fmt.percent(`${capped}%`), amount: label(limitRaw)})}</p>}
    {side === 'buy' && asset.minBuyInputRaw !== '1' && <p className="trade-caption">{tr('money.order.minimum', {amount: label(asset.minBuyInputRaw)})}</p>}
    {asset.market && (!marketOpen || asset.market.usSessions) && <MarketStateNote state={asset.market}/>}
    <div ref={termsRef}><IssuerCard issuer={issuer} transferFeeBps={asset.transferFeeBps} accepted={accepted} disabled={busy} highlight={state.termsRequired && !accepted}
      onAccepted={value => {money.terms?.record(issuer.issuerId, issuer.attestation.version, value); setTermsVersion(version => version + 1);}}/></div>
    {walletMissing ? <><p className="trade-caption">{tr('money.order.createWallet')}</p><button className="primary full" onClick={money.openFundWallet}>{tr('money.addMoney')}</button></>
      : <button className="primary full live-action" disabled={busy || !accepted || !marketOpen} onClick={review}>{busy ? tr('money.order.checkingPrice')
        : marketOpen ? tr('money.order.review', {side}) : marketLabel(asset.market!)}</button>}
    {!walletMissing && (state.fundingNeeded || side === 'buy' && (balanceRaw === null || balanceRaw === '0')) &&
      <button className="text-button full" disabled={busy} onClick={money.openFundWallet}>{tr('money.addMoney')}</button>}
  </>);
}

function OrderReview({order, asset, issuer, busy, phase, onConfirm, onEdit, onExpire}: {order: LiveOrder; asset: TradingAsset; issuer: TradingIssuer; busy: boolean;
  phase: string; onConfirm: () => void; onEdit: () => void; onExpire: () => void}) {
  const tr = useT();
  const [clock, setClock] = useState(Date.now);
  useEffect(() => {const timer = window.setInterval(() => setClock(Date.now()), 1000); return () => clearInterval(timer);}, []);
  const remaining = Math.max(0, Math.ceil((Date.parse(order.expiresAt) - clock) / 1000));
  useEffect(() => {if (remaining === 0) onExpire();}, [remaining === 0]);
  const terms = order.terms, buying = terms.side === 'buy';
  // The multiplier in force at review; older servers send none, which reads as plain token units.
  const scale = ShareScale.fromMultiplier(asset.decimals, terms.stockUiMultiplier);
  const quoted = (raw: string) => `${scale.approx(raw)} ${asset.symbol}`, least = (raw: string) => `${scale.label(raw)} ${asset.symbol}`;
  // An issuer fee comes out of every transfer: the simulated delivery is closer to what arrives.
  const received = asset.transferFeeBps > 0 && terms.simulatedOutputReceivedRaw ? terms.simulatedOutputReceivedRaw : terms.quotedOutputAmountRaw;
  const returned = terms.takerLamportsReturnUpperBound && terms.takerLamportsReturnUpperBound !== '0' ? terms.takerLamportsReturnUpperBound : null;
  const net = terms.simulatedTakerLamportsSpent ? signedLamports(terms.simulatedTakerLamportsSpent) : null;
  const side = buying ? 'buy' : 'sell';
  // Each line: the label's key (also the row's React key) and the value as shown.
  const lines: [MessageKey, string][] = [
    ['money.review.youPay', buying ? usdcLabel(terms.inputAmountRaw) : quoted(terms.inputAmountRaw)],
    ['money.review.youReceive', buying ? quoted(received) : usdcLabel(received)],
    ['money.review.minimumReceived', buying ? least(terms.minimumOutputAmountRaw) : usdcLabel(terms.minimumOutputAmountRaw)],
    ['money.review.networkFees', tr('money.review.atMost', {amount: solLabel(terms.totalLamportsUpperBound)})],
    ['money.review.swapFee', percentFromBps(terms.platformFeeBps)],
    ...(terms.route === 'rfq' ? [['money.review.price', tr('money.review.fixedQuote')] as [MessageKey, string]] : []),
    ...(returned ? [['money.review.returned', tr('money.review.returnedValue', {amount: solLabel(returned)})] as [MessageKey, string]] : []),
    ...(net?.negative && !returned ? [['money.review.solBack', solLabel(net.lamports)] as [MessageKey, string]] : []),
    ['money.review.issuer', issuer.name],
    ...(asset.transferFeeBps > 0 ? [['money.review.issuerFee', percentFromBps(asset.transferFeeBps)] as [MessageKey, string]] : []),
  ];
  const flags = new Set(order.reviewFlags);
  const makerDelivers = terms.settlement === 'maker_delivers_at_fill' || flags.has('rfq_maker_delivers_at_fill');
  if (makerDelivers) lines.splice(3, 0, ['money.review.delivery', tr('money.review.deliveryValue')]);
  return <>
    <h2>{tr('money.review.title', {side})}</h2>
    {issuer.warning && <p className="issuer-warning review" role="note"><span aria-hidden="true">!</span>{issuer.warning}</p>}
    <dl className="review-summary live-review">{lines.map(([name, value]) => <div key={name}><dt>{tr(name)}</dt><dd>{value}</dd></div>)}</dl>
    {(flags.has('closes_existing_wrapped_sol') || returned) && <p className="trade-caption">{tr('money.review.closesWrappedSol')}</p>}
    {flags.has('intermediate_token_account') && <p className="trade-caption">{tr('money.review.temporaryAccount')}</p>}
    {(flags.has('rfq_market_maker_fill') || terms.route === 'rfq') && <p className="trade-caption">{tr('money.review.makerFills')}</p>}
    {makerDelivers && <p className="trade-caption settlement-note" data-testid="live-order-settlement">{tr('money.review.makerDelivers')}</p>}
    <p className="quote-clock" role="timer">{remaining > 0 ? tr('money.review.expiresIn', {seconds: remaining}) : tr('money.review.expired')}</p>
    <button className="primary full live-action" disabled={busy || remaining === 0} onClick={onConfirm}>{phase === 'signing' ? tr('money.review.waitingWallet') : phase === 'submitting' ? tr('money.review.confirming') : tr('money.review.confirm', {side})}</button>
    <button className="text-button full" disabled={busy} onClick={onEdit}>{tr('money.review.edit')}</button>
    <p className="trade-disclosure">{tr('money.review.disclosure')}</p>
  </>;
}

function OrderResult({order, phase, caps, onDone, onRetry}: {order: LiveOrder; phase: string; caps: TradingCapabilities | null; onDone: () => void; onRetry: () => void}) {
  const tr = useT();
  const done = phase === 'confirmed', pending = phase === 'pending', expired = phase === 'expired';
  const rfq = order.terms.route === 'rfq';
  const asset = caps?.forMint(order.terms.side === 'buy' ? order.terms.outputMint : order.terms.inputMint);
  return <div className="live-result" role="status">
    <div className={`receipt-mark${done ? '' : pending ? ' pending' : ' muted'}`} aria-hidden="true">{done ? '✓' : pending ? '…' : '↻'}</div>
    <h2>{done ? tr('money.result.confirmedTitle') : pending ? tr('money.result.pendingTitle') : expired ? tr('money.result.expiredTitle') : tr('money.result.failedTitle')}</h2>
    <p className="receipt-text">{done ? tr('money.result.confirmedBody') : pending ? tr('money.result.pendingBody')
      : expired ? tr('money.result.expiredBody') : tr('money.result.failedBody')}</p>
    {asset && <p className="trade-caption">{tr('money.trade.label', {side: order.terms.side === 'buy' ? 'buy' : 'sell', symbol: asset.symbol})}</p>}
    {order.signature && <a className="text-button full" href={explorerUrl({rfq, wallet: order.wallet, signature: order.signature})} target="_blank" rel="noreferrer noopener">
      {rfq ? tr('money.explorer.walletActivity') : tr('money.explorer.transaction')}</a>}
    {done ? <button className="primary full" onClick={onDone}>{tr('common.done')}</button>
      : !pending && <button className="primary full" onClick={onRetry}>{expired ? tr('money.result.freshPrice') : tr('common.tryAgain')}</button>}
  </div>;
}
