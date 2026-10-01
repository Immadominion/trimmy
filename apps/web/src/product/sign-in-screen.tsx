import {useEffect, useRef, useState} from 'react';
import {useProductAuth, type ProductLoginMethod} from './product-auth';
import {SalArt, art} from './ui';
import {useT, type Translator} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';

/** Google and X are names and never translated; "email" is a word and is. Each method has its own whole sentence. */
const methods: Record<ProductLoginMethod, {name: string | null; icon: string; continueWith: MessageKey}> = {
  email: {name: null, icon: 'account-email-rounded.png', continueWith: 'firstDay.signIn.continueWithEmail'},
  google: {name: 'Google', icon: 'account-google-rounded.png', continueWith: 'firstDay.signIn.continueWithGoogle'},
  x: {name: 'X', icon: 'account-x-standalone-rounded.png', continueWith: 'firstDay.signIn.continueWithX'},
};
function methodName(method: ProductLoginMethod, tr: Translator): string {return methods[method].name ?? tr('firstDay.signIn.methodEmail');}
function authError(code: string | null, tr: Translator): string | null {
  if (!code) return null;
  if (code === 'PRODUCT_EMAIL_INVALID') return tr('firstDay.signIn.error.emailInvalid');
  if (code === 'PRODUCT_EMAIL_CODE_INVALID') return tr('firstDay.signIn.error.codeInvalid');
  if (code === 'PRODUCT_EMAIL_CODE_SEND_FAILED') return tr('firstDay.signIn.error.codeSendFailed');
  if (code === 'PRACTICE_COMMIT_PENDING') return tr('firstDay.signIn.error.commitPending');
  if (code === 'PRACTICE_PROFILE_PENDING') return tr('firstDay.signIn.error.profilePending');
  if (code === 'PRACTICE_WORKDAY_PENDING') return tr('firstDay.signIn.error.workdayPending');
  if (code === 'PRACTICE_DAILY_DESK_PENDING') return tr('firstDay.signIn.error.dailyDeskPending');
  if (code === 'PRACTICE_CLAIM_PENDING') return tr('firstDay.signIn.error.claimPending');
  if (code.includes('STORAGE')) return tr('firstDay.signIn.error.storage');
  if (code === 'PRODUCT_SIGN_OUT_FAILED') return tr('firstDay.signIn.error.signOutFailed');
  return tr('firstDay.signIn.error.generic');
}
export function SignInScreen({motion, hasDesk, onBack, onAccount, entryGate = false, onGuest, expiredGuestRecovery = false}: {
  motion: boolean; hasDesk: boolean; onBack: () => void; onAccount: () => void;
  /** Mobile's startup gate: only the labelled "Continue as guest" action grants guest access. */
  entryGate?: boolean; onGuest?: () => Promise<void> | void;
  /** Sign-in from an expired guest desk keeps that desk preserved and separate. */
  expiredGuestRecovery?: boolean;
}) {
  const auth = useProductAuth();
  const tr = useT();
  const [emailEntry, setEmailEntry] = useState(false), [email, setEmail] = useState(''), [code, setCode] = useState('');
  const [guestBusy, setGuestBusy] = useState(false), [guestError, setGuestError] = useState(false);
  const [resendAt, setResendAt] = useState(0), [clock, setClock] = useState(Date.now);
  const heading = useRef<HTMLHeadingElement>(null);
  const codeEntry = auth.email !== null;
  useEffect(() => {heading.current?.focus();}, [emailEntry, codeEntry, auth.phase === 'account-choice']);
  useEffect(() => {const timer = window.setInterval(() => setClock(Date.now()), 1000); return () => clearInterval(timer);}, []);
  useEffect(() => {if (auth.authenticated) onAccount();}, [auth.authenticated, onAccount]);
  async function back() {
    if (auth.busy) return;
    if (auth.subject || auth.errorCode === 'PRODUCT_SIGN_OUT_FAILED') {if (await auth.logout()) onBack(); return;}
    if (emailEntry || codeEntry) {auth.cancel(); setEmailEntry(false); setCode(''); return;}
    // Back or Escape at the startup gate never counts as choosing guest access.
    if (entryGate) return;
    auth.cancel(); onBack();
  }
  async function guest() {
    if (auth.busy || guestBusy || !onGuest) return;
    setGuestBusy(true); setGuestError(false);
    try {await onGuest();} catch {setGuestError(true);} finally {setGuestBusy(false);}
  }
  useEffect(() => {const previous = () => {if (!entryGate) window.history.replaceState(null, '', '#sign-in'); void back();}; window.addEventListener('popstate', previous); return () => window.removeEventListener('popstate', previous);});
  useEffect(() => {const escape = (event: KeyboardEvent) => {if (event.key === 'Escape') {event.preventDefault(); void back();}}; window.addEventListener('keydown', escape); return () => window.removeEventListener('keydown', escape);});
  function choose(method: ProductLoginMethod) {if (auth.busy) return; if (method === 'email') setEmailEntry(true); else void auth.loginWithProvider(method);}
  async function send() {setResendAt(Date.now() + 30000); await auth.sendEmailCode(email);}
  const preferred = auth.lastSuccessfulMethod ?? 'email';
  const message = auth.phase === 'account-choice' ? null : authError(auth.errorCode, tr);
  const loading = auth.phase === 'restoring' || auth.phase === 'connecting' || auth.phase === 'signing-out';
  return <section className="sign-in-screen" aria-label={tr('firstDay.signIn.label')}>
    {!entryGate && <button className="sign-in-close" aria-label={tr('firstDay.signIn.close')} disabled={auth.busy} onClick={() => void back()}>×</button>}
    <div className="sign-in-art"><SalArt motion={motion}/></div>
    <div className="sign-in-content">
      {auth.phase === 'account-choice' ? <>
        <h1 ref={heading} tabIndex={-1}>{tr('firstDay.signIn.choice.title')}</h1>
        <p>{auth.errorCode === 'GUEST_SESSION_EXPIRED' ? tr('firstDay.signIn.choice.expired') : tr('firstDay.signIn.choice.exists')}</p>
        <button className="primary full" onClick={() => void auth.openExistingAccount()}>{tr('firstDay.signIn.choice.open')}</button>
        <button className="text-button full" onClick={() => void back()}>{tr('firstDay.signIn.choice.keepGuest')}</button>
      </> : loading ? <>
        <h1 ref={heading} tabIndex={-1}>{auth.phase === 'signing-out' ? tr('firstDay.signIn.signingOut') : tr('firstDay.signIn.opening')}</h1>
        <p role="status">{auth.phase === 'connecting' ? tr('firstDay.signIn.restoring') : tr('firstDay.signIn.moment')}</p>
      </> : codeEntry ? <>
        <h1 ref={heading} tabIndex={-1}>{tr('firstDay.signIn.code.title')}</h1><p>{tr.rich('firstDay.signIn.code.sentTo', {email: auth.email})}</p>
        <form onSubmit={event => {event.preventDefault(); void auth.verifyEmailCode(code);}}>
          <label htmlFor="sign-in-code">{tr('firstDay.signIn.code.label')}</label><input id="sign-in-code" className="sign-in-code" autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6}" maxLength={6} value={code} disabled={auth.busy} onChange={event => setCode(event.target.value.replace(/\D/g, ''))}/>
          <button className="primary full" disabled={auth.busy || !/^\d{6}$/.test(code)}>{auth.busy ? tr('firstDay.signIn.code.signingIn') : tr('common.continue')}</button>
        </form>
        <button className="text-button full" disabled={auth.busy || clock < resendAt} onClick={() => {setResendAt(Date.now() + 30000); void auth.sendEmailCode(auth.email!);}}>{clock < resendAt ? tr('firstDay.signIn.code.resendIn', {seconds: Math.ceil((resendAt - clock) / 1000)}) : tr('firstDay.signIn.code.resend')}</button>
        <button className="text-button full" disabled={auth.busy} onClick={() => {auth.cancel(); setCode(''); setEmailEntry(true);}}>{tr('firstDay.signIn.code.otherEmail')}</button>
      </> : emailEntry ? <>
        <h1 ref={heading} tabIndex={-1}>{tr('firstDay.signIn.email.title')}</h1><p>{tr('firstDay.signIn.email.lede')}</p>
        <form onSubmit={event => {event.preventDefault(); void send();}}>
          <label htmlFor="sign-in-email">{tr('firstDay.signIn.email.label')}</label><input id="sign-in-email" type="email" autoComplete="email" placeholder={tr('firstDay.signIn.email.placeholder')} maxLength={254} required value={email} disabled={auth.busy} onChange={event => setEmail(event.target.value)}/>
          <button className="primary full" disabled={auth.busy || !email.trim()}>{auth.busy ? tr('firstDay.signIn.email.sending') : tr('firstDay.signIn.continueWithEmail')}</button>
        </form><button className="text-button full" disabled={auth.busy} onClick={() => {auth.cancel(); setEmailEntry(false);}}>{tr('firstDay.signIn.email.otherWays')}</button>
      </> : <>
        <h1 ref={heading} tabIndex={-1}>{entryGate ? tr('firstDay.signIn.title.gate') : expiredGuestRecovery ? tr('firstDay.signIn.title.expiredGuest') : auth.lastSuccessfulMethod ? tr('firstDay.signIn.title.returning') : hasDesk ? tr('firstDay.signIn.title.save') : tr('firstDay.signIn.title.new')}</h1>
        <p>{entryGate ? tr('firstDay.signIn.lede.gate') : expiredGuestRecovery ? tr('firstDay.signIn.lede.expiredGuest') : hasDesk ? tr('firstDay.signIn.lede.save') : tr('firstDay.signIn.lede.new')}</p>
        {expiredGuestRecovery && <p className="sign-in-notice" role="note">{tr('firstDay.signIn.expiredNotice')}</p>}
        <button className="primary full sign-in-preferred" disabled={auth.busy || !auth.enabled} onClick={() => choose(preferred)}><img src={art(`icons/${methods[preferred].icon}`)} alt=""/>{tr(methods[preferred].continueWith)}</button>
        {auth.lastSuccessfulMethod && <span className="last-login">{tr('firstDay.signIn.lastUsed')}</span>}
        {entryGate && onGuest && <button className="text-button full sign-in-guest" disabled={auth.busy || guestBusy} onClick={() => void guest()}>{guestBusy ? tr('firstDay.saving') : tr('firstDay.signIn.guest')}</button>}
        {guestError && <p className="sign-in-error" role="alert">{tr('firstDay.signIn.guestError')}</p>}
        <div className="sign-in-divider"><span>{tr('firstDay.signIn.divider')}</span></div>
        <div className="sign-in-social">{(['email', 'google', 'x'] as const).filter(method => method !== preferred).map(method => <div key={method}><button disabled={auth.busy || !auth.enabled} aria-label={tr(methods[method].continueWith)} onClick={() => choose(method)}><img src={art(`icons/${methods[method].icon}`)} alt=""/></button><span>{methodName(method, tr)}</span></div>)}</div>
        {!auth.enabled && <p className="sign-in-error" role="status">{tr('firstDay.signIn.unavailable')}</p>}
        {auth.phase === 'authenticating' && <p role="status" className="sign-in-status">{tr('firstDay.signIn.authenticating')}</p>}
      </>}
      {message && <div className="sign-in-error" role="alert"><p>{message}</p>{auth.errorCode === 'PRODUCT_SIGN_OUT_FAILED' ? <button className="text-button" disabled={auth.busy} onClick={() => void back()}>{tr('firstDay.signIn.retrySignOut')}</button> : auth.subject && <button className="text-button" disabled={auth.busy} onClick={() => void auth.retry()}>{tr('common.tryAgain')}</button>}</div>}
    </div>
  </section>;
}
