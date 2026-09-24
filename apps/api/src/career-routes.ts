import type {FastifyInstance, FastifyReply, FastifyRequest} from 'fastify';
import {GUEST_RATE_WINDOW_SECONDS} from './guest-rate-windows.js';
import {hashGuestCredential, requestGuestAuthorization} from './guest-session-routes.js';
import {GuestSessionError} from './guest-session-repository.js';
import type {GuestPaperScope, GuestSessionRepository} from './guest-session-repository.js';
import {
  PracticeAuthenticationUnavailable,
  requestPracticeBearerToken,
} from './practice-session-routes.js';
import {
  CareerRepositoryError,
  parseCareerDayContextWrite,
  parseCareerPromotionWrite,
  parseCareerTradeReasonWrite,
} from './career-repository.js';
import type {CareerRepository} from './career-repository.js';

export const CAREER_ACTIVITY_WEEK_ROUTE = '/v1/career/activity-week';
export const CAREER_SUMMARY_ROUTE = '/v1/career/summary';
export const CAREER_MISSIONS_ROUTE = '/v1/career/missions';
export const CAREER_REASON_ROUTE = '/v1/career/trade-reasons';
export const CAREER_PROMOTION_ROUTE = '/v1/career/promotions';
export const CAREER_DAY_CONTEXT_ROUTE = '/v1/career/day-context';

export interface CareerAdapters {
  readonly repository: CareerRepository;
  readonly authenticate: (request: FastifyRequest) => Promise<{readonly userId: string} | null>;
}

export function careerEnabled(adapters?: CareerAdapters): adapters is CareerAdapters {
  return typeof adapters?.authenticate === 'function' &&
    typeof adapters.repository?.getSummary === 'function' &&
    typeof adapters.repository?.getMissions === 'function' &&
    typeof adapters.repository?.getDayContext === 'function' &&
    typeof adapters.repository?.saveDayContext === 'function' &&
    typeof adapters.repository?.saveTradeReason === 'function' &&
    typeof adapters.repository?.promote === 'function';
}

/** Accepts a verified account or an active guest on the fixed Career routes only. */
export function createCareerAuthenticator(
  authenticateAccount: (request: FastifyRequest) => Promise<{readonly userId: string} | null>,
  guests: GuestSessionRepository,
) {
  return async (request: FastifyRequest): Promise<{readonly userId: string} | null> => {
    if (requestPracticeBearerToken(request)) return authenticateAccount(request);
    const credential = requestGuestAuthorization(request);
    if (!credential) return null;
    const scope: GuestPaperScope | undefined = request.method === 'GET' &&
        (request.routeOptions.url === '/v1/career/workdays' ||
          request.routeOptions.url === '/v1/career/daily-desk' ||
          request.routeOptions.url === CAREER_SUMMARY_ROUTE ||
          request.routeOptions.url === CAREER_MISSIONS_ROUTE ||
          request.routeOptions.url === CAREER_ACTIVITY_WEEK_ROUTE ||
          request.routeOptions.url === CAREER_DAY_CONTEXT_ROUTE)
      ? 'career_read'
      : ((request.method === 'POST' &&
          (request.routeOptions.url === '/v1/career/workdays/step' ||
            request.routeOptions.url === '/v1/career/workdays/draft' ||
            request.routeOptions.url === '/v1/career/daily-desk/complete' ||
            request.routeOptions.url === CAREER_REASON_ROUTE ||
            request.routeOptions.url === CAREER_PROMOTION_ROUTE)) ||
          (request.method === 'PUT' && request.routeOptions.url === CAREER_DAY_CONTEXT_ROUTE))
        ? 'career_write' : undefined;
    if (!scope) return null;
    const authorized = await guests.authorize(hashGuestCredential(credential), scope);
    return Object.freeze({userId: authorized.userId});
  };
}

const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;
const uuid = {
  type: 'string',
  pattern: '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  maxLength: 36,
} as const;
const reasonSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['schemaVersion', 'mutationId', 'orderId', 'note'],
  properties: {
    schemaVersion: {const: 1},
    mutationId: uuid,
    orderId: uuid,
    note: {type: 'string', minLength: 1, maxLength: 180},
  },
} as const;
const promotionSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['schemaVersion', 'mutationId', 'targetRank'],
  properties: {
    schemaVersion: {const: 1},
    mutationId: uuid,
    targetRank: {enum: ['analyst', 'trader', 'senior-trader', 'partner', 'legend']},
  },
} as const;
const dayContextSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['schemaVersion', 'mutationId', 'baseRevision', 'timeZone'],
  properties: {
    schemaVersion: {const: 1},
    mutationId: uuid,
    baseRevision: {type: 'integer', minimum: 1, maximum: Number.MAX_SAFE_INTEGER},
    // Syntax and PostgreSQL's installed IANA catalog are both checked by the
    // domain/storage layers so every rejected string receives one stable
    // Career error, including raw offsets and unknown zone names.
    timeZone: {type: 'string', minLength: 1, maxLength: 100},
  },
} as const;

