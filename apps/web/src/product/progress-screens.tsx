import {useEffect, useState} from 'react';
import type {CareerMissionBoard, CareerSummary} from './practice-client';
import type {ProgressState} from './use-progress';
import {art, Loading} from './ui';
import {missionText, rankName} from './career-milestones';
import {useT} from '../i18n/react';
import * as fmt from '../i18n/format';

export const storyPortrait = (speaker: string) => art(speaker === 'sal' ? 'sal-teaching-v2.png' : `persona-${speaker}-avatar-v1.png`);
/** Sal, Wolf, Oracle and Shark are names, the same in every language. */
const speakerName = (speaker: string) => speaker.charAt(0).toUpperCase() + speaker.slice(1);
function dayDate(date: string) {return new Date(`${date}T12:00:00Z`);}
export function storyWeek(date: string) {
  const today = dayDate(date), monday = new Date(today);
  monday.setUTCDate(today.getUTCDate() - (today.getUTCDay() + 6) % 7);
  return Array.from({length: 7}, (_, index) => {const day = new Date(monday); day.setUTCDate(day.getUTCDate() + index); return day.toISOString().slice(0, 10);});
}
/** A day of the activity week for its tooltip: the ISO day in English, as before; a written date elsewhere. */
export function activityDate(date: string): string {
  return fmt.isEnglish() ? date : fmt.date(dayDate(date), undefined, {weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC'});
}

export function DailyEntry({progress, onOpen}: {progress: ProgressState; onOpen: () => void}) {
  const tr = useT();
  if (progress.shift?.completedChoice && !progress.error && !progress.pending) return null;
  if (!progress.shift) return <section className="daily-entry daily-entry-loading">{progress.loading ? <Loading>{tr('career.daily.loading')}</Loading> : <><p>{tr('career.daily.loadFailed')}</p><button className="text-button" onClick={() => void progress.refresh()}>{tr('career.retry')}</button></>}</section>;
  const {shift} = progress;
  return <section className="daily-entry"><div><p className="daily-label">{tr('career.daily.today')}</p><h2>{shift.story.title}</h2><button className="text-button" onClick={onOpen}>{progress.pending ? tr('career.daily.checkClockOut') : shift.completedChoice ? tr('career.daily.reviewToday') : tr('career.daily.stepInside')}<span aria-hidden="true">↗</span></button>{progress.error != null && <p className="progress-stale">{tr('career.daily.storyStale')}</p>}</div><img src={storyPortrait(shift.story.speaker)} alt=""/></section>;
}

export function CareerScreen({career, missions, progress, error, onRetry, onMarket, onDaily}: {
  career: CareerSummary | null; missions: CareerMissionBoard | null; progress: ProgressState; error: unknown;
  onRetry: () => void; onMarket: () => void; onDaily: () => void;
}) {
  const tr = useT();
  const shift = progress.shift;
  const dates = shift ? storyWeek(shift.date) : [];
  const completed = new Set(shift?.history.map(item => item.date) ?? []);
  if (shift?.completedChoice) completed.add(shift.date);
  return <section className="career-screen" aria-label={tr('career.title')}>
    <div className="page-intro"><h1>{tr('career.title')}</h1><a className="career-rank-link" href="#career-progress" onClick={event => {event.preventDefault(); document.getElementById('career-progress')?.scrollIntoView({block:'nearest'});}}><img src={art('icons/nav-plumpy-career.png')} alt=""/>{career ? rankName(career.rank) : tr('career.progress.title')}</a></div>
    {error != null && <div className="progress-error" role="status">{tr('career.week.progressStale')} <button className="text-button" onClick={onRetry}>{tr('career.retry')}</button></div>}
    <div className="career-overview">
      <section className="career-week" aria-label={tr('career.week.title')}>
        <div className="section-line"><h2>{tr('career.week.title')}</h2>{dates.length > 0 && <span className="week-range">{fmt.date(dayDate(dates[0]!), 'en-GB', {day:'numeric',month:'short',timeZone:'UTC'})} – {fmt.date(dayDate(dates[6]!), 'en-GB', {day:'numeric',month:'short',timeZone:'UTC'})}</span>}</div>
        {!shift ? progress.loading ? <Loading>{tr('career.week.loading')}</Loading> : <div className="progress-error">{tr('career.week.loadFailed')} <button className="text-button" onClick={() => void progress.refresh()}>{tr('career.retry')}</button></div> : <>
          <ol className="desk-week-days">{dates.map(date => {
            const today = date === shift.date, done = completed.has(date);
            const label = tr('career.week.dayLabel', {day: fmt.date(dayDate(date), 'en-GB', {weekday:'long',day:'numeric',timeZone:'UTC'}),
              today: today ? 'yes' : 'no', state: done ? 'done' : date > shift.date ? 'upcoming' : 'missed'});
            return <li key={date} className={`${today ? 'today' : ''} ${done ? 'complete' : ''}`}><span>{fmt.date(dayDate(date), 'en-GB', {weekday:'short',timeZone:'UTC'})}</span>{today ? <button aria-label={label} onClick={onDaily}>{done ? <span className="completion-seal" aria-hidden="true">✓</span> : <img src={storyPortrait(shift.story.speaker)} alt=""/>}</button> : <div className="desk-day" aria-label={label}>{done ? <span className="completion-seal" aria-hidden="true">✓</span> : dayDate(date).getUTCDate()}</div>}</li>;
          })}</ol>
          <div className="career-today"><img src={storyPortrait(shift.story.speaker)} alt=""/><div><p className="daily-label">{shift.completedChoice ? tr('career.daily.completedToday') : tr('career.daily.today')}</p><h2>{shift.story.title}</h2><p>{shift.completedChoice ? tr('career.daily.decisionSaved') : tr('career.daily.momentWith', {name: speakerName(shift.story.speaker)})}</p><button className="primary" onClick={onDaily}>{shift.completedChoice ? tr('career.daily.reviewToday') : tr('career.daily.stepInside')}</button></div></div>
          {progress.error != null && <div className="progress-error" role="status">{tr('career.week.refreshFailed')} <button className="text-button" onClick={() => void progress.refresh()}>{tr('career.retry')}</button></div>}
        </>}
      </section>
      <aside className="career-progress" id="career-progress" aria-label={tr('career.week.rankActivity')}>
        {career ? <><img className="career-briefcase" src={art('rookie-briefcase-v1.png')} alt=""/><h2>{rankName(career.rank)}</h2><p className="career-trims">{tr.rich('career.progress.trimsTotal', {count: fmt.count(career.trims.total)})}</p><div className="career-meter" role="progressbar" aria-label={tr('career.progress.meter')} aria-valuenow={career.trims.total} aria-valuemin={career.rank.threshold} aria-valuemax={career.nextRank?.threshold ?? career.trims.total}><span style={{width:`${career.nextRank ? Math.min(100,Math.max(0,(career.trims.total-career.rank.threshold)/(career.nextRank.threshold-career.rank.threshold)*100)) : 100}%`}}/></div><p className="career-next-rank">{career.nextRank ? tr('career.progress.toNextRank', {count: fmt.count(career.nextRank.trimsRemaining), rank: rankName(career.nextRank)}) : tr('career.progress.soFar')}</p><div className="career-streak-line"><span className="career-flame" aria-hidden="true"/><strong>{tr('career.week.streak', {days: career.streak.days})}</strong></div>
        <p className="activity-week-label">{tr('career.activity.title')}</p>{progress.week ? <div className="activity-week" aria-label={tr('career.week.activityLabel')}>{storyWeek(progress.week.serverDate).map(date=><span key={date} title={tr(progress.week!.activeDates.includes(date) ? 'career.activity.dayActive' : 'career.activity.dayInactive', {date: activityDate(date)})} className={progress.week!.activeDates.includes(date) ? 'active' : ''}>{fmt.date(dayDate(date), 'en-GB', {weekday:'narrow',timeZone:'UTC'})}<span className="sr-only">{progress.week!.activeDates.includes(date) ? tr('career.week.active') : tr('career.week.noActivity')}</span></span>)}</div> : <p className="progress-stale">{progress.loading ? tr('career.week.activityLoading') : tr('career.week.activityUnavailable')}</p>}{progress.weekError != null && <button className="text-button" onClick={()=>void progress.refresh()}>{tr('career.week.retryActivity')}</button>}</> : error != null ? <div className="progress-stale"><p>{tr('career.progress.rankStale')}</p>{shift?.completedChoice && <p>{tr('career.week.storySaved')}</p>}<button className="text-button" onClick={onRetry}>{tr('career.week.retryProgress')}</button></div> : <Loading>{tr('career.progress.loading')}</Loading>}
      </aside>
    </div>
    {missions && <details className="career-milestones"><summary>{tr('career.week.tradingMilestones')} <span>{tr('career.week.milestoneCount', {done: missions.missions.filter(m=>m.status==='complete').length, total: missions.missions.length})}</span></summary><div>{missions.missions.map(mission=><article key={mission.id}><span className={`milestone-icon ${mission.status}`} aria-hidden="true">{mission.status==='complete' ? '✓' : <img src={art(mission.id==='write-a-reason' ? 'icons/career-comments.png' : 'icons/nav-plumpy-career.png')} alt=""/>}</span><div><h3>{missionText(mission).title}</h3><p>{missionText(mission).instruction}</p>{mission.id==='first-paper-buy' && mission.status==='ready' && <button className="text-button" onClick={onMarket}>{tr('career.week.browseMarket')}</button>}</div><span className="milestone-status">{mission.status==='complete' ? tr('career.milestones.complete') : mission.status==='locked' ? tr('career.milestones.locked') : mission.id==='first-paper-buy' ? tr('career.milestones.ready') : tr('career.week.continueOnMobile')}</span></article>)}</div></details>}
  </section>;
}

export function DailyStoryScreen({progress, onBack}: {progress: ProgressState; onBack: () => void}) {
  const tr = useT();
  const shift = progress.shift;
  const [draft, setDraft] = useState<string | null>(null);
  const [revealed, setRevealed] = useState(false);
  useEffect(()=>{setDraft(null);setRevealed(false);},[shift?.date,shift?.story.id]);
  const pendingChoice = progress.pending?.date === shift?.date && progress.pending?.caseId === shift?.story.id ? progress.pending?.choiceId : null;
  const choice = shift?.story.choices.find(item=>item.id===(shift.completedChoice ?? pendingChoice ?? draft));
  const done = shift?.completedChoice != null;
  return <section className="daily-story-screen" aria-label={tr('career.daily.today')}>
    <button className="company-back" disabled={progress.working} onClick={onBack}>{tr('career.daily.back')}</button>
    {!shift ? progress.loading ? <Loading>{tr('career.daily.loading')}</Loading> : <div className="progress-error">{tr('career.daily.loadFailed')} <button className="text-button" onClick={()=>void progress.refresh()}>{tr('career.retry')}</button></div> : <>
      <header className="daily-story-heading"><img src={storyPortrait(shift.story.speaker)} alt={speakerName(shift.story.speaker)}/><div><p className="daily-label">{speakerName(shift.story.speaker)} · {fmt.date(dayDate(shift.date), 'en-GB', {day:'numeric',month:'long',timeZone:'UTC'})}</p><h1>{shift.story.title}</h1></div></header>
      <p className="daily-story-body">{shift.story.body}</p>
      {done || revealed || progress.pending ? choice && <div className="daily-outcome"><span className="daily-label">{done ? tr('career.daily.savedResponse') : tr('career.daily.response')}</span><h2>{choice.label}</h2><p>{choice.outcome}</p><p className="daily-takeaway">{choice.takeaway}</p></div> : <fieldset className="daily-choices"><legend>{tr('career.daily.question')}</legend>{shift.story.choices.map(item=><label key={item.id} className={draft===item.id ? 'selected' : ''}><input type="radio" name="daily-response" value={item.id} checked={draft===item.id} onChange={()=>setDraft(item.id)}/><span>{item.label}</span></label>)}</fieldset>}
      {progress.error != null && <p className="progress-error" role="alert">{progress.pending ? tr('career.daily.pendingError') : tr('career.daily.updateError')}</p>}
      <div className="daily-story-actions">
        {done && <p className="daily-saved"><span className="completion-seal" aria-hidden="true">✓</span>{shift.trimsEarned > 0 ? tr('career.daily.dayCompletedTrims', {count: shift.trimsEarned}) : tr('career.daily.dayCompleted')}</p>}
        {/* A confirmed read can follow a lost write response. Replay its durable command before dismissing recovery. */}
        {progress.pending ? <button className="primary" disabled={progress.working} onClick={()=>void progress.recover()}>{progress.working ? tr('common.checking') : tr('career.daily.checkClockOutShort')}</button>
          : done ? <button className="primary" onClick={onBack}>{tr('career.daily.backToDesk')}</button>
          : revealed ? <><button className="primary" disabled={progress.working || !choice} onClick={()=>choice && void progress.complete(choice.id)}>{progress.working ? tr('career.saving') : tr('career.daily.clockOut')}</button><button className="text-button" disabled={progress.working} onClick={()=>setRevealed(false)}>{tr('career.daily.changeResponse')}</button></>
          : <button className="primary" disabled={!draft} onClick={()=>setRevealed(true)}>{tr('career.daily.seeWhatHappens')}</button>}
        {progress.error != null && !progress.pending && <button className="text-button" disabled={progress.working} onClick={()=>void progress.refresh()}>{tr('career.daily.refreshStory')}</button>}
      </div>
    </>}
  </section>;
}
