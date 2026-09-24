import {useCallback, useEffect, useRef, useState} from 'react';
import type {CareerActivityWeek, DailyDeskShift} from './practice-client';
import type {PracticeSession} from './practice-session';

export function useProgress(session: PracticeSession | null, enabled: boolean, page: string, onCompleted: () => Promise<void>, dailyEnabled = true) {
  const [shift, setShift] = useState<DailyDeskShift | null>(null);
  const [week, setWeek] = useState<CareerActivityWeek | null>(null);
  const [loading, setLoading] = useState(false);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [weekError, setWeekError] = useState<unknown>(null);
  const epoch = useRef(0), active = useRef(false), writing = useRef(false);
  const request = useRef<AbortController | null>(null);
  const refresh = useCallback(async () => {
    if (!session || !enabled || !active.current || writing.current) return;
    const turn = ++epoch.current;
    request.current?.abort();
    const controller = new AbortController(); request.current = controller;
    setLoading(true);
    const [daily, activity] = await Promise.allSettled([dailyEnabled ? session.readDailyDesk(controller.signal) : Promise.resolve(null), session.readActivityWeek(controller.signal)]);
    if (!active.current || turn !== epoch.current || controller.signal.aborted) return;
    if (daily.status === 'fulfilled') {setShift(daily.value); setError(null);} else setError(daily.reason);
    if (activity.status === 'fulfilled') {setWeek(activity.value); setWeekError(null);} else setWeekError(activity.reason);
    setLoading(false);
  }, [session, enabled, dailyEnabled]);
  useEffect(() => {
    active.current = true;
    if (!enabled) {setShift(null); setWeek(null); setError(null); setWeekError(null);}
    return () => {active.current = false; ++epoch.current; request.current?.abort();};
  }, [session, enabled]);
  useEffect(() => {
    if (!enabled || !['desk', 'career', 'profile', 'daily', 'work'].includes(page)) return;
    const resume = () => {if (!document.hidden && navigator.onLine && !writing.current) void refresh();};
    resume();
    const timer = window.setInterval(resume, 30000);
    window.addEventListener('focus', resume); window.addEventListener('online', resume); document.addEventListener('visibilitychange', resume);
    return () => {clearInterval(timer); window.removeEventListener('focus', resume); window.removeEventListener('online', resume); document.removeEventListener('visibilitychange', resume);};
  }, [enabled, page, refresh]);
  const submit = async (choice: string | null) => {
    if (!session || !enabled || writing.current || (!choice && !session.pendingDailyDesk) || (choice && !shift)) return false;
    writing.current = true; setWorking(true); setError(null); ++epoch.current; request.current?.abort(); setLoading(false);
    try {
      const confirmed = choice ? await session.completeDailyDesk(shift!, choice) : await session.retryPendingDailyDesk();
      if (!active.current) return false;
      if (confirmed) setShift(confirmed);
      await onCompleted();
      return true;
    } catch (reason) {if (active.current) setError(reason); return false;}
    finally {
      writing.current = false;
      if (active.current) {setWorking(false); void refresh();}
    }
  };
  return {shift, week, loading, working, error, weekError, refresh,
    pending: session?.pendingDailyDesk ?? null,
    complete: (choice: string) => submit(choice), recover: () => submit(null)};
}

export type ProgressState = ReturnType<typeof useProgress>;
