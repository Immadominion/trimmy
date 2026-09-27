/**
 * Real-money order entry, review, signing and result for one company's chosen
 * token. Mirrors mobile's LiveOrderFlow: the issuer card and its warning come
 * before the eligibility tick, the review shows the warning, terms, fees and
 * expiry before Confirm, and a signed order is reconciled by its id.
 */
import {useEffect, useId, useMemo, useRef, useState, useSyncExternalStore, type ReactNode} from 'react';
import {amountRaw, percentFromBps, rawDecimal, ShareScale, signedLamports, solLabel, usdcLabel, USDC_DECIMALS} from './amounts.js';
import {explorerUrl, type LiveOrder} from './live-order-client.js';
import {marketHours, marketLabel, type DiscoveryVariantRef, type MarketState, type TradingAsset, type TradingCapabilities, type TradingIssuer} from './live-trading.js';
import {useMoney} from './money-api.js';
import type {LiveOrderSession, OrderSessionState} from './order-session.js';
import {coherentHoldings} from './wallet-controller.js';

const idle: OrderSessionState = Object.freeze({phase: 'checking', order: null, notice: null, noticeCode: null, fundingNeeded: false, termsRequired: false});

/** The tradeable token this panel may trade, or why none: never another issuer's token by accident. */
export function resolveLiveAsset(caps: TradingCapabilities, assetId: string, mint: string | null, discovery: readonly DiscoveryVariantRef[] | null): TradingAsset | null {
  const variants = caps.variantsFor(assetId, discovery ?? undefined);
  return variants.find(asset => asset.mint === mint) ?? (mint === null ? variants[0] ?? null : null);
}

export function IssuerCard({issuer, transferFeeBps, accepted, onAccepted, disabled, highlight}: {
  issuer: TradingIssuer; transferFeeBps: number; accepted?: boolean; onAccepted?: (value: boolean) => void; disabled?: boolean; highlight?: boolean;
}) {
  const checkbox = useId();
  const facts = [issuer.productType, issuer.holderRights, issuer.excludedRegions.length ? `Not for residents of ${issuer.excludedRegions.join(', ')}` : '']
    .filter(Boolean);
  return <section className={`issuer-card${highlight ? ' needs-tick' : ''}`} aria-label={`${issuer.name} issuer terms`}>
    <div className="issuer-face">
      <h3>{issuer.name}{issuer.legalName && <small>{issuer.legalName}</small>}</h3>
      {issuer.warning && <p className="issuer-warning" role="note"><span aria-hidden="true">!</span>{issuer.warning}</p>}
      {issuer.summary && <p className="issuer-summary">{issuer.summary}</p>}
      {facts.map(fact => <p key={fact} className="issuer-fact">{fact}</p>)}
      {transferFeeBps > 0 && <p className="issuer-fee">Issuer fee: {percentFromBps(transferFeeBps)} on every buy and sell</p>}
    </div>
    {onAccepted && <label className="issuer-tick" htmlFor={checkbox}>
      <input id={checkbox} type="checkbox" checked={accepted === true} disabled={disabled} onChange={event => onAccepted(event.target.checked)}/>
      <span>{issuer.attestation.text}</span></label>}
    <a className="issuer-terms" href={issuer.termsUrl} target="_blank" rel="noreferrer noopener">Issuer terms ↗</a>
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
  const session = useMemo(() => money.createOrderSession(), [money.orders]);
  useEffect(() => {
    if (!session) return;
    void session.restore();
    const resume = () => {if (document.visibilityState !== 'hidden') session.resume();};
    document.addEventListener('visibilitychange', resume);
    return () => {document.removeEventListener('visibilitychange', resume); session.dispose();};
  }, [session]);
  useEffect(() => {void money.refreshCapabilities();}, [money.refreshCapabilities]);
  const state = useSyncExternalStore(session?.subscribe ?? (() => () => {}), session?.getState ?? (() => idle));
  if (!session) return <aside className="trade-panel live"><h2>Trade with your own money.</h2><p className="trade-caption">Sign in to use your wallet.</p></aside>;
  return <LivePanelBody {...props} session={session} state={state}/>;
}

