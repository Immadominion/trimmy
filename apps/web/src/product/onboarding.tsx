import {useEffect, useRef, useState} from 'react';
import type {ProductMarketClient, StockDiscoveryAsset} from './market-client';
import type {CareerSummary, PaperPortfolio, PaperPreview, PaperReceipt, ProductProfile} from './practice-client';
import type {PracticeSession} from './practice-session';
import {CompanyLogo, Loading, SalArt, art, enterPresses, errorCopy, micros, shares, toPaperMicros} from './ui';
import {FirstOrderCelebration} from './first-day-followup';
import {useT} from '../i18n/react';
import * as fmt from '../i18n/format';

type Phase = 'welcome' | 'note' | 'practice' | 'review' | 'receipt';
/** A null symbol shows the "Stock token" fallback, written at render time in the page's language. */
interface Company {assetId: string; name: string; symbol: string | null; mint: string}
export interface FirstDayProps {
  readonly initialStep: 'welcome' | 'note' | 'practice'; readonly motion: boolean;
  readonly market: ProductMarketClient; readonly session: PracticeSession;
  readonly portfolio: PaperPortfolio | null; readonly career: CareerSummary | null;
  readonly ensureDesk: () => Promise<void>; readonly onExplore: () => void;
  readonly onExit: (completed: boolean) => Promise<void>;
  /** The picked company rides along so the celebration can name it before public facts load. */
  readonly onCommitted: (receipt: PaperReceipt, company?: {readonly name: string; readonly logoUrl: string | null}) => Promise<void>; readonly onPending: () => void;
  /** Mobile's receipt Continue: records the confirmed order and opens the follow-up. */
  readonly onReceiptContinue: (orderId: string) => Promise<void>;
  readonly onStep?: (step: string) => void;
  readonly onSignIn?: () => void;
}
function companies(assets: readonly StockDiscoveryAsset[]): Company[] {
  const preferred = ['apple', 'tesla', 'meta'];
  const rank = (id: string) => {const index = preferred.indexOf(id); return index < 0 ? preferred.length : index;};
  return [...assets].sort((a, b) => rank(a.assetId) - rank(b.assetId)).flatMap(asset => {
    const variant = asset.variants.find(row => row.mint === asset.providerPrimaryVariantMint && row.advisory === null)
      ?? asset.variants.find(row => row.advisory === null);
    return variant ? [{assetId: asset.assetId, name: asset.name ?? asset.assetId.replaceAll('-', ' '),
      symbol: variant.symbol ?? asset.symbol ?? null, mint: variant.mint}] : [];
  }).slice(0, 3);
}
/** The web ships art for the three starter tokens; other logos come from public facts. */
export function tokenArt(symbol: string | null): string | null {return symbol !== null && ['AAPLx', 'TSLAx', 'METAx'].includes(symbol) ? art(`token-${symbol}.webp`) : null;}
function markHistory(phase: Phase, push: boolean): void {
  const previous: unknown = window.history.state;
  const state = {...(previous && typeof previous === 'object' && !Array.isArray(previous) ? previous : {}), trimmyFirstDay: phase};
  const url = phase === 'welcome' ? `${window.location.pathname}${window.location.search}` : '#start';
  if (push) window.history.pushState(state, '', url); else window.history.replaceState(state, '', url);
}

