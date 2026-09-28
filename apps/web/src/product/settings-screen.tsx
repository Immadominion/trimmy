import {useEffect, useId, useRef, useState} from 'react';
import type {ReactNode} from 'react';
import {PracticeError} from './practice-client';
import type {ReasonVisibility} from './career-actions';
import {PAPER_RESET_CONFIRMATION} from './career-actions';
import type {ReasonPrivacyState} from './use-reason-privacy';
import type {ReminderChoice, ReminderRecord} from './journey-store';
import {ReminderPreferencePage} from './first-day-followup';
import {art, micros} from './ui';

export interface PaperResetOutcome {readonly cashPaperMicros: string; readonly newerActivity: boolean}
export interface SettingsScreenProps {
  readonly signedIn: boolean; readonly authBusy: boolean; readonly handle: string | null; readonly persona: string | null;
  readonly paperLimit: string | null;
  readonly reminder: ReminderRecord | null; readonly remindersAvailable: boolean;
  readonly onSaveReminder: (choice: ReminderChoice) => Promise<void>;
  readonly sound: boolean; readonly onSound: () => void;
  readonly motion: boolean; readonly onMotion: (value: boolean) => void;
  readonly privacy: ReasonPrivacyState | null;
  readonly resetAvailable: boolean; readonly resetPending: boolean; readonly onResetPaper: () => Promise<PaperResetOutcome>;
  readonly closeAvailable: boolean; readonly onCloseAccount: () => Promise<void>;
  readonly onSignIn: () => void; readonly onSignOut: () => void; readonly onTrader: () => void; readonly onAddMoney: () => void;
  readonly onBack: () => void;
}

function Row({icon, title, subtitle, children, destructive = false}: {icon?: string; title: string; subtitle?: ReactNode; children?: ReactNode; destructive?: boolean}) {
  return <div className={`settings-row${destructive ? ' destructive' : ''}`}>{icon ? <img src={art(`icons/${icon}`)} alt="" width="25" height="25"/> : <span className="settings-row-spacer"/>}
    <div className="settings-row-copy"><strong>{title}</strong>{subtitle !== undefined && <p>{subtitle}</p>}</div>{children}</div>;
}
function Section({title, children}: {title: string; children: ReactNode}) {
  const id = useId();
  return <section className="settings-section" aria-labelledby={id}><h2 id={id}>{title}</h2><div className="settings-rows">{children}</div></section>;
}
function Modal({title, children, onClose}: {title: string; children: ReactNode; onClose: () => void}) {
  const id = useId(), panel = useRef<HTMLDivElement>(null), close = useRef(onClose); close.current = onClose;
  useEffect(() => {
    // Focus moves once, when the dialog opens; later renders never pull it back.
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    panel.current?.querySelector<HTMLElement>('input, button')?.focus();
    const key = (event: KeyboardEvent) => {if (event.key === 'Escape') {event.preventDefault(); close.current();}};
    window.addEventListener('keydown', key);
    return () => {window.removeEventListener('keydown', key); opener?.focus?.();};
  }, []);
  return <div className="settings-modal-backdrop" onClick={event => {if (event.target === event.currentTarget) onClose();}}>
    <div className="settings-modal" role="dialog" aria-modal="true" aria-labelledby={id} ref={panel}><h2 id={id}>{title}</h2>{children}</div>
  </div>;
}

