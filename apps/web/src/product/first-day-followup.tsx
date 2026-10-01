import {useEffect, useRef, useState} from 'react';
import type {CareerSummary} from './practice-client';
import type {FirstTradeEvidence} from './journey';
import type {ReminderChoice, ReminderRecord} from './journey-store';
import {downloadReminderCalendar} from './reminder-calendar';
import {CompanyLogo, Loading, art, micros, shares} from './ui';
import {useT} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';
import * as fmt from '../i18n/format';
import {rankName} from './career-milestones';
import {useUsage} from './usage';

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
  const tr = useT();
  const [busy, setBusy] = useState(false), [error, setError] = useState<MessageKey | null>(null);
  const locked = useRef(false), mounted = useRef(true);
  const heading = useHeadingFocus<HTMLHeadingElement>();
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  async function next() {
    if (locked.current || !evidence) return;
    locked.current = true; setBusy(true); setError(null);
    try {await onContinue();}
    catch {if (mounted.current) setError('firstDay.order.continueError');}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  useBackAction(() => void next());
  if (!evidence) return <section className="first-day journey-screen journey-state" aria-label={tr('firstDay.order.label')}>
    <img className="journey-state-art" src={art('career-world/trophy.png')} alt=""/>
    <h1 ref={heading} tabIndex={-1}>{loading ? tr('firstDay.order.opening') : tr('firstDay.order.loadFailed')}</h1>
    {loading ? <Loading>{tr('firstDay.order.loading')}</Loading> : <><p>{tr('firstDay.order.retryLede')}</p><button className="primary" onClick={onRetry}>{tr('common.tryAgain')}</button></>}
  </section>;
  const company = name ?? evidence.symbol;
  const reward = career?.firstConfirmedBuy?.orderId === evidence.orderId ? career : null;
  return <section className="first-day journey-screen first-order" aria-label={tr('firstDay.order.label')}>
    <div className="intro-receipt-mark" aria-hidden="true">✓</div>
    <h1 ref={heading} tabIndex={-1}>{tr('firstDay.order.title')}</h1>
    <p className="journey-lede">{tr('firstDay.order.lede')}</p>
    <div className="first-order-ticket">
      <div className="first-order-ticket-upper">
        <div className="first-order-company"><CompanyLogo name={company} url={logoUrl} size={46}/><strong>{company}</strong><span className="first-order-check" aria-label={tr('firstDay.order.buyConfirmed')}>✓</span></div>
        {evidence.cashDebitPaperMicros !== null && <><span className="first-order-label">{tr('firstDay.order.invested')}</span><span className="first-order-amount">{micros(evidence.cashDebitPaperMicros)}<small>{tr('common.paperUnit')}</small></span></>}
        <span className="first-order-shares">{tr.rich('firstDay.order.shares', {shares: shares(evidence.quantityMicros)})}</span>
      </div>
      <div className="first-order-ticket-lower"><span className="first-order-confirmed">{tr('firstDay.order.buyConfirmed')}</span>
        {reward && <span className="first-order-reward">{tr('firstDay.order.reward', {rank: rankName(reward.rank), trims: fmt.count(reward.trims.total)})}</span>}</div>
    </div>
    <button className="primary full" disabled={busy} onClick={() => void next()}>{busy ? tr('firstDay.saving') : tr('common.continue')}</button>
    {error && <p className="intro-error" role="alert">{tr(error)}</p>}
    <p className="intro-disclosure">{tr('firstDay.order.disclosure')}</p>
  </section>;
}

