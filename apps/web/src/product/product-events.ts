/**
 * First-party usage events for the browser product (API migration 0039).
 *
 * Records a few allowlisted moments with a random per-browser install id and a
 * session id. Never an account id, name, email, amount or free text: the names
 * and property values below are the only ones the API accepts. Events wait in
 * this browser (at most 200, at most 6 days) and are sent in small batches.
 * Turning "Share usage data" off stops recording and forgets anything unsent.
 */
export type ProductEventProps = Readonly<Record<string, string | number | boolean>>;
export type OnboardingStep = 'welcome' | 'note' | 'first_trade' | 'review' | 'first_order' | 'celebration' | 'gate' | 'reminders' | 'next_move' | 'home';
export type ProductEvent =
  | {readonly name: 'app_open'; readonly props: {readonly source: 'launch' | 'resume' | 'reminder' | 'push' | 'link'; readonly referrer?: string;
      readonly utm_source?: string; readonly utm_medium?: string; readonly utm_campaign?: string}}
  | {readonly name: 'onboarding_step' | 'onboarding_skip'; readonly props: {readonly step: OnboardingStep}}
  | {readonly name: 'gate_choice'; readonly props: {readonly choice: 'guest' | 'email' | 'google' | 'apple' | 'x'}}
  | {readonly name: 'reminder_choice'; readonly props: {readonly frequency: 'daily' | 'occasional' | 'off'; readonly permission: 'granted' | 'denied' | 'not_asked'}}
  | {readonly name: 'push_opt_in'; readonly props: {readonly enabled: boolean; readonly permission: 'granted' | 'denied' | 'not_asked'}}
  | {readonly name: 'tab_view'; readonly props: {readonly tab: 'desk' | 'market' | 'career' | 'profile'}}
  | {readonly name: 'workday_open'; readonly props: {readonly ordinal: number; readonly resumed: boolean}}
  | {readonly name: 'workday_waiting'; readonly props: {readonly state: 'tomorrow' | 'closed' | 'done'}}
  | {readonly name: 'mode_switch'; readonly props: {readonly to: 'real' | 'practice'}}
  | {readonly name: 'money_action'; readonly props: {readonly action: 'add_money_open' | 'wallet_create_start' | 'send_open' | 'fast_buy_open'}}
  | {readonly name: 'language_set'; readonly props: {readonly language: 'browser' | 'en' | 'es-419' | 'pt-BR' | 'fr'}}
  | {readonly name: 'startup_failed'; readonly props: {readonly stage: 'network' | 'guest' | 'profile' | 'sign_in' | 'unknown'}};

interface QueuedEvent {
  readonly id: string; readonly installId: string; readonly sessionId: string; readonly platform: 'web';
  readonly appVersion: string; readonly locale: string; readonly name: string; readonly props: ProductEventProps; readonly occurredAt: string;
}
export interface ProductEventsStorage {getItem(key: string): string | null; setItem(key: string, value: string): void; removeItem(key: string): void}
export interface ProductEventsOptions {
  readonly apiBase: string;
  readonly appVersion: string;
  /** The language the app is showing, as a BCP 47 tag. */
  readonly locale: () => string;
  /** The Authorization header value for linking this browser to the desk using it, or null when signed out. */
  readonly authorization?: () => Promise<string | null>;
  readonly fetch?: typeof fetch;
  readonly storage?: ProductEventsStorage | null;
  readonly now?: () => number;
  readonly uuid?: () => string;
  readonly schedule?: (callback: () => void, ms: number) => unknown;
}

const INSTALL_KEY = 'trimmy.install.v1', QUEUE_KEY = 'trimmy.events.queue.v1', OPT_OUT_KEY = 'trimmy.events.optOut.v1', ONCE_KEY = 'trimmy.events.once.v1';
const MAX_QUEUE = 200, BATCH = 50, MAX_AGE_MS = 6 * 86_400_000, SESSION_IDLE_MS = 30 * 60_000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const TOKEN = /^[a-z0-9][a-z0-9._-]{0,39}$/;

/** A token the API accepts (lowercase, short), or undefined. */
export function eventToken(value: string | null | undefined): string | undefined {
  const token = value?.trim().toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^[^a-z0-9]+/, '').slice(0, 40).replace(/[._-]+$/, '');
  return token && TOKEN.test(token) ? token : undefined;
}

