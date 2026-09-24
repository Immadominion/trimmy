import type {FastifyInstance, FastifyReply, FastifyRequest} from 'fastify';
import {
  CareerReasonSharingError,
  encodeCareerReasonCursor,
  isCareerReasonFriendsListItem,
  isCareerReasonInternalListItem,
  parseCareerReasonListHttpQuery,
  parseCareerReasonListPage,
  parseCareerReasonPrivacy,
  parseCareerReasonPrivacyWrite,
} from './career-reason-sharing.js';
import type {CareerReasonSharingRepository} from './career-reason-sharing.js';
import {GUEST_RATE_WINDOW_SECONDS} from './guest-rate-windows.js';
import {hashGuestCredential, requestGuestAuthorization} from './guest-session-routes.js';
import {GuestSessionError} from './guest-session-repository.js';
import type {GuestPaperScope, GuestSessionRepository} from './guest-session-repository.js';
import {
  PracticeAuthenticationUnavailable,
  requestPracticeBearerToken,
} from './practice-session-routes.js';
import {relationshipSafetyAvailable} from './relationship-safety-config.js';
import type {RelationshipSafetyReadiness} from './relationship-safety-config.js';

export const CAREER_REASON_LIST_ROUTE = '/v1/career/trade-reasons';
export const CAREER_REASON_PRIVACY_ROUTE = '/v1/career/reason-privacy';

export interface CareerReasonSharingAdapters {
  readonly repository: CareerReasonSharingRepository;
  readonly authenticate: (
    request: FastifyRequest,
  ) => Promise<{readonly userId: string} | null>;
}

export function careerReasonSharingEnabled(
  adapters?: CareerReasonSharingAdapters,
): adapters is CareerReasonSharingAdapters {
  return typeof adapters?.authenticate === 'function' &&
    typeof adapters.repository?.getPrivacy === 'function' &&
    typeof adapters.repository?.savePrivacy === 'function' &&
    typeof adapters.repository?.listReasons === 'function';
}

