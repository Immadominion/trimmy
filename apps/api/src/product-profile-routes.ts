import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { GUEST_RATE_WINDOW_SECONDS } from './guest-rate-windows.js';
import { hashGuestCredential, requestGuestAuthorization } from './guest-session-routes.js';
import { GuestSessionError } from './guest-session-repository.js';
import type { GuestPaperScope, GuestSessionRepository } from './guest-session-repository.js';
import { PracticeAuthenticationUnavailable, requestPracticeBearerToken } from './practice-session-routes.js';
import {
  ProductProfileRepositoryError, parseProductLaunchWrite, parseProductProfileWrite,
} from './product-profile-repository.js';
import type { ProductProfilePrincipal, ProductProfileRepository, ProductProfileSnapshot } from './product-profile-repository.js';

export const PRODUCT_PROFILE_ROUTE = '/v1/product/profile';
export const PRODUCT_LAUNCH_ROUTE = '/v1/product/launch';
export const PRODUCT_PROFILE_V2_MEDIA_TYPE = 'application/vnd.trimmy.product-profile.v2+json';

export interface ProductProfileAdapters {
  readonly repository: ProductProfileRepository;
  readonly authenticate: (request: FastifyRequest) => Promise<ProductProfilePrincipal | null>;
}

export function productProfileEnabled(adapters?: ProductProfileAdapters): adapters is ProductProfileAdapters {
  return typeof adapters?.authenticate === 'function' && typeof adapters.repository?.get === 'function' &&
    typeof adapters.repository?.put === 'function' && typeof adapters.repository?.advance === 'function';
}

const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;
const uuid = {type: 'string', pattern: '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$', maxLength: 36} as const;
const onboardingSchema = {
  type: 'object', additionalProperties: false,
  required: ['goal', 'knowledge', 'persona', 'dailyGoal', 'handle'],
  properties: {
    goal: {enum: ['learn', 'practice', 'trade', 'beat-friends']},
    knowledge: {enum: ['nothing', 'basics', 'practice', 'traded-before', 'daily-trader']},
    persona: {enum: ['wolf', 'oracle', 'shark']},
    dailyGoal: {enum: ['show-up', 'one-mission', 'three-missions']},
    handle: {type: 'string', pattern: '^[a-z][a-z0-9_]{2,17}$', maxLength: 18},
  },
} as const;
const putSchema = {
  type: 'object', additionalProperties: false,
  required: ['schemaVersion', 'mutationId', 'baseRevision', 'onboarding', 'launchCheckpoint'],
  properties: {
    schemaVersion: {const: 1}, mutationId: uuid,
    baseRevision: {type: 'integer', minimum: 0, maximum: 9007199254740991},
    onboarding: onboardingSchema,
    launchCheckpoint: {enum: ['first-trade', 'first-position', 'streak', 'save-desk', 'app']},
  },
} as const;
const nullableOnboardingSchema = {
  ...onboardingSchema,
  properties: Object.fromEntries(Object.entries(onboardingSchema.properties)
    .map(([key, schema]) => [key, 'enum' in schema
      ? {...schema, enum: [...schema.enum, null]}
      : {...schema, type: ['string', 'null']} ])),
};
const putV2Schema = {
  ...putSchema,
  properties: {...putSchema.properties, schemaVersion: {const: 2}, onboarding: nullableOnboardingSchema},
};
const launchSchema = {
  type: 'object', additionalProperties: false,
  required: ['schemaVersion', 'mutationId', 'baseRevision', 'action'],
  properties: {
    schemaVersion: {const: 1}, mutationId: uuid,
    baseRevision: {type: 'integer', minimum: 1, maximum: 9007199254740991},
    action: {enum: [
      'paper-trade-confirmed', 'first-position-collected', 'day-one-seen',
      'save-desk-later', 'save-desk-saved',
    ]},
  },
} as const;
const launchV2Schema = {
  ...launchSchema,
  properties: {...launchSchema.properties, schemaVersion: {const: 2},
    action: {enum: [...launchSchema.properties.action.enum, 'introduction-skipped', 'introduction-completed']}},
};

function wantsV2(request: FastifyRequest): boolean {
  const body = request.body as {schemaVersion?: unknown} | undefined;
  return body?.schemaVersion === 2 || (request.headers.accept ?? '').split(',').some(value => {
    const [media, ...parameters] = value.trim().toLowerCase().split(';').map(part => part.trim());
    if (media !== PRODUCT_PROFILE_V2_MEDIA_TYPE) return false;
    if (!parameters.length) return true;
    const quality = /^q=(0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)$/.exec(parameters[0] ?? '');
    return parameters.length === 1 && quality !== null && Number(quality[1]) > 0;
  });
}