/** Where a visit came from, from the page URL and referrer, as API tokens. */
export function arrivalProps(url: string, referrer: string, ownHosts: readonly string[] = []): ProductEvent & {name: 'app_open'} {
  let params: URLSearchParams | null = null, host: string | undefined;
  try {params = new URL(url).searchParams;} catch { /* no URL, no campaign */ }
  try {const ref = referrer ? new URL(referrer).hostname.replace(/^www\./, '') : ''; host = ref && !ownHosts.includes(ref) ? eventToken(ref) : undefined;} catch { /* malformed referrer */ }
  const campaign = {utm_source: eventToken(params?.get('utm_source')), utm_medium: eventToken(params?.get('utm_medium')), utm_campaign: eventToken(params?.get('utm_campaign'))};
  const linked = Object.values(campaign).some(Boolean) || Boolean(host);
  const props = Object.fromEntries(Object.entries({source: linked ? 'link' : 'launch', referrer: host, ...campaign}).filter(([, value]) => value !== undefined));
  return {name: 'app_open', props: props as (ProductEvent & {name: 'app_open'})['props']};
}

export class ProductEvents {
  readonly #options: ProductEventsOptions; readonly #storage: ProductEventsStorage | null;
  readonly #now: () => number; readonly #uuid: () => string; readonly #fetch: typeof fetch;
  #queue: QueuedEvent[] = []; #sessionId: string; #lastActivity: number; #enabled: boolean;
  #sending: Promise<void> | null = null; #backoffMs = 0; #timer = false; #seen = new Set<string>(); #linkedTo: string | null = null;