function LivePanelBody({assetId, mint, companyName, discovery, initialSide = 'buy', onDone, onPracticeInPaper, session, state}: LiveOrderPanelProps & {session: LiveOrderSession; state: OrderSessionState}) {
  const money = useMoney();
  const caps = money.capabilities;
  const asset = caps && caps.enabled ? resolveLiveAsset(caps, assetId, mint, discovery) : null;
  const issuer = asset && caps ? caps.issuerFor(asset) : null;
  const [side, setSide] = useState<'buy' | 'sell'>(initialSide);
  const [amount, setAmount] = useState(initialSide === 'buy' ? '5' : '');
  const [preset, setPreset] = useState<{text: string; raw: string} | null>(null);
  const [capped, setCapped] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [termsVersion, setTermsVersion] = useState(0);
  const touched = useRef(false), termsRef = useRef<HTMLDivElement>(null);
  const holdings = coherentHoldings(money.wallet);
  const holding = asset ? holdings?.stockTokens.find(token => token.mint === asset.mint) ?? null : null;
  const scale = useMemo(() => !asset ? ShareScale.plain(0) : holding && holding.decimals === asset.decimals
    ? ShareScale.fromDisplay(asset.decimals, holding.amountRaw, holding.displayAmount) : ShareScale.plain(asset.decimals), [asset, holding]);
  const balanceRaw = holdings === null ? null : side === 'sell' ? holding?.availableToTradeRaw ?? '0' : holdings.usdc.availableToTradeRaw;
  const limitRaw = asset ? side === 'sell' ? asset.maxSellInputRaw : asset.maxBuyInputRaw : '0';
  const maxRaw = balanceRaw === null || !asset ? null : BigInt(balanceRaw) < BigInt(limitRaw) ? balanceRaw : limitRaw;
  const symbol = asset?.symbol ?? companyName;
  const label = (raw: string) => side === 'sell' ? `${scale.label(raw)} ${symbol}` : usdcLabel(raw);
  const accepted = issuer !== null && money.terms?.accepted(issuer.issuerId, issuer.attestation.version) === true;
  void termsVersion;
  const enteredRaw = preset && preset.text === amount.trim() ? preset.raw : side === 'sell' ? scale.raw(amount) : amountRaw(amount, USDC_DECIMALS);

  const fill = (raw: string) => {
    const text = side === 'sell' ? scale.shares(raw) : rawDecimal(raw, USDC_DECIMALS);
    setAmount(text); setPreset({text, raw});
  };
  // A zero or unknown first balance may predate a deposit: keep the untouched field eligible for autofill.
  useEffect(() => {
    if (touched.current || !asset || maxRaw === null || BigInt(maxRaw) <= 0n) return;
    touched.current = true;
    if (side === 'sell') {fill(maxRaw); setCapped(balanceRaw !== null && BigInt(balanceRaw) > BigInt(limitRaw) ? 'Max' : null);}
    else if (BigInt(maxRaw) < 5_000_000n) fill(maxRaw);
  }, [asset?.mint, maxRaw, side]);
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
    setCapped(over ? value === 100 ? 'Max' : `${value}%` : null);
  }
  function switchSide() {
    touched.current = false; setSide(side === 'buy' ? 'sell' : 'buy'); setPreset(null); setCapped(null);
    setAmount(side === 'buy' ? '' : '5'); setNotice(null);
  }
  function review() {
    if (!asset || !issuer || !caps || session.busy) return;
    if (!accepted) {setNotice('Confirm the issuer terms first.'); termsRef.current?.scrollIntoView?.({block: 'center', behavior: 'smooth'}); return;}
    if (enteredRaw === null) {setNotice(`Enter a valid ${side === 'sell' ? 'share amount' : 'USDC amount'}.`); return;}
    if (BigInt(enteredRaw) > BigInt(limitRaw)) {setNotice(`Up to ${label(limitRaw)} per order.`); return;}
    if (side === 'buy' && BigInt(enteredRaw) < BigInt(asset.minBuyInputRaw)) {setNotice(`Orders for this token start at ${label(asset.minBuyInputRaw)}.`); return;}
    if (asset.market && asset.market.status !== 'open') {setNotice(`${marketLabel(asset.market)}.`); return;}
    setNotice(null);
    void session.preview({asset, issuer, side, amountRaw: enteredRaw, legacy: caps.legacy,
      spendable: () => {
        const current = coherentHoldings(money.wallet);
        return {raw: current === null ? null : side === 'sell' ? current.stockTokens.find(token => token.mint === asset.mint)?.availableToTradeRaw ?? '0'
          : current.usdc.availableToTradeRaw, fresh: money.walletFresh};
      }});
  }

  const phase = state.phase, order = state.order;
  const shownNotice = notice ?? state.notice;
  const wrap = (content: ReactNode) => <aside className="trade-panel live" aria-label="Real-money order" aria-busy={phase === 'checking' || phase === 'previewing' || phase === 'signing' || phase === 'submitting'}>
    <p className="money-badge real">Real money</p>{content}
    {shownNotice && <p className="trade-error" role="alert">{shownNotice}</p>}
  </aside>;
  const unavailable = (title: string, message: string, action?: {label: string; run: () => void}) => wrap(<>
    <h2>{title}</h2><p className="trade-caption">{message}</p>
    {action && <button className="primary full" onClick={action.run}>{action.label}</button>}
    {onPracticeInPaper && <button className="text-button full" onClick={onPracticeInPaper}>Practice in Paper</button>}</>);

  if (phase === 'account-changed') return unavailable('Your account changed', 'Reopen trading after signing in.');
  if (order && (phase === 'pending' || phase === 'confirmed' || phase === 'failed' || phase === 'expired')) {
    return wrap(<OrderResult order={order} phase={phase} caps={caps} onDone={() => {session.reset(); onDone?.();}}
      onRetry={() => {session.reset(); if (asset && issuer && caps?.enabled) review(); else void session.restore();}}/>);
  }
  if (phase === 'checking') return wrap(<div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>Checking your last order…</div>);
  if (phase === 'recovery-failed') return unavailable('Let’s check your last order', 'Try again when you’re connected.', {label: 'Try again', run: () => void session.restore()});
  if (money.capabilitiesFailed && !caps) return unavailable('Trading couldn’t connect', 'Try again when you’re connected.', {label: 'Try again', run: () => void money.refreshCapabilities(true)});
  if (!caps) return wrap(<div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>Checking trading…</div>);
  if (!caps.enabled) return unavailable('Trading is temporarily paused', 'Your wallet and holdings are still here.', {label: 'Try again', run: () => void money.refreshCapabilities(true)});
  if (!asset || !issuer) return unavailable('This token isn’t tradable here yet', mint ? caps.reasonFor(mint) : 'Choose another stock to trade.');
  // Ordering is disabled whenever the token's market is not open; the entry still shows when it opens.
  const marketOpen = asset.market === null || asset.market.status === 'open';
  if (order && (phase === 'reviewed' || phase === 'signing' || phase === 'submitting')) {
    return wrap(<OrderReview order={order} asset={asset} issuer={issuer} busy={phase !== 'reviewed'} phase={phase}
      onConfirm={() => void session.confirm()} onEdit={() => session.edit()} onExpire={() => session.expireQuote()}/>);
  }
  const walletMissing = money.wallet.context?.embeddedSolanaWallet.status === 'missing';
  const busy = phase === 'previewing';
  const available = balanceRaw === null ? 'Checking balance…' : `${label(balanceRaw)} available`;
  const unspendable = side === 'sell' && holding && holding.availableToTradeRaw !== holding.amountRaw;
  return wrap(<>
    <div className="live-heading"><div><h2>{side === 'sell' ? 'Sell' : 'Buy'} {symbol}</h2><p className="trade-caption">{caps.variantLabel(asset)} · Solana</p></div>
      <button className="text-button" disabled={busy} onClick={switchSide}>{side === 'sell' ? 'Buy instead' : 'Sell instead'}</button></div>
    <label className="amount-label" htmlFor="live-amount">{side === 'sell' ? 'You sell' : 'You pay'}</label>
    <div className="amount-field live-amount">{side === 'buy' && <span aria-hidden="true">$</span>}
      <input id="live-amount" inputMode="decimal" autoComplete="off" maxLength={40} value={amount} disabled={busy}
        onChange={event => {touched.current = true; const value = event.target.value.replace(/[^0-9.]/g, ''); setAmount(value); if (capped && preset?.text !== value.trim()) setCapped(null);}}
        aria-describedby="live-available live-limit"/>
      <span>{side === 'sell' ? symbol : 'USDC'}</span></div>
    <div className="live-available-row"><span id="live-available">{available}</span>
      <button className="text-button" disabled={busy || maxRaw === null || maxRaw === '0'} onClick={() => percent(100)}>Max</button></div>
    {unspendable && <p className="trade-caption">Some of your {symbol} is in another token account. Only {scale.label(holding.availableToTradeRaw)} {symbol} can be sold here.</p>}
    <div className="amount-options">{side === 'sell' ? [25, 50, 75].map(value => <button key={value} disabled={busy || maxRaw === null} onClick={() => percent(value)}>{value}%</button>)
      : [5, 10, 25, 50].map(value => <button key={value} disabled={busy} onClick={() => {touched.current = true; setPreset(null); setCapped(null); setAmount(String(value));}}>${value}</button>)}</div>
    <p className="trade-caption" id="live-limit">{capped === null ? `Order limit: ${label(limitRaw)}` : `${capped} capped at the order limit of ${label(limitRaw)}.`}
      {side === 'buy' && asset.minBuyInputRaw !== '1' && ` Orders start at ${label(asset.minBuyInputRaw)}.`}</p>
    {asset.market && (!marketOpen || asset.market.usSessions) && <MarketStateNote state={asset.market}/>}
    <div ref={termsRef}><IssuerCard issuer={issuer} transferFeeBps={asset.transferFeeBps} accepted={accepted} disabled={busy} highlight={state.termsRequired && !accepted}
      onAccepted={value => {money.terms?.record(issuer.issuerId, issuer.attestation.version, value); setTermsVersion(version => version + 1);}}/></div>
    {walletMissing ? <><p className="trade-caption">Create your wallet to continue.</p><button className="primary full" onClick={money.openFundWallet}>Add money</button></>
      : <button className="primary full live-action" disabled={busy || !accepted || !marketOpen} onClick={review}>{busy ? 'Checking price and fees…'
        : marketOpen ? `Review ${side === 'sell' ? 'sell' : 'buy'}` : marketLabel(asset.market!)}</button>}
    {!walletMissing && (state.fundingNeeded || side === 'buy' && (balanceRaw === null || balanceRaw === '0')) &&
      <button className="text-button full" disabled={busy} onClick={money.openFundWallet}>Add money</button>}
  </>);
}

