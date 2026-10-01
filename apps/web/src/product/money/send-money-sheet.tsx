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
import {TransferError, transferMessage, type TransferReview} from './wallet-transfer-client.js';

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
    ...positive(holdings.usdc.availableToTradeRaw) ? [{id: 'USDC', symbol: 'USDC', name: 'US dollars (USDC)', decimals: USDC_DECIMALS,
      availableRaw: holdings.usdc.availableToTradeRaw, scale: ShareScale.plain(USDC_DECIMALS)}] : [],
    ...positive(holdings.nativeSolLamports) ? [{id: 'SOL', symbol: 'SOL', name: 'Solana (SOL)', decimals: SOL_DECIMALS,
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
const label = (asset: SendAsset, raw: string) => isStockAsset(asset) ? asset.scale.label(raw) : formatRawUnits(raw, asset.decimals) ?? raw;
const rawFor = (asset: SendAsset, text: string) => isStockAsset(asset) ? asset.scale.raw(text.trim()) : amountRaw(text.trim(), asset.decimals);
const sol = (lamports: string) => `${rawDecimal(lamports, SOL_DECIMALS)} SOL`;

type Stage = 'details' | 'review' | 'sending' | 'done';

export function SendMoneySheet({onClose, nameFor}: {onClose(): void; nameFor?: (mint: string) => string | undefined}) {
  const money = useMoney();
  const titleId = useId();
  const holdings = coherentHoldings(money.wallet);
  const assets = holdings ? sendableAssets(holdings, nameFor) : [];
  const [assetId, setAssetId] = useState<string | null>(null);
  const asset = assets.find(item => item.id === assetId) ?? assets[0] ?? null;
  const [to, setTo] = useState(''), [amount, setAmount] = useState('');
  const [review, setReview] = useState<TransferReview | null>(null);
  const [stage, setStage] = useState<Stage>('details');
  const [busy, setBusy] = useState(true), [message, setMessage] = useState<string | null>(null);
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
    }catch {if(active.current){setMessage('Your previous send couldn’t be checked. Try checking again.');setBusy(false);setRecoveryFailed(true);}}
  }
  const [recoveryFailed,setRecoveryFailed]=useState(false);
  useEffect(()=>{void recover();},[]);

  // Watch a sent transfer for about a minute.
  useEffect(() => {
    if (stage !== 'sending' || signature === null || !money.transfers) return;
    let polls = 0;
    const timer = window.setInterval(() => {
      polls += 1;
      void money.transfers!.status(signature).then(next => {
        if (!active.current || next === 'pending' && polls < 30) return;
        clearInterval(timer); setStatus(next); setStage('done'); void money.refreshWallet();
      }, () => {if (polls >= 30 && active.current) {clearInterval(timer); setStage('done');}});
    }, 2000);
    return () => clearInterval(timer);
  }, [stage, signature, money.transfers, money]);

  function problem(): string | null {
    if (!asset) return null;
    const destination = to.trim();
    if (!ADDRESS.test(destination)) return 'Enter a Solana wallet address.';
    if (destination === holdings?.walletAddress) return 'That’s your own wallet. Enter another address.';
    const raw = rawFor(asset, amount);
    if (raw === null || raw === '0') return 'Enter an amount.';
    if (BigInt(raw) > BigInt(asset.availableRaw)) return `You have ${label(asset, asset.availableRaw)} ${asset.symbol} ready to send.`;
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
      if (next.assetId !== asset.id || next.destination !== destination || next.amountRaw !== raw || next.from !== holdings?.walletAddress) {
        throw new TransferError('TRANSFER_UNAVAILABLE');
      }
      if (active.current) {setReview(next); setStage('review');}
    } catch (error) {
      if (active.current && error instanceof TransferError && error.code === 'TRANSFER_PENDING') await recover();
      else if (active.current) setMessage(error instanceof TransferError ? error.message : transferMessage(''));
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
      if(!['SIGNING_CANCELLED','SIGNING_TIMEOUT','TRANSFER_STORAGE','ACCOUNT_REQUIRED','WALLET_CHANGED','WALLET_BUSY'].includes(code)) {await recover();return;}
      setMessage(transferMessage(code));
      if (['REVIEW_EXPIRED', 'INVALID_REVIEW', 'INVALID_SIGNATURE', 'QUOTE_EXPIRED'].includes(code)) {setReview(null); setStage('details');}
    } finally {if (active.current) setBusy(false);}
  }

  const close = () => {if (!busy) onClose();};
  return <div className="money-sheet-backdrop" onMouseDown={event => {if (event.target === event.currentTarget) close();}}>
    <section className="money-sheet send-money" role="dialog" aria-modal="true" aria-labelledby={titleId}
      onKeyDown={event => {if (event.key === 'Escape') {event.stopPropagation(); close();}}}>
      <header className="money-sheet-head"><h2 id={titleId}>Send</h2>
        <button ref={closeButton} className="money-close" aria-label="Close" disabled={busy} onClick={close}>×</button></header>
      {stage === 'details' ? !asset ? <div className="fund-state"><h3>Nothing to send yet</h3>
          <p className="fund-note">Add money or buy a stock first. Anything in your wallet can be sent from here.</p></div>
        : <form className="send-form" onSubmit={event => {event.preventDefault(); void preview();}}>
          <p className="fund-note">Only send to a Solana address. Sends can’t be undone.</p>
          <label>What to send<select data-testid="send-asset" value={asset.id} disabled={busy}
            onChange={event => {setAssetId(event.target.value); setAmount(''); setMessage(null);}}>
            {assets.map(item => <option key={item.id} value={item.id}>{`${item.name} · ${label(item, item.availableRaw)} ${item.symbol}`}</option>)}
          </select></label>
          <label>Recipient’s wallet address<input data-testid="send-destination" value={to} disabled={busy} autoComplete="off" spellCheck={false}
            maxLength={44} onChange={event => setTo(event.target.value.replace(/[^1-9A-HJ-NP-Za-km-z]/g, ''))}/></label>
          <label>{isStockAsset(asset) ? 'Shares' : `Amount (${asset.symbol})`}
            <span className="send-amount"><input data-testid="send-amount" inputMode="decimal" value={amount} disabled={busy} maxLength={40}
              onChange={event => setAmount(event.target.value.replace(/[^0-9.]/g, ''))}/>
              <button type="button" className="text-button" data-testid="send-max" disabled={busy}
                onClick={() => setAmount(isStockAsset(asset) ? asset.scale.shares(maxRaw(asset)) : rawDecimal(maxRaw(asset), asset.decimals))}>Max</button></span>
            <small>{`${label(asset, asset.availableRaw)} ${asset.symbol} ready to send`}</small></label>
          {asset.id === 'SOL' && <p className="fund-note subtle">Max keeps 0.002 SOL so you can still pay network fees.</p>}
          <button className="primary" data-testid="send-review" disabled={busy || recoveryFailed || !money.transfers}>{busy ? 'Checking…' : 'Review send'}</button>
        </form>
      : stage === 'review' && review ? <div className="send-review">
          <dl className="send-summary">
            <div><dt>You send</dt><dd>{reviewAmount(review, review.amountRaw, asset)}</dd></div>
            {review.receivedRaw !== review.amountRaw && <div><dt>They receive, after the issuer fee</dt><dd>{reviewAmount(review, review.receivedRaw, asset)}</dd></div>}
            <div><dt>Network fee</dt><dd>{sol(review.networkFeeLamports)}</dd></div>
            {review.createsAccount && <div><dt>{`Opens their ${review.symbol} account (once)`}</dt><dd>{sol(review.accountRentLamports)}</dd></div>}
          </dl>
          <h3>To this Solana wallet</h3>
          <code className="send-destination" data-testid="send-review-destination">{review.destination}</code>
          <p className="fund-note">Check every character. Sends can’t be undone, and Trimmy can’t get money back from a wrong address.</p>
          <button className="primary" data-testid="send-confirm" disabled={busy || recoveryFailed} onClick={() => void send()}>{busy ? 'Sending…' : 'Send now'}</button>
          <button className="text-button" disabled={busy} onClick={() => {setReview(null); setStage('details');}}>Edit</button>
        </div>
      : <div className="fund-state" role="status">
          <h3 data-testid="send-result">{stage === 'sending' ? 'Sending' : status === 'confirmed' ? 'Sent' : status === 'failed' ? 'It didn’t go through' : status==='expired'?'Send expired':'Still confirming'}</h3>
          <p className="fund-note">{stage === 'sending' ? 'This usually takes a few seconds.' : status === 'confirmed' ? 'It’s confirmed on Solana.'
            : status === 'failed' ? 'Solana refused it. Only the network fee was spent.' : status==='expired'?'This transaction expired without confirmation. You can review a new send.':'We’re still checking this send. Don’t send it again.'}</p>
          {signature && <a href={`https://solscan.io/tx/${signature}`} target="_blank" rel="noreferrer">View on Solscan</a>}
          {stage === 'done' && <button className="primary" onClick={()=>{
            try {if(status!=='pending')money.transfers?.acknowledge();onClose();}
            catch {setMessage('This send is saved. Try closing it again.');}
          }}>Done</button>}
        </div>}
      {recoveryFailed && <button className="primary" onClick={()=>{setRecoveryFailed(false);void recover();}}>Check previous send</button>}
      {message && <p className="fund-message" role="alert" data-testid="send-message">{message}</p>}
    </section>
  </div>;
}

function reviewAmount(review: TransferReview, raw: string, asset: SendAsset | null): string {
  const scale = review.assetId === 'SOL' || review.assetId === 'USDC' ? null
    : asset && asset.id === review.assetId ? ShareScale.fromMultiplier(review.decimals, review.uiMultiplier) : null;
  return `${scale ? scale.approx(raw) : formatRawUnits(raw, review.decimals) ?? raw} ${review.symbol}`;
}
