import {Component, useEffect, useRef, useState, type ReactNode} from 'react';
import {canExportWallet, parseRecoveryTarget, readRecoveryConfig, type RecoveryConfig, type RecoveryTarget} from './recovery-model.js';
import {loadRecoverySdk, type RecoverySdk, type RecoverySession} from './recovery-sdk-loader.js';

function Frame({children}: {children: ReactNode}) {
  return <main className="wallet-recovery"><header><img src="/trimmy-mark.png" alt=""/><span>Trimmy</span></header>
    <section aria-labelledby="recovery-title"><p className="recovery-eyebrow">Your wallet, with you</p>
      <h1 id="recovery-title">Keep access to<br/>your wallet.</h1>{children}</section>
    <footer>Need help? <a href="https://x.com/trimmyhq" target="_blank" rel="noreferrer">@trimmyhq</a><br/>Never send support a key or sign-in code.</footer></main>;
}

class RecoveryBoundary extends Component<{children: ReactNode}, {failed: boolean}> {
  override state = {failed: false};
  static getDerivedStateFromError() {return {failed: true};}
  override render() {return this.state.failed ? <Frame><p role="alert">Wallet recovery couldn’t load. Reopen this page from Trimmy.</p></Frame> : this.props.children;}
}

export function RecoveryPanel({session, target, exportWallet}: {
  session: RecoverySession; target: RecoveryTarget; exportWallet(address: string): Promise<void>;
}) {
  const initial = target.kind === 'expected' && session.identity?.addresses.includes(target.address) ? target.address : '';
  const [selected, select] = useState(initial), [busy, setBusy] = useState(false), [message, setMessage] = useState('');
  const active = useRef(true), pending = useRef(false), latest = useRef({session, target, selected});
  latest.current = {session, target, selected};
  useEffect(() => {active.current = true; return () => {active.current = false;};}, []);
  const allowed = !busy && session.ready && session.authenticated && !session.failed && canExportWallet(session.identity, target, selected);
  async function openExport() {
    const value = latest.current;
    if (!active.current || pending.current || !value.session.ready || !value.session.authenticated || value.session.failed ||
        !canExportWallet(value.session.identity, value.target, value.selected)) return;
    pending.current = true; setBusy(true); setMessage('');
    try {
      // No await between checking the current identity/selection and entering Privy's isolated UI.
      await exportWallet(value.selected);
      if (active.current) setMessage('Recovery window closed. You can reopen it if needed.');
    } catch {if (active.current) setMessage('The recovery window couldn’t open. Try again.');}
    finally {if (active.current) {pending.current = false; setBusy(false);}}
  }
  async function signOut() {
    if (pending.current) return;
    pending.current = true; setBusy(true); setMessage('');
    try {
      await latest.current.session.logout();
      // Keep actions locked until the SDK actually reports its signed-out state.
      if (active.current) setMessage('Signing out…');
    } catch {if (active.current) {pending.current = false; setBusy(false); setMessage('Couldn’t sign out. Try again.');}}
  }
  if (!session.ready) return <Frame><p role="status">Opening your account…</p></Frame>;
  if (session.failed) return <Frame><p role="alert">Your account couldn’t load. Reopen this page to try again.</p></Frame>;
  if (!session.authenticated) return <Frame><p>Sign in the same way you do in Trimmy. Then choose your wallet to open its recovery key in Privy.</p>
    <button className="recovery-primary" onClick={() => {try {session.login();} catch {setMessage('Sign-in couldn’t open. Try again.');}}}>Sign in to Trimmy</button>
    {message && <p role="status">{message}</p>}</Frame>;
  const wallets = session.identity?.addresses ?? [];
  const mismatch = target.kind === 'expected' && !wallets.includes(target.address);
  return <Frame><p>Use your recovery key to import this same wallet into another compatible Solana wallet.</p>
    {mismatch ? <div className="recovery-note" role="alert"><strong>This isn’t the matching account.</strong>
      <p>Sign in with the account you use for this wallet in Trimmy.</p><code>{target.address}</code></div>
      : wallets.length === 0 ? <p role="status">No Trimmy Solana wallet is linked to this account.</p>
      : <div className="recovery-wallets" role="radiogroup" aria-label="Choose a Solana wallet">
        {wallets.filter(address => target.kind !== 'expected' || target.address === address).map(address =>
          <button type="button" role="radio" aria-checked={selected === address} disabled={busy} key={address}
            className={`recovery-wallet ${selected === address ? 'selected' : ''}`} onClick={() => select(address)}>
            <span>Solana wallet</span><code>{address}</code>{selected === address && <span className="recovery-selected">Selected</span>}</button>)}
      </div>}
    {!mismatch && wallets.length > 0 && <><p className="recovery-note">Your key controls your funds. Keep it private. Privy displays it in a separate secure window; Trimmy does not receive it.</p>
      <button className="recovery-primary" disabled={!allowed} onClick={() => void openExport()}>{busy ? 'Please wait…' : 'Open recovery key'}</button></>}
    {message && <p role="status">{message}</p>}
    <button className="recovery-secondary" disabled={busy} onClick={() => void signOut()}>Switch account</button>
  </Frame>;
}

