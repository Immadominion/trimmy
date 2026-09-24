import {useEffect, useState} from 'react';
import type {CareerMissionBoard, CareerSummary} from './practice-client';
import type {ProgressState} from './use-progress';
import {art, Loading} from './ui';

export const storyPortrait = (speaker: string) => art(speaker === 'sal' ? 'sal-teaching-v2.png' : `persona-${speaker}-avatar-v1.png`);
const speakerName = (speaker: string) => speaker.charAt(0).toUpperCase() + speaker.slice(1);
function dayDate(date: string) {return new Date(`${date}T12:00:00Z`);}
export function storyWeek(date: string) {
  const today = dayDate(date), monday = new Date(today);
  monday.setUTCDate(today.getUTCDate() - (today.getUTCDay() + 6) % 7);
  return Array.from({length: 7}, (_, index) => {const day = new Date(monday); day.setUTCDate(day.getUTCDate() + index); return day.toISOString().slice(0, 10);});
}

export function DailyEntry({progress, onOpen}: {progress: ProgressState; onOpen: () => void}) {
  if (progress.shift?.completedChoice && !progress.error && !progress.pending) return null;
  if (!progress.shift) return <section className="daily-entry daily-entry-loading">{progress.loading ? <Loading>Opening today’s desk…</Loading> : <><p>Today’s desk couldn’t load.</p><button className="text-button" onClick={() => void progress.refresh()}>Retry</button></>}</section>;
  const {shift} = progress;
  return <section className="daily-entry"><div><p className="daily-label">Today at your desk</p><h2>{shift.story.title}</h2><button className="text-button" onClick={onOpen}>{progress.pending ? 'Check your clock-out' : shift.completedChoice ? 'Review today' : 'Step inside'}<span aria-hidden="true">↗</span></button>{progress.error != null && <p className="progress-stale">Today’s story couldn’t refresh.</p>}</div><img src={storyPortrait(shift.story.speaker)} alt=""/></section>;
}

