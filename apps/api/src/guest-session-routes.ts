import { createHash } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { parsePracticeIdentity } from './practice-identity.js';
import type { PracticeIdentityVerifier } from './practice-identity.js';
import { GUEST_RATE_WINDOW_SECONDS } from './guest-rate-windows.js';
import { GuestSessionError } from './guest-session-repository.js';
import type { GuestPaperScope, GuestSessionRepository } from './guest-session-repository.js';
import {GuestSourceError} from './guest-creation-source.js';
import type {GuestCreationSource} from './guest-creation-source.js';
import { requestPracticeBearerToken } from './practice-session-routes.js';

export const GUEST_SESSION_ROUTE = '/v1/guest/session';
export const GUEST_REFRESH_ROUTE = '/v1/guest/session/refresh';
export const GUEST_CLAIM_ROUTE = '/v1/guest/claim';

const credentialPattern = /^tg1_[A-Za-z0-9_-]{43}$/;
const replaySecretPattern = /^gr1_[A-Za-z0-9_-]{43}$/;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const uuid = {type: 'string', pattern: '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$', maxLength: 36} as const;
const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;

export interface GuestCreationMaterial {
  readonly guestId: string;
  readonly credential: string;
}

export interface GuestSessionAdapters {
  readonly repository: GuestSessionRepository;
  readonly verifier: PracticeIdentityVerifier;
  readonly source: GuestCreationSource;
}

export function guestSessionsEnabled(adapters?: GuestSessionAdapters): adapters is GuestSessionAdapters {
  return typeof adapters?.repository?.takeCreationAttempt === 'function' &&
    typeof adapters.repository.create === 'function' && typeof adapters.repository.authorize === 'function' &&
    typeof adapters.repository.refresh === 'function' && typeof adapters.repository.claim === 'function' &&
    typeof adapters.verifier?.verify === 'function' && typeof adapters.source?.hash === 'function';
}

export function parseGuestReplaySecret(value: unknown): string | null {
  if (typeof value !== 'string' || !replaySecretPattern.test(value)) return null;
  const secret = Buffer.from(value.slice(4), 'base64url');
  return secret.length === 32 && secret.toString('base64url') === value.slice(4) ? value : null;
}

