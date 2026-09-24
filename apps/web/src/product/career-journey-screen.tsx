import {useEffect, useRef, useState} from 'react';
import type {CareerActivityWeek, CareerMissionBoard, CareerSummary, WorkdayAssignment} from './practice-client';
import type {WorkdaysState} from './use-workdays';
import {CareerWorld} from './career-world';
import {art, Loading} from './ui';
import {storyWeek, storyPortrait} from './progress-screens';

export function WorkdayEntry({workdays, onOpen}: {workdays: WorkdaysState; onOpen: (id: string) => void}) {
  const current = workdays.journey?.assignments.find(item => !item.completedAt);
  if (!current) {
    if (workdays.journey) return null;
    return <section className="daily-entry"><div>{workdays.loading ? <Loading>Opening your assignments…</Loading> : <><p>Your assignments couldn’t load.</p><button className="text-button" onClick={() => void workdays.refresh()}>Try again</button></>}</div></section>;
  }
  return <section className="daily-entry workday-entry"><div><p className="daily-label">Day {current.ordinal} · {current.district}</p><h2>{current.title}</h2><p className="workday-entry-brief">{current.brief}</p><button className="text-button" onClick={() => onOpen(current.id)}>{current.step > 0 ? 'Continue assignment' : 'Start assignment'}</button></div><img src={storyPortrait(current.speaker)} alt=""/></section>;
}