export function CareerScreen({career, missions, progress, error, onRetry, onMarket, onDaily}: {
  career: CareerSummary | null; missions: CareerMissionBoard | null; progress: ProgressState; error: unknown;
  onRetry: () => void; onMarket: () => void; onDaily: () => void;
}) {
  const shift = progress.shift;
  const dates = shift ? storyWeek(shift.date) : [];
  const completed = new Set(shift?.history.map(item => item.date) ?? []);
  if (shift?.completedChoice) completed.add(shift.date);
  return <section className="career-screen" aria-label="Career">
    <div className="page-intro"><h1>Career</h1><a className="career-rank-link" href="#career-progress" onClick={event => {event.preventDefault(); document.getElementById('career-progress')?.scrollIntoView({block:'nearest'});}}><img src={art('icons/nav-plumpy-career.png')} alt=""/>{career?.rank.label ?? 'Your progress'}</a></div>
    {error != null && <div className="progress-error" role="status">Progress couldn’t refresh. <button className="text-button" onClick={onRetry}>Retry</button></div>}
    <div className="career-overview">
      <section className="career-week" aria-label="Your desk week">
        <div className="section-line"><h2>Your desk week</h2>{dates.length > 0 && <span className="week-range">{dayDate(dates[0]!).toLocaleDateString('en-GB',{day:'numeric',month:'short',timeZone:'UTC'})} – {dayDate(dates[6]!).toLocaleDateString('en-GB',{day:'numeric',month:'short',timeZone:'UTC'})}</span>}</div>
        {!shift ? progress.loading ? <Loading>Getting your week…</Loading> : <div className="progress-error">Your week couldn’t load. <button className="text-button" onClick={() => void progress.refresh()}>Retry</button></div> : <>
          <ol className="desk-week-days">{dates.map(date => {
            const today = date === shift.date, done = completed.has(date);
            const label = `${dayDate(date).toLocaleDateString('en-GB',{weekday:'long',day:'numeric',timeZone:'UTC'})}${today ? ', today' : ''}${done ? ', desk story completed' : date > shift.date ? ', upcoming' : ', no desk story completed'}`;
            return <li key={date} className={`${today ? 'today' : ''} ${done ? 'complete' : ''}`}><span>{dayDate(date).toLocaleDateString('en-GB',{weekday:'short',timeZone:'UTC'})}</span>{today ? <button aria-label={label} onClick={onDaily}>{done ? <span className="completion-seal" aria-hidden="true">✓</span> : <img src={storyPortrait(shift.story.speaker)} alt=""/>}</button> : <div className="desk-day" aria-label={label}>{done ? <span className="completion-seal" aria-hidden="true">✓</span> : dayDate(date).getUTCDate()}</div>}</li>;
          })}</ol>
          <div className="career-today"><img src={storyPortrait(shift.story.speaker)} alt=""/><div><p className="daily-label">{shift.completedChoice ? 'Completed today' : 'Today at your desk'}</p><h2>{shift.story.title}</h2><p>{shift.completedChoice ? 'Your decision is saved.' : `A moment with ${speakerName(shift.story.speaker)}.`}</p><button className="primary" onClick={onDaily}>{shift.completedChoice ? 'Review today' : 'Step inside'}</button></div></div>
          {progress.error != null && <div className="progress-error" role="status">Your week couldn’t refresh. <button className="text-button" onClick={() => void progress.refresh()}>Retry</button></div>}
        </>}
      </section>
      <aside className="career-progress" id="career-progress" aria-label="Your rank and activity">
        {career ? <><img className="career-briefcase" src={art('rookie-briefcase-v1.png')} alt=""/><h2>{career.rank.label}</h2><p className="career-trims"><strong>{career.trims.total.toLocaleString()}</strong> Trims</p><div className="career-meter" role="progressbar" aria-label="Trims toward next rank" aria-valuenow={career.trims.total} aria-valuemin={career.rank.threshold} aria-valuemax={career.nextRank?.threshold ?? career.trims.total}><span style={{width:`${career.nextRank ? Math.min(100,Math.max(0,(career.trims.total-career.rank.threshold)/(career.nextRank.threshold-career.rank.threshold)*100)) : 100}%`}}/></div><p className="career-next-rank">{career.nextRank ? `${career.nextRank.trimsRemaining.toLocaleString()} Trims to ${career.nextRank.label}` : 'Your career so far'}</p><div className="career-streak-line"><span className="career-flame" aria-hidden="true"/><strong>{career.streak.days} day streak</strong></div>
        <p className="activity-week-label">Activity this week</p>{progress.week ? <div className="activity-week" aria-label="Days with a trade, comment or desk story">{storyWeek(progress.week.serverDate).map(date=><span key={date} title={`${date}: ${progress.week!.activeDates.includes(date) ? 'Active' : 'No recorded activity'}`} className={progress.week!.activeDates.includes(date) ? 'active' : ''}>{dayDate(date).toLocaleDateString('en-GB',{weekday:'narrow',timeZone:'UTC'})}<span className="sr-only">{progress.week!.activeDates.includes(date) ? ', active' : ', no activity'}</span></span>)}</div> : <p className="progress-stale">{progress.loading ? 'Getting activity…' : 'Activity unavailable.'}</p>}{progress.weekError != null && <button className="text-button" onClick={()=>void progress.refresh()}>Retry activity</button>}</> : error != null ? <div className="progress-stale"><p>Your rank couldn’t refresh.</p>{shift?.completedChoice && <p>Today’s desk story is saved.</p>}<button className="text-button" onClick={onRetry}>Retry progress</button></div> : <Loading>Getting your progress…</Loading>}
      </aside>
    </div>
    {missions && <details className="career-milestones"><summary>Trading milestones <span>{missions.missions.filter(m=>m.status==='complete').length} of {missions.missions.length}</span></summary><div>{missions.missions.map(mission=><article key={mission.id}><span className={`milestone-icon ${mission.status}`} aria-hidden="true">{mission.status==='complete' ? '✓' : <img src={art(mission.id==='write-a-reason' ? 'icons/career-comments.png' : 'icons/nav-plumpy-career.png')} alt=""/>}</span><div><h3>{mission.title}</h3><p>{mission.instruction}</p>{mission.id==='first-paper-buy' && mission.status==='ready' && <button className="text-button" onClick={onMarket}>Browse market</button>}</div><span className="milestone-status">{mission.status==='complete' ? 'Complete' : mission.status==='locked' ? 'Locked' : mission.id==='first-paper-buy' ? 'Ready' : 'Continue on mobile'}</span></article>)}</div></details>}
  </section>;
}

