import {useEffect, useRef, useState} from 'react';
import type {ReactNode} from 'react';
import type {CareerSummary} from './practice-client';
import type {FirstTradeEvidence} from './journey';
import type {ReminderChoice, ReminderRecord} from './journey-store';
import {downloadReminderCalendar} from './reminder-calendar';
import {CompanyLogo, Loading, art, micros, shares} from './ui';

/**
 * Back and Escape run each screen's named action, as mobile's PopScope does.
 * One history entry is added so Back reaches this handler instead of leaving.
 */
function useBackAction(action: (() => void) | null) {
  const current = useRef(action); current.current = action;
  useEffect(() => {
    const state: unknown = window.history.state;
    window.history.pushState({...(state && typeof state === 'object' && !Array.isArray(state) ? state : {}), trimmyJourney: true}, '', window.location.href);
    const back = () => current.current?.();
    const key = (event: KeyboardEvent) => {if (event.key === 'Escape') {event.preventDefault(); current.current?.();}};
    window.addEventListener('popstate', back); window.addEventListener('keydown', key);
    return () => {window.removeEventListener('popstate', back); window.removeEventListener('keydown', key);};
  }, []);
}
function useHeadingFocus<T extends HTMLElement>() {
  const heading = useRef<T>(null);
  useEffect(() => {heading.current?.focus();}, []);
  return heading;
}

