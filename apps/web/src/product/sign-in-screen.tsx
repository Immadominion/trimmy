import {useEffect, useRef, useState} from 'react';
import {useProductAuth, type ProductLoginMethod} from './product-auth';
import {SalArt, art} from './ui';

const methods: Record<ProductLoginMethod, {name: string; icon: string}> = {
  email: {name: 'email', icon: 'account-email-rounded.png'},
  google: {name: 'Google', icon: 'account-google-rounded.png'},
  x: {name: 'X', icon: 'account-x-standalone-rounded.png'},
};
function authError(code: string | null): string | null {
  if (!code) return null;
  if (code === 'PRODUCT_EMAIL_INVALID') return 'Enter a valid email address.';
  if (code === 'PRODUCT_EMAIL_CODE_INVALID') return 'That code didn’t work. Check it and try again.';
  if (code === 'PRODUCT_EMAIL_CODE_SEND_FAILED') return 'We couldn’t send the code. Try again in a moment.';
  if (code === 'PRACTICE_COMMIT_PENDING') return 'Check your last order from your desk before signing in.';
  if (code === 'PRACTICE_PROFILE_PENDING') return 'Finish saving your desk before signing in.';
  if (code === 'PRACTICE_WORKDAY_PENDING') return 'Check your saved assignment in Career before signing in.';
  if (code === 'PRACTICE_DAILY_DESK_PENDING') return 'Check your earlier clock-out before signing in.';
  if (code === 'PRACTICE_CLAIM_PENDING') return 'Use the same sign-in method to finish saving this desk.';
  if (code.includes('STORAGE')) return 'Allow browser storage to keep your desk, then try again.';
  if (code === 'PRODUCT_SIGN_OUT_FAILED') return 'Sign-out didn’t finish. Please try again.';
  return 'Sign-in couldn’t finish. Your progress is safe. Please try again.';
}
export function SignInScreen({motion, hasDesk, onBack, onAccount, entryGate = false, onGuest, expiredGuestRecovery = false}: {
  motion: boolean; hasDesk: boolean; onBack: () => void; onAccount: () => void;
  /** Mobile's startup gate: only the labelled "Continue as guest" action grants guest access. */
  entryGate?: boolean; onGuest?: () => Promise<void> | void;
  /** Sign-in from an expired guest desk keeps that desk preserved and separate. */
  expiredGuestRecovery?: boolean;
}) {
  const auth = useProductAuth();
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
  const message = auth.phase === 'account-choice' ? null : authError(auth.errorCode);
  const loading = auth.phase === 'restoring' || auth.phase === 'connecting' || auth.phase === 'signing-out';
  return <section className="sign-in-screen" aria-label="Sign in">
    {!entryGate && <button className="sign-in-close" aria-label="Close sign in" disabled={auth.busy} onClick={() => void back()}>×</button>}
    <div className="sign-in-art"><SalArt motion={motion}/></div>
    <div className="sign-in-content">
      {auth.phase === 'account-choice' ? <>
        <h1 ref={heading} tabIndex={-1}>Your saved desk is waiting.</h1>
        <p>{auth.errorCode === 'GUEST_SESSION_EXPIRED' ? 'This guest session has expired. Open your account to pick up where you left off.' : 'There’s already a desk on this account. Your guest progress stays in this browser.'}</p>
        <button className="primary full" onClick={() => void auth.openExistingAccount()}>Open my account</button>
        <button className="text-button full" onClick={() => void back()}>Keep this guest desk</button>
      </> : loading ? <>
        <h1 ref={heading} tabIndex={-1}>{auth.phase === 'signing-out' ? 'See you soon.' : 'Opening your desk.'}</h1>
        <p role="status">{auth.phase === 'connecting' ? 'Restoring your progress…' : 'Just a moment…'}</p>
      </> : codeEntry ? <>
        <h1 ref={heading} tabIndex={-1}>Check your inbox.</h1><p>Enter the code sent to <strong>{auth.email}</strong>.</p>
        <form onSubmit={event => {event.preventDefault(); void auth.verifyEmailCode(code);}}>
          <label htmlFor="sign-in-code">Your six-digit code</label><input id="sign-in-code" className="sign-in-code" autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6}" maxLength={6} value={code} disabled={auth.busy} onChange={event => setCode(event.target.value.replace(/\D/g, ''))}/>
          <button className="primary full" disabled={auth.busy || !/^\d{6}$/.test(code)}>{auth.busy ? 'Signing in…' : 'Continue'}</button>
        </form>
        <button className="text-button full" disabled={auth.busy || clock < resendAt} onClick={() => {setResendAt(Date.now() + 30000); void auth.sendEmailCode(auth.email!);}}>{clock < resendAt ? `Send again in ${Math.ceil((resendAt - clock) / 1000)}s` : 'Send a new code'}</button>
        <button className="text-button full" disabled={auth.busy} onClick={() => {auth.cancel(); setCode(''); setEmailEntry(true);}}>Use a different email</button>
      </> : emailEntry ? <>
        <h1 ref={heading} tabIndex={-1}>Your email. Your desk.</h1><p>We’ll send a code. No password to remember.</p>
        <form onSubmit={event => {event.preventDefault(); void send();}}>
          <label htmlFor="sign-in-email">Email address</label><input id="sign-in-email" type="email" autoComplete="email" placeholder="you@example.com" maxLength={254} required value={email} disabled={auth.busy} onChange={event => setEmail(event.target.value)}/>
          <button className="primary full" disabled={auth.busy || !email.trim()}>{auth.busy ? 'Sending your code…' : 'Continue with email'}</button>
        </form><button className="text-button full" disabled={auth.busy} onClick={() => {auth.cancel(); setEmailEntry(false);}}>Other ways to sign in</button>
      </> : <>
        <h1 ref={heading} tabIndex={-1}>{entryGate ? 'Your desk awaits.' : expiredGuestRecovery ? 'Sign in to Trimmy.' : auth.lastSuccessfulMethod ? 'Welcome back.' : hasDesk ? 'Make this desk yours.' : 'Your seat’s waiting.'}</h1>
        <p>{entryGate ? 'Sign in or create your account.' : expiredGuestRecovery ? 'Open your account desk. The expired guest desk stays separate.' : hasDesk ? 'Save your progress. Pick up on any device.' : 'Sign in and settle back in.'}</p>
        {expiredGuestRecovery && <p className="sign-in-notice" role="note">Closing sign-in keeps the expired guest desk preserved.</p>}
        <button className="primary full sign-in-preferred" disabled={auth.busy || !auth.enabled} onClick={() => choose(preferred)}><img src={art(`icons/${methods[preferred].icon}`)} alt=""/>Continue with {methods[preferred].name}</button>
        {auth.lastSuccessfulMethod && <span className="last-login">Last used on this browser</span>}
        {entryGate && onGuest && <button className="text-button full sign-in-guest" disabled={auth.busy || guestBusy} onClick={() => void guest()}>{guestBusy ? 'Saving…' : 'Continue as guest'}</button>}
        {guestError && <p className="sign-in-error" role="alert">Couldn’t save your choice. Try again.</p>}
        <div className="sign-in-divider"><span>or continue with</span></div>
        <div className="sign-in-social">{(['email', 'google', 'x'] as const).filter(method => method !== preferred).map(method => <div key={method}><button disabled={auth.busy || !auth.enabled} aria-label={`Continue with ${methods[method].name}`} onClick={() => choose(method)}><img src={art(`icons/${methods[method].icon}`)} alt=""/></button><span>{methods[method].name}</span></div>)}</div>
        {!auth.enabled && <p className="sign-in-error" role="status">Sign-in isn’t available here yet.</p>}
        {auth.phase === 'authenticating' && <p role="status" className="sign-in-status">Opening secure sign-in…</p>}
      </>}
      {message && <div className="sign-in-error" role="alert"><p>{message}</p>{auth.errorCode === 'PRODUCT_SIGN_OUT_FAILED' ? <button className="text-button" disabled={auth.busy} onClick={() => void back()}>Try signing out again</button> : auth.subject && <button className="text-button" disabled={auth.busy} onClick={() => void auth.retry()}>Try again</button>}</div>}
    </div>
  </section>;
}
