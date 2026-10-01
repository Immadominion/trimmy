import {useEffect, useRef, useState} from 'react';
import type {CareerActivityWeek, CareerMissionBoard, CareerSummary, WorkdayAssignment} from './practice-client';
import type {WorkdaysState} from './use-workdays';
import {CareerWorld} from './career-world';
import {art, Loading} from './ui';
import {storyWeek, storyPortrait, activityDate} from './progress-screens';
import {PromotionMoment, ReasonComposer, missionText, rankLabel, rankName} from './career-milestones';
import type {CareerMilestones} from './career-milestones';
import {scheduleNotice, streakLine} from './workday-schedule';
import {useT} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';
import * as fmt from '../i18n/format';

const STAGES: readonly MessageKey[] = ['career.next.stagePin', 'career.next.stageCall', 'career.next.stageFile'];

export function WorkdayEntry({workdays, onOpen}: {workdays: WorkdaysState; onOpen: (id: string) => void}) {
  const tr = useT();
  const current = workdays.journey?.assignments.find(item => !item.completedAt);
  if (!current) {
    const notice = scheduleNotice(workdays.journey), next = workdays.journey?.upcoming;
    if (notice && next) return <section className="daily-entry workday-entry"><div><p className="daily-label">{tr('career.dayWith', {day: next.ordinal, name: next.district})}</p><h2>{notice.title}</h2><p className="workday-entry-brief">{notice.body}</p></div><img src={storyPortrait(next.speaker)} alt=""/></section>;
    if (workdays.journey) return null;
    return <section className="daily-entry"><div>{workdays.loading ? <Loading>{tr('career.assignments.loading')}</Loading> : <><p>{tr('career.assignments.loadFailed')}</p><button className="text-button" onClick={() => void workdays.refresh()}>{tr('common.tryAgain')}</button></>}</div></section>;
  }
  return <section className="daily-entry workday-entry"><div><p className="daily-label">{tr('career.dayWith', {day: current.ordinal, name: current.district})}</p><h2>{current.title}</h2><p className="workday-entry-brief">{current.brief}</p><button className="text-button" onClick={() => onOpen(current.id)}>{current.step > 0 ? tr('career.assignments.continue') : tr('career.assignments.start')}</button></div><img src={storyPortrait(current.speaker)} alt=""/></section>;
}

