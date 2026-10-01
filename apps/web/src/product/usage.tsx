import {createContext, useContext, useEffect, useMemo, useRef} from 'react';
import {getLocale} from '../i18n/runtime';
import {arrivalProps, ProductEvents, type OnboardingStep, type ProductEvent} from './product-events';
import {PracticeError} from './practice-client';

/**
 * Where the browser product records its usage events (see product-events.ts).
 * The production entry creates one recorder; tests and previews pass none,
 * and every call below is then a no-op.
 */
declare const __TRIMMY_WEB_VERSION__: string | undefined;
export const WEB_VERSION = typeof __TRIMMY_WEB_VERSION__ === 'string' ? __TRIMMY_WEB_VERSION__ : '0.1.0+local';
const OWN_HOSTS = ['app.trimmy.xyz', 'trimmy.xyz'];

export function createWebUsage(apiBase: string | null): ProductEvents | null {
  if (!apiBase) return null;
  try {return new ProductEvents({apiBase, appVersion: WEB_VERSION, locale: () => getLocale()});} catch {return null;}
}

const UsageContext = createContext<ProductEvents | null>(null);
export const UsageProvider = UsageContext.Provider;

export interface Usage {
  readonly recorder: ProductEvents | null;
  track(event: ProductEvent): void;
  /** At most once per browser (first-run steps), or once per session. */
  once(event: ProductEvent, options?: {perSession?: boolean}): void;
}
export function useUsage(): Usage {
  const recorder = useContext(UsageContext);
  return useMemo(() => ({
    recorder,
    track: event => {try {recorder?.track(event);} catch { /* Usage never breaks the product. */ }},
    once: (event, options) => {try {recorder?.once(event, options);} catch { /* Usage never breaks the product. */ }},
  }), [recorder]);
}

/** The first-day screens, as the step names the API counts. */
export function onboardingStep(screen: {journey: string | null; intro: string | null; home: boolean}): OnboardingStep | null {
  if (screen.home) return 'home';
  switch (screen.journey) {
    case 'celebration': return 'celebration';
    case 'gate': return 'gate';
    case 'reminders': return 'reminders';
    case 'money': return 'next_move';
  }
  switch (screen.intro) {
    case 'welcome': return 'welcome';
    case 'note': return 'note';
    case 'practice': return 'first_trade';
    case 'review': return 'review';
    case 'receipt': return 'first_order';
  }
  return null;
}

/** Which part of starting up a desk failed, from the error the desk shows. */
export function startupStage(error: unknown): UsageState['failed'] {
  if (error === null || error === undefined) return null;
  const code = error instanceof PracticeError ? error.code : '';
  if (code === 'PRACTICE_NETWORK_ERROR' || code === 'PRACTICE_TIMEOUT') return 'network';
  if (code.startsWith('GUEST_') || code.includes('_GUEST_')) return 'guest';
  if (code.includes('PROFILE')) return 'profile';
  if (code.includes('ACCOUNT')) return 'sign_in';
  return 'unknown';
}

type Tab = 'desk' | 'market' | 'career' | 'profile';
export interface UsageState {
  readonly page: string;
  readonly step: OnboardingStep | null;
  readonly workday: {readonly ordinal: number; readonly resumed: boolean} | null;
  readonly waiting: string | null;
  readonly fastBuy: boolean; readonly addMoney: boolean; readonly send: boolean;
  readonly real: boolean;
  readonly failed: 'network' | 'guest' | 'profile' | 'sign_in' | 'unknown' | null;
  /** The desk in use, to tie this browser to it, with its Authorization header. */
  readonly desk: {readonly key: string; readonly authorization: () => Promise<string | null>} | null;
}

/** Records what the workspace shows as it changes: one place instead of every button. */
export function useUsageObserver(state: UsageState): void {
  const usage = useUsage();
  const previous = useRef<UsageState | null>(null);
  useEffect(() => {
    if (!usage.recorder) return;
    usage.track(arrivalProps(window.location.href, document.referrer, OWN_HOSTS));
    const visible = () => {if (document.visibilityState === 'visible') usage.recorder?.resumed();};
    const leaving = () => {if (document.visibilityState === 'hidden') void usage.recorder?.flush();};
    document.addEventListener('visibilitychange', visible); document.addEventListener('visibilitychange', leaving);
    return () => {document.removeEventListener('visibilitychange', visible); document.removeEventListener('visibilitychange', leaving);};
  }, [usage]);
  useEffect(() => {
    if (!usage.recorder) return;
    const before = previous.current; previous.current = state;
    if (state.page !== before?.page && ['desk', 'market', 'career', 'profile'].includes(state.page)) usage.track({name: 'tab_view', props: {tab: state.page as Tab}});
    if (state.step && state.step !== before?.step) usage.once({name: 'onboarding_step', props: {step: state.step}});
    if (state.workday && (state.workday.ordinal !== before?.workday?.ordinal || before?.page !== 'work')) {
      usage.track({name: 'workday_open', props: state.workday});
    }
    if (state.waiting && state.waiting !== before?.waiting && (state.waiting === 'tomorrow' || state.waiting === 'closed' || state.waiting === 'done')) {
      usage.once({name: 'workday_waiting', props: {state: state.waiting}}, {perSession: true});
    }
    if (state.fastBuy && !before?.fastBuy) usage.track({name: 'money_action', props: {action: 'fast_buy_open'}});
    if (state.addMoney && !before?.addMoney) usage.track({name: 'money_action', props: {action: 'add_money_open'}});
    if (state.send && !before?.send) usage.track({name: 'money_action', props: {action: 'send_open'}});
    if (before && state.real !== before.real) usage.track({name: 'mode_switch', props: {to: state.real ? 'real' : 'practice'}});
    if (state.failed && state.failed !== before?.failed) usage.once({name: 'startup_failed', props: {stage: state.failed}}, {perSession: true});
    if (state.desk && state.desk.key !== before?.desk?.key) void usage.recorder.link(state.desk.key, state.desk.authorization);
  });
}
