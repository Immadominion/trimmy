import {useEffect, useRef, useState} from 'react';
import type {ProductMarketClient, StockCard} from './market-client';
import type {PracticeSession} from './practice-session';
import type {PaperPortfolio, PaperPreview, PaperReceipt} from './practice-client';
import {PracticeError} from './practice-client';
import type {TradeReasonReceipt} from './career-actions';
import {CompanyLogo, Loading, errorCopy, micros, shares, toPaperMicros, usd} from './ui';
import {categoryLabel, categoryOf, marketFigures, shareCount} from './market-social';
import {useT, type Translator} from '../i18n/react';

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
function reasonFailure(tr: Translator, error: unknown): string {
  const code = error instanceof PracticeError ? error.code : '';
  if (code === 'CAREER_INVALID_INPUT') return tr('market.fastBuy.reason.invalid', {max: 180});
  if (code === 'PRACTICE_NETWORK_ERROR') return tr('market.fastBuy.reason.offline');
  if (code === 'PRACTICE_TIMEOUT') return tr('market.fastBuy.reason.timeout');
  if (code === 'CAREER_REASON_EXISTS') return tr('market.fastBuy.reason.exists');
  if (code === 'CAREER_POSITION_REQUIRED') return tr('market.fastBuy.reason.position');
  return tr('market.fastBuy.reason.failed');
}
export function FastBuySheet(props: FastBuyProps) {
  const {market, session, portfolio} = props;
  const tr = useT();
  const [step, setStep] = useState<Step>('search');
  const [query, setQuery] = useState(''), [results, setResults] = useState<readonly StockCard[]>([]), [searching, setSearching] = useState(true), [searchError, setSearchError] = useState(false);
  const [searchAttempt, setSearchAttempt] = useState(0);
  const [company, setCompany] = useState<StockCard | null>(null), [amount, setAmount] = useState('100');
  const [preview, setPreview] = useState<PaperPreview | null>(null), [receipt, setReceipt] = useState<PaperReceipt | null>(null);
  const [busy, setBusy] = useState(false), [error, setError] = useState<unknown>(null), [clock, setClock] = useState(Date.now());
  const [note, setNote] = useState(''), [reason, setReason] = useState<TradeReasonReceipt | null>(null), [reasonError, setReasonError] = useState<{failure: unknown} | null>(null);
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
    catch (failure) {if (mounted.current) setReasonError({failure});}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  const name = company?.name ?? company?.assetId ?? null;
  return <div className="settings-modal-backdrop" onClick={event => {if (event.target === event.currentTarget && !locked.current) props.onClose();}}>
    <div className="settings-modal fast-buy" role="dialog" aria-modal="true" aria-labelledby="fast-buy-title">
      <div className="fast-buy-head"><h2 id="fast-buy-title" ref={heading} tabIndex={-1}>{step === 'search' ? tr('market.fastBuy.title') : step === 'review' ? tr('market.trade.reviewTitle', {action: 'buy'})
          : step === 'receipt' ? tr('market.fastBuy.confirmedTitle') : name === null ? tr('market.fastBuy.buyUnknown') : tr('market.fastBuy.buyName', {name})}</h2>
        <button className="rank-close" aria-label={tr('market.fastBuy.close')} disabled={busy} onClick={props.onClose}>×</button></div>
      {pending && !busy && <p className="trade-error" role="status">{tr('market.fastBuy.pending')}</p>}
      {step === 'search' && <>
        <label className="sr-only" htmlFor="fast-buy-search">{tr('market.fastBuy.search')}</label>
        <input id="fast-buy-search" className="reason-note" type="search" autoComplete="off" autoCorrect="off" autoCapitalize="none" spellCheck={false} placeholder={tr('market.fastBuy.search')} maxLength={80} value={query} onChange={event => setQuery(event.target.value)}/>
        <div className="fast-buy-results">{searching ? <Loading>{tr('market.fastBuy.finding')}</Loading> : searchError ? <p className="trade-error">{tr('market.fastBuy.searchFailed')}<button className="text-button" onClick={() => setSearchAttempt(value => value + 1)}>{tr('market.fastBuy.retry')}</button></p>
          : !results.length ? <p className="company-social-note">{tr('market.fastBuy.noMatches')}</p>
          : results.map(card => <button key={card.assetId} className="holder-row fast-buy-company" aria-label={tr('market.fastBuy.buyName', {name: card.name ?? card.assetId})} disabled={pending}
            onClick={() => {if (!card.primaryVariant) {setError(new PracticeError('FAST_BUY_NO_VERSION', 'This company has no available version.')); return;} setCompany(card); setError(null); setStep('amount');}}>
            <span className="holder-name fast-buy-name"><CompanyLogo name={card.name ?? card.assetId} url={card.imageUrl} size={32}/><span><strong>{card.name ?? card.assetId}</strong><small>{card.symbol ?? categoryLabel(categoryOf(card))}</small></span></span>
            <span className="holder-amount">{usd(marketFigures(card).price)}</span></button>)}</div>
      </>}
      {step === 'amount' && company && <>
        <p className="settings-modal-note">{tr('market.fastBuy.practiceBuy', {symbol: company.primaryVariant?.symbol ?? company.symbol ?? tr('market.fastBuy.tokenFallback')})}</p>
        <label className="settings-phrase" htmlFor="fast-buy-amount"><span>{tr('market.trade.amountToSpend')}</span></label>
        <div className="amount-field"><input id="fast-buy-amount" inputMode="decimal" autoComplete="off" maxLength={12} value={amount} disabled={busy} onChange={event => {setAmount(event.target.value); setError(null);}}/><span>{tr('common.paperUnit')}</span></div>
        <div className="amount-options">{['50', '100', '500'].map(value => <button key={value} aria-pressed={amount === value} disabled={busy} onClick={() => setAmount(value)}>{value}</button>)}</div>
        <p className="trade-available">{cash === null ? tr('market.trade.balanceUnavailable') : tr('market.trade.available', {amount: micros(cash.toString())})}</p>
        <button className="primary full" disabled={busy || pending || !valid} onClick={() => void review()}>{tr(busy ? 'market.fastBuy.checkingPrice' : 'market.fastBuy.reviewBuy')}</button>
        <button className="text-button full" disabled={busy} onClick={() => {setStep('search'); setError(null);}}>{tr('market.fastBuy.another')}</button>
      </>}
      {step === 'review' && preview && <>
        <dl className="review-summary"><div><dt>{tr('market.trade.shares')}</dt><dd>{shares(preview.quantityMicros)}</dd></div><div><dt>{tr('market.trade.pricePerShare')}</dt><dd>{tr('common.paperAmount', {amount: micros(preview.pricePaperMicros)})}</dd></div>
          <div className="review-total"><dt>{tr('market.fastBuy.total')}</dt><dd>{tr('common.paperAmount', {amount: micros(preview.cashDebitPaperMicros)})}</dd></div><div><dt>{tr('market.trade.cashAfter')}</dt><dd>{micros(preview.cashAfterPaperMicros)}</dd></div></dl>
        <button className="primary full" disabled={busy || pending || remaining === 0} onClick={() => void confirm()}>{tr(busy ? 'market.fastBuy.confirming' : 'market.fastBuy.confirm')}</button>
        <p className="quote-clock">{remaining > 0 ? tr('market.trade.expiresIn', {seconds: remaining}) : tr('market.trade.expired')}</p>
        <button className="text-button full" disabled={busy} onClick={() => {setPreview(null); setStep('amount');}}>{tr('market.trade.editAmount')}</button>
      </>}
      {step === 'receipt' && receipt && <>
        <div className="receipt-mark" aria-hidden="true">✓</div>
        <p className="receipt-text">{name === null ? tr('market.fastBuy.boughtUnknown', {shares: shareCount(receipt.quantityMicros)})
          : tr('market.trade.receiptShares', {action: 'buy', shares: shareCount(receipt.quantityMicros), name})}</p>
        <dl className="review-summary"><div><dt>{tr('market.trade.paperSpent')}</dt><dd>{micros(receipt.cashDebitPaperMicros)}</dd></div><div><dt>{tr('market.trade.cashLeft')}</dt><dd>{micros(receipt.cashAfterPaperMicros)}</dd></div></dl>
        {props.saveReason && !reason && <>
          <label className="settings-phrase" htmlFor="fast-buy-reason"><span>{tr('market.fastBuy.why')}</span></label>
          <input id="fast-buy-reason" className="reason-note" maxLength={180} autoComplete="off" placeholder={tr('market.fastBuy.reasonPlaceholder')} value={note} disabled={busy} onChange={event => {setNote(event.target.value.replace(/[\r\n]/gu, ' ')); setReasonError(null);}}/>
          {reasonError && <p className="trade-error" role="alert">{reasonFailure(tr, reasonError.failure)}</p>}
          <button className="primary full" disabled={busy || !note.trim()} onClick={() => void saveReason()}>{tr(busy ? 'market.fastBuy.saving' : reasonError ? 'market.fastBuy.retryReason' : 'market.fastBuy.saveReason')}</button>
          <button className="text-button full" disabled={busy} onClick={props.onClose}>{tr('market.fastBuy.skip')}</button>
        </>}
        {reason && <p className="reason-reward" role="status">{reason.trimsAwarded > 0 ? tr('market.fastBuy.reasonSavedTrims', {count: reason.trimsAwarded}) : tr('market.fastBuy.reasonSaved')}</p>}
        {(!props.saveReason || reason) && <button className="primary full" onClick={props.onClose}>{tr('common.done')}</button>}
        <p className="trade-disclosure">{tr('market.trade.disclosure')}</p>
      </>}
      {error !== null && <p className="trade-error" role="alert">{error instanceof PracticeError && error.code === 'FAST_BUY_NO_VERSION' ? tr('market.fastBuy.noVersion') : errorCopy(error)}</p>}
    </div>
  </div>;
}
