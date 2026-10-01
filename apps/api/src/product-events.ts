import type {FastifyInstance, FastifyRequest} from 'fastify';
import type {Pool} from 'pg';
import {hashGuestCredential, requestGuestAuthorization} from './guest-session-routes.js';
import {requestPracticeBearerToken} from './practice-session-routes.js';
import {GuestSessionError, type GuestSessionRepository} from './guest-session-repository.js';

/**
 * First-party product events (migration 0039). The apps record a handful of
 * allowlisted moments: opening the app and from where, each first-run step,
 * the tab in view, opening a workday or finding the desk closed, switching
 * modes, a few money screens, reminder and push choices, language changes and
 * failed launches. Everything the server already knows (orders, filed work,
 * streaks, wallets, live trades) is measured from its own tables instead.
 *
 * No property can carry an account id, name, email, amount or free text: every
 * value is an enum, a small integer, a boolean or a short lowercase token, and
 * anything else is refused before it reaches the database.
 */
export const PRODUCT_EVENTS_ROUTE = '/v1/events';
export const PRODUCT_INSTALL_LINK_ROUTE = '/v1/events/link';

type PropRule = {readonly kind: 'enum'; readonly values: readonly string[]; readonly required?: true}
  | {readonly kind: 'int'; readonly min: number; readonly max: number; readonly required?: true}
  | {readonly kind: 'bool'; readonly required?: true}
  /** A short lowercase token such as a referrer host or a campaign name. */
  | {readonly kind: 'token'; readonly required?: true};
const required = <T extends PropRule>(rule: T): T & {readonly required: true} => ({...rule, required: true});
const oneOf = (...values: string[]) => ({kind: 'enum', values} as const);

export const ONBOARDING_STEPS = ['welcome', 'note', 'first_trade', 'review', 'first_order', 'celebration', 'gate',
  'reminders', 'next_move', 'home'] as const;
const permission = oneOf('granted', 'denied', 'not_asked');

export const PRODUCT_EVENT_CATALOG: Readonly<Record<string, Readonly<Record<string, PropRule>>>> = Object.freeze({
  // A new session: cold start, back after 30 minutes away, or opened from a reminder, a push or a link.
  app_open: {source: required(oneOf('launch', 'resume', 'reminder', 'push', 'link')),
    referrer: {kind: 'token'}, utm_source: {kind: 'token'}, utm_medium: {kind: 'token'}, utm_campaign: {kind: 'token'}},
  // The first time an install reaches each first-run step, in order.
  onboarding_step: {step: required(oneOf(...ONBOARDING_STEPS))},
  onboarding_skip: {step: required(oneOf(...ONBOARDING_STEPS))},
  // How the player left the sign-in gate.
  gate_choice: {choice: required(oneOf('guest', 'email', 'google', 'apple', 'x'))},
  reminder_choice: {frequency: required(oneOf('daily', 'occasional', 'off')), permission: required(permission)},
  push_opt_in: {enabled: required({kind: 'bool'}), permission: required(permission)},
  // Once per tab per session.
  tab_view: {tab: required(oneOf('desk', 'market', 'career', 'profile'))},
  workday_open: {ordinal: required({kind: 'int', min: 1, max: 500}), resumed: required({kind: 'bool'})},
  // The player looked for work and found the desk waiting: today's is done, the market is closed, or everything is filed.
  workday_waiting: {state: required(oneOf('tomorrow', 'closed', 'done'))},
  mode_switch: {to: required(oneOf('real', 'practice'))},
  money_action: {action: required(oneOf('add_money_open', 'wallet_create_start', 'send_open', 'fast_buy_open'))},
  language_set: {language: required(oneOf('phone', 'browser', 'en', 'es-419', 'pt-BR', 'fr'))},
  // A launch that ended on an error screen, and where.
  startup_failed: {stage: required(oneOf('network', 'guest', 'profile', 'sign_in', 'unknown'))},
});

export interface ProductEvent {
  readonly id: string; readonly installId: string; readonly sessionId: string;
  readonly platform: 'android' | 'ios' | 'web'; readonly appVersion: string; readonly locale: string;
  readonly name: string; readonly props: Readonly<Record<string, string | number | boolean>>; readonly occurredAt: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const TOKEN = /^[a-z0-9][a-z0-9._-]{0,39}$/;
const VERSION = /^[0-9A-Za-z][0-9A-Za-z.+_-]{0,39}$/;
const LOCALE = /^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}$/;
const INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;
const EVENT_KEYS = new Set(['id', 'installId', 'sessionId', 'platform', 'appVersion', 'locale', 'name', 'props', 'occurredAt']);