/** Accepts a verified account or an active guest on the three fixed actions. */
export function createCareerReasonSharingAuthenticator(
  authenticateAccount: (
    request: FastifyRequest,
  ) => Promise<{readonly userId: string} | null>,
  guests: GuestSessionRepository,
) {
  return async (request: FastifyRequest): Promise<{readonly userId: string} | null> => {
    if (requestPracticeBearerToken(request)) return authenticateAccount(request);
    const credential = requestGuestAuthorization(request);
    if (!credential) return null;
    const scope: GuestPaperScope | undefined = request.method === 'GET' &&
        (request.routeOptions.url === CAREER_REASON_LIST_ROUTE ||
          request.routeOptions.url === CAREER_REASON_PRIVACY_ROUTE)
      ? 'career_read'
      : request.method === 'PUT' &&
          request.routeOptions.url === CAREER_REASON_PRIVACY_ROUTE
        ? 'career_write'
        : undefined;
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
const listQuerySchema = {
  type: 'object',
  additionalProperties: false,
  required: ['scope'],
  properties: {
    scope: {enum: ['self', 'everyone', 'friends']},
    limit: {type: 'string', pattern: '^(?:[1-9]|[1-4][0-9]|50)$', maxLength: 2},
    assetId: {
      type: 'string', pattern: '^[a-z0-9]+(?:-[a-z0-9]+)*$', maxLength: 100,
    },
    variantMint: {
      type: 'string', pattern: '^[1-9A-HJ-NP-Za-km-z]{32,44}$', maxLength: 44,
    },
    cursor: {type: 'string', pattern: '^[A-Za-z0-9_-]+$', maxLength: 512},
  },
} as const;
const privacyWriteSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['schemaVersion', 'mutationId', 'baseRevision', 'visibility'],
  properties: {
    schemaVersion: {const: 1},
    mutationId: uuid,
    baseRevision: {
      type: 'integer', minimum: 1, maximum: Number.MAX_SAFE_INTEGER,
    },
    visibility: {enum: ['friends', 'everyone', 'nobody']},
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

function authenticationProblem(
  error: unknown,
  reply: FastifyReply,
  request: FastifyRequest,
) {
  if (error instanceof GuestSessionError) {
    if (error.code === 'GUEST_SESSION_EXPIRED' ||
        error.code === 'GUEST_SESSION_REVOKED') {
      return problem(reply, request, 401, error.code,
        'This guest session is no longer available.');
    }
    if (error.code === 'GUEST_SESSION_RATE_LIMITED') {
      const fallback = request.method === 'GET'
        ? GUEST_RATE_WINDOW_SECONDS.careerRead
        : GUEST_RATE_WINDOW_SECONDS.careerWrite;
      reply.header('retry-after', String(error.retryAfterSeconds ?? fallback));
      return problem(reply, request, 429, error.code,
        'This guest desk is making requests too quickly. Try again shortly.');
    }
    if (error.code === 'GUEST_SESSION_UNAVAILABLE' ||
        error.code === 'GUEST_SESSION_STORAGE_INVALID' ||
        error.code === 'GUEST_SESSION_RUNTIME_ROLE_INVALID') {
      return problem(reply, request, 503, 'CAREER_REASON_SHARING_UNAVAILABLE',
        'Career reasons are unavailable. Try again.');
    }
    return problem(reply, request, 401, 'CAREER_REASON_SHARING_UNAUTHENTICATED',
      'An active guest session or verified account is required.');
  }
  if (error instanceof PracticeAuthenticationUnavailable) {
    return problem(reply, request, 503, 'CAREER_REASON_SHARING_UNAVAILABLE',
      'Career reasons are unavailable. Try again.');
  }
  request.log.error({errorCode: 'CAREER_REASON_SHARING_AUTHENTICATION_FAILED'},
    'career reason sharing authentication failed');
  return problem(reply, request, 503, 'CAREER_REASON_SHARING_UNAVAILABLE',
    'Career reasons are unavailable. Try again.');
}

async function authenticate(
  adapters: CareerReasonSharingAdapters,
  request: FastifyRequest,
  reply: FastifyReply,
) {
  try {
    const account = await adapters.authenticate(request);
    if (!account) {
      problem(reply, request, 401, 'CAREER_REASON_SHARING_UNAUTHENTICATED',
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
  error: CareerReasonSharingError,
  reply: FastifyReply,
  request: FastifyRequest,
) {
  const mapped: Partial<Record<CareerReasonSharingError['code'], readonly [number, string]>> = {
    CAREER_REASON_SHARING_INVALID_INPUT: [400, 'Career reason sharing input is invalid.'],
    CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND: [404, 'This career is unavailable.'],
    CAREER_REASON_FRIENDS_ACCOUNT_REQUIRED: [403,
      'A verified account is required to read friends reasons.'],
    CAREER_REASON_PRIVACY_REVISION_CONFLICT: [409,
      'Your reason privacy changed on another device. Refresh and try again.'],
    CAREER_REASON_SHARING_IDEMPOTENCY_CONFLICT: [409,
      'That mutation ID already belongs to another privacy change.'],
    CAREER_REASON_SHARING_REVISION_EXHAUSTED: [409,
      'Reason privacy cannot accept another revision.'],
  };
  const [status, message] = mapped[error.code] ??
    [503, 'Career reasons are unavailable. Try again.'];
  const code = error.code in mapped
    ? error.code
    : 'CAREER_REASON_SHARING_UNAVAILABLE';
  return problem(reply, request, status, code, message);
}

export function registerCareerReasonSharingRoutes(
  app: FastifyInstance,
  options?: CareerReasonSharingAdapters,
  relationshipSafetyEnabled = false,
  relationshipSafetyReadiness?: RelationshipSafetyReadiness,
): void {
  const adapters = careerReasonSharingEnabled(options) ? options : undefined;

  app.get(CAREER_REASON_LIST_ROUTE, {
    schema: {querystring: listQuerySchema},
  }, async (request, reply) => {
    reply.header('cache-control', 'no-store');
    if (!adapters) return problem(reply, request, 503,
      'CAREER_REASON_SHARING_UNAVAILABLE',
      'Career reasons are unavailable. Try again.');
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      // Fastify uses its own safe null-rooted query object. Copy the validated
      // values into a plain object before the strict domain parser examines it.
      const query = parseCareerReasonListHttpQuery({
        ...(request.query as Record<string, unknown>),
      });
      if (query.scope === 'friends' && !await relationshipSafetyAvailable(
        relationshipSafetyEnabled, relationshipSafetyReadiness)) {
        return problem(reply, request, 503, 'CAREER_REASON_SHARING_UNAVAILABLE',
          'Career reasons are unavailable. Try again.');
      }
      const page = parseCareerReasonListPage(
        await adapters.repository.listReasons(account.userId, query),
      );
      if (page.reasons.length > query.limit ||
          page.hasMore && page.reasons.length !== query.limit ||
          page.reasons.some(reason => query.scope === 'self' &&
            (!isCareerReasonInternalListItem(reason) || !reason.author.isViewer)) ||
          page.reasons.some(reason => query.scope === 'everyone' &&
            (!isCareerReasonInternalListItem(reason) || reason.deskCycle !== 'current')) ||
          page.reasons.some(reason => query.scope === 'friends' &&
            !isCareerReasonFriendsListItem(reason)) ||
          (query.scope === 'friends') !== (page.principalSocialId !== undefined) ||
          query.scope === 'friends' && query.cursor !== null &&
            query.cursor.principalSocialId !== page.principalSocialId ||
          page.reasons.some(reason => query.assetId !== null &&
            (reason.stock.assetId !== query.assetId ||
              reason.stock.variantMint !== query.variantMint)) ||
          page.reasons.some(reason => query.cursor !== null &&
            (reason.savedAt > query.cursor.savedAt ||
              (reason.savedAt === query.cursor.savedAt &&
                reason.reasonId >= query.cursor.reasonId)))) {
        throw new CareerReasonSharingError(
          'CAREER_REASON_SHARING_STORAGE_INVALID',
          'Career reason sharing storage is invalid.',
        );
      }
      return {
        schemaVersion: 1,
        scope: query.scope,
        filter: query.assetId === null ? null : {
          assetId: query.assetId,
          variantMint: query.variantMint,
        },
        reasons: query.scope === 'self' ? page.reasons : page.reasons.map(reason => ({
          reasonId: reason.reasonId,
          author: reason.author,
          stock: reason.stock,
          note: reason.note,
          savedAt: reason.savedAt,
        })),
        page: {
          limit: query.limit,
          nextCursor: page.hasMore
            ? encodeCareerReasonCursor(query, page.reasons.at(-1)!, page.principalSocialId)
            : null,
        },
      };
    } catch (error) {
      if (error instanceof CareerReasonSharingError) {
        return repositoryProblem(error, reply, request);
      }
      request.log.error({errorCode: 'CAREER_REASON_LIST_FAILED'},
        'career reason list failed');
      return problem(reply, request, 503, 'CAREER_REASON_SHARING_UNAVAILABLE',
        'Career reasons are unavailable. Try again.');
    }
  });

  app.get(CAREER_REASON_PRIVACY_ROUTE, {
    schema: {querystring: noQuery},
  }, async (request, reply) => {
    reply.header('cache-control', 'no-store');
    if (!adapters) return problem(reply, request, 503,
      'CAREER_REASON_SHARING_UNAVAILABLE',
      'Career reasons are unavailable. Try again.');
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      return {
        schemaVersion: 1,
        reasonPrivacy: parseCareerReasonPrivacy({
          ...parseCareerReasonPrivacy(await adapters.repository.getPrivacy(account.userId)),
          friendsSharing: await relationshipSafetyAvailable(
            relationshipSafetyEnabled, relationshipSafetyReadiness) ? 'available' : 'unavailable',
        }),
      };
    } catch (error) {
      if (error instanceof CareerReasonSharingError) {
        return repositoryProblem(error, reply, request);
      }
      request.log.error({errorCode: 'CAREER_REASON_PRIVACY_READ_FAILED'},
        'career reason privacy read failed');
      return problem(reply, request, 503, 'CAREER_REASON_SHARING_UNAVAILABLE',
        'Career reasons are unavailable. Try again.');
    }
  });

  app.put(CAREER_REASON_PRIVACY_ROUTE, {
    bodyLimit: 512,
    schema: {querystring: noQuery, body: privacyWriteSchema},
  }, async (request, reply) => {
    if (!adapters) return problem(reply, request, 503,
      'CAREER_REASON_SHARING_UNAVAILABLE',
      'Career reasons are unavailable. Try again.');
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      const body = request.body as Record<string, unknown>;
      const command = parseCareerReasonPrivacyWrite({
        mutationId: body['mutationId'],
        baseRevision: body['baseRevision'],
        visibility: body['visibility'],
      });
      return {
        schemaVersion: 1,
        reasonPrivacy: parseCareerReasonPrivacy({
          ...parseCareerReasonPrivacy(await adapters.repository.savePrivacy(account.userId, command)),
          friendsSharing: await relationshipSafetyAvailable(
            relationshipSafetyEnabled, relationshipSafetyReadiness) ? 'available' : 'unavailable',
        }),
      };
    } catch (error) {
      if (error instanceof CareerReasonSharingError) {
        return repositoryProblem(error, reply, request);
      }
      request.log.error({errorCode: 'CAREER_REASON_PRIVACY_WRITE_FAILED'},
        'career reason privacy write failed');
      return problem(reply, request, 503, 'CAREER_REASON_SHARING_UNAVAILABLE',
        'Career reasons are unavailable. Try again.');
    }
  });
}