function guestUuid(bytes: Buffer): string {
  const value = Buffer.from(bytes.subarray(0, 16));
  value[6] = (value[6]! & 0x0f) | 0x40;
  value[8] = (value[8]! & 0x3f) | 0x80;
  const hex = value.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** The 256-bit client proof makes requestId identification, never authorization. */
export function deriveGuestCreation(requestIdValue: string, replaySecretValue: string): GuestCreationMaterial {
  const requestId = requestIdValue.toLowerCase();
  const replaySecret = parseGuestReplaySecret(replaySecretValue);
  if (!uuidPattern.test(requestId) || !replaySecret) throw new Error('Guest creation material is invalid.');
  const input = `${requestId}\0${replaySecret}`;
  const credentialBytes = createHash('sha256')
    .update('trimmy.guest.creation.credential.v1\0').update(input).digest();
  const guestIdBytes = createHash('sha256')
    .update('trimmy.guest.creation.id.v1\0').update(input).digest();
  return Object.freeze({guestId: guestUuid(guestIdBytes),
    credential: `tg1_${credentialBytes.toString('base64url')}`});
}

export function parseGuestCredential(value: unknown): string | null {
  return typeof value === 'string' && credentialPattern.test(value) ? value : null;
}

export function hashGuestCredential(value: string): string {
  const parsed = parseGuestCredential(value);
  if (!parsed) throw new GuestSessionError('GUEST_SESSION_UNAUTHENTICATED', 'Guest session is invalid.');
  return createHash('sha256').update('trimmy.guest.v1\0').update(parsed).digest('hex');
}

export function hashGuestCreationRequest(requestIdValue: string): string {
  const requestId = requestIdValue.toLowerCase();
  if (!uuidPattern.test(requestId)) {
    throw new GuestSessionError('GUEST_SESSION_UNAVAILABLE', 'Guest session creation is unavailable.');
  }
  return createHash('sha256').update('trimmy.guest.creation.request.v1\0').update(requestId).digest('hex');
}

export function hashGuestReplaySecret(value: string): string {
  const replaySecret = parseGuestReplaySecret(value);
  if (!replaySecret) {
    throw new GuestSessionError('GUEST_SESSION_UNAVAILABLE', 'Guest session creation is unavailable.');
  }
  return createHash('sha256').update('trimmy.guest.creation.replay.v1\0').update(replaySecret).digest('hex');
}

function physicalHeader(request: FastifyRequest, name: string): string | null {
  const lower = name.toLowerCase();
  const values: string[] = [];
  for (let index = 0; index < request.raw.rawHeaders.length; index += 2) {
    if (request.raw.rawHeaders[index]?.toLowerCase() === lower) values.push(request.raw.rawHeaders[index + 1] ?? '');
  }
  if (values.length !== 1) return null;
  return values[0] ?? null;
}

export function requestGuestAuthorization(request: FastifyRequest): string | null {
  const header = physicalHeader(request, 'authorization');
  if (header === null || header.length > 64) return null;
  const match = /^Guest (.+)$/i.exec(header);
  return match?.[0] === header ? parseGuestCredential(match[1]) : null;
}

export function requestGuestClaimCredential(request: FastifyRequest): string | null {
  const header = physicalHeader(request, 'x-trimmy-guest');
  return header === null || header.length > 64 ? null : parseGuestCredential(header);
}

function problem(reply: FastifyReply, request: FastifyRequest, status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}

function guestProblem(error: GuestSessionError, reply: FastifyReply, request: FastifyRequest,
  retryAfterSeconds?: number) {
  if (error.code === 'GUEST_SESSION_RATE_LIMITED') {
    const exactRetryAfter = error.retryAfterSeconds ?? retryAfterSeconds;
    if (exactRetryAfter !== undefined) reply.header('retry-after', String(exactRetryAfter));
    return problem(reply, request, 429, error.code, 'This guest desk is making requests too quickly. Try again shortly.');
  }
  if (error.code === 'GUEST_CLAIM_ACCOUNT_EXISTS') {
    return problem(reply, request, 409, error.code, 'This sign-in already has a saved desk. Your guest desk is still available.');
  }
  if (error.code === 'GUEST_CLAIM_ALREADY_USED' || error.code === 'GUEST_CLAIM_IDEMPOTENCY_CONFLICT') {
    return problem(reply, request, 409, error.code, 'This guest desk cannot be claimed by that sign-in.');
  }
  if (error.code === 'GUEST_SESSION_EXPIRED' || error.code === 'GUEST_SESSION_REVOKED' ||
      error.code === 'GUEST_SESSION_UNAUTHENTICATED') {
    return problem(reply, request, 401, error.code, 'This guest session is no longer available.');
  }
  return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable. Try again.');
}

/** Accepts a verified account bearer or an active guest credential for paper only. */
export function createGuestPaperAuthenticator(
  authenticateAccount: (request: FastifyRequest) => Promise<{readonly userId: string} | null>,
  guests: GuestSessionRepository,
) {
  return async (request: FastifyRequest): Promise<{readonly userId: string} | null> => {
    const authorization = physicalHeader(request, 'authorization');
    if (authorization?.toLowerCase().startsWith('bearer ')) return authenticateAccount(request);
    const token = requestGuestAuthorization(request);
    if (!token) return null;
    const scope: GuestPaperScope | undefined = request.routeOptions.url === '/v1/account/paper/portfolio'
      ? 'paper_read' : request.routeOptions.url === '/v1/account/paper/orders/preview'
        ? 'paper_preview' : request.routeOptions.url === '/v1/account/paper/orders/commit'
          ? 'paper_commit' : request.routeOptions.url === '/v1/account/paper/reset'
            ? 'paper_reset' : undefined;
    if (!scope) return null;
    const authorized = await guests.authorize(hashGuestCredential(token), scope);
    return Object.freeze({userId: authorized.userId});
  };
}

export function registerGuestSessionRoutes(app: FastifyInstance, options?: GuestSessionAdapters): void {
  const adapters = guestSessionsEnabled(options) ? options : undefined;
  const creationAdmissions = new WeakMap<FastifyRequest, {readonly sourceHash: string; readonly attemptId: string}>();

  app.post(GUEST_SESSION_ROUTE, {
    bodyLimit: 256,
    onRequest: async (request, reply) => {
      if (!adapters) {
        return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
      }
      try {
        const admission = await adapters.repository.takeCreationAttempt(adapters.source.hash(request));
        creationAdmissions.set(request, admission);
      } catch (error) {
        if (error instanceof GuestSessionError) return guestProblem(error, reply, request);
        if (error instanceof GuestSourceError) {
          return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable. Try again.');
        }
        request.log.error({errorCode: 'GUEST_SESSION_ADMISSION_FAILED'}, 'guest session admission failed');
        return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable. Try again.');
      }
    },
    schema: {querystring: noQuery, body: {type: 'object', additionalProperties: false,
      required: ['schemaVersion', 'requestId', 'replaySecret'], properties: {schemaVersion: {const: 1}, requestId: uuid,
        replaySecret: {type: 'string', pattern: '^gr1_[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$', maxLength: 47}}}},
  }, async (request, reply) => {
    if (!adapters) return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
    try {
      const body = request.body as {requestId: string; replaySecret: string};
      const admission = creationAdmissions.get(request);
      creationAdmissions.delete(request);
      if (!admission) {
        return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable. Try again.');
      }
      const requestId = body.requestId.toLowerCase();
      const material = deriveGuestCreation(requestId, body.replaySecret);
      if (!uuidPattern.test(material.guestId) || !parseGuestCredential(material.credential)) {
        return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
      }
      const session = await adapters.repository.create({sourceHash: admission.sourceHash, attemptId: admission.attemptId,
        requestHash: hashGuestCreationRequest(requestId),
        replayHash: hashGuestReplaySecret(body.replaySecret),
        guestId: material.guestId, credentialHash: hashGuestCredential(material.credential)});
      return reply.code(201).send({schemaVersion: 1, requestId, guestId: session.guestId,
        token: material.credential, expiresAt: session.expiresAt, hardExpiresAt: session.hardExpiresAt});
    } catch (error) {
      if (error instanceof GuestSessionError) return guestProblem(error, reply, request);
      request.log.error({errorCode: 'GUEST_SESSION_CREATE_FAILED'}, 'guest session creation failed');
      return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable. Try again.');
    }
  });

  app.post(GUEST_REFRESH_ROUTE, {
    bodyLimit: 128,
    schema: {querystring: noQuery, body: {type: 'object', additionalProperties: false,
      required: ['schemaVersion'], properties: {schemaVersion: {const: 1}}}},
  }, async (request, reply) => {
    if (!adapters) return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
    const credential = requestGuestAuthorization(request);
    if (!credential) return problem(reply, request, 401, 'GUEST_SESSION_UNAUTHENTICATED', 'An active guest session is required.');
    try {
      const session = await adapters.repository.refresh(hashGuestCredential(credential));
      return {schemaVersion: 1, guestId: session.guestId, expiresAt: session.expiresAt,
        hardExpiresAt: session.hardExpiresAt};
    } catch (error) {
      if (error instanceof GuestSessionError) return guestProblem(error, reply, request, GUEST_RATE_WINDOW_SECONDS.refresh);
      request.log.error({errorCode: 'GUEST_SESSION_REFRESH_FAILED'}, 'guest session refresh failed');
      return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable. Try again.');
    }
  });

  app.post(GUEST_CLAIM_ROUTE, {
    bodyLimit: 256,
    schema: {querystring: noQuery, body: {type: 'object', additionalProperties: false,
      required: ['schemaVersion', 'idempotencyKey'], properties: {schemaVersion: {const: 1}, idempotencyKey: uuid}}},
  }, async (request, reply) => {
    if (!adapters) return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
    const bearer = requestPracticeBearerToken(request);
    const credential = requestGuestClaimCredential(request);
    if (!bearer || !credential) {
      return problem(reply, request, 401, 'GUEST_CLAIM_UNAUTHENTICATED', 'A verified sign-in and active guest desk are required.');
    }
    try {
      const verified = await adapters.verifier.verify(bearer);
      if (!verified) return problem(reply, request, 401, 'GUEST_CLAIM_UNAUTHENTICATED', 'A verified sign-in is required.');
      const identity = parsePracticeIdentity(verified);
      const body = request.body as {idempotencyKey: string};
      const claimed = await adapters.repository.claim({credentialHash: hashGuestCredential(credential), identity,
        idempotencyKey: body.idempotencyKey.toLowerCase()});
      return {schemaVersion: 1, status: 'claimed', guestId: claimed.guestId, claimedAt: claimed.claimedAt};
    } catch (error) {
      if (error instanceof GuestSessionError) return guestProblem(error, reply, request, GUEST_RATE_WINDOW_SECONDS.claim);
      request.log.error({errorCode: 'GUEST_SESSION_CLAIM_FAILED'}, 'guest session claim failed');
      return problem(reply, request, 503, 'GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable. Try again.');
    }
  });
}