/** The event in canonical form, or null when anything about it is outside the catalog. */
export function parseProductEvent(value: unknown, now = Date.now()): ProductEvent | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const v = value as Record<string, unknown>;
  if (!Object.keys(v).every(key => EVENT_KEYS.has(key))) return null;
  const {id, installId, sessionId, platform, appVersion, locale, name, occurredAt} = v;
  if (typeof id !== 'string' || !UUID.test(id) || typeof installId !== 'string' || !UUID.test(installId) ||
      typeof sessionId !== 'string' || !UUID.test(sessionId)) return null;
  if (platform !== 'android' && platform !== 'ios' && platform !== 'web') return null;
  if (typeof appVersion !== 'string' || !VERSION.test(appVersion) || typeof locale !== 'string' || locale.length > 35 ||
      !LOCALE.test(locale)) return null;
  if (typeof name !== 'string' || !Object.hasOwn(PRODUCT_EVENT_CATALOG, name)) return null;
  if (typeof occurredAt !== 'string' || !INSTANT.test(occurredAt)) return null;
  const at = Date.parse(occurredAt);
  // The database keeps the same window; an event outside it is dropped, not stored.
  if (!Number.isFinite(at) || at < now - 7 * 86_400_000 || at > now + 5 * 60_000) return null;
  const rules = PRODUCT_EVENT_CATALOG[name]!;
  const rawProps = v['props'] ?? {};
  if (!rawProps || typeof rawProps !== 'object' || Array.isArray(rawProps)) return null;
  const props: Record<string, string | number | boolean> = {};
  for (const [key, raw] of Object.entries(rawProps as Record<string, unknown>)) {
    const rule = rules[key];
    if (!rule) return null;
    if (rule.kind === 'enum' ? typeof raw !== 'string' || !rule.values.includes(raw)
      : rule.kind === 'int' ? typeof raw !== 'number' || !Number.isSafeInteger(raw) || raw < rule.min || raw > rule.max
      : rule.kind === 'bool' ? typeof raw !== 'boolean'
      : typeof raw !== 'string' || !TOKEN.test(raw)) return null;
    props[key] = raw as string | number | boolean;
  }
  for (const [key, rule] of Object.entries(rules)) if (rule.required && !Object.hasOwn(props, key)) return null;
  return Object.freeze({id, installId, sessionId, platform, appVersion, locale, name, props: Object.freeze(props),
    occurredAt: new Date(at).toISOString()});
}

/**
 * Recording needs no sign-in, so each process caps it: per install and in
 * total, per minute. Events over a cap are dropped quietly rather than refused,
 * so a misbehaving client cannot turn the cap into a retry storm.
 */
export class ProductEventBudget {
  readonly #perInstall: number; readonly #total: number; readonly #now: () => number;
  #minute = -1; #spent = 0; readonly #installs = new Map<string, number>();
  constructor({perInstall = 120, total = 3000, now = Date.now}: {perInstall?: number; total?: number; now?: () => number} = {}) {
    this.#perInstall = perInstall; this.#total = total; this.#now = now;
  }
  take(installId: string): boolean {
    const minute = Math.floor(this.#now() / 60_000);
    if (minute !== this.#minute) {this.#minute = minute; this.#spent = 0; this.#installs.clear();}
    const used = this.#installs.get(installId) ?? 0;
    if (used >= this.#perInstall || this.#spent >= this.#total) return false;
    // The per-minute map is cleared every minute, so it stays bounded by the total budget.
    this.#installs.set(installId, used + 1); this.#spent++;
    return true;
  }
}

export interface ProductEventStore {
  record(events: readonly ProductEvent[]): Promise<number>;
  link(userId: string, installId: string): Promise<void>;
  prune(): Promise<number>;
}
export interface ProductEventAdapters {
  store: ProductEventStore;
  /** The account or guest desk using the install; null when the request carries neither. */
  authenticate(request: FastifyRequest): Promise<{readonly userId: string} | null>;
  budget?: ProductEventBudget;
  now?: () => number;
}

export function productEventLinkAuthenticator(
  account: (request: FastifyRequest) => Promise<{readonly userId: string} | null>, guests: GuestSessionRepository,
): ProductEventAdapters['authenticate'] {
  return async request => {
    if (requestPracticeBearerToken(request)) return account(request);
    const credential = requestGuestAuthorization(request);
    if (!credential || request.routeOptions.url !== PRODUCT_INSTALL_LINK_ROUTE || request.method !== 'POST') return null;
    // A read scope: linking changes nothing a guest owns, and the write budgets stay for real work.
    const scope = await guests.authorize(hashGuestCredential(credential), 'profile_read');
    return {userId: scope.userId};
  };
}

export function postgresProductEvents(pool: Pick<Pool, 'connect' | 'query'>): ProductEventStore {
  return {
    async record(events) {
      const result = await pool.query('SELECT trimmy.product_events_record($1::jsonb) AS inserted', [JSON.stringify(events)]);
      const inserted = Number(result.rows[0]?.inserted);
      if (!Number.isSafeInteger(inserted) || inserted < 0 || inserted > events.length) throw Error('EVENTS_STORAGE_INVALID');
      return inserted;
    },
    async link(userId, installId) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [userId]);
        await client.query('SELECT trimmy.product_install_link($1,$2)', [userId, installId]);
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK'); throw error;
      } finally { client.release(); }
    },
    async prune() {
      const result = await pool.query('SELECT trimmy.product_events_prune() AS removed');
      return Number(result.rows[0]?.removed ?? 0);
    },
  };
}