/** The schedule is the calendar file's (reminder-calendar.ts): daily, or Monday, Wednesday and Friday, at 7 PM local time. */
const reminderChoices: readonly {id: ReminderChoice; label: MessageKey; caption: MessageKey}[] = [
  {id: 'daily', label: 'firstDay.reminders.daily', caption: 'firstDay.reminders.dailyCaption'},
  {id: 'occasional', label: 'firstDay.reminders.occasional', caption: 'firstDay.reminders.occasionalCaption'},
  {id: 'off', label: 'firstDay.reminders.off', caption: 'firstDay.reminders.offCaption'},
];
export interface ReminderPageProps {
  readonly saved: ReminderRecord | null;
  /** Saves the preference on this browser. Never requests a notification permission. */
  readonly onSave: (choice: ReminderChoice) => Promise<void>;
  readonly onDone: () => Promise<void>;
  readonly downloadCalendar?: (choice: Exclude<ReminderChoice, 'off'>) => boolean;
  /** From Settings: Back, Escape and × only close. In the first day they skip, as on mobile. */
  readonly onClose?: () => void;
}
/** Mobile's "A little nudge?" page with an honest browser delivery: a calendar event. */
export function ReminderPreferencePage({saved, onSave, onDone, downloadCalendar = downloadReminderCalendar, onClose}: ReminderPageProps) {
  const tr = useT();
  const usage = useUsage();
  const [selected, setSelected] = useState<ReminderChoice | null>(saved?.choice ?? null);
  const [confirmed, setConfirmed] = useState<ReminderChoice | null>(null);
  const [busy, setBusy] = useState(false), [message, setMessage] = useState<MessageKey | null>(null), [error, setError] = useState<MessageKey | null>(null);
  const locked = useRef(false), mounted = useRef(true);
  const heading = useHeadingFocus<HTMLHeadingElement>();
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  async function run(task: () => Promise<void>) {
    if (locked.current) return; locked.current = true; setBusy(true); setError(null);
    try {await task();} catch {if (mounted.current) setError('firstDay.reminders.saveError');}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  const save = (skip = false) => run(async () => {
    const choice = skip ? 'off' : selected;
    if (!choice) return;
    if (!skip && confirmed === choice) {await onDone(); return;}
    await onSave(choice);
    // A browser has no reminder permission to ask: the calendar file is the reminder.
    usage.track({name: 'reminder_choice', props: {frequency: choice, permission: 'not_asked'}});
    if (choice === 'off') {await onDone(); return;}
    // A browser tab cannot wake itself; keep the choice and offer the calendar.
    if (mounted.current) {setConfirmed(choice); setMessage('firstDay.reminders.saved');}
  });
  useBackAction(() => {if (onClose) onClose(); else void save(true);});
  return <section className="first-day journey-screen reminder-page" aria-label={tr('firstDay.reminders.label')}>
    <button className="intro-close" aria-label={onClose ? tr('firstDay.reminders.close') : tr('firstDay.reminders.skip')} disabled={busy} onClick={() => {if (onClose) onClose(); else void save(true);}}>×</button>
    <img className="journey-icon" src={art('icons/asset-bell.png')} alt="" width="52" height="52"/>
    <h1 ref={heading} tabIndex={-1}>{tr('firstDay.reminders.title')}</h1>
    <p className="journey-lede">{tr('firstDay.reminders.lede')}</p>
    <div className="setup-choices" role="radiogroup" aria-label={tr('firstDay.reminders.frequency')}>{reminderChoices.map(choice => <button key={choice.id}
      className="setup-choice" role="radio" aria-checked={selected === choice.id} disabled={busy}
      onClick={() => {setSelected(choice.id); setConfirmed(null); setMessage(null); setError(null);}}>
      <span><strong>{tr(choice.label)}</strong><small>{tr(choice.caption)}</small></span></button>)}</div>
    {message && confirmed && confirmed !== 'off' && <div className="journey-message" role="status"><p>{tr(message)}</p>
      <button className="secondary" disabled={busy} onClick={() => {if (!downloadCalendar(confirmed)) setError('firstDay.reminders.calendarError');}}>{tr('firstDay.reminders.addToCalendar')}</button></div>}
    {error && <p className="intro-error" role="alert">{tr(error)}</p>}
    <button className="primary full" disabled={busy || selected === null} onClick={() => void save()}>{busy ? tr('firstDay.saving') : tr('common.continue')}</button>
  </section>;
}

export interface MoneyChoiceProps {readonly onFinish: (addMoney: boolean) => Promise<void>}
/** Practice money or fund the wallet. Both finish the saved introduction first. */
export function MoneyChoicePage({onFinish}: MoneyChoiceProps) {
  const tr = useT();
  const [busy, setBusy] = useState(false), [error, setError] = useState(false);
  const locked = useRef(false), mounted = useRef(true);
  const heading = useHeadingFocus<HTMLHeadingElement>();
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  async function finish(addMoney: boolean) {
    if (locked.current) return; locked.current = true; setBusy(true); setError(false);
    try {await onFinish(addMoney);}
    catch {if (mounted.current) setError(true);}
    finally {locked.current = false; if (mounted.current) setBusy(false);}
  }
  useBackAction(() => void finish(false));
  return <section className="first-day journey-screen money-choice" aria-label={tr('firstDay.money.label')}>
    <button className="intro-close" aria-label={tr('firstDay.money.keepFree')} disabled={busy} onClick={() => void finish(false)}>×</button>
    <img className="journey-state-art" src={art('career-world/safe.png')} alt=""/>
    <h1 ref={heading} tabIndex={-1}>{tr('firstDay.money.title')}</h1>
    <p className="journey-lede">{tr('firstDay.money.lede')}</p>
    <div className="setup-choices">
      <button className="setup-choice" disabled={busy} onClick={() => void finish(false)}><img src={art('icons/goal-goal-animated.png')} alt="" width="34" height="34"/>
        <span><strong>{tr('firstDay.money.keepFree')}</strong><small>{tr('firstDay.money.keepFreeCaption')}</small></span></button>
      <button className="setup-choice" disabled={busy} onClick={() => void finish(true)}><span className="setup-choice-plus" aria-hidden="true">+</span>
        <span><strong>{tr('firstDay.money.add')}</strong><small>{tr('firstDay.money.addCaption')}</small></span></button>
    </div>
    <p className="journey-footnote">{tr('firstDay.money.footnote')}</p>
    {busy && <p className="journey-footnote" role="status">{tr('firstDay.saving')}</p>}
    {error && <p className="intro-error" role="alert">{tr('firstDay.money.error')}</p>}
  </section>;
}

/** An existing account keeps its own desk; guest trades are never merged here. */
export function GuestDeskPreserved({expired, onContinue}: {expired: boolean; onContinue: () => void}) {
  const tr = useT();
  const heading = useHeadingFocus<HTMLHeadingElement>();
  return <section className="first-day journey-screen journey-state" aria-label={tr('firstDay.preserved.title')}>
    <div className="journey-preserved-art"><img src={art('career-world/desk.png')} alt=""/><span aria-hidden="true">✓</span></div>
    <h1 ref={heading} tabIndex={-1}>{tr('firstDay.preserved.title')}</h1>
    <p className="journey-lede">{tr('firstDay.preserved.lede')}</p>
    <div className="journey-card"><img src={art('icons/settings-lock.png')} alt="" width="26" height="26"/>
      <p>{expired ? tr('firstDay.preserved.expired') : tr('firstDay.preserved.separate')}</p></div>
    <button className="primary full" onClick={onContinue}>{tr('firstDay.preserved.go')}</button>
  </section>;
}