function problem(
  reply: FastifyReply,
  request: FastifyRequest,
  status: number,
  code: string,
  message: string,
) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}

function authenticationProblem(error: unknown, reply: FastifyReply, request: FastifyRequest) {
  if (error instanceof GuestSessionError) {
    if (error.code === 'GUEST_SESSION_EXPIRED' || error.code === 'GUEST_SESSION_REVOKED') {
      return problem(reply, request, 401, error.code,
        'This guest session is no longer available.');
    }
    if (error.code === 'GUEST_SESSION_RATE_LIMITED') {
      reply.header('retry-after', String(request.method === 'GET'
        ? GUEST_RATE_WINDOW_SECONDS.careerRead : GUEST_RATE_WINDOW_SECONDS.careerWrite));
      return problem(reply, request, 429, error.code,
        'This guest desk is making requests too quickly. Try again shortly.');
    }
    if (error.code === 'GUEST_SESSION_UNAVAILABLE' || error.code === 'GUEST_SESSION_STORAGE_INVALID' ||
        error.code === 'GUEST_SESSION_RUNTIME_ROLE_INVALID') {
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
    }
    return problem(reply, request, 401, 'CAREER_UNAUTHENTICATED',
      'An active guest session or verified account is required.');
  }
  if (error instanceof PracticeAuthenticationUnavailable) {
    return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
  }
  request.log.error({errorCode: 'CAREER_AUTHENTICATION_FAILED'}, 'career authentication failed');
  return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
}

async function authenticate(adapters: CareerAdapters, request: FastifyRequest, reply: FastifyReply) {
  try {
    const account = await adapters.authenticate(request);
    if (!account) {
      problem(reply, request, 401, 'CAREER_UNAUTHENTICATED',
        'An active guest session or verified account is required.');
      return null;
    }
    return account;
  } catch (error) {
    authenticationProblem(error, reply, request);
    return null;
  }
}

function repositoryProblem(
  error: CareerRepositoryError,
  reply: FastifyReply,
  request: FastifyRequest,
) {
  const mapped: Partial<Record<CareerRepositoryError['code'], readonly [number, string]>> = {
    CAREER_INVALID_INPUT: [400, 'Career input is invalid.'],
    CAREER_ACCOUNT_NOT_FOUND: [404, 'This career is unavailable.'],
    CAREER_PROFILE_REQUIRED: [409, 'Finish setting up your Trimmy profile first.'],
    CAREER_ORDER_NOT_FOUND: [404, 'That paper order was not found.'],
    CAREER_BUY_ORDER_REQUIRED: [409, 'A reason can be added only to a paper buy.'],
    CAREER_POSITION_REQUIRED: [409, 'Hold this stock before adding a reason.'],
    CAREER_REASON_EXISTS: [409, 'That paper order already has a reason.'],
    CAREER_IDEMPOTENCY_CONFLICT: [409, 'That mutation ID already belongs to another Career action.'],
    CAREER_DAY_CONTEXT_REVISION_CONFLICT: [409, 'Your Career timezone changed on another device. Refresh and try again.'],
    CAREER_TIME_ZONE_CHANGE_TOO_SOON: [409, 'Your Career timezone can be changed once every 24 hours.'],
    CAREER_PROMOTION_RANK_MISMATCH: [409, 'That is not the next rank for this career.'],
    CAREER_PROMOTION_THRESHOLD_REQUIRED: [409, 'Earn the required Trims before promotion.'],
    CAREER_PROMOTION_MISSION_REQUIRED: [409, 'Finish the promotion mission first.'],
    CAREER_REVISION_EXHAUSTED: [409, 'This career cannot accept another revision.'],
  };
  const [status, message] = mapped[error.code] ?? [503, 'Your career is unavailable. Try again.'];
  const code = error.code in mapped ? error.code : 'CAREER_UNAVAILABLE';
  return problem(reply, request, status, code, message);
}

