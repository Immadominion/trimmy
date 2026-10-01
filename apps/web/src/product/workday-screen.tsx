import {useCallback, useEffect, useId, useRef, useState} from 'react';
import type {WorkdayAnswer, WorkdayAssignment} from './practice-client';
import type {ScheduleNotice} from './workday-schedule';
import {art} from './ui';
import {useT, type Translator} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';
import * as fmt from '../i18n/format';

export interface WorkdayScreenProps {
  readonly assignment: WorkdayAssignment;
  readonly working: boolean;
  readonly error: unknown;
  readonly pending: boolean;
  readonly onSubmit: (assignment: WorkdayAssignment, answer: WorkdayAnswer, draft?: string) => Promise<boolean>;
  readonly onSaveDraft: (assignment: WorkdayAssignment, draft: string) => Promise<boolean>;
  readonly onRecover: () => Promise<boolean>;
  readonly onBack: () => void;
  readonly registerLeaveGuard?: (guard: (() => Promise<boolean>) | null) => void;
  readonly onCue?: (cue: 'select' | 'paper' | 'saved' | 'complete') => void;
  /** When the next assignment opens, shown once this one is filed. */
  readonly next?: ScheduleNotice | null;
}

function errorCode(error: unknown): string {
  return error && typeof error === 'object' && 'code' in error ? String(error.code) : '';
}
function missNote(error: unknown): string | null {
  return error && typeof error === 'object' && 'feedback' in error && typeof error.feedback === 'string' ? error.feedback : null;
}
/** The copy for a failed step: a missed decision shows the server's own feedback for it. */
function workError(tr: Translator, error: unknown, work: WorkdayAssignment, choice: string | null): string {
  switch (errorCode(error)) {
    case 'CHECK_EVIDENCE': return tr('career.workday.error.evidence');
    case 'CHECK_DECISION': return missNote(error) ?? work.decision.choices.find(item => item.id === choice)?.feedback ?? tr('career.workday.error.decision');
    case 'WORK_CHANGED': return tr('career.workday.error.changed');
    case 'WORK_LOCKED': return tr('career.workday.error.locked');
    case 'WORK_TOMORROW': return tr('career.workday.error.tomorrow');
    case 'WORK_CLOSED': return tr('career.workday.error.closed');
    case 'PRACTICE_SESSION_CHANGED': case 'SESSION_CHANGED': return tr('career.workday.error.session');
    default: return tr('career.workday.error.default');
  }
}
/** The draft note's save state, shown beside the note. */
type DraftStatus = '' | 'saving' | 'saved' | 'unsaved' | 'notSaved';
const DRAFT_STATUS: Readonly<Record<Exclude<DraftStatus, ''>, MessageKey>> = {saving: 'career.saving', saved: 'career.workday.draft.saved',
  unsaved: 'career.workday.draft.unsaved', notSaved: 'career.workday.draft.notSaved'};
const STAGES: readonly MessageKey[] = ['career.workday.stage.evidence', 'career.workday.stage.decision', 'career.workday.stage.handoff'];
/**
 * A typed number answer in the plain form the server checks (`-12.5`).
 * English is unchanged; elsewhere either decimal mark is accepted.
 */
