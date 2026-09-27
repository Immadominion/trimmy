/**
 * Add money: crypto deposit to the account's own Solana wallet (Recommended).
 * Card funding is shown as Coming soon and cannot be used. This sheet never
 * requests a deposit or moves funds; it shows the receive address and keeps
 * the balance fresh while it is open. Copy mirrors mobile's fund_wallet_sheet.
 */
import {useEffect, useId, useMemo, useRef, useState} from 'react';
import {art} from '../ui.js';
import {shortenAddress} from './amounts.js';
import {requestRealAfterSignIn, useMoney} from './money-api.js';
import {qrMatrix} from './qr-matrix.js';
import {walletAddress} from './wallet-controller.js';

/** The receive address as a QR code: square finder eyes, round modules, like mobile. */
export function AddressQr({address}: {address: string}) {
  const matrix = useMemo(() => {try {return qrMatrix(address);} catch {return null;}}, [address]);
  if (!matrix) return null;
  const {size, modules} = matrix;
  const finder = (row: number, col: number) => (row < 8 && col < 8) || (row < 8 && col >= size - 8) || (row >= size - 8 && col < 8);
  const dots: string[] = [];
  modules.forEach((dark, index) => {
    const row = Math.floor(index / size), col = index % size;
    if (dark && !finder(row, col)) dots.push(`M${col + .5},${row + .08}a.42,.42 0 1,0 .001,0`);
  });
  const eyes = [[0, 0], [0, size - 7], [size - 7, 0]] as const;
  return <svg className="money-qr" viewBox={`-2 -2 ${size + 4} ${size + 4}`} role="img" aria-label={`Solana deposit address ${address}`} data-qr-size={size}>
    <rect x="-2" y="-2" width={size + 4} height={size + 4} fill="#fff"/>
    {eyes.map(([row, col]) => <g key={`${row}-${col}`} fill="none" stroke="currentColor">
      <rect x={col + .5} y={row + .5} width="6" height="6" rx="1.2" strokeWidth="1"/>
      <rect x={col + 2} y={row + 2} width="3" height="3" rx=".6" fill="currentColor" stroke="none"/>
    </g>)}
    <path d={dots.join('')} fill="currentColor"/>
  </svg>;
}