export function DailyStoryScreen({progress, onBack}: {progress: ProgressState; onBack: () => void}) {
  const shift = progress.shift;
  const [draft, setDraft] = useState<string | null>(null);
  const [revealed, setRevealed] = useState(false);
  useEffect(()=>{setDraft(null);setRevealed(false);},[shift?.date,shift?.story.id]);
  const pendingChoice = progress.pending?.date === shift?.date && progress.pending?.caseId === shift?.story.id ? progress.pending?.choiceId : null;
  const choice = shift?.story.choices.find(item=>item.id===(shift.completedChoice ?? pendingChoice ?? draft));
  const done = shift?.completedChoice != null;
  return <section className="daily-story-screen" aria-label="Today at your desk">
    <button className="company-back" disabled={progress.working} onClick={onBack}>← Back to my desk</button>
    {!shift ? progress.loading ? <Loading>Opening today’s desk…</Loading> : <div className="progress-error">Today’s desk couldn’t load. <button className="text-button" onClick={()=>void progress.refresh()}>Retry</button></div> : <>
      <header className="daily-story-heading"><img src={storyPortrait(shift.story.speaker)} alt={speakerName(shift.story.speaker)}/><div><p className="daily-label">{speakerName(shift.story.speaker)} · {dayDate(shift.date).toLocaleDateString('en-GB',{day:'numeric',month:'long',timeZone:'UTC'})}</p><h1>{shift.story.title}</h1></div></header>
      <p className="daily-story-body">{shift.story.body}</p>
      {done || revealed || progress.pending ? choice && <div className="daily-outcome"><span className="daily-label">{done ? 'Your saved response' : 'Your response'}</span><h2>{choice.label}</h2><p>{choice.outcome}</p><p className="daily-takeaway">{choice.takeaway}</p></div> : <fieldset className="daily-choices"><legend>What do you do?</legend>{shift.story.choices.map(item=><label key={item.id} className={draft===item.id ? 'selected' : ''}><input type="radio" name="daily-response" value={item.id} checked={draft===item.id} onChange={()=>setDraft(item.id)}/><span>{item.label}</span></label>)}</fieldset>}
      {progress.error != null && <p className="progress-error" role="alert">{progress.pending ? 'The connection ended before confirmation. Check your clock-out before trying another response.' : 'Your desk couldn’t update. Refresh today’s story and try again.'}</p>}
      <div className="daily-story-actions">
        {done && <p className="daily-saved"><span className="completion-seal" aria-hidden="true">✓</span>Day completed{shift.trimsEarned > 0 && ` · ${shift.trimsEarned} Trims earned`}</p>}
        {/* A confirmed read can follow a lost write response. Replay its durable command before dismissing recovery. */}
        {progress.pending ? <button className="primary" disabled={progress.working} onClick={()=>void progress.recover()}>{progress.working ? 'Checking…' : 'Check clock-out'}</button>
          : done ? <button className="primary" onClick={onBack}>Back to my desk</button>
          : revealed ? <><button className="primary" disabled={progress.working || !choice} onClick={()=>choice && void progress.complete(choice.id)}>{progress.working ? 'Saving…' : 'Clock out'}</button><button className="text-button" disabled={progress.working} onClick={()=>setRevealed(false)}>Change response</button></>
          : <button className="primary" disabled={!draft} onClick={()=>setRevealed(true)}>See what happens</button>}
        {progress.error != null && !progress.pending && <button className="text-button" disabled={progress.working} onClick={()=>void progress.refresh()}>Refresh today’s story</button>}
      </div>
    </>}
  </section>;
}