function profileResponse(request: FastifyRequest, reply: FastifyReply, profile: ProductProfileSnapshot | null) {
  reply.header('cache-control', 'no-store');
  const priorVary = reply.getHeader('vary');
  const vary = (Array.isArray(priorVary) ? priorVary.join(',') : String(priorVary ?? ''))
    .split(',').map(value => value.trim()).filter(Boolean);
  if (!vary.some(value => value === '*' || value.toLowerCase() === 'accept')) vary.push('Accept');
  reply.header('vary', vary.join(', '));
  if (wantsV2(request)) {
    reply.type(PRODUCT_PROFILE_V2_MEDIA_TYPE);
    return {schemaVersion: 2, profile};
  }
  // Older clients cannot truthfully represent unanswered preferences or an
  // introduction that ended without a trade. Never synthesize answers for them.
  if (profile && (Object.values(profile.onboarding).some(value => value === null) ||
      (profile.launchCheckpoint !== 'first-trade' && !profile.hasConfirmedPaperTrade))) {
    return problem(reply, request, 409, 'PRODUCT_PROFILE_UPGRADE_REQUIRED',
      'Update Trimmy to continue with this desk.');
  }
  if (!profile) return {schemaVersion: 1, profile: null};
  const {hasConfirmedPaperTrade: _hasConfirmedPaperTrade, ...legacy} = profile;
  return {schemaVersion: 1, profile: legacy};
}

function problem(reply: FastifyReply, request: FastifyRequest, status: number, code: string, message: string,
  currentProfile?: unknown) {
  return reply.code(status).send({error: {
    code, message, requestId: request.id,
    ...(currentProfile !== undefined ? {currentProfile} : {}),
  }});
}

function guestProblem(error: GuestSessionError, reply: FastifyReply, request: FastifyRequest) {
  if (error.code === 'GUEST_SESSION_RATE_LIMITED') {
    reply.header('retry-after', String(request.method === 'GET'
      ? GUEST_RATE_WINDOW_SECONDS.profileRead : GUEST_RATE_WINDOW_SECONDS.profileWrite));
    return problem(reply, request, 429, error.code,
      'This guest desk is making requests too quickly. Try again shortly.');
  }
  if (error.code === 'GUEST_SESSION_UNAVAILABLE' || error.code === 'GUEST_SESSION_STORAGE_INVALID' ||
      error.code === 'GUEST_SESSION_RUNTIME_ROLE_INVALID') {
    return problem(reply, request, 503, 'PRODUCT_PROFILE_UNAVAILABLE',
      'Your Trimmy profile is unavailable. Try again.');
  }
  if (error.code === 'GUEST_SESSION_EXPIRED' || error.code === 'GUEST_SESSION_REVOKED') {
    return problem(reply, request, 401, error.code, 'This guest session is no longer available.');
  }
  return problem(reply, request, 401, 'PRODUCT_PROFILE_UNAUTHENTICATED',
    'An active guest session or verified account is required.');
}

function repositoryProblem(error: ProductProfileRepositoryError, reply: FastifyReply, request: FastifyRequest) {
  const map: Partial<Record<ProductProfileRepositoryError['code'], readonly [number, string]>> = {
    PRODUCT_PROFILE_INVALID_INPUT: [400, 'Product profile input is invalid.'],
    PRODUCT_PROFILE_ACCOUNT_NOT_FOUND: [404, 'This Trimmy profile is unavailable.'],
    PRODUCT_PROFILE_IDEMPOTENCY_CONFLICT: [409, 'That mutation ID already belongs to another profile update.'],
    PRODUCT_PROFILE_REVISION_CONFLICT: [409, 'Your Trimmy profile changed. Refresh it and try again.'],
    PRODUCT_PROFILE_REVISION_EXHAUSTED: [409, 'This Trimmy profile cannot accept another revision.'],
    PRODUCT_PROFILE_CHECKPOINT_CONFLICT: [409, 'Complete each launch step in order.'],
    PRODUCT_PROFILE_PAPER_TRADE_REQUIRED: [409, 'Complete a paper trade before collecting your first position.'],
    PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED: [409, 'That launch moment is not ready yet.'],
    PRODUCT_PROFILE_PRINCIPAL_CONFLICT: [409, 'Your desk identity changed. Refresh it and try again.'],
    PRODUCT_PROFILE_MISSING: [409, 'Finish setting up your Trimmy profile first.'],
    PRODUCT_PROFILE_HANDLE_TAKEN: [409, 'That handle is already taken.'],
  };
  const [status, message] = map[error.code] ?? [503, 'Your Trimmy profile is unavailable. Try again.'];
  const code = error.code in map ? error.code : 'PRODUCT_PROFILE_UNAVAILABLE';
  return problem(reply, request, status, code, message,
    error.code === 'PRODUCT_PROFILE_REVISION_CONFLICT' ? error.currentProfile : undefined);
}