function Bridge({sdk, target}: {sdk: RecoverySdk; target: RecoveryTarget}) {
  const session = sdk.useSession(), {exportWallet} = sdk.useExportWallet();
  // Reset selection, notices and in-flight continuations on identity, readiness or wallet changes.
  const identityKey = JSON.stringify([session.ready, session.authenticated, session.failed, session.identity]);
  return <RecoveryPanel key={identityKey} session={session} target={target} exportWallet={exportWallet}/>;
}

export function WalletRecoveryPage({config = readRecoveryConfig(), loadSdk = loadRecoverySdk}: {
  config?: RecoveryConfig; loadSdk?: () => Promise<RecoverySdk>;
}) {
  const [sdk, setSdk] = useState<RecoverySdk | null>(null), [failed, setFailed] = useState(false);
  const [target, setTarget] = useState(() => parseRecoveryTarget(window.location.hash));
  const secure = window.top === window.self && (window.location.protocol === 'https:' || ['localhost', '127.0.0.1'].includes(window.location.hostname));
  useEffect(() => {
    document.title = 'Trimmy | Wallet recovery';
    const change = () => setTarget(previous => {
      const next = parseRecoveryTarget(window.location.hash);
      return previous.kind === 'expected' && next.kind === 'none' ? {kind: 'invalid'} : next;
    });
    window.addEventListener('hashchange', change);
    return () => window.removeEventListener('hashchange', change);
  }, []);
  const configKey = JSON.stringify(config);
  useEffect(() => {
    let current = true; setSdk(null); setFailed(false);
    if (secure && config.kind === 'enabled' && target.kind !== 'invalid') {
      void loadSdk().then(value => {if (current) setSdk(value);}, () => {if (current) setFailed(true);});
    }
    return () => {current = false;};
  }, [configKey, secure, target.kind, loadSdk]);
  if (!secure || target.kind === 'invalid') return <Frame><p role="alert">This recovery link isn’t valid. Open wallet recovery from Trimmy in your browser.</p></Frame>;
  if (config.kind !== 'enabled' || failed) return <Frame><p role="alert">Wallet recovery isn’t available here. Please try again later.</p></Frame>;
  if (!sdk) return <Frame><p role="status">Opening wallet recovery…</p></Frame>;
  return <RecoveryBoundary key={configKey}><sdk.PrivyProvider appId={config.appId} {...(config.clientId ? {clientId: config.clientId} : {})}
    config={{loginMethods: ['email', 'google', 'twitter', 'apple'],
      appearance: {theme: 'light', accentColor: '#7745D8', logo: '/trimmy-mark.png', landingHeader: 'Sign in to Trimmy', loginMessage: 'Use the same account as your Trimmy app.'},
      embeddedWallets: {ethereum: {createOnLogin: 'off'}, solana: {createOnLogin: 'off'}, disableAutomaticMigration: true}}}>
    <Bridge key={JSON.stringify(target)} sdk={sdk} target={target}/></sdk.PrivyProvider></RecoveryBoundary>;
}