const PRUNE_INTERVAL_MS = 60 * 60_000;

export function registerProductEventRoutes(app: FastifyInstance, adapters?: ProductEventAdapters) {
  const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;
  const budget = adapters?.budget ?? new ProductEventBudget();
  const now = adapters?.now ?? Date.now;
  app.post<{Body: {schemaVersion: 1; events: unknown[]}}>(PRODUCT_EVENTS_ROUTE, {
    bodyLimit: 32_768,
    schema: {querystring: noQuery, body: {type: 'object', additionalProperties: false, required: ['schemaVersion', 'events'],
      properties: {schemaVersion: {const: 1}, events: {type: 'array', minItems: 1, maxItems: 50}}}},
  }, async (request, reply) => {
    reply.header('cache-control', 'no-store');
    if (!adapters) return reply.code(503).send({code: 'EVENTS_UNAVAILABLE'});
    const parsed = request.body.events.map(event => parseProductEvent(event, now()));
    // One malformed event means a client out of step with the catalog: refuse the batch so it is noticed, not half-kept.
    if (parsed.some(event => event === null)) return reply.code(400).send({code: 'EVENTS_INVALID'});
    const kept = (parsed as ProductEvent[]).filter(event => budget.take(event.installId));
    try {
      const accepted = kept.length ? await adapters.store.record(kept) : 0;
      return reply.code(202).send({schemaVersion: 1, accepted});
    } catch {
      request.log.warn({route: PRODUCT_EVENTS_ROUTE}, 'Product events were not recorded.');
      return reply.code(503).send({code: 'EVENTS_UNAVAILABLE'});
    }
  });
  app.post<{Body: {schemaVersion: 1; installId: string}}>(PRODUCT_INSTALL_LINK_ROUTE, {
    bodyLimit: 1024,
    schema: {querystring: noQuery, body: {type: 'object', additionalProperties: false, required: ['schemaVersion', 'installId'],
      properties: {schemaVersion: {const: 1}, installId: {type: 'string', pattern: UUID.source}}}},
  }, async (request, reply) => {
    reply.header('cache-control', 'no-store');
    if (!adapters) return reply.code(503).send({code: 'EVENTS_UNAVAILABLE'});
    try {
      const principal = await adapters.authenticate(request);
      if (!principal) return reply.code(401).send({code: 'ACCOUNT_REQUIRED'});
      await adapters.store.link(principal.userId, request.body.installId);
      return reply.code(204).send();
    } catch (error) {
      if (error instanceof GuestSessionError) {
        const rate = error.code === 'GUEST_SESSION_RATE_LIMITED';
        if (rate) reply.header('retry-after', '60');
        return reply.code(rate ? 429 : error.code.includes('UNAVAILABLE') ? 503 : 401).send({code: error.code});
      }
      if (error instanceof Error && error.message === 'ACCOUNT_REQUIRED') return reply.code(401).send({code: 'ACCOUNT_REQUIRED'});
      return reply.code(503).send({code: 'EVENTS_UNAVAILABLE'});
    }
  });
  if (!adapters) return;
  let timer: ReturnType<typeof setInterval> | undefined;
  const prune = () => {adapters.store.prune().catch(() => app.log.warn('Product event pruning will retry.'));};
  app.addHook('onReady', async () => {timer = setInterval(prune, PRUNE_INTERVAL_MS); timer.unref?.();});
  app.addHook('onClose', async () => {if (timer) clearInterval(timer);});
}
