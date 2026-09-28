/**
 * Operator alerts to a chat webhook (Slack or Discord) when
 * TRIMMY_ALERT_WEBHOOK_URL is set. Without it nothing is sent.
 *
 * Each kind is sent at most once per window; what happens in between is counted
 * and sent when the window ends. Details are route names, codes, token symbols
 * and order ids only: never a user, wallet, amount, credential or provider text.
 */
export type AlertKind = 'server_error' | 'order_failed' | 'order_not_executed' | 'token_sweep_failed' | 'process_error';

const LABELS: Readonly<Record<AlertKind, string>> = Object.freeze({
  server_error: 'Server error',
  order_failed: 'Real-money order failed on chain',
  order_not_executed: 'Signed real-money order was never executed',
  token_sweep_failed: 'Token sweep failing; the Market is going stale',
  process_error: 'Unhandled error in the API process',
});

export interface OpsAlertsOptions {
  readonly url: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly windowMs?: number;
  readonly service?: string;
}

export class OpsAlerts {
  readonly #url: URL;
  readonly #fetch: typeof globalThis.fetch;
  readonly #now: () => number;
  readonly #windowMs: number;
  readonly #service: string;
  readonly #kinds = new Map<AlertKind, {sentAt: number; held: number; lastDetail: string; timer: ReturnType<typeof setTimeout> | null}>();

  constructor(options: OpsAlertsOptions) {
    const url = new URL(options.url);
    if (url.protocol !== 'https:' || url.username || url.password) throw new Error('TRIMMY_ALERT_WEBHOOK_URL must be an https URL');
    this.#url = url;
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#now = options.now ?? Date.now;
    this.#windowMs = options.windowMs ?? 10 * 60_000;
    this.#service = options.service ?? 'trimmy-api';
  }

  /** Never throws and never waits: an alert must not slow or break a request. */
  notify(kind: AlertKind, detail: string): void {
    const clean = detail.replace(/[^\w .:/@#()-]/gu, '').slice(0, 200);
    const now = this.#now();
    const state = this.#kinds.get(kind);
    if (state && now - state.sentAt < this.#windowMs) {
      state.held += 1;
      state.lastDetail = clean;
      state.timer ??= setTimeout(() => this.#flush(kind), state.sentAt + this.#windowMs - now);
      state.timer.unref?.();
      return;
    }
    this.#kinds.set(kind, {sentAt: now, held: 0, lastDetail: clean, timer: state?.timer ?? null});
    this.#send(kind, clean, 0);
  }

  #flush(kind: AlertKind): void {
    const state = this.#kinds.get(kind);
    if (!state) return;
    state.timer = null;
    if (state.held === 0) return;
    const held = state.held;
    state.held = 0;
    state.sentAt = this.#now();
    this.#send(kind, state.lastDetail, held);
  }

  #send(kind: AlertKind, detail: string, more: number): void {
    const text = `[${this.#service}] ${LABELS[kind]}: ${detail}${more ? ` (and ${more} more in the last ${Math.round(this.#windowMs / 60_000)} min)` : ''}`;
    const host = this.#url.hostname;
    const body = host === 'hooks.slack.com' ? {text} : host.endsWith('discord.com') || host.endsWith('discordapp.com')
      ? {content: text, allowed_mentions: {parse: []}} : {text, content: text};
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 5_000);
    timer.unref?.();
    void this.#fetch(this.#url, {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify(body),
      signal: abort.signal, redirect: 'error'}).catch(() => undefined).finally(() => clearTimeout(timer));
  }
}

export function readOpsAlerts(env: NodeJS.ProcessEnv, fetch?: typeof globalThis.fetch): OpsAlerts | undefined {
  const url = env['TRIMMY_ALERT_WEBHOOK_URL'];
  if (!url) return undefined;
  return new OpsAlerts({url, ...(fetch ? {fetch} : {})});
}