function typedAnswer(typed: string): string {
  const text = typed.trim(), sign = text.startsWith('-') ? '-' : '';
  return sign + fmt.normalizeDecimalInput(text.slice(sign.length));
}
/** The dollar sign's place around a typed amount: before it in English (`$`), after it in French (`$US`). */
function dollarAffixes(): {readonly before: string; readonly after: string} {
  const sample = fmt.usd('$1'), at = sample.indexOf('1');
  return at < 0 ? {before: '$', after: ''} : {before: sample.slice(0, at).trim(), after: sample.slice(at + 1).trim()};
}
/** A saved number answer as the player reads it: `$200` and `12%` in English. */
function savedNumber(value: string, unit: string | null): string {
  const english = `${unit === '$' ? '$' : ''}${value}${unit === '%' ? '%' : ''}`;
  if (fmt.isEnglish()) return english;
  const negative = value.startsWith('-'), digits = negative ? value.slice(1) : value;
  if (unit === '$') return fmt.usd(`${negative ? '-' : ''}$${digits}`);
  if (unit === '%') return fmt.percent(`${value}%`);
  return fmt.number(value);
}
function Pin({selected}: {selected: boolean}) {
  return <svg className="workday-pin" viewBox="0 0 24 24" aria-hidden="true" fill={selected ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round"><path d="m9 3 6 0-1 6 3 3v2H7v-2l3-3-1-6Z"/><path d="M12 14v7" strokeLinecap="round"/></svg>;
}

/** Each stage and reward is displayed only after the server returns it. */
export function WorkdayScreen(props: WorkdayScreenProps) {
  const tr = useT();
  const work = props.assignment, complete = work.completedAt !== null;
  const latest = useRef(props); latest.current = props;
  const [selected, setSelected] = useState<readonly string[]>([]);
  const [choice, setChoice] = useState<string | null>(null);
  const [number, setNumber] = useState('');
  const [note, setNote] = useState(work.draft);
  const noteRef = useRef(note); noteRef.current = note;
  const savedNote = useRef(work.draft);
  const editBase = useRef<WorkdayAssignment | null>(null);
  const seenAssignment = useRef(work);
  const acknowledgedDrafts = useRef(new Set<string>());
  const remoteNote = useRef<WorkdayAssignment | null>(null);
  const [noteConflict, setNoteConflict] = useState<WorkdayAssignment | null>(null);
  const unfiledNote = useRef<string | null>(null);
  const [retainedNote, setRetainedNote] = useState<string | null>(null);
  const [hint, setHint] = useState(false), [sources, setSources] = useState(false);
  const [draftStatus, setDraftStatus] = useState<DraftStatus>('');
  const [localError, setLocalError] = useState(false), [localBusy, setLocalBusy] = useState(false);
  const [dismissedError, setDismissedError] = useState<unknown>(null);
  const writing = useRef(false), mounted = useRef(false), leaveApproved = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const draftJob = useRef<{text: string; promise: Promise<boolean>} | null>(null);
  const leaveChoice = useRef<{promise: Promise<boolean>; resolve: (value: boolean) => void} | null>(null);
  const [leaveDialog, setLeaveDialog] = useState(false);
  const keepWriting = useRef<HTMLButtonElement>(null), leaveWithoutSaving = useRef<HTMLButtonElement>(null);
  const noteInput = useRef<HTMLTextAreaElement>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  const headingId = useId(), noteId = useId(), hintId = useId(), dialogId = useId(), errorId = useId();
  const locked = props.working || localBusy || props.pending;
  // A hint unlocks after a missed answer, so the first try is the player's own.
  const hintReady = work.misses > 0 || errorCode(props.error) === 'CHECK_DECISION';
  const reward = work.trims ?? (work.misses === 0 ? 20 : 10);

  useEffect(() => {
    mounted.current = true;
    return () => {mounted.current = false; if (timer.current) clearTimeout(timer.current); leaveChoice.current?.resolve(false);};
  }, []);
  useEffect(() => {
    if (timer.current) clearTimeout(timer.current);
    if (work.step === 3 && seenAssignment.current.id === work.id && seenAssignment.current.step === 2 &&
      noteRef.current !== savedNote.current && noteRef.current !== work.draft) {
      unfiledNote.current = noteRef.current; setRetainedNote(noteRef.current);
    }
    setSelected([]); setChoice(null); setNumber(''); setHint(false); setSources(false); setLocalError(false);
    setNote(work.draft); noteRef.current = work.draft; savedNote.current = work.draft; setDraftStatus(''); leaveApproved.current = false;
    editBase.current = null; seenAssignment.current = work; acknowledgedDrafts.current.clear(); remoteNote.current = null; setNoteConflict(null);
    heading.current?.focus();
  }, [work.id, work.step]);
  useEffect(() => {
    const previous = seenAssignment.current;
    const dirty = noteRef.current !== savedNote.current;
    const ownAcknowledgement = draftJob.current?.text === work.draft || acknowledgedDrafts.current.has(work.draft);
    acknowledgedDrafts.current.delete(work.draft);
    if (!dirty || noteRef.current === work.draft) {
      setNote(work.draft); noteRef.current = work.draft; editBase.current = null;
      remoteNote.current = null; setNoteConflict(null);
    } else if (work.step === 2 && previous.id === work.id && work.revision !== previous.revision && !ownAcknowledgement) {
      if (timer.current) clearTimeout(timer.current);
      remoteNote.current = work; setNoteConflict(work); setDraftStatus('notSaved');
    }
    savedNote.current = work.draft;
    seenAssignment.current = work;
  }, [work.id, work.step, work.revision, work.draft]);
  useEffect(() => {
    if (errorCode(props.error) === 'WORK_CHANGED' && work.step === 2 && noteRef.current !== savedNote.current) {
      if (timer.current) clearTimeout(timer.current);
      remoteNote.current = work; setNoteConflict(work); setDraftStatus('notSaved');
    }
  }, [props.error, work]);

  const persistNote = useCallback(async (): Promise<boolean> => {
    const original = latest.current.assignment;
    if (original.step !== 2 || original.completedAt !== null || noteRef.current === savedNote.current) return true;
    if (remoteNote.current) return false;
    if (draftJob.current) {
      const previous = await draftJob.current.promise;
      if (!previous || !mounted.current || latest.current.assignment.id !== original.id) return false;
      return persistNote();
    }
    const text = noteRef.current;
    const base = editBase.current ?? original;
    setDraftStatus('saving');
    const promise = (async () => {
      try {
        const saved = await latest.current.onSaveDraft(base, text);
        if (!mounted.current || latest.current.assignment.id !== original.id) return false;
        if (saved) {
          savedNote.current = text;
          if (latest.current.assignment.draft !== text) acknowledgedDrafts.current.add(text);
          if (noteRef.current === text) editBase.current = null;
        }
        if (noteRef.current === text) setDraftStatus(saved ? 'saved' : 'notSaved');
        return saved;
      } catch {if (mounted.current) setDraftStatus('notSaved'); return false;}
    })();
    draftJob.current = {text, promise};
    try {return await promise;} finally {if (draftJob.current?.promise === promise) draftJob.current = null;}
  }, []);

  const guardLeave = useCallback(async (): Promise<boolean> => {
    if (leaveApproved.current) return true;
    if (leaveChoice.current) return leaveChoice.current.promise;
    if (writing.current || (latest.current.working && !draftJob.current)) return false;
    if (timer.current) clearTimeout(timer.current);
    let saved = unfiledNote.current === null && await persistNote();
    // Typing may continue while the leave-triggered save waits. Flush that newer text too.
    while (saved && mounted.current && latest.current.assignment.step === 2 && noteRef.current !== savedNote.current) saved = await persistNote();
    if (!mounted.current) return false;
    if (saved && unfiledNote.current === null) {leaveApproved.current = true; return true;}
    const existingChoice = leaveChoice.current as {promise: Promise<boolean>; resolve: (value: boolean) => void} | null;
    if (existingChoice) return existingChoice.promise;
    let resolve!: (value: boolean) => void;
    const promise = new Promise<boolean>(settle => {resolve = settle;});
    leaveChoice.current = {promise, resolve};
    setLeaveDialog(true);
    return promise;
  }, [persistNote]);
  useEffect(() => {props.registerLeaveGuard?.(guardLeave); return () => props.registerLeaveGuard?.(null);}, [props.registerLeaveGuard, guardLeave]);
  useEffect(() => {if (leaveDialog) keepWriting.current?.focus();}, [leaveDialog]);
  useEffect(() => {
    const warn = (event: BeforeUnloadEvent) => {if (unfiledNote.current !== null || (latest.current.assignment.step === 2 && noteRef.current !== savedNote.current)) {event.preventDefault(); event.returnValue = '';}};
    window.addEventListener('beforeunload', warn); return () => window.removeEventListener('beforeunload', warn);
  }, []);

  function decideLeave(leave: boolean) {
    if (leave && unfiledNote.current !== null) {unfiledNote.current = null; setRetainedNote(null);}
    leaveApproved.current = leave; setLeaveDialog(false);
    leaveChoice.current?.resolve(leave); leaveChoice.current = null;
    if (!leave) (unfiledNote.current === null ? noteInput.current : heading.current)?.focus();
  }
  function changeNote(text: string) {
    if (!editBase.current && text !== savedNote.current) editBase.current = latest.current.assignment;
    setNote(text); noteRef.current = text; leaveApproved.current = false;
    setDraftStatus(text === savedNote.current ? 'saved' : 'unsaved');
    if (timer.current) clearTimeout(timer.current);
    if (!remoteNote.current) timer.current = setTimeout(() => {void persistNote();}, 650);
  }
  function resolveNote(useSaved: boolean) {
    if (latest.current.working || latest.current.pending || writing.current) return;
    if (timer.current) clearTimeout(timer.current);
    const current = latest.current.assignment;
    savedNote.current = current.draft; remoteNote.current = null; setNoteConflict(null);
    setDismissedError(latest.current.error); setLocalError(false); leaveApproved.current = false;
    if (useSaved) {
      noteRef.current = current.draft; setNote(current.draft); editBase.current = null; setDraftStatus('saved');
    } else {
      editBase.current = current; setDraftStatus('unsaved'); void persistNote();
    }
  }
  function toggle(id: string) {
    if (locked) return;
    props.onCue?.('select'); setLocalError(false); setDismissedError(props.error);
    setSelected(items => items.includes(id) ? items.filter(item => item !== id) : [...items, id]);
  }
  async function submit() {
    if (writing.current || locked || complete || remoteNote.current) return;
    writing.current = true; setLocalBusy(true); setLocalError(false); setDismissedError(null); leaveApproved.current = false;
    if (timer.current) clearTimeout(timer.current);
    const original = latest.current.assignment.step === 2 && editBase.current ? editBase.current : latest.current.assignment;
    const answer: WorkdayAnswer = original.step === 1 ? {value: original.decision.kind === 'number' ? typedAnswer(number) : choice!} : {ids: selected};
    try {
      if (draftJob.current && !await draftJob.current.promise) {setLocalError(true); return;}
      const saved = await latest.current.onSubmit(original, answer, ...(original.step === 2 ? [noteRef.current] : []));
      if (!mounted.current) return;
      if (saved) props.onCue?.(original.step === 2 ? 'complete' : 'saved'); else setLocalError(true);
    } catch {if (mounted.current) setLocalError(true);}
    finally {writing.current = false; if (mounted.current) setLocalBusy(false);}
  }
  async function recover() {
    if (writing.current || props.working) return;
    writing.current = true; setLocalBusy(true); setLocalError(false);
    try {if (!await latest.current.onRecover() && mounted.current) setLocalError(true);}
    catch {if (mounted.current) setLocalError(true);}
    finally {writing.current = false; if (mounted.current) setLocalBusy(false);}
  }
  async function back() {if (await guardLeave()) latest.current.onBack();}
  const count = work.step === 0 ? work.evidence.count : work.file.count;
  const ready = work.step === 1 ? work.decision.kind === 'number' ? /^-?(?:\d+(?:\.\d*)?|\.\d+)$/.test(typedAnswer(number)) : choice !== null : selected.length === count;
  const source = (selectable: boolean) => <div className="workday-source-list">{work.rows.map(row => {
    const pinned = selectable && selected.includes(row.id);
    const content = <><span className="workday-source-label">{row.label}{selectable && <Pin selected={pinned}/>}</span><strong>{row.value}</strong><p>{row.detail}</p></>;
    return selectable ? <button key={row.id} type="button" className={`workday-choice workday-source${pinned ? ' selected' : ''}`} aria-pressed={pinned} aria-label={tr(pinned ? 'career.workday.unpinRow' : 'career.workday.pinRow', {label: row.label, value: row.value})} disabled={locked} onClick={() => toggle(row.id)}>{content}</button>
      : <article className="workday-source workday-source-reading" key={row.id}>{content}</article>;
  })}</div>;
  const orderedParts = [...work.file.parts.slice(work.ordinal % work.file.parts.length), ...work.file.parts.slice(0, work.ordinal % work.file.parts.length)];
  const decisionAnswer = work.answers['1'];
  const savedDecision = decisionAnswer && 'value' in decisionAnswer
    ? work.decision.choices.find(item => item.id === decisionAnswer.value)?.label ?? savedNumber(decisionAnswer.value, work.decision.unit) : null;
  const dollar = dollarAffixes();

  return <section className="workday-screen" aria-labelledby={headingId}>
    <div className="workday-topbar"><button className="company-back" disabled={localBusy || (props.working && !draftJob.current)} onClick={() => void back()}>{tr('career.backToCareerArrow')}</button><span>{tr('career.day', {day: work.ordinal})}</span></div>
    <ol className="workday-stages" aria-label={tr('career.workday.stages')}>{STAGES.map((label, index) => <li key={label} className={index < work.step ? 'complete' : index === work.step ? 'current' : ''} aria-current={index === work.step && !complete ? 'step' : undefined}><span aria-hidden="true">{index < work.step ? '✓' : index + 1}</span>{tr(label)}<small className="sr-only">{index < work.step ? tr('career.workday.stage.confirmed') : index === work.step && !complete ? tr('career.workday.stage.current') : tr('career.workday.stage.notCompleted')}</small></li>)}</ol>
    {complete ? <div className="workday-filed"><img className="workday-filed-art" src={art(`career-world/${work.art}.png`)} alt=""/><p className="workday-eyebrow">{tr('career.dayWith', {day: work.ordinal, name: work.title})}</p><h1 id={headingId} ref={heading} tabIndex={-1}>{tr('career.workday.filed')}</h1><p className="workday-feedback">{work.feedback}</p><article className="workday-artifact"><h2>{work.title}</h2><p>{work.artifact}</p><p className="workday-reward"><span className="completion-seal" aria-hidden="true">✓</span>{tr('career.workday.trimsEarned', {count: reward})}</p></article>{props.next && <aside className="workday-context" role="status"><strong>{props.next.title}</strong> {props.next.body}</aside>}<details className="workday-review"><summary>{tr('career.workday.review')}</summary><dl><div><dt>{tr('career.workday.stage.evidence')}</dt><dd>{work.rows.filter(row => {const answer = work.answers['0']; return answer && 'ids' in answer && answer.ids.includes(row.id);}).map(row => tr('career.workday.rowValue', {label: row.label, value: row.value})).join(' · ')}</dd></div>{savedDecision && <div><dt>{tr('career.workday.stage.decision')}</dt><dd>{savedDecision}</dd></div>}</dl>{source(false)}</details></div> : <>
      <header className="workday-heading"><div><p className="workday-eyebrow">{work.district}</p><h1 id={headingId} ref={heading} tabIndex={-1}>{work.title}</h1><p>{work.brief}</p></div><img src={art(work.speaker === 'sal' ? 'sal-teaching-v2.png' : `persona-${work.speaker}-avatar-v1.png`)} alt={tr('career.workday.speaker', {speaker: work.speaker})}/></header>
      {work.contextNote && <aside className="workday-context">{work.contextNote}</aside>}
      {work.step === 2 && work.decisionNote && <aside className="workday-context">{work.decisionNote}</aside>}
      <div className="workday-task">
        {work.step === 0 ? <><div className="workday-task-heading"><h2>{work.evidence.prompt}</h2><span aria-live="polite">{selected.length} / {count}</span></div><p className="workday-source-caption">{work.sourceTitle} · {work.sourceLabel}</p>{source(true)}</> : <>
          <button className="workday-sources-toggle" aria-expanded={sources} onClick={() => {setSources(!sources); props.onCue?.('paper');}}><img src={art('icons/career-comments.png')} alt=""/>{work.sourceTitle}<span aria-hidden="true">{sources ? '−' : '+'}</span></button>
          {sources && <><p className="workday-source-caption">{work.sourceLabel}</p>{source(false)}</>}
          {work.step === 1 ? <><h2>{work.decision.prompt}</h2>{work.decision.kind === 'number' ? <label className="workday-number"><span className="sr-only">{work.decision.unit ? tr('career.workday.answerIn', {kind: work.decision.unit === '$' ? 'dollars' : work.decision.unit === '%' ? 'percent' : 'other', unit: work.decision.unit}) : tr('career.workday.answer')}</span>{work.decision.unit === '$' && dollar.before ? <span aria-hidden="true">{dollar.before}</span> : null}<input value={number} inputMode="decimal" maxLength={18} placeholder="0" disabled={locked} onChange={event => {setNumber(event.target.value); setLocalError(false); setDismissedError(props.error);}}/>{work.decision.unit === '$' ? dollar.after ? <span aria-hidden="true">{dollar.after}</span> : null : work.decision.unit && <span aria-hidden="true">{work.decision.unit}</span>}</label>
            : <div className="workday-option-list" role="group" aria-label={tr('career.workday.chooseDecision')}>{work.decision.choices.map(item => <button className={`workday-choice${choice === item.id ? ' selected' : ''}`} aria-pressed={choice === item.id} disabled={locked} key={item.id} onClick={() => {setChoice(item.id); setLocalError(false); setDismissedError(props.error); props.onCue?.('select');}}><span>{item.label}</span><Pin selected={choice === item.id}/></button>)}</div>}
            {hintReady && <><button className="text-button workday-hint-toggle" aria-expanded={hint} aria-controls={hintId} onClick={() => setHint(!hint)}>{hint ? tr('career.workday.hideHint') : tr('career.workday.hint')}</button>{hint && <aside className="workday-hint" id={hintId}>{work.decision.hint}</aside>}</>}
          </> : <><div className="workday-task-heading"><h2>{work.file.prompt}</h2><span aria-live="polite">{selected.length} / {count}</span></div><p className="workday-task-copy">{tr('career.workday.chooseFacts', {count})}</p><div className="workday-option-list">{orderedParts.map(item => <button key={item.id} className={`workday-choice${selected.includes(item.id) ? ' selected' : ''}`} aria-pressed={selected.includes(item.id)} disabled={locked} onClick={() => toggle(item.id)}><span>{item.text}</span><Pin selected={selected.includes(item.id)}/></button>)}</div><div className="workday-note"><label htmlFor={noteId}>{tr('career.workday.note')} <span>{tr('career.workday.optional')}</span></label><textarea id={noteId} ref={noteInput} value={note} maxLength={280} rows={3} placeholder={tr('career.workday.notePlaceholder')} disabled={localBusy} onChange={event => changeNote(event.target.value)}/><div><span role="status">{draftStatus ? tr(DRAFT_STATUS[draftStatus]) : work.draft ? tr('career.workday.draft.saved') : ''}</span><span>{note.length} / 280</span></div></div></>}
        </>}
      </div>
    </>}
    {complete && retainedNote !== null && <aside className="workday-note-conflict workday-unfiled-note" aria-label={tr('career.workday.unsent')}><h3>{tr('career.workday.unsent')}</h3><p>{tr('career.workday.unsentBody')}</p><div><p>{retainedNote || tr('career.workday.removedNote')}</p></div><button className="text-button" onClick={() => {unfiledNote.current = null; setRetainedNote(null);}}>{tr('career.workday.discardEdits')}</button></aside>}
    {noteConflict && !complete && <aside className="workday-note-conflict" aria-label={tr('career.workday.conflictLabel')}><h3>{tr('career.workday.conflictTitle')}</h3><p>{tr('career.workday.conflictBody')}</p><div><strong>{tr('career.workday.savedNote')}</strong><p>{noteConflict.draft || tr('career.workday.noSavedNote')}</p></div><div className="workday-conflict-actions"><button className="secondary" disabled={locked} onClick={() => resolveNote(true)}>{tr('career.workday.useSaved')}</button><button className="text-button" disabled={locked} onClick={() => resolveNote(false)}>{tr('career.workday.keepMine')}</button></div></aside>}
    {((props.error != null && props.error !== dismissedError) || localError) && <p className="workday-error" id={errorId} role="alert">{workError(tr, props.error, work, choice)}</p>}
    {props.pending && <p className="workday-pending" role="status">{tr('career.workday.pending')}</p>}
    <footer className="workday-actions">{props.pending ? <button className="primary" disabled={localBusy || props.working} onClick={() => void recover()}>{localBusy || props.working ? tr('common.checking') : tr('career.workday.checkLastSave')}</button>
      : complete ? <button className="primary" onClick={() => void back()}>{tr('career.backToCareer')}</button>
      : <><button className="primary" disabled={!ready || locked || noteConflict !== null} onClick={() => void submit()}>{localBusy || props.working ? tr('career.saving') : work.step === 0 ? tr('career.workday.checkEvidence') : work.step === 1 ? tr('career.workday.sendDecision') : tr('career.workday.fileUpdate')}</button>{work.step === 2 && <span>{tr('career.workday.trimsWhenFiled', {count: reward})}</span>}</>}</footer>
    {leaveDialog && <div className="workday-dialog-backdrop"><div className="workday-leave-dialog" role="alertdialog" aria-modal="true" aria-labelledby={dialogId} onKeyDown={event => {if (event.key === 'Escape') {event.preventDefault(); decideLeave(false);} if (event.key === 'Tab') {event.preventDefault(); (document.activeElement === keepWriting.current ? leaveWithoutSaving.current : keepWriting.current)?.focus();}}}><h2 id={dialogId}>{retainedNote !== null ? tr('career.workday.leaveEditsTitle') : tr('career.workday.leaveNoteTitle')}</h2><p>{retainedNote !== null ? tr('career.workday.unsentBody') : tr('career.workday.leaveNoteBody')}</p><div><button className="primary" ref={keepWriting} onClick={() => decideLeave(false)}>{retainedNote !== null ? tr('career.workday.keepReading') : tr('career.workday.keepWriting')}</button><button className="text-button" ref={leaveWithoutSaving} onClick={() => decideLeave(true)}>{retainedNote !== null ? tr('career.workday.discardAndLeave') : tr('career.workday.leaveWithoutSaving')}</button></div></div></div>}
  </section>;
}
