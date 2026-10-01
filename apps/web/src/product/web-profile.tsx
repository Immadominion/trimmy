import {useEffect, useId, useRef, useState} from 'react';
import type {CareerMissionBoard, CareerSummary, ProductOnboarding, ProductProfile} from './practice-client';
import {MobileAppPrompt} from './onboarding';
import {art} from './ui';
import {useT} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';
import * as fmt from '../i18n/format';
import {rankName} from './career-milestones';

export type TraderPersona = NonNullable<ProductOnboarding['persona']>;
const traders: readonly {id: TraderPersona; label: MessageKey; description: MessageKey}[] = [
  {id: 'wolf', label: 'profile.trader.wolf', description: 'profile.trader.wolfDescription'},
  {id: 'oracle', label: 'profile.trader.oracle', description: 'profile.trader.oracleDescription'},
  {id: 'shark', label: 'profile.trader.shark', description: 'profile.trader.sharkDescription'},
];

export interface WebProfileProps {
  readonly profile: ProductProfile | null;
  readonly career: CareerSummary | null;
  readonly missions: CareerMissionBoard | null;
  readonly hasIdentity: boolean;
  readonly signedIn: boolean;
  /** How the account signs in (an email or X @handle), shown when there is no Trimmy handle. */
  readonly accountLabel?: string | null;
  readonly authBusy?: boolean;
  readonly busy?: boolean;
  readonly progressError?: boolean;
  readonly motion: boolean;
  readonly onMotion: (enabled: boolean) => void;
  readonly onCareer: () => void;
  readonly onSignIn: () => void;
  readonly onSignOut: () => void;
  readonly onStart?: () => void;
  readonly onRetry?: () => void;
  /** Resolve only after the server has saved the choice and the current profile has refreshed. */
  readonly onPersona?: (persona: TraderPersona) => Promise<void>;
  /** Opens Settings: reminders, sound, paper reset, comment privacy and account closure. */
  readonly onSettings?: () => void;
}

function ProfileIcon({file}: {file: string}) {
  return <img className="web-profile-icon" src={art(`icons/${file}`)} alt="" width="25" height="25"/>;
}

