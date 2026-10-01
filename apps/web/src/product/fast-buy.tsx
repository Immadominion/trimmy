import {useEffect, useRef, useState} from 'react';
import type {ProductMarketClient, StockCard} from './market-client';
import type {PracticeSession} from './practice-session';
import type {PaperPortfolio, PaperPreview, PaperReceipt} from './practice-client';
import {PracticeError} from './practice-client';
import type {TradeReasonReceipt} from './career-actions';
import {CompanyLogo, Loading, errorCopy, micros, shares, toPaperMicros, usd} from './ui';
import {categoryLabel, categoryOf, marketFigures} from './market-social';

/**
 * Mobile's compact Fast buy (practice): find a company, choose an amount,
 * review the quote, confirm, then optionally say why. It uses the same durable
 * PracticeSession preview and commit boundary as the company page.
 */
export interface FastBuyProps {
  readonly market: ProductMarketClient; readonly session: PracticeSession; readonly portfolio: PaperPortfolio | null;
  readonly ensureDesk: () => Promise<void>; readonly onCommitted: (receipt: PaperReceipt) => Promise<void>; readonly onPending: () => void;
  readonly saveReason: ((orderId: string, note: string) => Promise<TradeReasonReceipt>) | null;
  readonly onClose: () => void;
}
type Step = 'search' | 'amount' | 'review' | 'receipt';
function reasonFailure(error: unknown): string {
  const code = error instanceof PracticeError ? error.code : '';
  if (code === 'CAREER_INVALID_INPUT') return 'Use one line and 180 characters or fewer.';
  if (code === 'PRACTICE_NETWORK_ERROR') return 'Trade confirmed. You are offline, so your reason was not saved. Try again.';
  if (code === 'PRACTICE_TIMEOUT') return 'Trade confirmed. Saving the reason took too long. Try again.';
  if (code === 'CAREER_REASON_EXISTS') return 'This trade already has a saved reason. Refresh your career.';
  if (code === 'CAREER_POSITION_REQUIRED') return 'Trade confirmed. Hold this stock before saving a reason.';
  return 'Trade confirmed. Your reason was not saved. Try again.';
}
export function FastBuySheet(props: FastBuyProps) {
  const {market, session, portfolio} = props;
  const [step, setStep] = useState<Step>('search');
  const [query, setQuery] = useState(''), [results, setResults] = useState<readonly StockCard[]>([]), [searching, setSearching] = useState(true), [searchError, setSearchError] = useState(false);
  const [searchAttempt, setSearchAttempt] = useState(0);
  const [company, setCompany] = useState<StockCard | null>(null), [amount, setAmount] = useState('100');
  const [preview, setPreview] = useState<PaperPreview | null>(null), [receipt, setReceipt] = useState<PaperReceipt | null>(null);
  const [busy, setBusy] = useState(false), [error, setError] = useState<unknown>(null), [clock, setClock] = useState(Date.now());
  const [note, setNote] = useState(''), [reason, setReason] = useState<TradeReasonReceipt | null>(null), [reasonError, setReasonError] = useState<string | null>(null);
  const heading = useRef<HTMLHeadingElement>(null), locked = useRef(false), mounted = useRef(true);
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  useEffect(() => {heading.current?.focus();}, [step]);
  useEffect(() => {
    const key = (event: KeyboardEvent) => {if (event.key === 'Escape' && !locked.current) {event.preventDefault(); props.onClose();}};
    window.addEventListener('keydown', key); return () => window.removeEventListener('keydown', key);
  }, [props.onClose]);
  useEffect(() => {
    if (step !== 'search') return;
    const controller = new AbortController(); setSearching(true); setSearchError(false);
    const timer = window.setTimeout(() => {
      const text = query.trim();
      void (text ? market.cards(text, {signal: controller.signal}).then(page => page.results) : market.catalog(0, {signal: controller.signal}).then(page => page.cards))
        .then(rows => {if (!controller.signal.aborted) {setResults(rows); setSearching(false);}}, () => {if (!controller.signal.aborted) {setSearchError(true); setSearching(false);}});
    }, query ? 300 : 0);
    return () => {clearTimeout(timer); controller.abort();};
  }, [market, query, step, searchAttempt]);
  useEffect(() => {if (!preview) return; const id = window.setInterval(() => setClock(Date.now()), 1000); return () => clearInterval(id);}, [preview]);
  const amountMicros = toPaperMicros(amount), cash = portfolio ? BigInt(portfolio.cashPaperMicros) : null;
  const valid = amountMicros !== null && cash !== null && BigInt(amountMicros) <= cash;
  const remaining = preview ? Math.max(0, Math.ceil((Date.parse(preview.expiresAt) - clock) / 1000)) : 0;
  const pending = session.pendingCommit !== null;
  async function run(task: () => Promise<void>) {
    if (locked.current) return; locked.current = true; setBusy(true); setError(null);
    try {await task();} catch (reason) {if (mounted.current) setError(reason);} finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  const review = () => run(async () => {
    if (!company?.primaryVariant || !amountMicros) return;
    await props.ensureDesk();
    const quote = await session.previewOrder({action: 'buy', assetId: company.assetId, variantMint: company.primaryVariant.mint, amount: {kind: 'paper_amount', paperMicros: amountMicros}});
    if (mounted.current) {setPreview(quote); setClock(Date.now()); setStep('review');}
  });
  const confirm = () => run(async () => {
    if (!preview || Date.parse(preview.expiresAt) <= Date.now()) return;
    try {
      const order = await session.commitOrder(preview);
      if (mounted.current) {setReceipt(order); setPreview(null); setStep('receipt');}
      await props.onCommitted(order);
    } catch (reason) {props.onPending(); throw reason;}
  });
  async function saveReason() {
    if (!receipt || !props.saveReason || locked.current) return;
    const text = note.trim(); if (!text) return;
    locked.current = true; setBusy(true); setReasonError(null);
    try {const saved = await props.saveReason(receipt.id, text); if (mounted.current) setReason(saved);}
    catch (failure) {if (mounted.current) setReasonError(reasonFailure(failure));}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  const name = company?.name ?? company?.assetId ?? 'this company';
  return <div className="settings-modal-backdrop" onClick={event => {if (event.target === event.currentTarget && !locked.current) props.onClose();}}>
    <div className="settings-modal fast-buy" role="dialog" aria-modal="true" aria-labelledby="fast-buy-title">
      <div className="fast-buy-head"><h2 id="fast-buy-title" ref={heading} tabIndex={-1}>{step === 'search' ? 'Fast buy' : step === 'review' ? 'Review your buy.' : step === 'receipt' ? 'Buy confirmed' : `Buy ${name}`}</h2>
        <button className="rank-close" aria-label="Close fast buy" disabled={busy} onClick={props.onClose}>×</button></div>
      {pending && !busy && <p className="trade-error" role="status">An order still needs checking. Check it from your desk first.</p>}
      {step === 'search' && <>
        <label className="sr-only" htmlFor="fast-buy-search">Search a name or ticker</label>
        <input id="fast-buy-search" className="reason-note" type="search" autoComplete="off" placeholder="Search a name or ticker" maxLength={80} value={query} onChange={event => setQuery(event.target.value)}/>
        <div className="fast-buy-results">{searching ? <Loading>Finding companies…</Loading> : searchError ? <p className="trade-error">Search did not finish. Try again.<button className="text-button" onClick={() => setSearchAttempt(value => value + 1)}>Retry</button></p>
          : !results.length ? <p className="company-social-note">No matches yet.</p>
          : results.map(card => <button key={card.assetId} className="holder-row fast-buy-company" aria-label={`Buy ${card.name ?? card.assetId}`} disabled={pending}
            onClick={() => {if (!card.primaryVariant) {setError(new PracticeError('FAST_BUY_NO_VERSION', 'This company has no available version.')); return;} setCompany(card); setError(null); setStep('amount');}}>
            <span className="holder-name fast-buy-name"><CompanyLogo name={card.name ?? card.assetId} url={card.imageUrl} size={32}/><span><strong>{card.name ?? card.assetId}</strong><small>{card.symbol ?? categoryLabel(categoryOf(card))}</small></span></span>
            <span className="holder-amount">{usd(marketFigures(card).price)}</span></button>)}</div>
      </>}
      {step === 'amount' && company && <>
        <p className="settings-modal-note">{company.primaryVariant?.symbol ?? company.symbol ?? 'Token'} · practice buy</p>
        <label className="settings-phrase" htmlFor="fast-buy-amount"><span>Amount to spend</span></label>
        <div className="amount-field"><input id="fast-buy-amount" inputMode="decimal" autoComplete="off" maxLength={12} value={amount} disabled={busy} onChange={event => {setAmount(event.target.value); setError(null);}}/><span>paper</span></div>
        <div className="amount-options">{['50', '100', '500'].map(value => <button key={value} aria-pressed={amount === value} disabled={busy} onClick={() => setAmount(value)}>{value}</button>)}</div>
        <p className="trade-available">{cash === null ? 'Paper balance unavailable. Refresh your desk.' : `${micros(cash.toString())} paper available`}</p>
        <button className="primary full" disabled={busy || pending || !valid} onClick={() => void review()}>{busy ? 'Checking price…' : 'Review buy'}</button>
        <button className="text-button full" disabled={busy} onClick={() => {setStep('search'); setError(null);}}>Choose another company</button>
      </>}
      {step === 'review' && preview && <>
        <dl className="review-summary"><div><dt>Shares</dt><dd>{shares(preview.quantityMicros)}</dd></div><div><dt>Price per share</dt><dd>{micros(preview.pricePaperMicros)} paper</dd></div>
          <div className="review-total"><dt>Total</dt><dd>{micros(preview.cashDebitPaperMicros)} paper</dd></div><div><dt>Paper cash after</dt><dd>{micros(preview.cashAfterPaperMicros)}</dd></div></dl>
        <button className="primary full" disabled={busy || pending || remaining === 0} onClick={() => void confirm()}>{busy ? 'Confirming buy…' : 'Confirm buy'}</button>
        <p className="quote-clock">{remaining > 0 ? `Quote expires in ${remaining}s` : 'Quote expired. Get a new review.'}</p>
        <button className="text-button full" disabled={busy} onClick={() => {setPreview(null); setStep('amount');}}>Edit amount</button>
      </>}
      {step === 'receipt' && receipt && <>
        <div className="receipt-mark" aria-hidden="true">✓</div>
        <p className="receipt-text">Bought {shares(receipt.quantityMicros)} shares of {name}.</p>
        <dl className="review-summary"><div><dt>Paper spent</dt><dd>{micros(receipt.cashDebitPaperMicros)}</dd></div><div><dt>Paper cash left</dt><dd>{micros(receipt.cashAfterPaperMicros)}</dd></div></dl>
        {props.saveReason && !reason && <>
          <label className="settings-phrase" htmlFor="fast-buy-reason"><span>Why did you buy?</span></label>
          <input id="fast-buy-reason" className="reason-note" maxLength={180} autoComplete="off" placeholder="One clear line" value={note} disabled={busy} onChange={event => {setNote(event.target.value.replace(/[\r\n]/gu, ' ')); setReasonError(null);}}/>
          {reasonError && <p className="trade-error" role="alert">{reasonError}</p>}
          <button className="primary full" disabled={busy || !note.trim()} onClick={() => void saveReason()}>{busy ? 'Saving…' : reasonError ? 'Retry reason' : 'Save reason'}</button>
          <button className="text-button full" disabled={busy} onClick={props.onClose}>Skip</button>
        </>}
        {reason && <p className="reason-reward" role="status">Reason saved{reason.trimsAwarded > 0 ? ` · +${reason.trimsAwarded} Trims` : ''}</p>}
        {(!props.saveReason || reason) && <button className="primary full" onClick={props.onClose}>Done</button>}
        <p className="trade-disclosure">Confirmed paper order. No real money was moved.</p>
      </>}
      {error !== null && <p className="trade-error" role="alert">{error instanceof PracticeError && error.code === 'FAST_BUY_NO_VERSION' ? 'This company has no available version.' : errorCopy(error)}</p>}
    </div>
  </div>;
}
