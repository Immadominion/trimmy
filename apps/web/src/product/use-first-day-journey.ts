import {useCallback, useMemo, useRef, useState} from 'react';
import {PracticeError} from './practice-client.js';
import type {CareerSummary, ProductProfile} from './practice-client.js';
import type {PracticeSession, PracticeStorage} from './practice-session.js';
import {JourneyStore, journeyPrincipal} from './journey-store.js';
import type {JourneyPrincipal, ReminderChoice, SignInIntent} from './journey-store.js';
import {firstTradeEvidence, journeyView} from './journey.js';

export interface FirstDayJourneyOptions {
  readonly apiBase: string | null; readonly storage: PracticeStorage;
  readonly session: PracticeSession | null; readonly accountId: string | null;
  /** undefined until the server profile has been read once. */
  readonly profile: ProductProfile | null | undefined; readonly career: CareerSummary | null;
  readonly guestDisposition: 'claimed' | 'none' | 'preserved' | null;
  readonly restoreGuest: () => Promise<unknown>; readonly refresh: () => Promise<void>;
  /** False once this workspace (identity epoch) has been replaced. */
  readonly active: () => boolean;
}

/**
 * Binds the pure first-day rules to this workspace's session and browser
 * storage. Every server write goes through PracticeSession's durable launch
 * command; local steps are written before the server checkpoint moves.
 */
export function useFirstDayJourney(options: FirstDayJourneyOptions) {
  const {apiBase, storage, session, accountId, profile, career} = options;
  const store = useMemo(() => {
    if (!apiBase) return null;
    try {return new JourneyStore(storage, apiBase);} catch {return null;}
  }, [apiBase, storage]);
  const [, setRevision] = useState(0);
  const bump = useCallback(() => setRevision(value => value + 1), []);
  const gateOpen = useRef(false);
  const latest = useRef(options); latest.current = options;
  const guest = session?.guest ?? null;
  const principal: JourneyPrincipal | null = !session?.hasIdentity ? null
    : session.isAccount ? (accountId ? journeyPrincipal({accountId}) : null) : guest ? journeyPrincipal({guestId: guest.guestId}) : null;
  const evidence = firstTradeEvidence(career, session?.lastReceipt ?? null);
  const identity = !session?.hasIdentity ? 'none' : session.isAccount ? 'account' : 'guest';
  const view = journeyView({identity, profile, evidence,
    guestChosen: store?.guestChosen() ?? false, gateOpen: gateOpen.current,
    step: principal && store ? store.step(principal) : null, celebratedOrder: store?.celebratedOrder() ?? null});
  // Mobile's `_entryAccountGateOpen`: only the guest choice or a sign-in closes an open gate.
  if (view.kind === 'gate') gateOpen.current = true;
  const preservedNotice = identity === 'account' && options.guestDisposition === 'preserved' && principal !== null &&
    store !== null && !store.preservedNoticeSeen(principal);

  const chooseGuest = useCallback(async () => {
    if (!store) throw new Error('Your choice could not be saved in this browser.');
    store.chooseGuest(); gateOpen.current = false; bump();
  }, [store, bump]);

  /** Records the celebrated order, then moves the server checkpoint once. Never buys again. */
  const continueAfterCelebration = useCallback(async (orderId: string) => {
    const {session: current, restoreGuest, refresh, active} = latest.current;
    if (!current || !store) throw new Error('Practice unavailable');
    await restoreGuest();
    if (!active()) return;
    const owner = current.isAccount ? (latest.current.accountId ? journeyPrincipal({accountId: latest.current.accountId}) : null)
      : current.guest ? journeyPrincipal({guestId: current.guest.guestId}) : null;
    if (!owner) throw new Error('Practice unavailable');
    store.acknowledgeCelebration(owner, orderId); bump();
    const saved = await current.ensureProfile();
    if (!active()) return;
    if (saved.launchCheckpoint === 'first-trade') {
      try {await current.advanceLaunch('paper-trade-confirmed');}
      catch (error) {
        // An exact replay or another tab may already have moved on; only a real stop is an error.
        if (!(error instanceof PracticeError && error.code === 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT')) throw error;
        const reread = await current.readProfile();
        if (!reread || reread.launchCheckpoint === 'first-trade') throw error;
      }
    }
    if (active()) await refresh();
  }, [store, bump]);

  const saveReminder = useCallback(async (choice: ReminderChoice) => {
    if (!store || !principal) throw new Error('Your choice could not be saved in this browser.');
    store.saveReminder(principal, choice); bump();
  }, [store, principal, bump]);
  const reminderDone = useCallback(async () => {
    if (!store || !principal) throw new Error('Your choice could not be saved in this browser.');
    store.setStep(principal, 2); bump();
  }, [store, principal, bump]);
  const acknowledgePreserved = useCallback(() => {if (store && principal) {store.acknowledgePreservedNotice(principal); bump();}}, [store, principal, bump]);
  const setSignInIntent = useCallback((intent: SignInIntent | null) => store?.setSignInIntent(intent), [store]);
  const consumeSignInIntent = useCallback(() => store?.consumeSignInIntent() ?? null, [store]);
  const forgetGuestChoice = useCallback(() => store?.forgetGuestChoice(), [store]);

  return {store, view, principal, evidence, preservedNotice,
    reminder: principal && store ? store.reminder(principal) : null,
    chooseGuest, continueAfterCelebration, saveReminder, reminderDone, acknowledgePreserved,
    setSignInIntent, consumeSignInIntent, forgetGuestChoice, refreshView: bump};
}
export type FirstDayJourney = ReturnType<typeof useFirstDayJourney>;
