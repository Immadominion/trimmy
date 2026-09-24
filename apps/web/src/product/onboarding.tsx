import {useEffect, useRef, useState} from 'react';
import type {ProductMarketClient, StockDiscoveryAsset} from './market-client';
import type {CareerSummary, PaperPortfolio, PaperPreview, PaperReceipt, ProductProfile} from './practice-client';
import type {PracticeSession} from './practice-session';
import {CompanyLogo, Loading, SalArt, art, errorCopy, micros, shares, toPaperMicros} from './ui';

type Phase = 'welcome' | 'note' | 'practice' | 'review' | 'receipt';
interface Company {assetId: string; name: string; symbol: string; mint: string}
export interface FirstDayProps {
  readonly initialStep: 'welcome' | 'note' | 'practice'; readonly motion: boolean;
  readonly market: ProductMarketClient; readonly session: PracticeSession;
  readonly portfolio: PaperPortfolio | null; readonly career: CareerSummary | null;
  readonly ensureDesk: () => Promise<void>; readonly onExplore: () => void;
  readonly onExit: (completed: boolean) => Promise<void>;
  readonly onCommitted: (receipt: PaperReceipt) => Promise<void>; readonly onPending: () => void;
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
      symbol: variant.symbol ?? asset.symbol ?? 'Stock token', mint: variant.mint}] : [];
  }).slice(0, 3);
}
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
  const [notice, setNotice] = useState<string | null>(null), [clock, setClock] = useState(Date.now);
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
    else void exit(phase === 'receipt');
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
      try {await callbacks.current.onCommitted(order);}
      catch {if (mounted.current) setNotice('Your order is confirmed. Your desk is still refreshing.');}
    } catch (reason) {if (mounted.current) {setError(reason); callbacks.current.onPending();}}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  const receiptCareer = receipt && career?.firstConfirmedBuy?.orderId === receipt.id ? career : null;
  const companyName = selected?.name ?? receipt?.symbol ?? 'your company';
  return <section className={`first-day first-day-${phase}`} data-motion={props.motion} aria-label="Your first day">
    {phase !== 'welcome' && <button className="intro-close" aria-label={phase === 'receipt' ? 'Go to your desk' : 'Skip first day'} disabled={busy}
      onClick={() => void exit(phase === 'receipt')}>×</button>}
    {phase === 'welcome' && <div className="intro-welcome"><div className="intro-art"><SalArt motion={props.motion}/></div><div className="intro-copy">
      <p className="intro-eyebrow">Sal’s saved you a seat.</p><h1 ref={heading} tabIndex={-1}>Your first day starts here.</h1>
      <p>Pick a company. Make a move.<br/>Find your feet on Wall Street.</p><div className="intro-actions"><button className="primary" onClick={() => go('note')}>Start my first day</button>
      <button className="text-button" onClick={props.onExplore}>Take a look around</button></div><p className="intro-disclosure">No sign-in needed.</p></div><MobileAppPrompt/></div>}
    {phase === 'note' && <div className="intro-note"><img className="intro-note-pin" src={art('ruby-pin-1.png')} alt=""/><p className="intro-eyebrow">A note from Sal</p><h1 ref={heading} tabIndex={-1}>Welcome to the floor.</h1>
      <p>{'Your first day starts with practice.\n\nPick a company. It’s free.'}</p><img className="intro-note-arrow" src={art('curly-arrow.png')} alt=""/><button className="primary" disabled={busy} onClick={() => void prepare()}>{busy ? 'Opening your desk…' : 'Continue'}</button></div>}
    {phase === 'practice' && <div className="intro-practice"><div className="intro-heading"><p className="intro-eyebrow">Your first move</p><h1 ref={heading} tabIndex={-1}>Pick a company you know.</h1><p>Start small. This one’s practice.</p></div>
      {loading && <Loading>Finding companies…</Loading>}
      {marketError !== null && <div className="intro-error" role="alert"><p>{errorCopy(marketError)}</p><button className="text-button" disabled={busy} onClick={() => setReload(value => value + 1)}>Try companies again</button></div>}
      {!loading && !marketError && choices.length === 0 && <div className="intro-error"><p>No companies are available just yet.</p><button className="text-button" disabled={busy} onClick={() => setReload(value => value + 1)}>Try companies again</button></div>}
      <div className="intro-companies" aria-label="Choose a company">{choices.map(company => <button className="intro-company" key={company.mint} aria-label={`Choose ${company.name}`} aria-pressed={selected?.mint === company.mint}
        disabled={busy || pending || !ready} onClick={() => {setSelected(company); setError(null);}}><CompanyLogo name={company.name} url={['AAPLx', 'TSLAx', 'METAx'].includes(company.symbol) ? art(`token-${company.symbol}.webp`) : null}/><span className="intro-company-label"><strong>{company.name}</strong><small>{company.symbol}</small></span></button>)}</div>
      <div className="intro-amount"><label htmlFor="first-day-amount">Amount to practice</label><div className="intro-amount-input"><input id="first-day-amount" inputMode="decimal" autoComplete="off" maxLength={12}
        value={amount} aria-invalid={cash !== null && !validAmount} aria-describedby="first-day-balance first-day-amount-help" disabled={busy || pending} onChange={event => {setAmount(event.target.value); setError(null);}}/><span>paper</span></div>
        <div className="intro-amount-options">{['50', '100', '500'].map(value => <button key={value} disabled={busy || pending || maximum === null || BigInt(value) * 1_000_000n > maximum}
          aria-pressed={amount === value} onClick={() => {setAmount(value); setError(null);}}>{value}</button>)}</div>
        <p className="intro-balance" id="first-day-balance">{cash === null ? 'Your paper balance is unavailable.' : maximum! < 1_000_000n ? `${micros(cash.toString())} paper available. You need at least 1 paper to practice.` : `${micros(cash.toString())} paper available. Practice with 1 to ${micros(maximum!.toString())} paper.`}</p>
        {(!ready || cash === null) && !busy && <button className="text-button" onClick={() => void prepare()}>Refresh your desk</button>}
      </div><button className="primary" disabled={busy || pending || !ready || !selected || !validAmount} onClick={() => void review()}>{busy ? 'Getting ready…' : 'Review paper buy'}</button>
      <p className="intro-disclosure">You’ll review your quote before confirming. No real money moves.</p></div>}
    {phase === 'review' && preview && <div className="intro-review"><p className="intro-eyebrow">{companyName}</p><h1 ref={heading} tabIndex={-1}>Review your first move.</h1>
      <dl className="intro-summary"><div><dt>Company token</dt><dd>{preview.symbol}</dd></div><div><dt>Shares</dt><dd>{shares(preview.quantityMicros)}</dd></div>
        <div><dt>Price per share</dt><dd>{micros(preview.pricePaperMicros)} paper</dd></div><div><dt>Fees</dt><dd>0.00 paper</dd></div>
        <div><dt>Paper to spend</dt><dd>{micros(preview.cashDebitPaperMicros)} paper</dd></div><div><dt>Paper cash after</dt><dd>{micros(preview.cashAfterPaperMicros)} paper</dd></div></dl>
      <button className="primary" disabled={busy || pending || remaining === 0} onClick={() => void confirm()}>{busy ? 'Confirming…' : 'Confirm paper buy'}</button>
      <p className="intro-disclosure">{remaining > 0 ? `Quote expires in ${remaining}s` : 'Quote expired. Get a new review.'}</p><button className="text-button" disabled={busy} onClick={edit}>Edit amount</button></div>}
    {phase === 'receipt' && receipt && <div className="intro-receipt"><div className="intro-receipt-mark" aria-hidden="true">✓</div><h1 ref={heading} tabIndex={-1}>Your first move is made.</h1>
      <p>You bought {shares(receipt.quantityMicros)} shares of {receipt.symbol}.</p><dl className="intro-summary"><div><dt>Paper spent</dt><dd>{micros(receipt.cashDebitPaperMicros)}</dd></div>
        <div><dt>Paper cash left</dt><dd>{micros(receipt.cashAfterPaperMicros)}</dd></div></dl>
      {receiptCareer && <p className="intro-reward">{receiptCareer.rank.label} · {receiptCareer.trims.total.toLocaleString()} Trims total</p>}
      <button className="primary" disabled={busy} onClick={() => void exit(true)}>{busy ? 'Updating your desk…' : 'Go to my desk'}</button><p className="intro-disclosure">Confirmed paper order. No real money moved.</p><MobileAppPrompt/></div>}
    {pending && phase !== 'receipt' && <div className="intro-pending" role="status"><strong>Your last order needs checking.</strong><p>Return to your desk to recover its result before making another move.</p><button className="text-button" disabled={busy} onClick={() => void exit(false)}>Check from desk</button></div>}
    {error !== null && <p className="intro-error" role="alert">{errorCopy(error)}</p>}
    {notice !== null && <p className="intro-error" role="status">{notice}</p>}
  </section>;
}

function downloadUrl(value: unknown): string | null {
  if (typeof value !== 'string' || value.length > 2048 || value.trim() !== value) return null;
  try {const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password ? url.href : null;}
  catch {return null;}
}
export function MobileAppPrompt() {
  const url = downloadUrl(import.meta.env?.['VITE_TRIMMY_ANDROID_APK_URL']);
  return <aside className="intro-mobile-prompt"><div><strong>Better on mobile.</strong><p>Get Trimmy on your phone for the full experience.</p></div>
    <div>{url ? <><a className="secondary" href={url} target="_blank" rel="noopener noreferrer">Download for Android</a><small>APK download</small></> : <small>Download coming soon</small>}
    <a className="text-button" href="https://x.com/trimmyhq" target="_blank" rel="noopener noreferrer">Launch updates</a></div></aside>;
}