const visibilityLabel: Record<ReasonVisibility, string> = {nobody: 'Nobody', everyone: 'Everyone', friends: 'Friends'};
const friendsLine = (available: boolean) => available ? 'Only your Trimmy friends can see them on each stock page.' : 'Not available yet. Shares nothing until friends exist.';
function describe(visibility: ReasonVisibility, friendsAvailable: boolean): string {
  return visibility === 'nobody' ? 'Only you can see your comments.' : visibility === 'everyone' ? 'Anyone in Trimmy can see them on each stock page.' : friendsLine(friendsAvailable);
}
function privacySubtitle(state: ReasonPrivacyState): string {
  const {privacy, pending, failure} = state;
  if (state.saving && pending) return `Saving ${visibilityLabel[pending.visibility]}.`;
  if (state.loading && !privacy) return 'Loading your choice.';
  if (failure) {
    const code = failure.code, retry = failure.retryAfterSeconds;
    if (/EXPIRED|REVOKED/.test(code)) return 'This guest desk needs recovery.';
    if (failure.status === 429) return `Too many changes. Try to ${privacy ? 'save' : 'load'} again ${retry ? `in ${retry} ${retry === 1 ? 'second' : 'seconds'}` : 'shortly'}.`;
    if (!privacy) return code === 'PRACTICE_NETWORK_ERROR' ? 'You are offline. Your choice could not load.' : code === 'PRACTICE_TIMEOUT' ? 'Your choice took too long to load.'
      : failure.status === 401 ? 'Your session needs a refresh before this can load.' : code === 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND' ? 'This account is closed.' : 'Your choice could not load.';
    const notSaved = pending ? `${visibilityLabel[pending.visibility]} is not saved yet.` : 'Your choice is not saved yet.';
    return code === 'PRACTICE_NETWORK_ERROR' ? `You are offline. ${notSaved}` : code === 'PRACTICE_TIMEOUT' ? `Saving took too long. ${notSaved}`
      : failure.status === 401 ? `Your session needs a refresh. ${notSaved}` : code === 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND' ? 'This account is closed. Nothing was saved.'
      : code === 'CAREER_REASON_SHARING_IDEMPOTENCY_CONFLICT' ? 'That save could not be matched. Choose again.' : `Couldn't save. ${notSaved}`;
  }
  if (!privacy) return 'Your choice is not available yet.';
  const line = describe(privacy.visibility, privacy.friendsSharing === 'available');
  return state.notice === 'saved' ? `Saved. ${line}` : state.notice === 'changed-elsewhere' ? `Changed on another device. Refreshed. ${line}` : line;
}
function resetFailure(error: unknown): string {
  const code = error instanceof PracticeError ? error.code : '';
  if (code === 'PAPER_PORTFOLIO_CHANGED') return 'Your paper desk changed. It was refreshed. Review it, then confirm the reset again.';
  if (code === 'PAPER_RESET_NOT_NEEDED') return 'Your paper desk is already fresh. Nothing was cleared.';
  if (code === 'PRACTICE_NETWORK_ERROR') return 'You are offline. Your exact reset request is saved for a safe retry.';
  if (code === 'PRACTICE_TIMEOUT') return 'The reset took too long to confirm. Your exact request is saved for a safe retry.';
  if (error instanceof PracticeError && error.status === 401) return 'Your paper desk needs a fresh session before the reset can finish.';
  if (error instanceof PracticeError && error.status === 429) return 'Paper resets are limited. Try this saved request again later.';
  if (error instanceof PracticeError && (error.status === null || error.status >= 500)) return 'The reset could not be confirmed. Your exact request is saved for a safe retry.';
  return 'Paper was not reset. Refresh your desk and try again.';
}

