import {useEffect, useRef, useState} from 'react';
import {PendingMutations, ambiguous, careerApi, newMutationId} from './career-actions.js';
import type {DayContext, DayContextWrite} from './career-actions.js';
import type {ProductApiClient, ProductIdentity} from './product-api.js';
import type {JourneyPrincipal} from './journey-store.js';

/** The browser's IANA zone, or null. Raw offsets and 'UTC' aliases are not calendar zones. */
export function browserTimeZone(): string | null {
  try {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    return typeof zone === 'string' && zone.length <= 100 && /^(?:[A-Za-z][A-Za-z0-9_+-]*)(?:\/[A-Za-z0-9_+-]+)+$/u.test(zone) ? zone : null;
  } catch {return null;}
}
/** Mobile's careerDayRefreshDelay: two seconds after the next Career day, or fifteen minutes. */
export function careerDayRefreshDelay(now: number, nextDayAt: string | null): number {
  const fallback = 15 * 60_000;
  const target = nextDayAt ? Date.parse(nextDayAt) + 2000 : Number.NaN;
  return Number.isFinite(target) && target > now ? Math.min(target - now, 36 * 3_600_000) : fallback;
}

/**
 * Server-owned Career calendar for web-first desks. Like mobile, the automatic
 * write only configures a fresh record with this browser's zone; a configured
 * record is never changed. An ambiguous write keeps its mutation ID for a retry.
 */
export function useCareerDayContext(options: {
  api: ProductApiClient | null; identity: ProductIdentity | null; principal: JourneyPrincipal | null; pending: PendingMutations | null;
  enabled: boolean; onConfigured: () => void; onNewDay: () => void;
}) {
  const {api, identity, principal, pending, enabled} = options;
  const [context, setContext] = useState<DayContext | null>(null);
  const callbacks = useRef(options); callbacks.current = options;
  // The guest record object changes after unrelated saves; the principal is the stable identity.
  const hasIdentity = identity !== null;
  useEffect(() => {
    const identity = callbacks.current.identity;
    if (!enabled || !api || !identity || !principal || !pending) {setContext(null); return;}
    const bound: ProductIdentity = identity;
    let active = true, timer: ReturnType<typeof setTimeout> | null = null;
    const controller = new AbortController();
    const schedule = (next: DayContext | null) => {
      if (!active) return;
      timer = setTimeout(() => {if (active) {callbacks.current.onNewDay(); void sync();}}, careerDayRefreshDelay(Date.now(), next?.nextDayAt ?? null));
    };
    async function sync() {
      let current: DayContext | null = null;
      try {
        current = await careerApi.readDayContext(api!, callbacks.current.identity ?? bound, controller.signal);
        if (!active) return;
        setContext(current);
        if (current.configured) {pending!.clear('day-context', principal!); return;}
        const zone = browserTimeZone();
        if (!zone) return;
        const saved = pending!.read<DayContextWrite>('day-context', principal!);
        const body: DayContextWrite = saved && saved.timeZone === zone && saved.baseRevision === current.revision ? saved
          : {schemaVersion: 1, mutationId: newMutationId(), baseRevision: current.revision, timeZone: zone};
        if (body !== saved) pending!.save('day-context', principal!, body);
        try {
          current = await careerApi.saveDayContext(api!, callbacks.current.identity ?? bound, body, controller.signal);
          pending!.clear('day-context', principal!);
          if (active) {setContext(current); callbacks.current.onConfigured();}
        } catch (error) {if (!ambiguous(error)) pending!.clear('day-context', principal!);}
      } catch { /* Career keeps working on the server's default day; the next sync retries. */ }
      finally {schedule(current);}
    }
    void sync();
    return () => {active = false; controller.abort(); if (timer) clearTimeout(timer);};
  }, [enabled, api, hasIdentity, principal, pending]);
  return context;
}