/** Uses the same optional persona and server progress as mobile; it creates no local profile. */
export function WebProfile(props: WebProfileProps) {
  const {profile, career, missions, signedIn, hasIdentity, motion} = props;
  const tr = useT();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<TraderPersona | null>(null);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState(false);
  const editButton = useRef<HTMLButtonElement>(null);
  const mounted = useRef(false);
  const persona = profile?.onboarding.persona ?? null;
  const trader = traders.find(item => item.id === persona);
  const handle = profile?.onboarding.handle;
  const inputGroup = useId();
  const motionId = useId();
  const editorId = useId();
  const completed = missions?.missions.filter(item => item.status === 'complete').length;
  const rankProgress = career?.nextRank
    ? Math.min(100, Math.max(0, (career.trims.total - career.rank.threshold) /
      Math.max(1, career.nextRank.threshold - career.rank.threshold) * 100)) : 100;

  useEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);

  function openEditor() {
    setDraft(persona); setSaveError(false); setEditing(true);
  }
  function closeEditor() {
    if (saving) return;
    setEditing(false); setSaveError(false); editButton.current?.focus();
  }
  async function savePersona() {
    if (!draft || !props.onPersona || saving) return;
    setSaving(true); setSaveError(false);
    try {
      await props.onPersona(draft);
      if (!mounted.current) return;
      setEditing(false); editButton.current?.focus();
    } catch {
      if (mounted.current) setSaveError(true);
    } finally {
      if (mounted.current) setSaving(false);
    }
  }

  return <section className="web-profile" aria-labelledby="web-profile-heading">
    <div className="page-intro"><h1 id="web-profile-heading">{tr('profile.page.title')}</h1>{props.onSettings && <button className="text-button web-profile-settings-link" onClick={props.onSettings}><ProfileIcon file="settings-gear.png"/>{tr('profile.page.settings')}</button>}</div>
    <div className="web-profile-overview">
      <section className="web-profile-identity" aria-label={tr('profile.page.identityLabel')}>
        <div className="web-profile-person">
          <div className={`web-profile-avatar${persona ? ' chosen' : ''}`}>
            <img src={art(persona ? `persona-${persona}-avatar-v1.png` : 'icons/nav-plumpy-profile.png')}
              alt={trader ? tr('profile.page.avatarAlt', {persona: trader.id}) : ''} width="108" height="108"/>
          </div>
          <div className="web-profile-name">
            <h2>{handle ? `@${handle}` : props.accountLabel ?? (trader ? tr(trader.label) : tr('profile.page.makeItYours'))}</h2>
            {(handle || props.accountLabel) && trader && <p>{tr(trader.label)}</p>}
            {!trader && <p>{tr('profile.page.choosePrompt')}</p>}
            {career && <span className="web-profile-rank">{rankName(career.rank)}</span>}
          </div>
        </div>
        {hasIdentity && props.onPersona && <button ref={editButton} className="web-profile-edit" onClick={openEditor}
          aria-expanded={editing} aria-controls={editorId} disabled={saving || props.authBusy}>
          <ProfileIcon file="profile-edit.png"/>{tr(trader ? 'profile.trader.change' : 'profile.trader.choose')}
        </button>}
        {!hasIdentity && props.onStart && <button className="text-button" onClick={props.onStart}>{tr('profile.page.start')} <span aria-hidden="true">→</span></button>}
      </section>

      <section className="web-profile-progress" aria-labelledby="profile-progress-heading">
        <div className="web-profile-section-title"><h2 id="profile-progress-heading">{tr('profile.page.progressTitle')}</h2>
          {career && <button className="text-button" onClick={props.onCareer}>{tr('profile.page.career')} <span aria-hidden="true">→</span></button>}
        </div>
        {props.progressError && <div className="web-profile-progress-error" role="status"><span>{tr('profile.page.progressStale')}</span>
          {props.onRetry && <button className="text-button" disabled={props.busy} onClick={props.onRetry}>{tr('profile.page.retry')}</button>}</div>}
        {career ? <>
          <dl className="web-profile-stats">
            <div><dt>{tr('profile.page.trimsEarned')}</dt><dd>{fmt.integer(career.trims.total)}</dd></div>
            <div><dt>{tr('profile.page.streakDays', {days: career.streak.days})}</dt><dd>{fmt.integer(career.streak.days)}</dd></div>
            {missions && <div><dt>{tr('profile.page.milestones')}</dt><dd>{fmt.integer(completed ?? 0, 'raw')}<small> / {fmt.integer(missions.missions.length, 'raw')}</small></dd></div>}
          </dl>
          {career.nextRank ? <div className="web-profile-promotion">
            <div><span>{rankName(career.rank)}</span><span>{rankName(career.nextRank)}</span></div>
            <progress value={rankProgress} max="100" aria-label={tr('profile.page.rankProgress', {rank: rankName(career.nextRank)})}/>
            <p>{career.nextRank.trimsRemaining > 0
              ? tr('profile.page.trimsToRank', {count: fmt.count(career.nextRank.trimsRemaining), rank: rankName(career.nextRank)})
              : tr(career.nextRank.promotionRequired ? 'profile.page.promotionMilestone' : 'profile.page.nextRankReady')}</p>
          </div> : <p className="web-profile-progress-note">{tr('profile.page.topRank', {rank: rankName(career.rank)})}</p>}
        </> : <div className="web-profile-progress-empty">
          <img src={art('rookie-briefcase-v1.png')} width="64" height="64" alt=""/>
          <div><strong>{tr(props.busy ? 'profile.page.progressLoading' : hasIdentity ? 'profile.page.progressUnavailable' : 'profile.page.careerStarts')}</strong>
            <p>{tr(hasIdentity ? 'profile.page.progressUnchanged' : 'profile.page.firstMove')}</p>
            {hasIdentity && props.onRetry && !props.busy && !props.progressError && <button className="text-button" onClick={props.onRetry}>{tr('common.tryAgain')}</button>}
          </div>
        </div>}
      </section>
    </div>

    {editing && <form className="web-profile-persona-editor" id={editorId} onSubmit={event => {event.preventDefault(); void savePersona();}} aria-busy={saving}>
      <fieldset disabled={saving}><legend>{tr('profile.trader.legend')}</legend><p>{tr('profile.trader.question')}</p>
        <div className="web-profile-traders">{traders.map(item => <label key={item.id} className={`web-profile-trader${draft === item.id ? ' selected' : ''}`}>
          <input type="radio" name={inputGroup} value={item.id} checked={draft === item.id} onChange={() => {setDraft(item.id); setSaveError(false);}}/>
          <img src={art(`persona-${item.id}-avatar-v1.png`)} width="64" height="64" alt=""/>
          <span><strong>{tr(item.label)}</strong><small>{tr(item.description)}</small></span>
        </label>)}</div>
      </fieldset>
      {saveError && <p className="web-profile-save-error" role="alert">{tr('profile.trader.saveError')}</p>}
      <div className="web-profile-editor-actions"><button className="text-button" type="button" onClick={closeEditor} disabled={saving}>{tr('common.cancel')}</button>
        <button className="primary" type="submit" disabled={!draft || saving}>{tr(saving ? 'profile.trader.saving' : 'profile.trader.save')}</button></div>
    </form>}

    <div className="web-profile-settings">
      <section className="web-profile-group" aria-labelledby="profile-account-heading">
        <h2 id="profile-account-heading">{tr('profile.account.title')}</h2>
        <div className="web-profile-setting-row"><ProfileIcon file="settings-lock.png"/>
          <div><strong>{tr(signedIn ? 'profile.account.signedInTitle' : 'profile.account.guestTitle')}</strong>
            <p>{tr(signedIn ? 'profile.account.signedInBody' : 'profile.account.guestBody')}</p>
          </div>
        </div>
        <div className="web-profile-account-action">{signedIn
          ? <button className="text-button" disabled={props.authBusy} onClick={props.onSignOut}>{tr('profile.account.signOut')}</button>
          : <button className="primary" disabled={props.authBusy} onClick={props.onSignIn}>{tr('profile.account.signIn')}</button>}</div>
      </section>
      <section className="web-profile-group" aria-labelledby="profile-preferences-heading">
        <h2 id="profile-preferences-heading">{tr('profile.preferences.title')}</h2>
        <div className="web-profile-setting-row"><ProfileIcon file="settings-gear.png"/>
          <label htmlFor={motionId}><strong>{tr('profile.preferences.motion')}</strong><span>{tr('profile.preferences.motionHint')}</span></label>
          <input className="web-profile-switch" id={motionId} type="checkbox" role="switch" checked={motion} onChange={event => props.onMotion(event.target.checked)}/>
        </div>
        <a className="web-profile-help" href="https://x.com/trimmyhq" target="_blank" rel="noopener noreferrer">{tr('profile.preferences.help')} <span aria-hidden="true">↗</span></a>
      </section>
    </div>
    <MobileAppPrompt/>
  </section>;
}