/** Mobile's Settings in the web frame. Rows the browser cannot support say so plainly. */
export function SettingsScreen(props: SettingsScreenProps) {
  const [view, setView] = useState<'list' | 'reminders'>('list');
  const [dialog, setDialog] = useState<null | 'privacy' | 'reset' | 'reset-done' | 'close'>(null);
  const [draft, setDraft] = useState<ReasonVisibility>('nobody'), [phrase, setPhrase] = useState('');
  const [resetting, setResetting] = useState(false), [resetResult, setResetResult] = useState<PaperResetOutcome | null>(null), [message, setMessage] = useState<string | null>(null);
  const [closing, setClosing] = useState(false), [closeError, setCloseError] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null), mounted = useRef(true);
  const reducedMotion = typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  useEffect(() => {if (view === 'list') heading.current?.focus();}, [view]);
  if (view === 'reminders') return <ReminderPreferencePage saved={props.reminder} onSave={props.onSaveReminder}
    onDone={async () => {setView('list');}} onClose={() => setView('list')}/>;
  const privacy = props.privacy;
  async function reset() {
    if (resetting) return; setResetting(true); setMessage(null);
    try {const outcome = await props.onResetPaper(); if (mounted.current) {setResetResult(outcome); setDialog('reset-done');}}
    catch (error) {if (mounted.current) {setDialog(null); setMessage(resetFailure(error));}}
    finally {if (mounted.current) {setResetting(false); setPhrase('');}}
  }
  async function closeAccount() {
    if (closing) return; setClosing(true); setCloseError(false);
    try {await props.onCloseAccount();} catch {if (mounted.current) setCloseError(true);} finally {if (mounted.current) setClosing(false);}
  }
  return <section className="settings-screen" aria-labelledby="settings-heading">
    <button className="company-back" onClick={props.onBack}>← Back to Profile</button>
    <div className="page-intro"><h1 id="settings-heading" ref={heading} tabIndex={-1}>Settings</h1></div>
    {message && <div className="notice" role="status">{message}<button className="text-button" onClick={() => setMessage(null)}>Dismiss</button></div>}
    <div className="settings-grid">
      <Section title="Account">
        {!props.signedIn && <Row icon="settings-lock.png" title="Sign in" subtitle="Sign in to keep your progress."><button className="secondary" disabled={props.authBusy} onClick={props.onSignIn}>Sign in</button></Row>}
        {props.signedIn && props.handle && <Row icon="profile-edit.png" title="Handle" subtitle={`@${props.handle}`}/>}
        <Row icon="nav-plumpy-profile.png" title="Your trader" subtitle={props.persona ?? 'Choose a character'}><button className="text-button" aria-label={props.persona ? 'Change your trader' : 'Choose your trader'} onClick={props.onTrader}>{props.persona ? 'Change' : 'Choose'}</button></Row>
        {props.signedIn && <Row icon="settings-gear.png" title="Sign out"><button className="text-button" disabled={props.authBusy} onClick={props.onSignOut}>Sign out</button></Row>}
        {props.remindersAvailable && <Row icon="asset-bell.png" title="Reminders" subtitle={props.reminder ? {daily: 'Once a day, around 7 PM.', occasional: 'Mon, Wed and Fri, around 7 PM.', off: 'Keep it quiet.'}[props.reminder.choice] + ' Saved on this browser.' : 'Not set on this browser.'}>
          <button className="text-button" aria-label="Change reminders" onClick={() => setView('reminders')}>Change</button></Row>}
        <Row icon="goal-goal-animated.png" title="Add money" subtitle={props.signedIn ? 'See your deposit options.' : 'Sign in to see your deposit options.'}><button className="text-button" aria-label="Add money" onClick={props.onAddMoney}>Open</button></Row>
      </Section>
      <Section title="Preferences">
        <Row icon="settings-sound.png" title="Sound" subtitle="Sounds for key moments."><input className="web-profile-switch" type="checkbox" role="switch" aria-label="Sound" checked={props.sound} onChange={props.onSound}/></Row>
        <Row icon="settings-gear.png" title="Animations" subtitle={reducedMotion ? 'Limited by your device setting.' : 'Movement and celebrations.'}>
          <input className="web-profile-switch" type="checkbox" role="switch" aria-label="Animations" checked={props.motion && !reducedMotion} disabled={reducedMotion} onChange={event => props.onMotion(event.target.checked)}/></Row>
        <Row title="Reduce motion" subtitle={reducedMotion ? 'On. Follows your device setting.' : 'Off. Follows your device setting.'}/>
        <Row icon="settings-haptics.png" title="Haptics" subtitle="Not available in a browser."/>
        <Row title="Language" subtitle="English"/>
      </Section>
      <Section title="Paper">
        <Row title="Paper limit" subtitle={props.paperLimit && /^\d{1,15}$/.test(props.paperLimit) ? `${Number(props.paperLimit).toLocaleString('en-US')} paper` : 'Unavailable right now.'}/>
        {props.resetAvailable && <Row title="Reset paper" destructive subtitle={resetting ? 'Resetting your paper desk.' : props.resetPending ? 'Your confirmed reset is waiting to finish.' : 'Clear paper trades and start again.'}>
          <button className="text-button danger" disabled={resetting} onClick={() => props.resetPending ? void reset() : (setPhrase(''), setDialog('reset'))}>{props.resetPending ? 'Finish reset' : 'Reset'}</button></Row>}
      </Section>
      {privacy && <Section title="Privacy">
        <Row icon="career-comments.png" title="Who can see my comments" subtitle={<span role="status">{privacySubtitle(privacy)}</span>}>
          {privacy.failure && !privacy.saving ? <button className="text-button" onClick={() => void privacy.retry()}>Try again</button>
            : <button className="text-button" aria-label="Change who can see my comments" disabled={!privacy.privacy || privacy.saving} onClick={() => {setDraft(privacy.pending?.visibility ?? privacy.privacy!.visibility); setDialog('privacy');}}>Change</button>}
        </Row>
      </Section>}
      <Section title="Support">
        <Row title="Help" subtitle="Find @trimmyhq on X for help or feedback."><a className="text-button" aria-label="Open help on X" href="https://x.com/trimmyhq" target="_blank" rel="noopener noreferrer">Open</a></Row>
      </Section>
      <Section title="Legal">
        <Row title="Terms"><a className="text-button" aria-label="Open the terms" href="https://trimmy.xyz/terms/" target="_blank" rel="noopener noreferrer">Open</a></Row>
        <Row title="Privacy"><a className="text-button" aria-label="Open the privacy notice" href="https://trimmy.xyz/privacy/" target="_blank" rel="noopener noreferrer">Open</a></Row>
      </Section>
      {props.signedIn && props.closeAvailable && <Section title="Account closure">
        <Row title="Close account" destructive subtitle="Review what happens to your records and wallet."><button className="text-button danger" onClick={() => {setCloseError(false); setDialog('close');}}>Close account</button></Row>
      </Section>}
    </div>
    {dialog === 'privacy' && privacy?.privacy && <Modal title="Who can see my comments" onClose={() => setDialog(null)}>
      <p className="settings-modal-note">Now: {visibilityLabel[privacy.privacy.visibility]}.</p>
      <div className="setup-choices" role="radiogroup" aria-label="Who can see my comments">{(['nobody', 'everyone', 'friends'] as const).map(option => <button key={option}
        className="setup-choice" role="radio" aria-checked={draft === option} onClick={() => setDraft(option)}>
        <span><strong>{visibilityLabel[option]}</strong><small>{option === 'nobody' ? 'Only you. This is the default.' : option === 'everyone' ? 'Anyone in Trimmy, on each stock page.' : friendsLine(privacy.privacy!.friendsSharing === 'available')}</small></span></button>)}</div>
      {draft === 'everyone' && <p className="settings-consent" role="status">Your comments and your handle will show on that stock&apos;s page for anyone in Trimmy. Money never shows.</p>}
      <button className="primary full" onClick={() => {setDialog(null); void privacy.choose(draft);}}>Save</button>
    </Modal>}
    {dialog === 'reset' && <Modal title="Reset your paper desk?" onClose={() => {if (!resetting) setDialog(null);}}>
      <p>This starts a fresh paper desk. Past receipts stay in your record. Your Career, Trims, rank, streak and money do not change.</p>
      <label className="settings-phrase"><span>Type “reset my paper desk” to continue.</span>
        <input aria-label="Confirmation phrase. Type reset my paper desk." autoComplete="off" autoCapitalize="none" spellCheck={false} placeholder={PAPER_RESET_CONFIRMATION}
          value={phrase} disabled={resetting} onChange={event => setPhrase(event.target.value)}/></label>
      <div className="settings-modal-actions"><button className="text-button" disabled={resetting} onClick={() => setDialog(null)}>Cancel</button>
        <button className="primary danger" disabled={resetting || phrase !== PAPER_RESET_CONFIRMATION} onClick={() => void reset()}>{resetting ? 'Resetting…' : 'Reset paper desk'}</button></div>
    </Modal>}
    {dialog === 'reset-done' && resetResult && <Modal title="Paper desk reset" onClose={() => setDialog(null)}>
      <p>{resetResult.newerActivity ? `Newer trades were kept. Your balance is ${micros(resetResult.cashPaperMicros)} paper.` : `Your desk is ready with ${micros(resetResult.cashPaperMicros)} paper.`}</p>
      <div className="settings-modal-actions"><button className="primary" onClick={() => setDialog(null)}>Done</button></div>
    </Modal>}
    {dialog === 'close' && <Modal title="Close your account?" onClose={() => {if (!closing) setDialog(null);}}>
      <p>You will lose access to the saved account. Records that must be kept stay protected.</p>
      <p>If you funded a wallet, keep access to it first. Closing will not move its funds.</p>
      {closeError && <p className="intro-error" role="alert">Your account was not closed. Try again.</p>}
      <div className="settings-modal-actions"><button className="text-button" disabled={closing} onClick={() => setDialog(null)}>Cancel</button>
        <button className="primary danger" disabled={closing} onClick={() => void closeAccount()}>{closing ? 'Closing…' : 'Close account'}</button></div>
    </Modal>}
  </section>;
}
