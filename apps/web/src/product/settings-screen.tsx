import {useEffect, useId, useRef, useState} from 'react';
import type {KeyboardEvent, ReactNode} from 'react';
import {PracticeError} from './practice-client';
import type {ReasonVisibility} from './career-actions';
import type {ReasonPrivacyState} from './use-reason-privacy';
import type {ReminderChoice, ReminderRecord} from './journey-store';
import {ReminderPreferencePage} from './first-day-followup';
import type {ProductLogin, ProductLoginMethod} from './product-auth';
import {art, micros} from './ui';
import {useLanguageChoice, useT, type Translator} from '../i18n/react';
import {LOCALES, LOCALE_NAMES, browserLanguages, resolveLocale, type Locale} from '../i18n/locales';
import type {MessageKey} from '../i18n/runtime';
import * as fmt from '../i18n/format';

const loginIcons: Record<ProductLoginMethod, string> = {email: 'account-email-rounded.png', google: 'account-google-rounded.png', x: 'account-x-standalone-rounded.png'};

export interface PaperResetOutcome {readonly cashPaperMicros: string; readonly newerActivity: boolean}
export interface SettingsScreenProps {
  readonly signedIn: boolean; readonly authBusy: boolean; readonly handle: string | null; readonly persona: string | null;
  /** How this account signs in, e.g. an email or an X @handle. */
  readonly logins?: readonly ProductLogin[];
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
    // Focus moves once, when the dialog opens; later renders never pull it back. A choice group starts on its checked option.
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    (panel.current?.querySelector<HTMLElement>('[role="radio"][aria-checked="true"]') ?? panel.current?.querySelector<HTMLElement>('input, button'))?.focus();
    const key = (event: globalThis.KeyboardEvent) => {if (event.key === 'Escape') {event.preventDefault(); close.current();}};
    window.addEventListener('keydown', key);
    return () => {window.removeEventListener('keydown', key); opener?.focus?.();};
  }, []);
  return <div className="settings-modal-backdrop" onClick={event => {if (event.target === event.currentTarget) onClose();}}>
    <div className="settings-modal" role="dialog" aria-modal="true" aria-labelledby={id} ref={panel}><h2 id={id}>{title}</h2>{children}</div>
  </div>;
}

/** A language's own name, marked with its language so screen readers say it right. */
function LanguageName({locale}: {locale: Locale}) {
  return <span lang={locale}>{LOCALE_NAMES[locale]}</span>;
}
type LanguageOption = Locale | 'browser';
const languageOptions: readonly LanguageOption[] = ['browser', ...LOCALES];

/** Browser language, then each language by its own name. Arrow keys move the choice; Save applies it. */
function LanguageDialog({choice, onSave, onClose}: {choice: Locale | null; onSave: (choice: Locale | null) => void; onClose: () => void}) {
  const tr = useT();
  const [draft, setDraft] = useState<LanguageOption>(choice ?? 'browser');
  const browser = resolveLocale(browserLanguages());
  function move(event: KeyboardEvent<HTMLDivElement>) {
    const step = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' || event.key === 'ArrowLeft' ? -1 : 0;
    const index = event.key === 'Home' ? 0 : event.key === 'End' ? languageOptions.length - 1
      : step ? (languageOptions.indexOf(draft) + step + languageOptions.length) % languageOptions.length : -1;
    const next = languageOptions[index];
    if (next === undefined) return;
    event.preventDefault(); setDraft(next);
    event.currentTarget.querySelector<HTMLElement>(`[data-language="${next}"]`)?.focus();
  }
  return <Modal title={tr('profile.language.title')} onClose={onClose}>
    <div className="setup-choices" role="radiogroup" aria-label={tr('profile.language.title')} onKeyDown={move}>{languageOptions.map(option =>
      <button key={option} className="setup-choice" role="radio" aria-checked={draft === option} tabIndex={draft === option ? 0 : -1} data-language={option}
        {...(option === 'browser' ? {} : {lang: option})} onClick={() => setDraft(option)}>
        {option === 'browser'
          ? <span><strong>{tr('profile.language.browser')}</strong><small>{tr.rich('profile.language.browserHint', {language: <LanguageName locale={browser}/>})}</small></span>
          : <span><strong>{LOCALE_NAMES[option]}</strong></span>}
      </button>)}</div>
    <button className="primary full" onClick={() => onSave(draft === 'browser' ? null : draft)}>{tr('common.save')}</button>
  </Modal>;
}
type LanguageNote = {readonly kind: 'not-saved'} | {readonly kind: 'failed'; readonly locale: Locale};