/** Accepts an existing verified account or an active guest for this route only. */
export function createProductProfileAuthenticator(
  authenticateAccount: (request: FastifyRequest) => Promise<{readonly userId: string} | null>,
  guests: GuestSessionRepository,
) {
  return async (request: FastifyRequest): Promise<ProductProfilePrincipal | null> => {
    if (requestPracticeBearerToken(request)) {
      const account = await authenticateAccount(request);
      return account ? Object.freeze({kind: 'account' as const, userId: account.userId}) : null;
    }
    const credential = requestGuestAuthorization(request);
    const route = request.routeOptions.url;
    if (!credential || (route !== PRODUCT_PROFILE_ROUTE && route !== PRODUCT_LAUNCH_ROUTE)) return null;
    const scope: GuestPaperScope | undefined = request.method === 'GET' && route === PRODUCT_PROFILE_ROUTE
      ? 'profile_read'
      : (request.method === 'PUT' && route === PRODUCT_PROFILE_ROUTE) ||
          (request.method === 'POST' && route === PRODUCT_LAUNCH_ROUTE) ? 'profile_write' : undefined;
    if (!scope) return null;
    const authorized = await guests.authorize(hashGuestCredential(credential), scope);
    return Object.freeze({kind: 'guest' as const, userId: authorized.userId, guestId: authorized.guestId});
  };
}

async function authenticate(adapters: ProductProfileAdapters, request: FastifyRequest, reply: FastifyReply) {
  try {
    const account = await adapters.authenticate(request);
    if (!account) {
      problem(reply, request, 401, 'PRODUCT_PROFILE_UNAUTHENTICATED',
        'An active guest session or verified account is required.');
      return null;
    }
    return account;
  } catch (error) {
    if (error instanceof GuestSessionError) guestProblem(error, reply, request);
    else if (error instanceof PracticeAuthenticationUnavailable) {
      problem(reply, request, 503, 'PRODUCT_PROFILE_UNAVAILABLE', 'Your Trimmy profile is unavailable.');
    } else {
      request.log.error({errorCode: 'PRODUCT_PROFILE_AUTHENTICATION_FAILED'}, 'product profile authentication failed');
      problem(reply, request, 503, 'PRODUCT_PROFILE_UNAVAILABLE', 'Your Trimmy profile is unavailable. Try again.');
    }
    return null;
  }
}

export function registerProductProfileRoutes(app: FastifyInstance, options?: ProductProfileAdapters): void {
  const adapters = productProfileEnabled(options) ? options : undefined;

  app.get(PRODUCT_PROFILE_ROUTE, {schema: {querystring: noQuery}}, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'PRODUCT_PROFILE_UNAVAILABLE', 'Your Trimmy profile is unavailable.');
    }
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      return profileResponse(request, reply, await adapters.repository.get(account.userId));
    } catch (error) {
      if (error instanceof ProductProfileRepositoryError) return repositoryProblem(error, reply, request);
      request.log.error({errorCode: 'PRODUCT_PROFILE_READ_FAILED'}, 'product profile read failed');
      return problem(reply, request, 503, 'PRODUCT_PROFILE_UNAVAILABLE',
        'Your Trimmy profile is unavailable. Try again.');
    }
  });

  app.put(PRODUCT_PROFILE_ROUTE, {
    bodyLimit: 1024,
    schema: {querystring: noQuery, body: {anyOf: [putSchema, putV2Schema]}},
  }, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'PRODUCT_PROFILE_UNAVAILABLE', 'Your Trimmy profile is unavailable.');
    }
    const account = await authenticate(adapters, request, reply);
    if (!account) return;
    try {
      const body = request.body as Record<string, unknown>;
      const command = parseProductProfileWrite({
        mutationId: body['mutationId'], baseRevision: body['baseRevision'], onboarding: body['onboarding'],
        launchCheckpoint: body['launchCheckpoint'],
      });
      return profileResponse(request, reply, await adapters.repository.put(account.userId, command));
    } catch (error) {
      if (error instanceof ProductProfileRepositoryError) return repositoryProblem(error, reply, request);
      request.log.error({errorCode: 'PRODUCT_PROFILE_WRITE_FAILED'}, 'product profile write failed');
      return problem(reply, request, 503, 'PRODUCT_PROFILE_UNAVAILABLE',
        'Your Trimmy profile is unavailable. Try again.');
    }
  });

  app.post(PRODUCT_LAUNCH_ROUTE, {
    bodyLimit: 512,
    schema: {querystring: noQuery, body: {anyOf: [launchSchema, launchV2Schema]}},
  }, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'PRODUCT_PROFILE_UNAVAILABLE', 'Your Trimmy profile is unavailable.');
    }
    const principal = await authenticate(adapters, request, reply);
    if (!principal) return;
    try {
      const body = request.body as Record<string, unknown>;
      const command = parseProductLaunchWrite({
        mutationId: body['mutationId'], baseRevision: body['baseRevision'], action: body['action'],
      });
      return profileResponse(request, reply, await adapters.repository.advance(principal, command));
    } catch (error) {
      if (error instanceof ProductProfileRepositoryError) return repositoryProblem(error, reply, request);
      request.log.error({errorCode: 'PRODUCT_LAUNCH_WRITE_FAILED'}, 'product launch write failed');
      return problem(reply, request, 503, 'PRODUCT_PROFILE_UNAVAILABLE',
        'Your Trimmy profile is unavailable. Try again.');
    }
  });
}