export function CareerJourneyScreen({workdays, career, missions, week, progressError, onRetry, onOpen, onMarket, motion, sound, onSound}: {
  workdays: WorkdaysState; career: CareerSummary | null; missions: CareerMissionBoard | null; week: CareerActivityWeek | null;
  progressError: boolean; onRetry: () => void; onOpen: (id: string) => void; onMarket: () => void;
  motion: boolean; sound: boolean; onSound: () => void;
}) {
  const [showRank, setShowRank] = useState(false);
  const rank = useRef<HTMLDialogElement>(null), rankButton = useRef<HTMLButtonElement>(null);
  const current = workdays.journey?.assignments.find(item => !item.completedAt);
  useEffect(() => {if (showRank) rank.current?.showModal?.(); else rank.current?.close?.();}, [showRank]);
  const close = () => {setShowRank(false); rankButton.current?.focus();};
  return <section className="career-journey" aria-label="Career">
    <header className="page-intro"><h1>Career</h1><div className="career-header-actions"><button className="career-sound" aria-label={sound ? 'Mute Career sounds' : 'Enable Career sounds'} aria-pressed={sound} onClick={onSound}><img src={art('icons/settings-sound.png')} alt=""/><span>{sound ? 'Sound on' : 'Sound off'}</span></button><button ref={rankButton} className="career-rank-link" onClick={() => setShowRank(true)} aria-haspopup="dialog"><img src={art('icons/nav-plumpy-career.png')} alt=""/>{career?.rank.label ?? 'Your progress'}</button></div></header>
    {workdays.pending && <div className="work-recovery" role="status"><span>An earlier save needs checking.</span><button className="text-button" disabled={workdays.working} onClick={() => void workdays.recover()}>{workdays.working ? 'Checking…' : 'Check saved work'}</button></div>}
    {workdays.readError != null && workdays.journey && !workdays.pending && <div className="work-recovery" role="status"><span>Your assignments couldn’t refresh.</span><button className="text-button" onClick={() => void workdays.refresh()}>Try again</button></div>}
    <div className="career-journey-layout"><CareerWorld assignments={workdays.journey?.assignments ?? null} loading={workdays.loading} error={workdays.readError ? 'Your assignments couldn’t load.' : null} motion={motion} onOpen={onOpen} onRetry={() => void workdays.refresh()}/>
      <aside className="career-current" aria-label="Your next assignment">{current ? <><img className="career-current-art" src={art(`career-world/${current.art}.png`)} alt=""/><p className="daily-label">Day {current.ordinal} · {current.district}</p><h2>{current.title}</h2><p>{current.brief}</p><ol className="work-stage-list">{['Pin the evidence', 'Make your call', 'File your update'].map((label, index) => <li key={label} className={index < current.step ? 'done' : index === current.step ? 'active' : ''}><span aria-hidden="true">{index < current.step ? '✓' : index + 1}</span>{label}{index < current.step && <span className="sr-only">, saved</span>}</li>)}</ol><button className="primary" onClick={() => onOpen(current.id)}>{current.step > 0 ? 'Continue assignment' : 'Start assignment'}</button></> : workdays.journey ? <><img className="career-current-art" src={art('career-world/trophy.png')} alt=""/><h2>All filed.</h2><p>Your {workdays.journey.completedCount} assignments are saved. Open a completed day to revisit your work.</p></> : <Loading>Opening your path…</Loading>}
      {workdays.journey && <p className="career-filed-count">{workdays.journey.completedCount} of {workdays.journey.assignments.length} assignments filed</p>}</aside>
    </div>
    {showRank && <dialog className="career-rank-dialog" ref={rank} aria-labelledby="career-rank-title" onCancel={event => {event.preventDefault(); close();}} onClick={event => {if (event.target === event.currentTarget) close();}}><div className="career-rank-content"><div className="section-line"><h2 id="career-rank-title">Your progress</h2><button className="rank-close" aria-label="Close progress" onClick={close}>×</button></div>
      {progressError && <p className="progress-stale">Your rank couldn’t refresh.{career && ' Showing the last confirmed progress.'} <button className="text-button" onClick={onRetry}>Try again</button></p>}
      {career ? <><div className="career-progress"><img className="career-briefcase" src={art('rookie-briefcase-v1.png')} alt=""/><h2>{career.rank.label}</h2><p className="career-trims"><strong>{career.trims.total.toLocaleString()}</strong> Trims</p><div className="career-meter" role="progressbar" aria-label="Trims toward next rank" aria-valuenow={career.trims.total} aria-valuemin={career.rank.threshold} aria-valuemax={career.nextRank?.threshold ?? Math.max(career.trims.total, career.rank.threshold + 1)}><span style={{width: `${career.nextRank ? Math.min(100, Math.max(0, (career.trims.total - career.rank.threshold) / Math.max(1, career.nextRank.threshold - career.rank.threshold) * 100)) : 100}%`}}/></div><p className="career-next-rank">{career.nextRank ? career.nextRank.trimsRemaining > 0 ? `${career.nextRank.trimsRemaining} Trims to ${career.nextRank.label}` : 'Finish your promotion milestone.' : 'Your career so far'}</p><div className="career-streak-line"><span className="career-flame" aria-hidden="true"/><strong>{career.streak.days} {career.streak.days === 1 ? 'day' : 'days'} in a row</strong></div>{week && <><p className="activity-week-label">Activity this week</p><div className="activity-week" aria-label="Days with recorded activity">{storyWeek(week.serverDate).map(date => <span key={date} className={week.activeDates.includes(date) ? 'active' : ''} title={`${date}: ${week.activeDates.includes(date) ? 'Active' : 'No recorded activity'}`}>{new Date(`${date}T12:00:00Z`).toLocaleDateString('en-GB', {weekday: 'narrow', timeZone: 'UTC'})}</span>)}</div></>}</div></> : !progressError && <Loading>Getting your progress…</Loading>}
      {missions && <div className="career-milestones"><h3>Trading milestones</h3>{missions.missions.map(mission => <article key={mission.id}><span className={`milestone-icon ${mission.status}`} aria-hidden="true">{mission.status === 'complete' ? '✓' : <img src={art(mission.id === 'write-a-reason' ? 'icons/career-comments.png' : 'icons/nav-plumpy-career.png')} alt=""/>}</span><div><h3>{mission.title}</h3><p>{mission.instruction}</p>{mission.status === 'ready' && (mission.id === 'first-paper-buy' ? <button className="text-button" onClick={() => {close(); onMarket();}}>Browse market</button> : <p>Continue on mobile</p>)}</div><span className="milestone-status">{mission.status === 'complete' ? 'Complete' : mission.status === 'locked' ? 'Locked' : 'Ready'}</span></article>)}</div>}
    </div></dialog>}
  </section>;
}

export function canOpenWork(assignment: WorkdayAssignment, assignments: readonly WorkdayAssignment[]): boolean {
  return assignment.completedAt !== null || assignments.find(item => !item.completedAt)?.id === assignment.id;
}