export interface CelebrationProps {
  readonly evidence: FirstTradeEvidence | null; readonly name: string | null; readonly logoUrl: string | null;
  readonly career: CareerSummary | null; readonly loading: boolean;
  readonly onContinue: () => Promise<void>; readonly onRetry: () => void;
}
/** The confirmed first order. Continue records it; it never places another order. */
export function FirstOrderCelebration({evidence, name, logoUrl, career, loading, onContinue, onRetry}: CelebrationProps) {
  const [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null);
  const locked = useRef(false), mounted = useRef(true);
  const heading = useHeadingFocus<HTMLHeadingElement>();
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  async function next() {
    if (locked.current || !evidence) return;
    locked.current = true; setBusy(true); setError(null);
    try {await onContinue();}
    catch {if (mounted.current) setError('Couldn’t continue. Try again.');}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  useBackAction(() => void next());
  if (!evidence) return <section className="first-day journey-screen journey-state" aria-label="Your first order">
    <img className="journey-state-art" src={art('career-world/trophy.png')} alt=""/>
    <h1 ref={heading} tabIndex={-1}>{loading ? 'Opening your trade' : 'Couldn’t load your trade'}</h1>
    {loading ? <Loading>Opening your first stock…</Loading> : <><p>Try again to see your confirmed order.</p><button className="primary" onClick={onRetry}>Try again</button></>}
  </section>;
  const company = name ?? evidence.symbol;
  const reward = career?.firstConfirmedBuy?.orderId === evidence.orderId ? career : null;
  return <section className="first-day journey-screen first-order" aria-label="Your first order">
    <div className="intro-receipt-mark" aria-hidden="true">✓</div>
    <h1 ref={heading} tabIndex={-1}>You’ve placed your first order!</h1>
    <p className="journey-lede">Now let’s create your trader profile.</p>
    <div className="first-order-ticket">
      <div className="first-order-ticket-upper">
        <div className="first-order-company"><CompanyLogo name={company} url={logoUrl} size={46}/><strong>{company}</strong><span className="first-order-check" aria-label="Buy confirmed">✓</span></div>
        {evidence.cashDebitPaperMicros !== null && <><span className="first-order-label">Invested</span><span className="first-order-amount">{micros(evidence.cashDebitPaperMicros)}<small>paper</small></span></>}
        <span className="first-order-shares">Shares <strong>{shares(evidence.quantityMicros)}</strong></span>
      </div>
      <div className="first-order-ticket-lower"><span className="first-order-confirmed">Buy confirmed</span>
        {reward && <span className="first-order-reward">{reward.rank.label} · {reward.trims.total.toLocaleString()} Trims total</span>}</div>
    </div>
    <button className="primary full" disabled={busy} onClick={() => void next()}>{busy ? 'Saving…' : 'Continue'}</button>
    {error && <p className="intro-error" role="alert">{error}</p>}
    <p className="intro-disclosure">Confirmed paper order. No real money moved.</p>
  </section>;
}

const reminderChoices: readonly {id: ReminderChoice; label: string; caption: string}[] = [
  {id: 'daily', label: 'Once a day', caption: 'Around 7 PM, your time.'},
  {id: 'occasional', label: 'A few times a week', caption: 'Mon, Wed and Fri, around 7 PM.'},
  {id: 'off', label: 'Keep it quiet', caption: 'I’ll come back on my own.'},
];
export interface ReminderPageProps {
  readonly saved: ReminderRecord | null;
  /** Saves the preference on this browser. Never requests a notification permission. */
  readonly onSave: (choice: ReminderChoice) => Promise<void>;
  readonly onDone: () => Promise<void>;
  readonly downloadCalendar?: (choice: Exclude<ReminderChoice, 'off'>) => boolean;
}
/** Mobile's "A little nudge?" page with an honest browser delivery: a calendar event. */
export function ReminderPreferencePage({saved, onSave, onDone, downloadCalendar = downloadReminderCalendar}: ReminderPageProps) {
  const [selected, setSelected] = useState<ReminderChoice | null>(saved?.choice ?? null);
  const [confirmed, setConfirmed] = useState<ReminderChoice | null>(null);
  const [busy, setBusy] = useState(false), [message, setMessage] = useState<string | null>(null), [error, setError] = useState<string | null>(null);
  const locked = useRef(false), mounted = useRef(true);
  const heading = useHeadingFocus<HTMLHeadingElement>();
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  async function run(task: () => Promise<void>) {
    if (locked.current) return; locked.current = true; setBusy(true); setError(null);
    try {await task();} catch {if (mounted.current) setError('Couldn’t save that. Try again.');}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  const save = (skip = false) => run(async () => {
    const choice = skip ? 'off' : selected;
    if (!choice) return;
    if (!skip && confirmed === choice) {await onDone(); return;}
    await onSave(choice);
    if (choice === 'off') {await onDone(); return;}
    // A browser tab cannot wake itself; keep the choice and offer the calendar.
    if (mounted.current) {setConfirmed(choice); setMessage('Your preference is saved. Browsers can’t send Trimmy reminders while it’s closed, so add it to your calendar.');}
  });
  useBackAction(() => void save(true));
  return <section className="first-day journey-screen reminder-page" aria-label="Reminders">
    <button className="intro-close" aria-label="Skip reminders" disabled={busy} onClick={() => void save(true)}>×</button>
    <img className="journey-icon" src={art('icons/asset-bell.png')} alt="" width="52" height="52"/>
    <h1 ref={heading} tabIndex={-1}>A little nudge?</h1>
    <p className="journey-lede">How often would you like a reminder?</p>
    <div className="setup-choices" role="radiogroup" aria-label="Reminder frequency">{reminderChoices.map(choice => <button key={choice.id}
      className="setup-choice" role="radio" aria-checked={selected === choice.id} disabled={busy}
      onClick={() => {setSelected(choice.id); setConfirmed(null); setMessage(null); setError(null);}}>
      <span><strong>{choice.label}</strong><small>{choice.caption}</small></span></button>)}</div>
    {message && confirmed && confirmed !== 'off' && <div className="journey-message" role="status"><p>{message}</p>
      <button className="secondary" disabled={busy} onClick={() => {if (!downloadCalendar(confirmed)) setError('Couldn’t create the calendar file. Try again.');}}>Add to calendar</button></div>}
    {error && <p className="intro-error" role="alert">{error}</p>}
    <button className="primary full" disabled={busy || selected === null} onClick={() => void save()}>{busy ? 'Saving…' : 'Continue'}</button>
  </section>;
}

export interface MoneyChoiceProps {readonly onFinish: (addMoney: boolean) => Promise<void>}
/** Practice money or fund the wallet. Both finish the saved introduction first. */
export function MoneyChoicePage({onFinish}: MoneyChoiceProps) {
  const [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null);
  const locked = useRef(false), mounted = useRef(true);
  const heading = useHeadingFocus<HTMLHeadingElement>();
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  async function finish(addMoney: boolean) {
    if (locked.current) return; locked.current = true; setBusy(true); setError(null);
    try {await onFinish(addMoney);}
    catch {if (mounted.current) setError('Your trade is safe. Try continuing again.');}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  useBackAction(() => void finish(false));
  return <section className="first-day journey-screen money-choice" aria-label="Your next move">
    <button className="intro-close" aria-label="Keep using free money" disabled={busy} onClick={() => void finish(false)}>×</button>
    <img className="journey-state-art" src={art('career-world/safe.png')} alt=""/>
    <h1 ref={heading} tabIndex={-1}>Your next move.</h1>
    <p className="journey-lede">Keep finding your feet, or fund your wallet.</p>
    <div className="setup-choices">
      <button className="setup-choice" disabled={busy} onClick={() => void finish(false)}><img src={art('icons/goal-goal-animated.png')} alt="" width="34" height="34"/>
        <span><strong>Keep using free money</strong><small>Build your confidence on the desk.</small></span></button>
      <button className="setup-choice" disabled={busy} onClick={() => void finish(true)}><span className="setup-choice-plus" aria-hidden="true">+</span>
        <span><strong>Add money</strong><small>See your deposit options.</small></span></button>
    </div>
    <p className="journey-footnote">You can add money from your desk any time.</p>
    {busy && <p className="journey-footnote" role="status">Saving…</p>}
    {error && <p className="intro-error" role="alert">{error}</p>}
  </section>;
}

/** An existing account keeps its own desk; guest trades are never merged here. */
export function GuestDeskPreserved({expired, onContinue}: {expired: boolean; onContinue: () => void}) {
  const heading = useHeadingFocus<HTMLHeadingElement>();
  return <section className="first-day journey-screen journey-state" aria-label="Welcome back">
    <div className="journey-preserved-art"><img src={art('career-world/desk.png')} alt=""/><span aria-hidden="true">✓</span></div>
    <h1 ref={heading} tabIndex={-1}>Welcome back</h1>
    <p className="journey-lede">Your saved trades and progress are ready.</p>
    <div className="journey-card"><img src={art('icons/settings-lock.png')} alt="" width="26" height="26"/>
      <p>{expired ? 'Your expired guest desk is preserved separately. It can no longer trade or merge.' : 'Your guest trades stay separate. Sign out to return to that desk.'}</p></div>
    <button className="primary full" onClick={onContinue}>Go to my desk</button>
  </section>;
}

export function JourneyFrame({children}: {children: ReactNode}) {return <div className="journey-frame">{children}</div>;}
