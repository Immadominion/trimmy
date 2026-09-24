import type {FastifyInstance, FastifyReply, FastifyRequest} from 'fastify';
import {parsePracticeUserId} from './practice-repository.js';
import {PracticeAuthenticationUnavailable} from './practice-session-routes.js';
import {parseXPublicProfile, XProfileLookupError} from './x-profile-lookup.js';
import type {XProfileLookupErrorCode, XProfileResolver} from './x-profile-lookup.js';

export const X_PROFILE_ROUTE = '/v1/social/x/profile';
export interface SocialXAdapters {
  readonly lookup: XProfileResolver;
  /** Existing-account lookup only. In production use createPracticeAuthenticator;
   * never a caller-selected UUID or a provisioning/session fallback. */
  readonly authenticate: (request: FastifyRequest) => Promise<{readonly userId: string} | null>;
  /** Shared with invitation addressing so both routes consume one provider budget. */
  readonly budget?: XProfileRequestBudget;
}
export function socialXEnabled(value?: SocialXAdapters): value is SocialXAdapters {
  return typeof value?.lookup?.lookup === 'function' && typeof value.authenticate === 'function';
}

const hour = 3_600_000;
/** Conservative single-process spending budget, shared by all callers of a route.
 * Sliding-window entries remain bounded to20. Failures consume attempts. No cache,
 * retry, identity proof or persisted claim is created. Process restart resets it;
 * a distributed gateway budget is still required before multi-instance exposure. */
export class XProfileRequestBudget {
  readonly #now: () => number;
  #events: {userId: string; at: number}[] = [];
  #busy = false;
  #latestTime = -1;
  #cooldownUntil = 0;
  #disabled = false;
  constructor({now = () => Math.floor(performance.now())}: {now?: () => number} = {}) { this.#now = now; }

  async run<T>(userId: string, operation: () => Promise<T>): Promise<T> {
    userId = parsePracticeUserId(userId);
    let now: number;
    try { now = this.#now(); } catch { throw new XProfileLookupError('X_LOOKUP_BUDGET_UNAVAILABLE'); }
    if (!Number.isSafeInteger(now) || now < 0 || now < this.#latestTime || now > Number.MAX_SAFE_INTEGER - hour) {
      throw new XProfileLookupError('X_LOOKUP_BUDGET_UNAVAILABLE');
    }
    this.#latestTime = now;
    if (this.#disabled) throw new XProfileLookupError('X_LOOKUP_BUDGET_UNAVAILABLE');
    this.#events = this.#events.filter(event => event.at > now - hour);
    const userEvents = this.#events.filter(event => event.userId === userId);
    const last = this.#events.at(-1);
    const userLast = userEvents.at(-1);
    if (this.#busy || now < this.#cooldownUntil || this.#events.length >= 20 || userEvents.length >= 5 ||
      last !== undefined && now - last.at < 1000 || userLast !== undefined && now - userLast.at < 15_000) {
      throw new XProfileLookupError('X_LOOKUP_RATE_LIMITED');
    }
    this.#events.push({userId, at: now}); this.#busy = true;
    try { return await operation(); }
    catch (error) {
      if (error instanceof XProfileLookupError) {
        if (['X_PROVIDER_AUTH_FAILED', 'X_PROVIDER_ACCESS_DENIED', 'X_PROVIDER_PAYMENT_REQUIRED'].includes(error.code)) this.#disabled = true;
        if (error.code === 'X_PROVIDER_RATE_LIMITED') {
          try {
            const observed = this.#now();
            if (!Number.isSafeInteger(observed) || observed < this.#latestTime || observed > Number.MAX_SAFE_INTEGER - hour) this.#disabled = true;
            else { this.#latestTime = observed; this.#cooldownUntil = observed + 900_000; }
          } catch { this.#disabled = true; }
        }
      }
      throw error;
    } finally { this.#busy = false; }
  }
}

function problem(request: FastifyRequest, reply: FastifyReply, status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}
const unavailable = (request: FastifyRequest, reply: FastifyReply) =>
  problem(request, reply, 503, 'SOCIAL_X_UNAVAILABLE', 'X profile lookup is unavailable.');
const unauthorized = (request: FastifyRequest, reply: FastifyReply) =>
  problem(request, reply, 401, 'SOCIAL_X_UNAUTHENTICATED', 'A verified existing account is required.');

function failure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  // Reconstruct known errors; an injected adapter's modified message is untrusted.
  const statuses: Record<XProfileLookupErrorCode, number> = {
    X_HANDLE_INVALID: 400, X_PROFILE_NOT_FOUND: 404,
    X_LOOKUP_RATE_LIMITED: 429, X_PROVIDER_RATE_LIMITED: 429, X_LOOKUP_TIMEOUT: 504,
    X_LOOKUP_NOT_CONFIGURED: 503, X_LOOKUP_BUDGET_UNAVAILABLE: 503, X_PROVIDER_AUTH_FAILED: 503,
    X_PROVIDER_ACCESS_DENIED: 503, X_PROVIDER_PAYMENT_REQUIRED: 503,
    X_PROVIDER_UNAVAILABLE: 502, X_RESPONSE_INVALID: 502,
  };
  const safe = error instanceof XProfileLookupError && Object.hasOwn(statuses, error.code) ? new XProfileLookupError(error.code)
    : new XProfileLookupError('X_PROVIDER_UNAVAILABLE');
  return problem(request, reply, statuses[safe.code], safe.code, safe.message);
}

/** No POST/HEAD registration. The parent app owns exact GET-only CORS preflight.
 * Validated input + existing verified account precede every spending reservation. */
export function registerSocialXRoutes(app: FastifyInstance, options?: SocialXAdapters,
  budget = new XProfileRequestBudget()): void {
  const adapters = socialXEnabled(options) ? options : undefined;
  const activeBudget = adapters?.budget ?? budget;
  const verifiedUsers = new WeakMap<FastifyRequest, string>();
  app.get<{Querystring: {username: string}}>(X_PROFILE_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {type: 'object', additionalProperties: false, required: ['username'],
      properties: {username: {type: 'string', minLength: 1, maxLength: 15, pattern: '^[A-Za-z0-9_]+$'}}}},
    onRequest: async (request, reply) => {
      reply.header('cache-control', 'no-store');
      if (!adapters) return unavailable(request, reply);
      if (request.headers['transfer-encoding'] !== undefined ||
        request.headers['content-length'] !== undefined && request.headers['content-length'] !== '0') {
        return problem(request, reply, 400, 'X_HANDLE_INVALID', 'The profile lookup accepts query parameters only.');
      }
      try {
        const identity = await adapters.authenticate(request);
        if (!identity) return unauthorized(request, reply);
        verifiedUsers.set(request, parsePracticeUserId(identity.userId));
      } catch (error) {
        return error instanceof PracticeAuthenticationUnavailable ? unavailable(request, reply) : unauthorized(request, reply);
      }
    },
  }, async (request, reply) => {
    if (!adapters) return unavailable(request, reply);
    const userId = verifiedUsers.get(request);
    if (!userId) return unauthorized(request, reply);
    const username = request.query.username;
    if (typeof username !== 'string' || /^[A-Za-z0-9_]{1,15}$/.exec(username)?.[0] !== username) {
      return problem(request, reply, 400, 'X_HANDLE_INVALID', 'Enter a valid X username.');
    }
    try {
      const profile = await activeBudget.run(userId,
        async () => parseXPublicProfile(await adapters.lookup.lookup(username), username));
      return {schemaVersion: 1, profile, invitationCreated: false};
    } catch (error) { return failure(error, request, reply); }
  });
}
