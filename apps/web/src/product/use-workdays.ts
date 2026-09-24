import {useCallback, useEffect, useRef, useState} from 'react';
import {PracticeError, type WorkdayAssignment, type WorkdayJourney, type WorkdayAnswer} from './practice-client';
import type {PracticeSession} from './practice-session';

export type WorkAnswer = WorkdayAnswer;

/** The server owns steps, drafts and completion. Reads never advance the journey. */
export function useWorkdays(session: PracticeSession | null, enabled: boolean, page: string, onCompleted: () => Promise<void>) {
  const [journey, setJourney] = useState<WorkdayJourney | null>(null);
  const [loading, setLoading] = useState(false), [working, setWorking] = useState(false);
  const [error, setError] = useState<unknown>(null), [readError, setReadError] = useState<unknown>(null);
  const current = useRef<WorkdayJourney | null>(null);
  const lifecycle = useRef(0), readEpoch = useRef(0), mounted = useRef(false);
  const request = useRef<AbortController | null>(null), queue = useRef<Promise<unknown>>(Promise.resolve());
  const outstanding = useRef(0);
  // Only this hook's acknowledged draft writes may rebase an already queued action.
  const localDraftRevisions = useRef(new Map<string, Map<number, number>>());
  const accept = useCallback((next: WorkdayJourney) => {
    const previous = current.current;
    if (previous?.contentVersion === next.contentVersion && next.assignments.some(item => {
      const old = previous.assignments.find(row => row.id === item.id);
      return old && old.revision > item.revision;
    })) return;
    current.current = next; setJourney(next);
  }, []);
  const refresh = useCallback(async () => {
    if (!session || !enabled || !mounted.current || outstanding.current) return;
    const life = lifecycle.current, epoch = ++readEpoch.current;
    request.current?.abort();
    const controller = new AbortController(); request.current = controller; setLoading(true);
    try {
      const next = await session.readWorkdays(controller.signal);
      if (!mounted.current || lifecycle.current !== life || readEpoch.current !== epoch || controller.signal.aborted) return;
      accept(next); setReadError(null);
    } catch (reason) {
      if (mounted.current && lifecycle.current === life && readEpoch.current === epoch && !controller.signal.aborted) setReadError(reason);
    } finally {
      if (mounted.current && lifecycle.current === life && readEpoch.current === epoch) setLoading(false);
    }
  }, [session, enabled, accept]);

  useEffect(() => {
    mounted.current = true; ++lifecycle.current;
    current.current = null; setJourney(null); setError(null); setReadError(null); setLoading(false); setWorking(false);
    outstanding.current = 0; queue.current = Promise.resolve(); localDraftRevisions.current.clear();
    return () => {mounted.current = false; ++lifecycle.current; ++readEpoch.current; request.current?.abort();};
  }, [session, enabled]);
  useEffect(() => {
    if (!enabled || !['desk', 'career', 'profile', 'work', 'daily'].includes(page)) return;
    const resume = () => {if (!document.hidden && navigator.onLine) void refresh();};
    resume();
    const timer = window.setInterval(resume, 30000);
    window.addEventListener('focus', resume); window.addEventListener('online', resume); document.addEventListener('visibilitychange', resume);
    return () => {clearInterval(timer); window.removeEventListener('focus', resume); window.removeEventListener('online', resume); document.removeEventListener('visibilitychange', resume);};
  }, [enabled, page, refresh]);

  const write = useCallback((operation: {kind: 'step'; assignment: WorkdayAssignment; answer: WorkAnswer; draft?: string} |
    {kind: 'draft'; assignment: WorkdayAssignment; draft: string} | {kind: 'recover'}): Promise<boolean> => {
    if (!session || !enabled || !mounted.current) return Promise.resolve(false);
    const life = lifecycle.current;
    outstanding.current++; setWorking(true); setError(null); setLoading(false);
    ++readEpoch.current; request.current?.abort();
    const valid = () => mounted.current && lifecycle.current === life;
    const task = async () => {
      if (!valid()) return false;
      let completed = operation.kind === 'recover';
      try {
        let next: WorkdayJourney | null;
        if (operation.kind === 'recover') next = await session.retryPendingWorkday();
        else {
          if (session.pendingWorkdayMutation) throw new PracticeError('PRACTICE_WORKDAY_PENDING', 'An earlier save needs checking.');
          const original = operation.assignment;
          const latest = current.current?.assignments.find(item => item.id === original.id);
          if (!latest || latest.step !== original.step) throw new PracticeError('WORK_CHANGED', 'Your work changed on another screen. Review the latest saved step.');
          let revision = original.revision;
          const chain = localDraftRevisions.current.get(original.id);
          while (chain?.has(revision)) revision = chain.get(revision)!;
          if (revision !== latest.revision) throw new PracticeError('WORK_CHANGED', 'Your work changed on another screen. Review the latest saved step.');
          if (operation.kind === 'draft') {
            if (latest.draft === operation.draft) return true;
            next = await session.saveWorkdayDraft(latest, operation.draft);
            if (!valid()) return false;
            const saved = next.assignments.find(item => item.id === latest.id);
            if (saved && saved.step === latest.step && saved.revision > latest.revision) {
              const revisions = chain ?? new Map<number, number>();
              revisions.set(latest.revision, saved.revision); localDraftRevisions.current.set(latest.id, revisions);
            }
          } else {
            next = await session.saveWorkdayStep(latest, operation.answer, operation.draft === undefined ? {} : {draft: operation.draft});
            if (!valid()) return false;
            completed = latest.step === 2;
            localDraftRevisions.current.delete(latest.id);
          }
        }
        if (!valid()) return false;
        if (next) accept(next);
        setError(null);
        if (completed) {try {await onCompleted();} catch { /* A summary failure cannot undo confirmed work. */ }}
        return valid();
      } catch (reason) {
        if (valid()) setError(reason);
        return false;
      } finally {
        if (valid()) {
          outstanding.current--;
          if (!outstanding.current) {setWorking(false); void refresh();}
        }
      }
    };
    const result = queue.current.then(task, task); queue.current = result;
    return result;
  }, [session, enabled, accept, onCompleted, refresh]);
  return {journey, loading, working, error: error ?? readError, readError, refresh, pending: session?.pendingWorkdayMutation ?? null,
    saveStep: (assignment: WorkdayAssignment, answer: WorkAnswer, draft?: string) => write({kind: 'step', assignment, answer, ...(draft === undefined ? {} : {draft})}),
    saveDraft: (assignment: WorkdayAssignment, draft: string) => write({kind: 'draft', assignment, draft}),
    recover: () => write({kind: 'recover'})};
}
export type WorkdaysState = ReturnType<typeof useWorkdays>;
