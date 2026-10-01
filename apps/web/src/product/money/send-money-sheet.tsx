/**
 * Send: USDC, SOL or a stock token to another Solana wallet. The server
 * reviews and simulates the transfer; the embedded wallet signs exactly that
 * transaction here; nothing is sent without the signature. Copy mirrors
 * mobile's send_money_flow.dart.
 */
import {useEffect, useId, useRef, useState} from 'react';
import {amountRaw, formatRawUnits, rawDecimal, ShareScale, SOL_DECIMALS, USDC_DECIMALS} from './amounts.js';
import {useMoney} from './money-api.js';
import {coherentHoldings} from './wallet-controller.js';
import type {HoldingsSnapshot} from './wallet-models.js';
import {TransferError, transferCopy, type TransferReview} from './wallet-transfer-client.js';
import type {MoneyCopy} from './live-order-client.js';
import {useT} from '../../i18n/react.js';
import {t} from '../../i18n/runtime.js';
import * as fmt from '../../i18n/format.js';

const ADDRESS = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
/** SOL kept back by Max, so the wallet can still pay fees afterwards. */
const SOL_RESERVE = 2_000_000n;

export interface SendAsset {
  /** `USDC`, `SOL` or the token's mint, as the server takes it. */
  readonly id: string; readonly symbol: string; readonly name: string; readonly decimals: number;
  /** What is ready to send from the token's main account. */
  readonly availableRaw: string; readonly scale: ShareScale;
}
export const isStockAsset = (asset: SendAsset) => asset.id !== 'USDC' && asset.id !== 'SOL';

/** Everything in the wallet that can be sent now, cash first. */
export function sendableAssets(holdings: HoldingsSnapshot, nameFor?: (mint: string) => string | undefined): SendAsset[] {
  const positive = (raw: string) => /^[0-9]+$/.test(raw) && BigInt(raw) > 0n;
  return [
    ...positive(holdings.usdc.availableToTradeRaw) ? [{id: 'USDC', symbol: 'USDC', name: t('money.send.usdcName'), decimals: USDC_DECIMALS,
      availableRaw: holdings.usdc.availableToTradeRaw, scale: ShareScale.plain(USDC_DECIMALS)}] : [],
    ...positive(holdings.nativeSolLamports) ? [{id: 'SOL', symbol: 'SOL', name: t('money.send.solName'), decimals: SOL_DECIMALS,
      availableRaw: holdings.nativeSolLamports, scale: ShareScale.plain(SOL_DECIMALS)}] : [],
    ...holdings.stockTokens.filter(token => positive(token.availableToTradeRaw)).map(token => ({id: token.mint, symbol: token.symbol,
      name: nameFor?.(token.mint) ?? token.name, decimals: token.decimals, availableRaw: token.availableToTradeRaw,
      scale: ShareScale.fromDisplay(token.decimals, token.amountRaw, token.displayAmount)})),
  ];
}

export function maxRaw(asset: SendAsset): string {
  if (asset.id !== 'SOL') return asset.availableRaw;
  const left = BigInt(asset.availableRaw) - SOL_RESERVE;
  return left > 0n ? left.toString() : '0';
}
/** An amount for reading, in the page's language. */
const label = (asset: SendAsset, raw: string) => isStockAsset(asset) ? asset.scale.label(raw) : fmt.number(formatRawUnits(raw, asset.decimals) ?? raw);
const rawFor = (asset: SendAsset, text: string) => isStockAsset(asset) ? asset.scale.raw(text.trim()) : amountRaw(text.trim(), asset.decimals);
const sol = (lamports: string) => `${fmt.number(rawDecimal(lamports, SOL_DECIMALS))} SOL`;

type Stage = 'details' | 'review' | 'sending' | 'done';