export function CareerJourneyScreen({workdays, career, missions, week, progressError, onRetry, onOpen, onMarket, motion, sound, onSound, milestones}: {
  workdays: WorkdaysState; career: CareerSummary | null; missions: CareerMissionBoard | null; week: CareerActivityWeek | null;
  progressError: boolean; onRetry: () => void; onOpen: (id: string) => void; onMarket: () => void;
  motion: boolean; sound: boolean; onSound: () => void;
  /** Mobile's milestone actions: comment on a held buy and claim an earned promotion. */
  milestones?: CareerMilestones;
}) {
  const tr = useT();
  const [showRank, setShowRank] = useState(false);
  const rank = useRef<HTMLDialogElement>(null), rankButton = useRef<HTMLButtonElement>(null);
  const current = workdays.journey?.assignments.find(item => !item.completedAt);
  const notice = scheduleNotice(workdays.journey), next = workdays.journey?.upcoming ?? null;
  const streak = career ? streakLine(career.streak) : null;
  useEffect(() => {if (showRank) rank.current?.showModal?.(); else rank.current?.close?.();}, [showRank]);
  const close = () => {setShowRank(false); rankButton.current?.focus();};
  return <section className="career-journey" aria-label={tr('career.title')}>
    <header className="page-intro"><h1>{tr('career.title')}</h1><div className="career-header-actions"><button className="career-sound" aria-label={sound ? tr('career.sound.mute') : tr('career.sound.enable')} aria-pressed={sound} onClick={onSound}><img src={art('icons/settings-sound.png')} alt=""/><span>{sound ? tr('career.sound.on') : tr('career.sound.off')}</span></button><button ref={rankButton} className="career-rank-link" onClick={() => setShowRank(true)} aria-haspopup="dialog"><img src={art('icons/nav-plumpy-career.png')} alt=""/>{career ? rankName(career.rank) : tr('career.progress.title')}</button></div></header>
    {workdays.pending && <div className="work-recovery" role="status"><span>{tr('career.assignments.pendingSave')}</span><button className="text-button" disabled={workdays.working} onClick={() => void workdays.recover()}>{workdays.working ? tr('common.checking') : tr('career.assignments.checkSaved')}</button></div>}
    {workdays.readError != null && workdays.journey && !workdays.pending && <div className="work-recovery" role="status"><span>{tr('career.assignments.refreshFailed')}</span><button className="text-button" onClick={() => void workdays.refresh()}>{tr('common.tryAgain')}</button></div>}
    <div className="career-journey-layout"><CareerWorld assignments={workdays.journey?.assignments ?? null} upcoming={next} loading={workdays.loading} error={workdays.readError ? tr('career.assignments.loadFailed') : null} motion={motion} onOpen={onOpen} onRetry={() => void workdays.refresh()}/>
      <aside className="career-current" aria-label={tr('career.next.label')}>{current ? <><img className="career-current-art" src={art(`career-world/${current.art}.png`)} alt=""/><p className="daily-label">{tr('career.dayWith', {day: current.ordinal, name: current.district})}</p><h2>{current.title}</h2><p>{current.brief}</p><ol className="work-stage-list">{STAGES.map((label, index) => <li key={label} className={index < current.step ? 'done' : index === current.step ? 'active' : ''}><span aria-hidden="true">{index < current.step ? '✓' : index + 1}</span>{tr(label)}{index < current.step && <span className="sr-only">{tr('career.next.stageSaved')}</span>}</li>)}</ol><button className="primary" onClick={() => onOpen(current.id)}>{current.step > 0 ? tr('career.assignments.continue') : tr('career.assignments.start')}</button></> : notice && next ? <><img className="career-current-art" src={art(`career-world/${next.art}.png`)} alt=""/><p className="daily-label">{tr('career.dayWith', {day: next.ordinal, name: next.district})}</p><h2>{notice.title}</h2><p>{notice.body}</p></> : workdays.journey ? <><img className="career-current-art" src={art('career-world/trophy.png')} alt=""/><h2>{tr('career.next.allFiled')}</h2><p>{tr('career.next.allFiledBody', {count: workdays.journey.completedCount})}</p></> : <Loading>{tr('career.next.loading')}</Loading>}
      {workdays.journey && <p className="career-filed-count">{tr('career.next.filedCount', {done: workdays.journey.completedCount, total: workdays.journey.total ?? workdays.journey.assignments.length})}</p>}</aside>
    </div>
    {showRank && <dialog className="career-rank-dialog" ref={rank} aria-labelledby="career-rank-title" onCancel={event => {event.preventDefault(); close();}} onClick={event => {if (event.target === event.currentTarget) close();}}><div className="career-rank-content"><div className="section-line"><h2 id="career-rank-title">{tr('career.progress.title')}</h2><button className="rank-close" aria-label={tr('career.progress.close')} onClick={close}>×</button></div>
      {progressError && <p className="progress-stale">{career ? tr('career.progress.rankStaleShowing') : tr('career.progress.rankStale')} <button className="text-button" onClick={onRetry}>{tr('common.tryAgain')}</button></p>}
      {career ? <><div className="career-progress"><img className="career-briefcase" src={art('rookie-briefcase-v1.png')} alt=""/><h2>{rankName(career.rank)}</h2><p className="career-trims">{tr.rich('career.progress.trimsTotal', {count: fmt.count(career.trims.total)})}</p><div className="career-meter" role="progressbar" aria-label={tr('career.progress.meter')} aria-valuenow={career.trims.total} aria-valuemin={career.rank.threshold} aria-valuemax={career.nextRank?.threshold ?? Math.max(career.trims.total, career.rank.threshold + 1)}><span style={{width: `${career.nextRank ? Math.min(100, Math.max(0, (career.trims.total - career.rank.threshold) / Math.max(1, career.nextRank.threshold - career.rank.threshold) * 100)) : 100}%`}}/></div><p className="career-next-rank">{career.nextRank ? career.nextRank.trimsRemaining > 0 ? tr('career.progress.toNextRank', {count: fmt.count(career.nextRank.trimsRemaining, 'raw'), rank: rankName(career.nextRank)}) : tr('career.progress.finishPromotion') : tr('career.progress.soFar')}</p><div className="career-streak-line"><span className="career-flame" aria-hidden="true"/><strong>{streak!.days}</strong></div><p className="career-next-rank">{streak!.note}</p>{week && <><p className="activity-week-label">{tr('career.activity.title')}</p><div className="activity-week" aria-label={tr('career.activity.recorded')}>{storyWeek(week.serverDate).map(date => <span key={date} className={week.activeDates.includes(date) ? 'active' : ''} title={tr(week.activeDates.includes(date) ? 'career.activity.dayActive' : 'career.activity.dayInactive', {date: activityDate(date)})}>{fmt.date(`${date}T12:00:00Z`, 'en-GB', {weekday: 'narrow', timeZone: 'UTC'})}</span>)}</div></>}</div></> : !progressError && <Loading>{tr('career.progress.loading')}</Loading>}
      {milestones?.promotion && <div className="promotion-result" role="status"><img src={art('icons/goal-goal-animated.png')} alt=""/><div><strong>{tr('career.promotion.unlocked', {rank: rankLabel(milestones.promotion.toRank)})}</strong><span>{tr('career.trimsGained', {count: milestones.promotion.trimsAwarded})}</span></div></div>}
      {milestones?.message && <p className="progress-stale" role="status">{tr(milestones.message)} <button className="text-button" onClick={milestones.dismissMessage}>{tr('common.dismiss')}</button></p>}
      {missions && <div className="career-milestones"><h3>{tr('career.milestones.title')}</h3>{missions.missions.map(mission => {
        const promotable = milestones?.eligible?.id === mission.id && mission.promotesToRank !== null;
        return <article key={mission.id}><span className={`milestone-icon ${mission.status}`} aria-hidden="true">{mission.status === 'complete' ? '✓' : <img src={art(mission.id === 'write-a-reason' ? 'icons/career-comments.png' : 'icons/nav-plumpy-career.png')} alt=""/>}</span><div>
          <h3>{mission.id === 'write-a-reason' ? tr('career.milestones.commentTitle') : missionText(mission).title}</h3><p>{missionText(mission).instruction}</p>
          {mission.status === 'ready' && (mission.id === 'write-a-reason' && milestones
            ? <button className="text-button" onClick={() => {if (milestones.openComment()) close();}}>{tr('career.milestones.writeComment')}</button>
            : <button className="text-button" onClick={() => {close(); onMarket();}}>{tr('career.milestones.findStock')}</button>)}
          {promotable && milestones && <button className="text-button" disabled={milestones.promoting} onClick={() => void milestones.promote(mission).then(done => {if (done) close();})}>{milestones.promoting ? tr('career.milestones.confirming') : tr('career.milestones.become', {rank: rankLabel(mission.promotesToRank!)})}</button>}
        </div><span className="milestone-status">{mission.status === 'complete' ? tr('career.milestones.complete') : mission.status === 'locked' ? tr('career.milestones.locked') : tr('career.milestones.ready')}</span></article>;
      })}</div>}
    </div></dialog>}
    {milestones?.composer && <ReasonComposer target={milestones.composer} companyName={null} pending={milestones.pendingComment} onSave={milestones.saveComment} onClose={milestones.closeComment}/>}
    {milestones?.moment && milestones.promotion && <PromotionMoment receipt={milestones.promotion} onContinue={milestones.dismissPromotion}/>}
  </section>;
}

export function canOpenWork(assignment: WorkdayAssignment, assignments: readonly WorkdayAssignment[]): boolean {
  return assignment.completedAt !== null || assignments.find(item => !item.completedAt)?.id === assignment.id;
}