function OrderReview({order, asset, issuer, busy, phase, onConfirm, onEdit, onExpire}: {order: LiveOrder; asset: TradingAsset; issuer: TradingIssuer; busy: boolean;
  phase: string; onConfirm: () => void; onEdit: () => void; onExpire: () => void}) {
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
  const lines: [string, string][] = [
    ['You pay', buying ? usdcLabel(terms.inputAmountRaw) : quoted(terms.inputAmountRaw)],
    ['You receive ≈', buying ? quoted(received) : usdcLabel(received)],
    ['Minimum received', buying ? least(terms.minimumOutputAmountRaw) : usdcLabel(terms.minimumOutputAmountRaw)],
    ['Network + account fees', `≤ ${solLabel(terms.totalLamportsUpperBound)}`],
    ['Swap fee', percentFromBps(terms.platformFeeBps)],
    ...(terms.route === 'rfq' ? [['Price', 'Fixed quote from a market maker'] as [string, string]] : []),
    ...(returned ? [['Returned to your wallet', `Up to ${solLabel(returned)} from your wrapped SOL account`] as [string, string]] : []),
    ...(net?.negative && !returned ? [['SOL back ≈', solLabel(net.lamports)] as [string, string]] : []),
    ['Issuer', issuer.name],
    ...(asset.transferFeeBps > 0 ? [['Issuer fee', percentFromBps(asset.transferFeeBps)] as [string, string]] : []),
  ];
  const flags = new Set(order.reviewFlags);
  const makerDelivers = terms.settlement === 'maker_delivers_at_fill' || flags.has('rfq_maker_delivers_at_fill');
  if (makerDelivers) lines.splice(3, 0, ['Delivery', 'By the market maker at fill']);
  return <>
    <h2>Review your {buying ? 'buy' : 'sell'}</h2>
    {issuer.warning && <p className="issuer-warning review" role="note"><span aria-hidden="true">!</span>{issuer.warning}</p>}
    <dl className="review-summary live-review">{lines.map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value}</dd></div>)}</dl>
    {(flags.has('closes_existing_wrapped_sol') || returned) && <p className="trade-caption">This order closes your existing wrapped SOL account and returns it to your wallet as SOL.</p>}
    {flags.has('intermediate_token_account') && <p className="trade-caption">The route uses a temporary token account that closes within the same transaction.</p>}
    {(flags.has('rfq_market_maker_fill') || terms.route === 'rfq') && <p className="trade-caption">A market maker fills this order at the fixed price above and pays the network fee.</p>}
    {makerDelivers && <p className="trade-caption settlement-note" data-testid="live-order-settlement">The market maker creates your tokens just in time, after you sign, and delivers them when the order fills. The fill is all or nothing: you get the full amount or the order doesn’t go through.</p>}
    <p className="quote-clock" role="timer">{remaining > 0 ? `Quote expires in ${remaining}s` : 'Quote expired. Get a new review.'}</p>
    <button className="primary full live-action" disabled={busy || remaining === 0} onClick={onConfirm}>{phase === 'signing' ? 'Waiting for your wallet…' : phase === 'submitting' ? 'Confirming…' : `Confirm ${buying ? 'buy' : 'sell'}`}</button>
    <button className="text-button full" disabled={busy} onClick={onEdit}>Edit amount</button>
    <p className="trade-disclosure">Confirm signs this exact order with your Trimmy wallet. Amounts are the reviewed quote; the transaction shows the final amounts.</p>
  </>;
}

