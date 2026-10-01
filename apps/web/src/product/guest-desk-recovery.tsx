import {useEffect, useRef, useState} from 'react';
import {art} from './ui';
import {useT} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';

/**
 * Mobile's guest_desk_recovery_screen for a guest credential that can no longer
 * open its paper desk. Sign-in keeps the old desk untouched; starting over is
 * deliberately two steps deep and archives the old record instead of deleting it.
 */
export function GuestDeskRecovery({failure, canSignIn, onSignIn, onStartNew}: {
  failure: 'expired' | 'ended'; canSignIn: boolean; onSignIn: () => void; onStartNew: () => Promise<void>;
}) {
  const tr = useT();
  const [confirming, setConfirming] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState<MessageKey | null>(null);
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
    catch {if (mounted.current) setError(expired ? 'shell.guestRecovery.expiredFailed' : 'shell.guestRecovery.endedFailed');}
    finally {if (mounted.current) setBusy(false);}
  }
  return <section className="first-day journey-screen journey-state guest-recovery" aria-label={tr('shell.guestRecovery.label')}>
    <img className="journey-state-art" src={art(`career-world/${confirming ? 'folders' : 'safe'}.png`)} alt=""/>
    <h1 ref={heading} tabIndex={-1}>{confirming ? tr('shell.guestRecovery.confirmTitle') : expired ? tr('shell.guestRecovery.expiredTitle') : tr('shell.guestRecovery.endedTitle')}</h1>
    <p className="journey-lede">{confirming ? tr('shell.guestRecovery.confirmBody')
      : expired ? tr('shell.guestRecovery.expiredBody')
      : tr('shell.guestRecovery.endedBody')}</p>
    <div className={`journey-card${confirming ? ' warning' : ''}`}><p>{confirming ? tr('shell.guestRecovery.confirmWarning')
      : tr('shell.guestRecovery.signInNote')}</p></div>
    {confirming ? <>
      <button className="primary full" disabled={busy} onClick={() => void startNew()}>{busy ? tr('shell.guestRecovery.opening') : tr('shell.guestRecovery.startNew')}</button>
      <button className="text-button full" disabled={busy} onClick={() => {setConfirming(false); setError(null);}}>{tr('shell.guestRecovery.keep')}</button>
    </> : <>
      <button className="primary full" disabled={!canSignIn} onClick={onSignIn}>{tr('common.signIn')}</button>
      {!canSignIn && <p className="journey-footnote">{tr('shell.guestRecovery.signInUnavailable')}</p>}
      <button className="text-button full" onClick={() => {setConfirming(true); setError(null);}}>{tr('shell.guestRecovery.startNewGuest')}</button>
    </>}
    {error && <p className="intro-error" role="alert">{tr(error)}</p>}
  </section>;
}
