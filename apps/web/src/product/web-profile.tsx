import {useEffect, useId, useRef, useState} from 'react';
import type {CareerMissionBoard, CareerSummary, ProductOnboarding, ProductProfile} from './practice-client';
import {MobileAppPrompt} from './onboarding';
import {art} from './ui';

export type TraderPersona = NonNullable<ProductOnboarding['persona']>;
const traders: readonly {id: TraderPersona; label: string; description: string}[] = [
  {id: 'wolf', label: 'The Wolf', description: 'Bold. Fast. Loves a big move.'},
  {id: 'oracle', label: 'The Oracle', description: 'Patient. Reads before moving.'},
  {id: 'shark', label: 'The Shark', description: 'Calm when the crowd gets loud.'},
];

export interface WebProfileProps {
  readonly profile: ProductProfile | null;
  readonly career: CareerSummary | null;
  readonly missions: CareerMissionBoard | null;
  readonly hasIdentity: boolean;
  readonly signedIn: boolean;
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
}

function ProfileIcon({file}: {file: string}) {
  return <img className="web-profile-icon" src={art(`icons/${file}`)} alt="" width="25" height="25"/>;
}

/** Uses the same optional persona and server progress as mobile; it creates no local profile. */
export function WebProfile(props: WebProfileProps) {
  const {profile, career, missions, signedIn, hasIdentity, motion} = props;
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
    <div className="page-intro"><h1 id="web-profile-heading">Profile</h1></div>
    <div className="web-profile-overview">
      <section className="web-profile-identity" aria-label="Your trader">
        <div className="web-profile-person">
          <div className={`web-profile-avatar${persona ? ' chosen' : ''}`}>
            <img src={art(persona ? `persona-${persona}-avatar-v1.png` : 'icons/nav-plumpy-profile.png')}
              alt={trader ? `${trader.label}, your chosen trader` : ''} width="108" height="108"/>
          </div>
          <div className="web-profile-name">
            <h2>{handle ? `@${handle}` : trader ? trader.label : 'Make it yours'}</h2>
            {handle && trader && <p>{trader.label}</p>}
            {!trader && <p>Choose who you play as.</p>}
            {career && <span className="web-profile-rank">{career.rank.label}</span>}
          </div>
        </div>
        {hasIdentity && props.onPersona && <button ref={editButton} className="web-profile-edit" onClick={openEditor}
          aria-expanded={editing} aria-controls={editorId} disabled={saving || props.authBusy}>
          <ProfileIcon file="profile-edit.png"/>{trader ? 'Change your trader' : 'Choose your trader'}
        </button>}
        {!hasIdentity && props.onStart && <button className="text-button" onClick={props.onStart}>Start my first day <span aria-hidden="true">→</span></button>}
      </section>

      <section className="web-profile-progress" aria-labelledby="profile-progress-heading">
        <div className="web-profile-section-title"><h2 id="profile-progress-heading">Your progress</h2>
          {career && <button className="text-button" onClick={props.onCareer}>Career <span aria-hidden="true">→</span></button>}
        </div>
        {props.progressError && <div className="web-profile-progress-error" role="status"><span>Progress couldn’t refresh.</span>
          {props.onRetry && <button className="text-button" disabled={props.busy} onClick={props.onRetry}>Retry</button>}</div>}
        {career ? <>
          <dl className="web-profile-stats">
            <div><dt>Trims earned</dt><dd>{career.trims.total.toLocaleString()}</dd></div>
            <div><dt>Day{career.streak.days === 1 ? '' : 's'} in a row</dt><dd>{career.streak.days.toLocaleString()}</dd></div>
            {missions && <div><dt>Milestones</dt><dd>{completed}<small> / {missions.missions.length}</small></dd></div>}
          </dl>
          {career.nextRank ? <div className="web-profile-promotion">
            <div><span>{career.rank.label}</span><span>{career.nextRank.label}</span></div>
            <progress value={rankProgress} max="100" aria-label={`Progress toward ${career.nextRank.label}`}/>
            <p>{career.nextRank.trimsRemaining > 0
              ? `${career.nextRank.trimsRemaining.toLocaleString()} more Trims to ${career.nextRank.label}.`
              : career.nextRank.promotionRequired ? 'Finish your promotion milestone in Career.' : 'Your next rank is ready in Career.'}</p>
          </div> : <p className="web-profile-progress-note">{career.rank.label}. Look how far you’ve come.</p>}
        </> : <div className="web-profile-progress-empty">
          <img src={art('rookie-briefcase-v1.png')} width="64" height="64" alt=""/>
          <div><strong>{props.busy ? 'Loading your progress…' : hasIdentity ? 'Your progress is unavailable.' : 'Your career starts here.'}</strong>
            <p>{hasIdentity ? 'Your saved progress has not changed.' : 'Make your first move and earn your first Trims.'}</p>
            {hasIdentity && props.onRetry && !props.busy && !props.progressError && <button className="text-button" onClick={props.onRetry}>Try again</button>}
          </div>
        </div>}
      </section>
    </div>

    {editing && <form className="web-profile-persona-editor" id={editorId} onSubmit={event => {event.preventDefault(); void savePersona();}} aria-busy={saving}>
      <fieldset disabled={saving}><legend>Pick your trader</legend><p>Who will you play as?</p>
        <div className="web-profile-traders">{traders.map(item => <label key={item.id} className={`web-profile-trader${draft === item.id ? ' selected' : ''}`}>
          <input type="radio" name={inputGroup} value={item.id} checked={draft === item.id} onChange={() => {setDraft(item.id); setSaveError(false);}}/>
          <img src={art(`persona-${item.id}-avatar-v1.png`)} width="64" height="64" alt=""/>
          <span><strong>{item.label}</strong><small>{item.description}</small></span>
        </label>)}</div>
      </fieldset>
      {saveError && <p className="web-profile-save-error" role="alert">Couldn’t save your trader. Your choice is still here. Try again.</p>}
      <div className="web-profile-editor-actions"><button className="text-button" type="button" onClick={closeEditor} disabled={saving}>Cancel</button>
        <button className="primary" type="submit" disabled={!draft || saving}>{saving ? 'Saving…' : 'Save trader'}</button></div>
    </form>}

    <div className="web-profile-settings">
      <section className="web-profile-group" aria-labelledby="profile-account-heading">
        <h2 id="profile-account-heading">Account</h2>
        <div className="web-profile-setting-row"><ProfileIcon file="settings-lock.png"/>
          <div><strong>{signedIn ? 'One account, every device' : 'Keep your progress together'}</strong>
            <p>{signedIn ? 'Use this same account on mobile for your trades, Trims and completed tasks.' : 'Sign in to pick up your trades and career on mobile.'}</p>
          </div>
        </div>
        <div className="web-profile-account-action">{signedIn
          ? <button className="text-button" disabled={props.authBusy} onClick={props.onSignOut}>Sign out</button>
          : <button className="primary" disabled={props.authBusy} onClick={props.onSignIn}>Sign in or create account</button>}</div>
      </section>
      <section className="web-profile-group" aria-labelledby="profile-preferences-heading">
        <h2 id="profile-preferences-heading">Preferences</h2>
        <div className="web-profile-setting-row"><ProfileIcon file="settings-gear.png"/>
          <label htmlFor={motionId}><strong>Character motion</strong><span>On this browser. Your device’s reduced-motion setting always applies.</span></label>
          <input className="web-profile-switch" id={motionId} type="checkbox" role="switch" checked={motion} onChange={event => props.onMotion(event.target.checked)}/>
        </div>
        <a className="web-profile-help" href="https://x.com/trimmyhq" target="_blank" rel="noopener noreferrer">Help &amp; feedback <span aria-hidden="true">↗</span></a>
      </section>
    </div>
    <MobileAppPrompt/>
  </section>;
}