export function FundWalletSheet({onClose}: {onClose(): void}) {
  const money = useMoney();
  const titleId = useId();
  const [method, setMethod] = useState<'crypto' | 'card'>('crypto');
  const [busy, setBusy] = useState(false), [message, setMessage] = useState<string | null>(null);
  const [copied, setCopied] = useState(false), [refreshing, setRefreshing] = useState(false);
  const closeButton = useRef<HTMLButtonElement>(null), opener = useRef<Element | null>(null);
  const refreshRef = useRef(money.refreshWallet); refreshRef.current = money.refreshWallet;
  useEffect(() => {
    opener.current = document.activeElement; closeButton.current?.focus();
    return () => {if (opener.current instanceof HTMLElement) opener.current.focus();};
  }, []);
  // Keep the balance current while the sheet is open, as mobile checks every 8 seconds.
  useEffect(() => {
    if (!money.available) return;
    const update = () => {
      if (document.visibilityState === 'hidden') return;
      setRefreshing(true);
      void refreshRef.current().finally(() => setRefreshing(false));
    };
    update();
    const timer = window.setInterval(update, 8000);
    window.addEventListener('focus', update);
    return () => {clearInterval(timer); window.removeEventListener('focus', update);};
  }, [money.available]);
  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 2000);
    return () => clearTimeout(timer);
  }, [copied]);

  const state = money.wallet, address = walletAddress(state);
  const walletIssue = state.context?.embeddedSolanaWallet.status === 'ambiguous' ? 'We couldn’t confirm your wallet.'
    : state.phase === 'offline' && !navigator.onLine ? 'You’re offline. Reconnect to load your wallet.'
    : state.checked && !refreshing && state.context === null ? 'Couldn’t load your wallet.' : null;
  async function create() {
    setBusy(true); setMessage(null);
    try {
      const outcome = await money.setUpWallet();
      setMessage(outcome === 'ready' || outcome === 'awaiting-server' ? null : 'Couldn’t create your wallet. Try again.');
      void money.refreshWallet();
    } catch {setMessage('Couldn’t create your wallet. Try again.');}
    finally {setBusy(false);}
  }
  async function copy(value: string) {
    try {await navigator.clipboard.writeText(value); setCopied(true);}
    catch {setMessage('Couldn’t copy the address. Select it and copy it instead.');}
  }
  function signIn() {requestRealAfterSignIn(); onClose(); window.location.hash = 'sign-in';}

  return <div className="money-sheet-backdrop" onMouseDown={event => {if (event.target === event.currentTarget) onClose();}}>
    <section className="money-sheet fund-wallet" role="dialog" aria-modal="true" aria-labelledby={titleId}
      onKeyDown={event => {if (event.key === 'Escape') {event.stopPropagation(); onClose();}}}>
      <header className="money-sheet-head"><h2 id={titleId}>Add money</h2>
        <button ref={closeButton} className="money-close" aria-label="Close" onClick={onClose}>×</button></header>
      <div className="fund-methods" role="radiogroup" aria-label="How to add money">
        <button role="radio" aria-checked={method === 'crypto'} className={method === 'crypto' ? 'selected' : ''} onClick={() => setMethod('crypto')}>
          <span>Crypto</span><small className="fund-tag recommended">Recommended</small></button>
        <button role="radio" aria-checked={false} aria-disabled="true" className="unavailable" onClick={() => setMethod('card')}>
          <span>Card</span><small className="fund-tag">Coming soon</small></button>
      </div>
      {method === 'card' ? <div className="fund-card-soon" role="status"><h3>Card payments are coming soon.</h3>
        <p>For now, add money with crypto: send USDC to your wallet on Solana.</p>
        <button className="secondary" onClick={() => setMethod('crypto')}>Use crypto</button></div>
      : !money.available ? <div className="fund-state"><img src={art('career-world/safe.png')} alt="" loading="lazy"/>
        <h3>A wallet for your money</h3><p>Sign in to create your own Solana wallet and add money.</p>
        <button className="primary" onClick={signIn}>Sign in</button></div>
      : address === null ? state.context?.embeddedSolanaWallet.status === 'missing' ? <div className="fund-state">
          <img src={art('career-world/safe.png')} alt="" loading="lazy"/><h3>A wallet for your money</h3>
          <button className="primary" disabled={busy || state.setupBusy || !money.canSetUpWallet} onClick={() => void create()}>{busy || state.setupBusy ? 'Creating…' : 'Create wallet'}</button>
          {money.walletSdk === 'unavailable' && <p className="fund-note">Wallet setup isn’t available in this browser right now.</p>}
        </div>
        : walletIssue !== null ? <div className="fund-state"><h3 data-testid="fund-wallet-unavailable">{walletIssue}</h3>
          <button className="text-button" disabled={refreshing} onClick={() => {setRefreshing(true); void money.refreshWallet().finally(() => setRefreshing(false));}}>{refreshing ? 'Checking…' : 'Try again'}</button></div>
        : <div className="fund-state" role="status"><span className="loading-dot" aria-hidden="true"/>Checking your wallet…</div>
      : <div className="fund-deposit">
        <div className="money-qr-frame"><AddressQr address={address}/></div>
        <h3>Solana</h3>
        <p className="fund-address" aria-label={address}>{shortenAddress(address)}</p>
        <p className="fund-note">Send only USDC or SOL to this account on the Solana network.</p>
        <p className="fund-note subtle">USDC is your cash for trades. A little SOL pays network fees.</p>
        <button className="primary" onClick={() => void copy(address)}>{copied ? 'Copied' : 'Copy address'}</button>
        <details className="fund-full-address"><summary>Show full address</summary><code>{address}</code></details>
      </div>}
      {message && <p className="fund-message" role="alert">{message}</p>}
    </section>
  </div>;
}