/** First-day practice uses the same persisted guest, preview and receipt boundary as the desk. */
export function FirstDay(props: FirstDayProps) {
  const {market, session, portfolio, career} = props;
  const [phase, setPhase] = useState<Phase>(() => props.initialStep === 'practice' && !session.hasIdentity ? 'note' : props.initialStep);
  const [choices, setChoices] = useState<readonly Company[]>([]);
  const [selected, setSelected] = useState<Company | null>(null);
  const [amount, setAmount] = useState('100');
  const [preview, setPreview] = useState<PaperPreview | null>(null);
  const [receipt, setReceipt] = useState<PaperReceipt | null>(null);
  const [busy, setBusy] = useState(false), [loading, setLoading] = useState(false);
  const [ready, setReady] = useState(false), [reload, setReload] = useState(0);
  const [error, setError] = useState<unknown>(null), [marketError, setMarketError] = useState<unknown>(null);
  const [notice, setNotice] = useState(false), [clock, setClock] = useState(Date.now);
  const tr = useT();
  const locked = useRef(false), mounted = useRef(true), initialCheck = useRef(false);
  const callbacks = useRef(props); callbacks.current = props;
  const currentPhase = useRef(phase); currentPhase.current = phase;
  const heading = useRef<HTMLHeadingElement>(null);
  const backAction = useRef<() => void>(() => {});
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  useEffect(() => {
    markHistory(currentPhase.current, false);
    const back = () => {markHistory(currentPhase.current, false); backAction.current();};
    const key = (event: KeyboardEvent) => {if (event.key === 'Escape') {event.preventDefault(); backAction.current();}};
    window.addEventListener('popstate', back); window.addEventListener('keydown', key);
    return () => {window.removeEventListener('popstate', back); window.removeEventListener('keydown', key);};
  }, []);
  useEffect(() => {callbacks.current.onStep?.(phase); heading.current?.focus();}, [phase]);
  useEffect(() => {
    if (phase !== 'review') return;
    const tick = () => setClock(Date.now());
    const timer = window.setInterval(tick, 1000); document.addEventListener('visibilitychange', tick);
    return () => {window.clearInterval(timer); document.removeEventListener('visibilitychange', tick);};
  }, [phase]);
  const needsCompanies = phase === 'practice' || phase === 'review';
  useEffect(() => {
    if (!needsCompanies) return;
    const controller = new AbortController(); setLoading(true); setMarketError(null);
    void market.search('a', {limit: 20, signal: controller.signal}).then(page => {
      if (controller.signal.aborted) return;
      const rows = companies(page.results); setChoices(rows);
      setSelected(prior => rows.find(row => row.assetId === prior?.assetId && row.mint === prior.mint) ?? null);
    }).catch(reason => {if (!controller.signal.aborted) setMarketError(reason);})
      .finally(() => {if (!controller.signal.aborted) setLoading(false);});
    return () => controller.abort();
  }, [market, needsCompanies, reload]);

  function go(next: Phase, push = true) {
    if (!mounted.current) return;
    currentPhase.current = next; markHistory(next, push); setPhase(next); setError(null);
  }
  /** false: Skip (records introduction-skipped). true: leave for the desk without any launch write. */
  async function exit(completed: boolean) {
    if (locked.current) return; locked.current = true; setBusy(true); setError(null);
    markHistory(currentPhase.current, false);
    try {await callbacks.current.onExit(completed);}
    catch (reason) {if (mounted.current) setError(reason);}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  function edit() {if (locked.current) return; setPreview(null); go('practice', false);}
  backAction.current = () => {
    if (locked.current) return;
    if (phase === 'review') edit();
    else if (phase === 'welcome') callbacks.current.onExplore();
    // The celebration owns Back: it continues, as on mobile. It never skips.
    else if (phase !== 'receipt') void exit(false);
  };
  function completedProfile(profile: ProductProfile | null): boolean {
    return profile?.launchCheckpoint === 'app' || profile?.hasConfirmedPaperTrade === true;
  }
  async function prepare() {
    if (locked.current) return; locked.current = true; setBusy(true); setError(null);
    initialCheck.current = true;
    try {
      await callbacks.current.ensureDesk(); if (!mounted.current) return;
      const profile = await session.readProfile(); if (!mounted.current) return;
      if (!profile) throw new Error('Your first-day profile is unavailable.');
      if (completedProfile(profile)) {await callbacks.current.onExit(profile.hasConfirmedPaperTrade); return;}
      initialCheck.current = true; setReady(true); if (currentPhase.current !== 'practice') go('practice');
    } catch (reason) {if (mounted.current) setError(reason);}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  useEffect(() => {
    // Resuming an existing first-day desk is safe; a fresh URL does not issue a guest.
    if (phase === 'practice' && session.hasIdentity && !initialCheck.current) {initialCheck.current = true; void prepare();}
  }, [phase, session]);

  const cash = portfolio ? BigInt(portfolio.cashPaperMicros) : null;
  const maximum = cash === null ? null : cash < 10_000_000_000n ? cash : 10_000_000_000n;
  const amountMicros = toPaperMicros(amount);
  const validAmount = amountMicros !== null && BigInt(amountMicros) >= 1_000_000n && maximum !== null && BigInt(amountMicros) <= maximum;
  const pending = session.pendingCommit !== null;
  const remaining = preview ? Math.max(0, Math.ceil((Date.parse(preview.expiresAt) - clock) / 1000)) : 0;
  async function review() {
    if (locked.current || !selected || !validAmount || !amountMicros || pending || !ready) return;
    locked.current = true; setBusy(true); setError(null);
    try {
      await callbacks.current.ensureDesk(); if (!mounted.current) return;
      const profile = await session.readProfile(); if (!mounted.current) return;
      if (!profile) throw new Error('Your first-day profile is unavailable.');
      if (completedProfile(profile)) {await callbacks.current.onExit(profile.hasConfirmedPaperTrade); return;}
      const quote = await session.previewOrder({action: 'buy', assetId: selected.assetId, variantMint: selected.mint,
        amount: {kind: 'paper_amount', paperMicros: amountMicros}});
      if (mounted.current) {setPreview(quote); setClock(Date.now()); go('review');}
    } catch (reason) {if (mounted.current) setError(reason);}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  async function confirm() {
    if (locked.current || !preview || pending || Date.parse(preview.expiresAt) <= Date.now()) return;
    locked.current = true; setBusy(true); setError(null);
    try {
      const order = await session.commitOrder(preview);
      if (!mounted.current) return;
      setReceipt(order); setPreview(null); go('receipt');
      try {await callbacks.current.onCommitted(order, selected ? {name: selected.name, logoUrl: tokenArt(selected.symbol)} : undefined);}
      catch {if (mounted.current) setNotice(true);}
    } catch (reason) {if (mounted.current) {setError(reason); callbacks.current.onPending();}}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  const companyName = selected?.name ?? receipt?.symbol ?? tr('firstDay.review.companyFallback');
  if (phase === 'receipt' && receipt) return <FirstOrderCelebration evidence={{orderId: receipt.id, assetId: receipt.assetId,
    variantMint: receipt.variantMint, symbol: receipt.symbol, quantityMicros: receipt.quantityMicros, cashDebitPaperMicros: receipt.cashDebitPaperMicros}}
    name={selected?.name ?? null} logoUrl={tokenArt(receipt.symbol)}
    career={career} loading={false} onRetry={() => {}} onContinue={() => callbacks.current.onReceiptContinue(receipt.id)}/>;
  return <section className={`first-day first-day-${phase}`} data-motion={props.motion} aria-label={tr('firstDay.screen.label')}>
    {phase !== 'welcome' && <button className="intro-close" aria-label={tr('firstDay.skip')} disabled={busy}
      onClick={() => void exit(false)}>×</button>}
    {phase === 'welcome' && <div className="intro-welcome"><div className="intro-art"><SalArt motion={props.motion}/></div><div className="intro-copy">
      <p className="intro-eyebrow">{tr('firstDay.welcome.eyebrow')}</p><h1 ref={heading} tabIndex={-1}>{tr('firstDay.welcome.title')}</h1>
      <p>{tr.rich('firstDay.welcome.lede')}</p><div className="intro-actions"><button className="primary" onClick={() => go('note')}>{tr('firstDay.welcome.start')}</button>
      <button className="text-button" onClick={props.onExplore}>{tr('firstDay.welcome.explore')}</button></div><p className="intro-disclosure">{tr('firstDay.welcome.noSignIn')}</p></div><MobileAppPrompt/></div>}
    {phase === 'note' && <div className="intro-note"><img className="intro-note-pin" src={art('ruby-pin-1.png')} alt=""/><p className="intro-eyebrow">{tr('firstDay.note.eyebrow')}</p><h1 ref={heading} tabIndex={-1}>{tr('firstDay.note.title')}</h1>
      <p>{tr('firstDay.note.body')}</p><img className="intro-note-arrow" src={art('curly-arrow.png')} alt=""/><button className="primary" disabled={busy} onClick={() => void prepare()}>{busy ? tr('firstDay.note.opening') : tr('common.continue')}</button></div>}
    {phase === 'practice' && <div className="intro-practice"><div className="intro-heading"><p className="intro-eyebrow">{tr('firstDay.practice.eyebrow')}</p><h1 ref={heading} tabIndex={-1}>{tr('firstDay.practice.title')}</h1><p>{tr('firstDay.practice.lede')}</p></div>
      {loading && <Loading>{tr('firstDay.practice.loading')}</Loading>}
      {marketError !== null && <div className="intro-error" role="alert"><p>{errorCopy(marketError)}</p><button className="text-button" disabled={busy} onClick={() => setReload(value => value + 1)}>{tr('firstDay.practice.retryCompanies')}</button></div>}
      {!loading && !marketError && choices.length === 0 && <div className="intro-error"><p>{tr('firstDay.practice.noCompanies')}</p><button className="text-button" disabled={busy} onClick={() => setReload(value => value + 1)}>{tr('firstDay.practice.retryCompanies')}</button></div>}
      <div className="intro-companies" aria-label={tr('firstDay.practice.companiesLabel')}>{choices.map(company => <button className="intro-company" key={company.mint} aria-label={tr('firstDay.practice.chooseCompany', {name: company.name})} aria-pressed={selected?.mint === company.mint}
        disabled={busy || pending || !ready} onClick={() => {setSelected(company); setError(null);}}><CompanyLogo name={company.name} url={tokenArt(company.symbol)}/><span className="intro-company-label"><strong>{company.name}</strong><small>{company.symbol ?? tr('firstDay.practice.symbolFallback')}</small></span></button>)}</div>
      <div className="intro-amount"><label htmlFor="first-day-amount">{tr('firstDay.practice.amountLabel')}</label><div className="intro-amount-input"><input id="first-day-amount" inputMode="decimal" autoComplete="off" maxLength={12}
        value={amount} aria-invalid={cash !== null && !validAmount} aria-describedby="first-day-balance first-day-amount-help" disabled={busy || pending} onChange={event => {setAmount(event.target.value); setError(null);}}
        onKeyDown={enterPresses(!busy && !pending && ready && selected !== null && validAmount, () => void review())}/><span>{tr('common.paperUnit')}</span></div>
        <div className="intro-amount-options">{['50', '100', '500'].map(value => <button key={value} disabled={busy || pending || maximum === null || BigInt(value) * 1_000_000n > maximum}
          aria-pressed={amount === value} onClick={() => {setAmount(value); setError(null);}}>{fmt.number(value)}</button>)}</div>
        <p className="intro-balance" id="first-day-balance">{cash === null ? tr('firstDay.practice.balanceUnavailable') : maximum! < 1_000_000n
          ? tr('firstDay.practice.balanceTooLow', {cash: micros(cash.toString()), minimum: 1})
          : tr('firstDay.practice.balanceRange', {cash: micros(cash.toString()), minimum: 1, maximum: micros(maximum!.toString())})}</p>
        {(!ready || cash === null) && !busy && <button className="text-button" onClick={() => void prepare()}>{tr('firstDay.practice.refreshDesk')}</button>}
      </div><button className="primary" disabled={busy || pending || !ready || !selected || !validAmount} onClick={() => void review()}>{busy ? tr('firstDay.practice.preparing') : tr('firstDay.practice.review')}</button>
      <p className="intro-disclosure">{tr('firstDay.practice.disclosure')}</p></div>}
    {phase === 'review' && preview && <div className="intro-review"><p className="intro-eyebrow">{companyName}</p><h1 ref={heading} tabIndex={-1}>{tr('firstDay.review.title')}</h1>
      <dl className="intro-summary"><div><dt>{tr('firstDay.review.token')}</dt><dd>{preview.symbol}</dd></div><div><dt>{tr('firstDay.review.shares')}</dt><dd>{shares(preview.quantityMicros)}</dd></div>
        <div><dt>{tr('firstDay.review.price')}</dt><dd>{tr('common.paperAmount', {amount: micros(preview.pricePaperMicros)})}</dd></div><div><dt>{tr('firstDay.review.fees')}</dt><dd>{tr('common.paperAmount', {amount: fmt.number('0.00')})}</dd></div>
        <div><dt>{tr('firstDay.review.spend')}</dt><dd>{tr('common.paperAmount', {amount: micros(preview.cashDebitPaperMicros)})}</dd></div><div><dt>{tr('firstDay.review.cashAfter')}</dt><dd>{tr('common.paperAmount', {amount: micros(preview.cashAfterPaperMicros)})}</dd></div></dl>
      <button className="primary" disabled={busy || pending || remaining === 0} onClick={() => void confirm()}>{busy ? tr('firstDay.review.confirming') : tr('firstDay.review.confirm')}</button>
      <p className="intro-disclosure">{remaining > 0 ? tr('firstDay.review.expiresIn', {seconds: remaining}) : tr('firstDay.review.expired')}</p><button className="text-button" disabled={busy} onClick={edit}>{tr('firstDay.review.edit')}</button></div>}
    {pending && phase !== 'receipt' && <div className="intro-pending" role="status"><strong>{tr('firstDay.pending.title')}</strong><p>{tr('firstDay.pending.body')}</p><button className="text-button" disabled={busy} onClick={() => void exit(true)}>{tr('firstDay.pending.check')}</button></div>}
    {error !== null && <p className="intro-error" role="alert">{errorCopy(error)}</p>}
    {notice && <p className="intro-error" role="status">{tr('firstDay.receipt.refreshing')}</p>}
  </section>;
}

function downloadUrl(value: unknown): string | null {
  if (typeof value !== 'string' || value.length > 2048 || value.trim() !== value) return null;
  try {const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password ? url.href : null;}
  catch {return null;}
}
export function MobileAppPrompt() {
  const tr = useT();
  const url = downloadUrl(import.meta.env?.['VITE_TRIMMY_ANDROID_APK_URL']);
  return <aside className="intro-mobile-prompt"><div><strong>{tr('firstDay.mobile.title')}</strong><p>{tr('firstDay.mobile.body')}</p></div>
    <div>{url ? <><a className="secondary" href={url} target="_blank" rel="noopener noreferrer">{tr('firstDay.mobile.download')}</a><small>{tr('firstDay.mobile.apk')}</small></> : <small>{tr('firstDay.mobile.soon')}</small>}
    <a className="text-button" href="https://x.com/trimmyhq" target="_blank" rel="noopener noreferrer">{tr('firstDay.mobile.updates')}</a></div></aside>;
}