function OrderResult({order, phase, caps, onDone, onRetry}: {order: LiveOrder; phase: string; caps: TradingCapabilities | null; onDone: () => void; onRetry: () => void}) {
  const done = phase === 'confirmed', pending = phase === 'pending', expired = phase === 'expired';
  const rfq = order.terms.route === 'rfq';
  const asset = caps?.forMint(order.terms.side === 'buy' ? order.terms.outputMint : order.terms.inputMint);
  return <div className="live-result" role="status">
    <div className={`receipt-mark${done ? '' : pending ? ' pending' : ' muted'}`} aria-hidden="true">{done ? '✓' : pending ? '…' : '↻'}</div>
    <h2>{done ? 'Trade confirmed' : pending ? 'Confirming your trade' : expired ? 'Quote expired' : 'Trade didn’t complete'}</h2>
    <p className="receipt-text">{done ? 'Your order is confirmed on Solana.' : pending ? 'You can close this. Reopen the trade to check its status.'
      : expired ? 'Get a fresh price to continue.' : 'Your order wasn’t filled.'}</p>
    {asset && <p className="trade-caption">{order.terms.side === 'buy' ? 'Buy' : 'Sell'} {asset.symbol}</p>}
    {order.signature && <a className="text-button full" href={explorerUrl({rfq, wallet: order.wallet, signature: order.signature})} target="_blank" rel="noreferrer noopener">
      {rfq ? 'View wallet activity ↗' : 'View transaction ↗'}</a>}
    {done ? <button className="primary full" onClick={onDone}>Done</button>
      : !pending && <button className="primary full" onClick={onRetry}>{expired ? 'Get fresh price' : 'Try again'}</button>}
  </div>;
}