export function SendMoneySheet({onClose, nameFor}: {onClose(): void; nameFor?: (mint: string) => string | undefined}) {
  const money = useMoney();
  const tr = useT();
  const titleId = useId();
  const holdings = coherentHoldings(money.wallet);
  const assets = holdings ? sendableAssets(holdings, nameFor) : [];
  const [assetId, setAssetId] = useState<string | null>(null);
  const asset = assets.find(item => item.id === assetId) ?? assets[0] ?? null;
  const [to, setTo] = useState(''), [amount, setAmount] = useState('');
  const [review, setReview] = useState<TransferReview | null>(null);
  const [stage, setStage] = useState<Stage>('details');
  const [busy, setBusy] = useState(true), [message, setMessage] = useState<MoneyCopy | null>(null);
  const [signature, setSignature] = useState<string | null>(null), [status, setStatus] = useState<'pending' | 'confirmed' | 'failed' | 'expired'>('pending');
  const closeButton = useRef<HTMLButtonElement>(null), opener = useRef<Element | null>(null), active = useRef(true);
  useEffect(() => {
    active.current = true; opener.current = document.activeElement; closeButton.current?.focus();
    return () => {active.current = false; if (opener.current instanceof HTMLElement) opener.current.focus();};
  }, []);
  // What can be sent comes from a fresh read of the wallet.
  const refreshRef = useRef(money.refreshWallet); refreshRef.current = money.refreshWallet;
  useEffect(() => {void refreshRef.current();}, []);

  const transfersRef=useRef(money.transfers);transfersRef.current=money.transfers;
  async function recover() {
    setBusy(true);setMessage(null);setRecoveryFailed(false);
    try {
      const saved=await transfersRef.current?.recovery();
      if(!active.current)return;
      if(saved) {
        if (holdings?.walletAddress && saved.review.from !== holdings.walletAddress) throw new TransferError('WALLET_CHANGED');
        setReview(saved.review);setSignature(saved.signature);
        if(saved.status==='reviewed')setStage('review');
        else {setStatus(saved.status);setStage(saved.status==='pending'?'sending':'done');}
      }
      setBusy(false);
    }catch {if(active.current){setMessage({key: 'money.send.recoveryFailed'});setBusy(false);setRecoveryFailed(true);}}
  }
  const [recoveryFailed,setRecoveryFailed]=useState(false);
  useEffect(()=>{void recover();},[]);

  // Provider refreshes must not restart the observation window.
  useEffect(() => {
    if (stage !== 'sending' || signature === null || !transfersRef.current) return;
    let polls = 0, checking = false, cancelled = false;
    const timer = window.setInterval(() => {
      if (checking) return;
      checking = true; polls += 1;
      void transfersRef.current!.status(signature).then(next => {
        if (cancelled || !active.current || next === 'pending' && polls < 30) return;
        clearInterval(timer); setStatus(next); setStage('done'); void refreshRef.current();
      }, () => {if (!cancelled && polls >= 30 && active.current) {clearInterval(timer); setStage('done');}})
        .finally(() => {checking = false;});
    }, 2000);
    return () => {cancelled = true; clearInterval(timer);};
  }, [stage, signature]);

  function problem(): MoneyCopy | null {
    if (!asset) return null;
    const destination = to.trim();
    if (!ADDRESS.test(destination)) return {key: 'money.send.needAddress'};
    if (destination === holdings?.walletAddress) return {key: 'money.sendError.destinationSelf'};
    const raw = rawFor(asset, amount);
    if (raw === null || raw === '0') return {key: 'money.send.needAmount'};
    const ready = asset;
    if (BigInt(raw) > BigInt(asset.availableRaw)) return {key: 'money.send.tooMuch', params: {get amount() {return label(ready, ready.availableRaw);}, symbol: asset.symbol}};
    return null;
  }

  async function preview() {
    if (!asset || !money.transfers || busy || recoveryFailed) return;
    const issue = problem();
    if (issue) {setMessage(issue); return;}
    const destination = to.trim(), raw = rawFor(asset, amount)!;
    setBusy(true); setMessage(null);
    try {
      const next = await money.transfers.preview({asset: asset.id, destination, amountRaw: raw});
      // The review must be the send that was asked for, from this wallet.
      if (next.assetId !== asset.id || next.destination !== destination || next.amountRaw !== raw || next.decimals !== asset.decimals || next.from !== holdings?.walletAddress) {
        throw new TransferError('TRANSFER_UNAVAILABLE');
      }
      if (active.current) {setReview(next); setStage('review');}
    } catch (error) {
      if (active.current && error instanceof TransferError && error.code === 'TRANSFER_PENDING') await recover();
      else if (active.current) setMessage(error instanceof TransferError ? error.copy : transferCopy(''));
    }
    finally {if (active.current) setBusy(false);}
  }

  async function send() {
    if (!review || !money.transfers || busy) return;
    setBusy(true); setMessage(null);
    try {
      const sent = await money.transfers.send(review);
      if (active.current) {setSignature(sent); setStage('sending');}
    } catch (error) {
      if (!active.current) return;
      const code = error instanceof TransferError ? error.code : error instanceof Error && 'code' in error ? String(error.code) : '';
      if(!['INVALID_TRANSACTION','SIGNATURE_MISMATCH','SIGNING_CANCELLED','SIGNING_TIMEOUT','TRANSFER_STORAGE','ACCOUNT_REQUIRED','WALLET_CHANGED','WALLET_BUSY'].includes(code)) {await recover();return;}
      setMessage(transferCopy(code));
      if (['REVIEW_EXPIRED', 'INVALID_REVIEW', 'INVALID_SIGNATURE', 'QUOTE_EXPIRED'].includes(code)) {setReview(null); setStage('details');}
    } finally {if (active.current) setBusy(false);}
  }

  const close = () => {if (!busy) onClose();};
  return <div className="money-sheet-backdrop" onMouseDown={event => {if (event.target === event.currentTarget) close();}}>
    <section className="money-sheet send-money" role="dialog" aria-modal="true" aria-labelledby={titleId}
      onKeyDown={event => {if (event.key === 'Escape') {event.stopPropagation(); close();}}}>
      <header className="money-sheet-head"><h2 id={titleId}>{tr('money.send.title')}</h2>
        <button ref={closeButton} className="money-close" aria-label={tr('money.close')} disabled={busy} onClick={close}>×</button></header>
      {stage === 'details' ? !asset ? <div className="fund-state"><h3>{tr('money.send.emptyTitle')}</h3>
          <p className="fund-note">{tr('money.send.emptyBody')}</p></div>
        : <form className="send-form" onSubmit={event => {event.preventDefault(); void preview();}}>
          <p className="fund-note">{tr('money.send.warning')}</p>
          <label>{tr('money.send.what')}<select data-testid="send-asset" value={asset.id} disabled={busy}
            onChange={event => {setAssetId(event.target.value); setAmount(''); setMessage(null);}}>
            {assets.map(item => <option key={item.id} value={item.id}>{`${item.name} · ${label(item, item.availableRaw)} ${item.symbol}`}</option>)}
          </select></label>
          <label>{tr('money.send.recipient')}<input data-testid="send-destination" value={to} disabled={busy} autoComplete="off" spellCheck={false}
            maxLength={44} onChange={event => setTo(event.target.value.replace(/[^1-9A-HJ-NP-Za-km-z]/g, ''))}/></label>
          <label>{isStockAsset(asset) ? tr('money.send.shares') : tr('money.send.amount', {symbol: asset.symbol})}
            <span className="send-amount"><input data-testid="send-amount" inputMode="decimal" value={amount} disabled={busy} maxLength={40}
              onChange={event => setAmount(fmt.amountCharacters(event.target.value))}/>
              <button type="button" className="text-button" data-testid="send-max" disabled={busy}
                onClick={() => setAmount(fmt.decimalInput(isStockAsset(asset) ? asset.scale.shares(maxRaw(asset)) : rawDecimal(maxRaw(asset), asset.decimals)))}>{tr('money.max')}</button></span>
            <small>{tr('money.send.ready', {amount: label(asset, asset.availableRaw), symbol: asset.symbol})}</small></label>
          {asset.id === 'SOL' && <p className="fund-note subtle">{tr('money.send.solReserve', {amount: fmt.number('0.002')})}</p>}
          <button className="primary" data-testid="send-review" disabled={busy || recoveryFailed || !money.transfers}>{busy ? tr('common.checking') : tr('money.send.review')}</button>
        </form>
      : stage === 'review' && review ? <div className="send-review">
          <dl className="send-summary">
            <div><dt>{tr('money.send.youSend')}</dt><dd>{reviewAmount(review, review.amountRaw, asset)}</dd></div>
            {review.receivedRaw !== review.amountRaw && <div><dt>{tr('money.send.theyReceive')}</dt><dd>{reviewAmount(review, review.receivedRaw, asset)}</dd></div>}
            <div><dt>{tr('money.send.networkFee')}</dt><dd>{sol(review.networkFeeLamports)}</dd></div>
            {review.createsAccount && <div><dt>{tr('money.send.opensAccount', {symbol: review.symbol})}</dt><dd>{sol(review.accountRentLamports)}</dd></div>}
          </dl>
          <h3>{tr('money.send.toWallet')}</h3>
          <code className="send-destination" data-testid="send-review-destination">{review.destination}</code>
          <p className="fund-note">{tr('money.send.checkAddress')}</p>
          <button className="primary" data-testid="send-confirm" disabled={busy || recoveryFailed} onClick={() => void send()}>{busy ? tr('money.send.sending') : tr('money.send.sendNow')}</button>
          <button className="text-button" disabled={busy} onClick={() => {setReview(null); setStage('details');}}>{tr('money.send.edit')}</button>
        </div>
      : <div className="fund-state" role="status">
          <h3 data-testid="send-result">{stage === 'sending' ? tr('money.send.status.sending') : status === 'confirmed' ? tr('money.send.status.sent') : status === 'failed' ? tr('money.send.status.failed') : status==='expired'?tr('money.send.status.expired'):tr('money.send.status.pending')}</h3>
          <p className="fund-note">{stage === 'sending' ? tr('money.send.body.sending') : status === 'confirmed' ? tr('money.send.body.sent')
            : status === 'failed' ? tr('money.send.body.failed') : status==='expired'?tr('money.send.body.expired'):tr('money.send.body.pending')}</p>
          {signature && <a href={`https://solscan.io/tx/${signature}`} target="_blank" rel="noreferrer">{tr('money.send.solscan')}</a>}
          {stage === 'done' && <button className="primary" onClick={()=>{
            try {if(status!=='pending')money.transfers?.acknowledge();onClose();}
            catch {setMessage({key: 'money.send.saved'});}
          }}>{tr('common.done')}</button>}
        </div>}
      {recoveryFailed && <button className="primary" onClick={()=>{setRecoveryFailed(false);void recover();}}>{tr('money.send.checkPrevious')}</button>}
      {message && <p className="fund-message" role="alert" data-testid="send-message">{tr(message.key, message.params)}</p>}
    </section>
  </div>;
}

function reviewAmount(review: TransferReview, raw: string, asset: SendAsset | null): string {
  const scale = review.assetId === 'SOL' || review.assetId === 'USDC' ? null
    : asset && asset.id === review.assetId ? ShareScale.fromMultiplier(review.decimals, review.uiMultiplier) : null;
  return `${scale ? scale.approx(raw) : fmt.number(formatRawUnits(raw, review.decimals) ?? raw)} ${review.symbol}`;
}