  constructor(options: ProductEventsOptions) {
    this.#options = options;
    this.#storage = options.storage === undefined ? safeLocalStorage() : options.storage;
    this.#now = options.now ?? Date.now;
    this.#uuid = options.uuid ?? (() => crypto.randomUUID());
    this.#fetch = options.fetch ?? ((...args) => fetch(...args));
    this.#enabled = this.#read(OPT_OUT_KEY) !== 'true';
    this.#sessionId = this.#uuid(); this.#lastActivity = this.#now();
    if (this.#enabled) this.#queue = this.#loadQueue();
  }

  get enabled(): boolean {return this.#enabled;}
  get installId(): string {
    const saved = this.#read(INSTALL_KEY);
    if (saved && UUID.test(saved)) return saved;
    const fresh = this.#uuid(); this.#write(INSTALL_KEY, fresh); return fresh;
  }

  /** Records an event. A new session starts after 30 minutes without one. */
  track(event: ProductEvent): void {
    if (!this.#enabled) return;
    const now = this.#now();
    if (now - this.#lastActivity > SESSION_IDLE_MS) this.#sessionId = this.#uuid();
    this.#lastActivity = now;
    const props = Object.fromEntries(Object.entries(event.props).filter(([, value]) => value !== undefined)) as ProductEventProps;
    this.#queue.push({id: this.#uuid(), installId: this.installId, sessionId: this.#sessionId, platform: 'web', appVersion: this.#options.appVersion,
      locale: this.#options.locale(), name: event.name, props, occurredAt: new Date(now).toISOString()});
    if (this.#queue.length > MAX_QUEUE) this.#queue.splice(0, this.#queue.length - MAX_QUEUE);
    this.#saveQueue();
    if (this.#queue.length >= 20) void this.flush(); else this.#arm();
  }

  /** Records an event at most once per browser (first-run steps), or per session with `perSession`. */
  once(event: ProductEvent, {perSession = false}: {perSession?: boolean} = {}): void {
    const key = `${event.name}:${JSON.stringify(event.props)}`;
    if (perSession) {const sessionKey = `${this.#sessionId}:${key}`; if (this.#seen.has(sessionKey)) return; this.#seen.add(sessionKey); this.track(event); return;}
    const done = new Set<string>(this.#readJson(ONCE_KEY, []));
    if (done.has(key)) return;
    done.add(key); this.#write(ONCE_KEY, JSON.stringify([...done].slice(-100)));
    this.track(event);
  }

  /** Back after 30 minutes away: a new session that starts with an app_open. */
  resumed(): void {
    if (this.#enabled && this.#now() - this.#lastActivity > SESSION_IDLE_MS) this.track({name: 'app_open', props: {source: 'resume'}});
  }

  /** Turns recording on or off. Off forgets every unsent event and the first-run marks. */
  setEnabled(enabled: boolean): void {
    this.#enabled = enabled;
    this.#write(OPT_OUT_KEY, enabled ? 'false' : 'true');
    if (!enabled) {this.#queue = []; this.#remove(QUEUE_KEY); this.#remove(ONCE_KEY); this.#linkedTo = null;}
  }

  /**
   * Ties this browser to the desk now using it, once per desk per page load.
   * `authorization` gives that desk's header when it differs from the default.
   */
  async link(deskKey: string, authorization = this.#options.authorization): Promise<void> {
    if (!this.#enabled || this.#linkedTo === deskKey || !authorization) return;
    const header = await authorization().catch(() => null);
    if (!header) return;
    try {
      const response = await this.#fetch(`${this.#options.apiBase}/v1/events/link`, {method: 'POST', credentials: 'omit', cache: 'no-store',
        headers: {'Content-Type': 'application/json', Accept: 'application/json', Authorization: header},
        body: JSON.stringify({schemaVersion: 1, installId: this.installId})});
      if (response.status === 204) this.#linkedTo = deskKey;
    } catch { /* Linking is retried on the next desk change or page load. */ }
  }

  /** Sends what is waiting, in batches. Never throws. */
  flush(): Promise<void> {
    if (this.#sending) return this.#sending;
    this.#sending = this.#send().finally(() => {this.#sending = null;});
    return this.#sending;
  }

  async #send(): Promise<void> {
    this.#dropStale();
    while (this.#enabled && this.#queue.length) {
      const batch = this.#queue.slice(0, BATCH);
      let response: Response;
      try {
        response = await this.#fetch(`${this.#options.apiBase}/v1/events`, {method: 'POST', credentials: 'omit', cache: 'no-store',
          headers: {'Content-Type': 'application/json', Accept: 'application/json'}, body: JSON.stringify({schemaVersion: 1, events: batch})});
      } catch {response = new Response(null, {status: 599});}
      if (response.status === 202 || response.status === 400) {
        // 400 means this batch can never be accepted (an app out of step with the catalog): drop it rather than retry forever.
        const sent = new Set(batch.map(item => item.id));
        this.#queue = this.#queue.filter(item => !sent.has(item.id)); this.#saveQueue(); this.#backoffMs = 0;
        continue;
      }
      this.#backoffMs = Math.min(600_000, this.#backoffMs ? this.#backoffMs * 2 : 30_000);
      this.#arm(this.#backoffMs);
      return;
    }
  }

  #arm(ms = 15_000): void {
    if (this.#timer) return;
    this.#timer = true;
    (this.#options.schedule ?? ((callback, delay) => setTimeout(callback, delay)))(() => {this.#timer = false; void this.flush();}, ms);
  }
  #dropStale(): void {
    const oldest = this.#now() - MAX_AGE_MS, before = this.#queue.length;
    this.#queue = this.#queue.filter(item => Date.parse(item.occurredAt) >= oldest);
    if (this.#queue.length !== before) this.#saveQueue();
  }
  #loadQueue(): QueuedEvent[] {
    const saved = this.#readJson<unknown[]>(QUEUE_KEY, []);
    return saved.filter((item): item is QueuedEvent => !!item && typeof item === 'object' && typeof (item as QueuedEvent).id === 'string' &&
      UUID.test((item as QueuedEvent).id) && typeof (item as QueuedEvent).name === 'string').slice(-MAX_QUEUE);
  }
  #saveQueue(): void {if (this.#queue.length) this.#write(QUEUE_KEY, JSON.stringify(this.#queue)); else this.#remove(QUEUE_KEY);}
  #readJson<T>(key: string, fallback: T): T {
    try {const value = JSON.parse(this.#read(key) ?? 'null'); return Array.isArray(value) ? value as T : fallback;} catch {return fallback;}
  }
  #read(key: string): string | null {try {return this.#storage?.getItem(key) ?? null;} catch {return null;}}
  #write(key: string, value: string): void {try {this.#storage?.setItem(key, value);} catch { /* Storage can be full or blocked; events stay in memory. */ }}
  #remove(key: string): void {try {this.#storage?.removeItem(key);} catch { /* Nothing to forget. */ }}
}

function safeLocalStorage(): ProductEventsStorage | null {
  try {return typeof localStorage === 'undefined' ? null : localStorage;} catch {return null;}
}
