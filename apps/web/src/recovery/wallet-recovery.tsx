import {Component, useEffect, useRef, useState, type ReactNode} from 'react';
import {canExportWallet, parseRecoveryTarget, readRecoveryConfig, type RecoveryConfig, type RecoveryTarget} from './recovery-model.js';
import {loadRecoverySdk, type RecoverySdk, type RecoverySession} from './recovery-sdk-loader.js';
import {useT} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';

function Frame({children}: {children: ReactNode}) {
  const tr = useT();
  return <main className="wallet-recovery"><header><img src="/trimmy-mark.png" alt=""/><span>Trimmy</span></header>
    <section aria-labelledby="recovery-title"><p className="recovery-eyebrow">{tr('recovery.eyebrow')}</p>
      <h1 id="recovery-title">{tr.rich('recovery.title')}</h1>{children}</section>
    <footer>{tr.rich('recovery.footer', {link: <a href="https://x.com/trimmyhq" target="_blank" rel="noreferrer">@trimmyhq</a>})}</footer></main>;
}

/** The boundary's notice; a class component cannot read the language itself. */
function LoadFailed() {
  const tr = useT();
  return <Frame><p role="alert">{tr('recovery.loadFailed')}</p></Frame>;
}

class RecoveryBoundary extends Component<{children: ReactNode}, {failed: boolean}> {
  override state = {failed: false};
  static getDerivedStateFromError() {return {failed: true};}
  override render() {return this.state.failed ? <LoadFailed/> : this.props.children;}
}

export function RecoveryPanel({session, target, exportWallet}: {
  session: RecoverySession; target: RecoveryTarget; exportWallet(address: string): Promise<void>;
}) {
  const tr = useT();
  const initial = target.kind === 'expected' && session.identity?.addresses.includes(target.address) ? target.address : '';
  // Notices are kept as message keys, so they follow a language change.
  const [selected, select] = useState(initial), [busy, setBusy] = useState(false), [message, setMessage] = useState<MessageKey | ''>('');
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
      if (active.current) setMessage('recovery.wallet.windowClosed');
    } catch {if (active.current) setMessage('recovery.wallet.windowFailed');}
    finally {if (active.current) {pending.current = false; setBusy(false);}}
  }
  async function signOut() {
    if (pending.current) return;
    pending.current = true; setBusy(true); setMessage('');
    try {
      await latest.current.session.logout();
      // Keep actions locked until the SDK actually reports its signed-out state.
      if (active.current) setMessage('recovery.wallet.signingOut');
    } catch {if (active.current) {pending.current = false; setBusy(false); setMessage('recovery.wallet.signOutFailed');}}
  }
  if (!session.ready) return <Frame><p role="status">{tr('recovery.account.opening')}</p></Frame>;
  if (session.failed) return <Frame><p role="alert">{tr('recovery.account.failed')}</p></Frame>;
  if (!session.authenticated) return <Frame><p>{tr('recovery.signIn.intro')}</p>
    <button className="recovery-primary" onClick={() => {try {session.login();} catch {setMessage('recovery.signIn.failed');}}}>{tr('recovery.signIn.button')}</button>
    {message && <p role="status">{tr(message)}</p>}</Frame>;
  const wallets = session.identity?.addresses ?? [];
  const mismatch = target.kind === 'expected' && !wallets.includes(target.address);
  return <Frame><p>{tr('recovery.wallet.intro')}</p>
    {mismatch ? <div className="recovery-note" role="alert"><strong>{tr('recovery.wallet.mismatchTitle')}</strong>
      <p>{tr('recovery.wallet.mismatchBody')}</p><code>{target.address}</code></div>
      : wallets.length === 0 ? <p role="status">{tr('recovery.wallet.none')}</p>
      : <div className="recovery-wallets" role="radiogroup" aria-label={tr('recovery.wallet.chooseLabel')}>
        {wallets.filter(address => target.kind !== 'expected' || target.address === address).map(address =>
          <button type="button" role="radio" aria-checked={selected === address} disabled={busy} key={address}
            className={`recovery-wallet ${selected === address ? 'selected' : ''}`} onClick={() => select(address)}>
            <span>{tr('recovery.wallet.solana')}</span><code>{address}</code>{selected === address && <span className="recovery-selected">{tr('recovery.wallet.selected')}</span>}</button>)}
      </div>}
    {!mismatch && wallets.length > 0 && <><p className="recovery-note">{tr('recovery.wallet.keyNote')}</p>
      <button className="recovery-primary" disabled={!allowed} onClick={() => void openExport()}>{busy ? tr('recovery.wallet.wait') : tr('recovery.wallet.openKey')}</button></>}
    {message && <p role="status">{tr(message)}</p>}
    <button className="recovery-secondary" disabled={busy} onClick={() => void signOut()}>{tr('recovery.wallet.switchAccount')}</button>
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
  const tr = useT();
  const [sdk, setSdk] = useState<RecoverySdk | null>(null), [failed, setFailed] = useState(false);
  const [target, setTarget] = useState(() => parseRecoveryTarget(window.location.hash));
  const secure = window.top === window.self && (window.location.protocol === 'https:' || ['localhost', '127.0.0.1'].includes(window.location.hostname));
  // The page owns its title, in the page's language.
  const title = tr('recovery.documentTitle');
  useEffect(() => {document.title = title;}, [title]);
  useEffect(() => {
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
  if (!secure || target.kind === 'invalid') return <Frame><p role="alert">{tr('recovery.invalidLink')}</p></Frame>;
  if (config.kind !== 'enabled' || failed) return <Frame><p role="alert">{tr('recovery.unavailable')}</p></Frame>;
  if (!sdk) return <Frame><p role="status">{tr('recovery.opening')}</p></Frame>;
  return <RecoveryBoundary key={configKey}><sdk.PrivyProvider appId={config.appId} {...(config.clientId ? {clientId: config.clientId} : {})}
    config={{loginMethods: ['email', 'google', 'twitter', 'apple'],
      appearance: {theme: 'light', accentColor: '#7745D8', logo: '/trimmy-mark.png', landingHeader: tr('recovery.privy.landingHeader'), loginMessage: tr('recovery.privy.loginMessage')},
      embeddedWallets: {ethereum: {createOnLogin: 'off'}, solana: {createOnLogin: 'off'}, disableAutomaticMigration: true}}}>
    <Bridge key={JSON.stringify(target)} sdk={sdk} target={target}/></sdk.PrivyProvider></RecoveryBoundary>;
}
