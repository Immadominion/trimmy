import {useEffect, useRef, useState} from 'react';
import {art} from './ui';

/**
 * Mobile's guest_desk_recovery_screen for a guest credential that can no longer
 * open its paper desk. Sign-in keeps the old desk untouched; starting over is
 * deliberately two steps deep and archives the old record instead of deleting it.
 */
export function GuestDeskRecovery({failure, canSignIn, onSignIn, onStartNew}: {
  failure: 'expired' | 'ended'; canSignIn: boolean; onSignIn: () => void; onStartNew: () => Promise<void>;
}) {
  const [confirming, setConfirming] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null);
  const heading = useRef<HTMLHeadingElement>(null), mounted = useRef(true);
  const expired = failure === 'expired';
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  useEffect(() => {heading.current?.focus();}, [confirming]);
  useEffect(() => {
    if (!confirming) return;
    const key = (event: KeyboardEvent) => {if (event.key === 'Escape' && !busy) {event.preventDefault(); setConfirming(false); setError(null);}};
    window.addEventListener('keydown', key); return () => window.removeEventListener('keydown', key);
  }, [confirming, busy]);
  async function startNew() {
    if (busy) return; setBusy(true); setError(null);
    try {await onStartNew();}
    catch {if (mounted.current) setError(expired ? 'Couldn’t start again. Your expired desk is still preserved.' : 'Couldn’t start again. Your old desk is still preserved.');}
    finally {if (mounted.current) setBusy(false);}
  }
  return <section className="first-day journey-screen journey-state guest-recovery" aria-label="Guest desk recovery">
    <img className="journey-state-art" src={art(`career-world/${confirming ? 'folders' : 'safe'}.png`)} alt=""/>
    <h1 ref={heading} tabIndex={-1}>{confirming ? 'Start fresh?' : expired ? 'Guest session expired' : 'Guest session ended'}</h1>
    <p className="journey-lede">{confirming ? 'This removes this browser’s access to your old desk. You can’t undo it.'
      : expired ? 'Your guest records are preserved. This desk can no longer trade or be saved to an account.'
      : 'Your guest records are preserved, but this browser can no longer open the desk.'}</p>
    <div className={`journey-card${confirming ? ' warning' : ''}`}><p>{confirming ? 'Your balance, positions and history won’t move to the new desk.'
      : 'Sign in to open your saved account. Your guest desk stays untouched.'}</p></div>
    {confirming ? <>
      <button className="primary full" disabled={busy} onClick={() => void startNew()}>{busy ? 'Opening…' : 'Start a new desk'}</button>
      <button className="text-button full" disabled={busy} onClick={() => {setConfirming(false); setError(null);}}>Keep this desk</button>
    </> : <>
      <button className="primary full" disabled={!canSignIn} onClick={onSignIn}>Sign in</button>
      {!canSignIn && <p className="journey-footnote">Sign-in is unavailable right now.</p>}
      <button className="text-button full" onClick={() => {setConfirming(true); setError(null);}}>Start a new guest desk</button>
    </>}
    {error && <p className="intro-error" role="alert">{error}</p>}
  </section>;
}