/** The typed confirmation, compared exactly in English; elsewhere accents, capitals, apostrophe styles and extra spaces do not count. */
function loosePhrase(text: string): string {
  return text.normalize('NFD').replace(/\p{M}/gu, '').replace(/[’‘`´]/gu, '\'').replace(/\s+/gu, ' ').trim().toLocaleLowerCase();
}

const visibilityKey: Record<ReasonVisibility, MessageKey> = {nobody: 'profile.privacy.nobody', everyone: 'profile.privacy.everyone', friends: 'profile.privacy.friends'};
const friendsLine = (tr: Translator, available: boolean) => tr(available ? 'profile.privacy.friendsLine' : 'profile.privacy.friendsUnavailable');
function describe(tr: Translator, visibility: ReasonVisibility, friendsAvailable: boolean): string {
  return visibility === 'nobody' ? tr('profile.privacy.nobodyLine') : visibility === 'everyone' ? tr('profile.privacy.everyoneLine') : friendsLine(tr, friendsAvailable);
}
function privacySubtitle(tr: Translator, state: ReasonPrivacyState): string {
  const {privacy, pending, failure} = state;
  if (state.saving && pending) return tr('profile.privacy.saving', {visibility: pending.visibility});
  if (state.loading && !privacy) return tr('profile.privacy.loading');
  if (failure) {
    const code = failure.code, retry = failure.retryAfterSeconds;
    if (/EXPIRED|REVOKED/.test(code)) return tr('profile.privacy.needsRecovery');
    if (failure.status === 429) return retry
      ? tr(privacy ? 'profile.privacy.rateLimitedSave' : 'profile.privacy.rateLimitedLoad', {seconds: retry})
      : tr(privacy ? 'profile.privacy.rateLimitedSaveSoon' : 'profile.privacy.rateLimitedLoadSoon');
    if (!privacy) return tr(code === 'PRACTICE_NETWORK_ERROR' ? 'profile.privacy.offlineLoad' : code === 'PRACTICE_TIMEOUT' ? 'profile.privacy.slowLoad'
      : failure.status === 401 ? 'profile.privacy.sessionLoad' : code === 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND' ? 'profile.privacy.accountClosed' : 'profile.privacy.loadFailed');
    const notSaved = pending ? tr('profile.privacy.notSaved', {visibility: pending.visibility}) : tr('profile.privacy.choiceNotSaved');
    return code === 'PRACTICE_NETWORK_ERROR' ? tr('profile.privacy.offlineSave', {notSaved}) : code === 'PRACTICE_TIMEOUT' ? tr('profile.privacy.slowSave', {notSaved})
      : failure.status === 401 ? tr('profile.privacy.sessionSave', {notSaved}) : code === 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND' ? tr('profile.privacy.accountClosedNotSaved')
      : code === 'CAREER_REASON_SHARING_IDEMPOTENCY_CONFLICT' ? tr('profile.privacy.unmatched') : tr('profile.privacy.saveFailed', {notSaved});
  }
  if (!privacy) return tr('profile.privacy.unavailable');
  const line = describe(tr, privacy.visibility, privacy.friendsSharing === 'available');
  return state.notice === 'saved' ? tr('profile.privacy.saved', {line}) : state.notice === 'changed-elsewhere' ? tr('profile.privacy.changedElsewhere', {line}) : line;
}
function resetFailure(error: unknown): MessageKey {
  const code = error instanceof PracticeError ? error.code : '';
  if (code === 'PAPER_PORTFOLIO_CHANGED') return 'profile.reset.error.changed';
  if (code === 'PAPER_RESET_NOT_NEEDED') return 'profile.reset.error.notNeeded';
  if (code === 'PRACTICE_NETWORK_ERROR') return 'profile.reset.error.offline';
  if (code === 'PRACTICE_TIMEOUT') return 'profile.reset.error.timeout';
  if (error instanceof PracticeError && error.status === 401) return 'profile.reset.error.session';
  if (error instanceof PracticeError && error.status === 429) return 'profile.reset.error.rateLimited';
  if (error instanceof PracticeError && (error.status === null || error.status >= 500)) return 'profile.reset.error.unconfirmed';
  return 'profile.reset.error.failed';
}

/** Mobile's Settings in the web frame. Rows the browser cannot support say so plainly. */
export function SettingsScreen(props: SettingsScreenProps) {
  const tr = useT();
  const language = useLanguageChoice();
  const [view, setView] = useState<'list' | 'reminders'>('list');
  const [dialog, setDialog] = useState<null | 'privacy' | 'reset' | 'reset-done' | 'close' | 'language'>(null);
  const [draft, setDraft] = useState<ReasonVisibility>('nobody'), [phrase, setPhrase] = useState('');
  const [resetting, setResetting] = useState(false), [resetResult, setResetResult] = useState<PaperResetOutcome | null>(null), [message, setMessage] = useState<MessageKey | null>(null);
  const [closing, setClosing] = useState(false), [closeError, setCloseError] = useState(false);
  const [languageNote, setLanguageNote] = useState<LanguageNote | null>(null);
  const heading = useRef<HTMLHeadingElement>(null), mounted = useRef(true);
  const reducedMotion = typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  useEffect(() => {if (view === 'list') heading.current?.focus();}, [view]);
  if (view === 'reminders') return <ReminderPreferencePage saved={props.reminder} onSave={props.onSaveReminder}
    onDone={async () => {setView('list');}} onClose={() => setView('list')}/>;
  const privacy = props.privacy;
  const resetPhrase = tr('profile.reset.phrase');
  const phraseTyped = loosePhrase(phrase) === loosePhrase(resetPhrase);
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
  /** The whole page switches at once; storage that refuses the choice still leaves it on for this visit. */
  async function chooseLanguage(choice: Locale | null) {
    setDialog(null); setLanguageNote(null);
    try {
      const result = await language.choose(choice);
      if (!mounted.current) return;
      setLanguageNote(choice !== null && result.locale !== choice ? {kind: 'failed', locale: choice} : result.saved ? null : {kind: 'not-saved'});
    } catch {if (mounted.current && choice !== null) setLanguageNote({kind: 'failed', locale: choice});}
  }
  const languageSubtitle = <span role="status">
    {language.choice === null ? tr.rich('profile.language.browserCurrent', {language: <LanguageName locale={language.locale}/>}) : <LanguageName locale={language.choice}/>}
    {languageNote && <span className="settings-language-note">{languageNote.kind === 'not-saved' ? tr('profile.language.notSaved')
      : tr.rich('profile.language.loadFailed', {language: <LanguageName locale={languageNote.locale}/>})}</span>}
  </span>;
  return <section className="settings-screen" aria-labelledby="settings-heading">
    <button className="company-back" onClick={props.onBack}>← {tr('profile.settings.back')}</button>
    <div className="page-intro"><h1 id="settings-heading" ref={heading} tabIndex={-1}>{tr('profile.settings.title')}</h1></div>
    {message && <div className="notice" role="status">{tr(message)}<button className="text-button" onClick={() => setMessage(null)}>{tr('common.dismiss')}</button></div>}
    <div className="settings-grid">
      <Section title={tr('profile.account.title')}>
        {!props.signedIn && <Row icon="settings-lock.png" title={tr('profile.settings.signInTitle')} subtitle={tr('profile.settings.signInHint')}><button className="secondary" disabled={props.authBusy} onClick={props.onSignIn}>{tr('common.signIn')}</button></Row>}
        {props.signedIn && props.logins?.map(login => <Row key={login.method} icon={loginIcons[login.method]} title={tr('profile.settings.signedInWith', {method: login.method})} subtitle={login.label}/>)}
        {props.signedIn && props.handle && <Row icon="profile-edit.png" title={tr('profile.settings.handle')} subtitle={`@${props.handle}`}/>}
        <Row icon="nav-plumpy-profile.png" title={tr('profile.settings.trader')} subtitle={props.persona ?? tr('profile.settings.chooseCharacter')}><button className="text-button" aria-label={tr(props.persona ? 'profile.trader.change' : 'profile.trader.choose')} onClick={props.onTrader}>{tr(props.persona ? 'profile.settings.change' : 'profile.settings.choose')}</button></Row>
        {props.signedIn && <Row icon="settings-gear.png" title={tr('profile.account.signOut')}><button className="text-button" disabled={props.authBusy} onClick={props.onSignOut}>{tr('profile.account.signOut')}</button></Row>}
        {props.remindersAvailable && <Row icon="asset-bell.png" title={tr('profile.settings.reminders')} subtitle={props.reminder ? tr('profile.settings.remindersSaved', {choice: props.reminder.choice}) : tr('profile.settings.remindersNotSet')}>
          <button className="text-button" aria-label={tr('profile.settings.changeReminders')} onClick={() => setView('reminders')}>{tr('profile.settings.change')}</button></Row>}
        <Row icon="goal-goal-animated.png" title={tr('profile.settings.addMoney')} subtitle={tr(props.signedIn ? 'profile.settings.addMoneyHint' : 'profile.settings.addMoneySignIn')}><button className="text-button" aria-label={tr('profile.settings.addMoney')} onClick={props.onAddMoney}>{tr('profile.settings.open')}</button></Row>
      </Section>
      <Section title={tr('profile.preferences.title')}>
        <Row icon="settings-sound.png" title={tr('profile.settings.sound')} subtitle={tr('profile.settings.soundHint')}><input className="web-profile-switch" type="checkbox" role="switch" aria-label={tr('profile.settings.sound')} checked={props.sound} onChange={props.onSound}/></Row>
        <Row icon="settings-gear.png" title={tr('profile.settings.animations')} subtitle={tr(reducedMotion ? 'profile.settings.animationsLimited' : 'profile.settings.animationsHint')}>
          <input className="web-profile-switch" type="checkbox" role="switch" aria-label={tr('profile.settings.animations')} checked={props.motion && !reducedMotion} disabled={reducedMotion} onChange={event => props.onMotion(event.target.checked)}/></Row>
        <Row title={tr('profile.settings.reduceMotion')} subtitle={tr(reducedMotion ? 'profile.settings.reduceMotionOn' : 'profile.settings.reduceMotionOff')}/>
        <Row icon="settings-haptics.png" title={tr('profile.settings.haptics')} subtitle={tr('profile.settings.hapticsHint')}/>
        <Row title={tr('profile.language.title')} subtitle={languageSubtitle}>
          <button className="text-button" aria-label={tr('profile.language.change')} onClick={() => setDialog('language')}>{tr('profile.settings.change')}</button></Row>
      </Section>
      <Section title={tr('profile.settings.paperSection')}>
        <Row title={tr('profile.settings.paperLimit')} subtitle={props.paperLimit && /^\d{1,15}$/.test(props.paperLimit) ? tr('common.paperAmount', {amount: fmt.integer(Number(props.paperLimit), 'en-US')}) : tr('profile.settings.paperLimitUnavailable')}/>
        {props.resetAvailable && <Row title={tr('profile.reset.row')} destructive subtitle={tr(resetting ? 'profile.reset.rowBusy' : props.resetPending ? 'profile.reset.rowPending' : 'profile.reset.rowHint')}>
          <button className="text-button danger" disabled={resetting} onClick={() => props.resetPending ? void reset() : (setPhrase(''), setDialog('reset'))}>{tr(props.resetPending ? 'profile.reset.finish' : 'profile.reset.open')}</button></Row>}
      </Section>
      {privacy && <Section title={tr('profile.privacy.section')}>
        <Row icon="career-comments.png" title={tr('profile.privacy.title')} subtitle={<span role="status">{privacySubtitle(tr, privacy)}</span>}>
          {privacy.failure && !privacy.saving ? <button className="text-button" onClick={() => void privacy.retry()}>{tr('common.tryAgain')}</button>
            : <button className="text-button" aria-label={tr('profile.privacy.change')} disabled={!privacy.privacy || privacy.saving} onClick={() => {setDraft(privacy.pending?.visibility ?? privacy.privacy!.visibility); setDialog('privacy');}}>{tr('profile.settings.change')}</button>}
        </Row>
      </Section>}
      <Section title={tr('profile.settings.supportSection')}>
        <Row title={tr('profile.settings.help')} subtitle={tr('profile.settings.helpHint')}><a className="text-button" aria-label={tr('profile.settings.helpLabel')} href="https://x.com/trimmyhq" target="_blank" rel="noopener noreferrer">{tr('profile.settings.open')}</a></Row>
      </Section>
      <Section title={tr('profile.settings.legalSection')}>
        <Row title={tr('profile.settings.terms')}><a className="text-button" aria-label={tr('profile.settings.termsLabel')} href="https://trimmy.xyz/terms/" target="_blank" rel="noopener noreferrer">{tr('profile.settings.open')}</a></Row>
        <Row title={tr('profile.settings.privacyNotice')}><a className="text-button" aria-label={tr('profile.settings.privacyNoticeLabel')} href="https://trimmy.xyz/privacy/" target="_blank" rel="noopener noreferrer">{tr('profile.settings.open')}</a></Row>
      </Section>
      {props.signedIn && props.closeAvailable && <Section title={tr('profile.closure.section')}>
        <Row title={tr('profile.closure.action')} destructive subtitle={tr('profile.closure.rowHint')}><button className="text-button danger" onClick={() => {setCloseError(false); setDialog('close');}}>{tr('profile.closure.action')}</button></Row>
      </Section>}
    </div>
    {dialog === 'language' && <LanguageDialog choice={language.choice} onSave={choice => void chooseLanguage(choice)} onClose={() => setDialog(null)}/>}
    {dialog === 'privacy' && privacy?.privacy && <Modal title={tr('profile.privacy.title')} onClose={() => setDialog(null)}>
      <p className="settings-modal-note">{tr('profile.privacy.now', {visibility: privacy.privacy.visibility})}</p>
      <div className="setup-choices" role="radiogroup" aria-label={tr('profile.privacy.title')}>{(['nobody', 'everyone', 'friends'] as const).map(option => <button key={option}
        className="setup-choice" role="radio" aria-checked={draft === option} onClick={() => setDraft(option)}>
        <span><strong>{tr(visibilityKey[option])}</strong><small>{option === 'nobody' ? tr('profile.privacy.nobodyOption') : option === 'everyone' ? tr('profile.privacy.everyoneOption') : friendsLine(tr, privacy.privacy!.friendsSharing === 'available')}</small></span></button>)}</div>
      {draft === 'everyone' && <p className="settings-consent" role="status">{tr('profile.privacy.consent')}</p>}
      <button className="primary full" onClick={() => {setDialog(null); void privacy.choose(draft);}}>{tr('common.save')}</button>
    </Modal>}
    {dialog === 'reset' && <Modal title={tr('profile.reset.title')} onClose={() => {if (!resetting) setDialog(null);}}>
      <p>{tr('profile.reset.body')}</p>
      <label className="settings-phrase"><span>{tr('profile.reset.phrasePrompt', {phrase: resetPhrase})}</span>
        <input aria-label={tr('profile.reset.phraseLabel', {phrase: resetPhrase})} autoComplete="off" autoCapitalize="none" spellCheck={false} placeholder={resetPhrase}
          value={phrase} disabled={resetting} onChange={event => setPhrase(event.target.value)}/></label>
      <div className="settings-modal-actions"><button className="text-button" disabled={resetting} onClick={() => setDialog(null)}>{tr('common.cancel')}</button>
        <button className="primary danger" disabled={resetting || !phraseTyped} onClick={() => void reset()}>{tr(resetting ? 'profile.reset.confirming' : 'profile.reset.confirm')}</button></div>
    </Modal>}
    {dialog === 'reset-done' && resetResult && <Modal title={tr('profile.reset.doneTitle')} onClose={() => setDialog(null)}>
      <p>{tr(resetResult.newerActivity ? 'profile.reset.doneNewer' : 'profile.reset.done', {amount: micros(resetResult.cashPaperMicros)})}</p>
      <div className="settings-modal-actions"><button className="primary" onClick={() => setDialog(null)}>{tr('common.done')}</button></div>
    </Modal>}
    {dialog === 'close' && <Modal title={tr('profile.closure.title')} onClose={() => {if (!closing) setDialog(null);}}>
      <p>{tr('profile.closure.body')}</p>
      <p>{tr('profile.closure.wallet')}</p>
      {closeError && <p className="intro-error" role="alert">{tr('profile.closure.error')}</p>}
      <div className="settings-modal-actions"><button className="text-button" disabled={closing} onClick={() => setDialog(null)}>{tr('common.cancel')}</button>
        <button className="primary danger" disabled={closing} onClick={() => void closeAccount()}>{tr(closing ? 'profile.closure.closing' : 'profile.closure.action')}</button></div>
    </Modal>}
  </section>;
}