export function registerCareerRoutes(app: FastifyInstance, options?: CareerAdapters): void {
  const adapters = careerEnabled(options) ? options : undefined;

  app.get(CAREER_SUMMARY_ROUTE, {schema: {querystring: noQuery}}, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
    }
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      return {schemaVersion: 1, career: await adapters.repository.getSummary(account.userId)};
    } catch (error) {
      if (error instanceof CareerRepositoryError) return repositoryProblem(error, reply, request);
      request.log.error({errorCode: 'CAREER_READ_FAILED'}, 'career read failed');
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
    }
  });

  app.get(CAREER_ACTIVITY_WEEK_ROUTE, {schema: {querystring: noQuery}}, async (request, reply) => {
    if (!adapters?.repository.getActivityWeek) return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Activity could not be loaded.');
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {return {schemaVersion: 1, activityWeek: await adapters.repository.getActivityWeek(account.userId)};}
    catch (error) {
      if (error instanceof CareerRepositoryError) return repositoryProblem(error, reply, request);
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Activity could not be loaded.');
    }
  });

  app.get(CAREER_MISSIONS_ROUTE, {schema: {querystring: noQuery}}, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
    }
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      const board = await adapters.repository.getMissions(account.userId);
      return {schemaVersion: 1, career: {revision: board.revision, currentRank: board.currentRank},
        missions: board.missions};
    } catch (error) {
      if (error instanceof CareerRepositoryError) return repositoryProblem(error, reply, request);
      request.log.error({errorCode: 'CAREER_MISSIONS_READ_FAILED'}, 'career missions read failed');
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your missions are unavailable. Try again.');
    }
  });

  app.get(CAREER_DAY_CONTEXT_ROUTE, {schema: {querystring: noQuery}}, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
    }
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      return {schemaVersion: 1, dayContext: await adapters.repository.getDayContext(account.userId)};
    } catch (error) {
      if (error instanceof CareerRepositoryError) return repositoryProblem(error, reply, request);
      request.log.error({errorCode: 'CAREER_DAY_CONTEXT_READ_FAILED'}, 'career day context read failed');
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
    }
  });

  app.put(CAREER_DAY_CONTEXT_ROUTE, {
    bodyLimit: 512,
    schema: {querystring: noQuery, body: dayContextSchema},
  }, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
    }
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      const body = request.body as Record<string, unknown>;
      const command = parseCareerDayContextWrite({
        mutationId: body['mutationId'],
        baseRevision: body['baseRevision'],
        timeZone: body['timeZone'],
      });
      return {schemaVersion: 1,
        dayContext: await adapters.repository.saveDayContext(account.userId, command)};
    } catch (error) {
      if (error instanceof CareerRepositoryError) return repositoryProblem(error, reply, request);
      request.log.error({errorCode: 'CAREER_DAY_CONTEXT_WRITE_FAILED'}, 'career day context write failed');
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your timezone was not saved. Try again.');
    }
  });

  app.post(CAREER_REASON_ROUTE, {
    bodyLimit: 1024,
    schema: {querystring: noQuery, body: reasonSchema},
  }, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
    }
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      const body = request.body as Record<string, unknown>;
      const command = parseCareerTradeReasonWrite({
        mutationId: body['mutationId'],
        orderId: body['orderId'],
        note: body['note'],
      });
      const receipt = await adapters.repository.saveTradeReason(account.userId, command);
      return reply.code(201).send({schemaVersion: 1, reason: receipt});
    } catch (error) {
      if (error instanceof CareerRepositoryError) return repositoryProblem(error, reply, request);
      request.log.error({errorCode: 'CAREER_REASON_WRITE_FAILED'}, 'career reason write failed');
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your reason was not saved. Try again.');
    }
  });

  app.post(CAREER_PROMOTION_ROUTE, {
    bodyLimit: 512,
    schema: {querystring: noQuery, body: promotionSchema},
  }, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your career is unavailable. Try again.');
    }
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      const body = request.body as Record<string, unknown>;
      const command = parseCareerPromotionWrite({
        mutationId: body['mutationId'],
        targetRank: body['targetRank'],
      });
      const receipt = await adapters.repository.promote(account.userId, command);
      return reply.code(201).send({schemaVersion: 1, promotion: receipt});
    } catch (error) {
      if (error instanceof CareerRepositoryError) return repositoryProblem(error, reply, request);
      request.log.error({errorCode: 'CAREER_PROMOTION_WRITE_FAILED'}, 'career promotion failed');
      return problem(reply, request, 503, 'CAREER_UNAVAILABLE', 'Your promotion could not be saved. Try again.');
    }
  });
}
