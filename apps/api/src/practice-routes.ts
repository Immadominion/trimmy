import { Buffer } from 'node:buffer';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { parsePracticeProgress } from '@trimmy/domain';
import {
  PracticeRepositoryError, parsePracticeUserId, parsePracticeWrite,
} from './practice-repository.js';
import type { PracticeRepository, PracticeSnapshot, PracticeWrite } from './practice-repository.js';
import { PracticeAuthenticationUnavailable } from './practice-session-routes.js';

export const PRACTICE_PROGRESS_ROUTE = '/v1/practice/progress';
const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;

/** The application must inject a verifier that resolves a server-owned account UUID. */
export interface PracticeSyncAdapters {
  readonly repository: PracticeRepository;
  readonly authenticate: (request: FastifyRequest) => Promise<{readonly userId: string} | null>;
}

export function practiceSyncEnabled(adapters: PracticeSyncAdapters | undefined): adapters is PracticeSyncAdapters {
  return typeof adapters?.authenticate === 'function' &&
    typeof adapters.repository?.get === 'function' && typeof adapters.repository?.put === 'function';
}

function problem(reply: FastifyReply, request: FastifyRequest, status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}

function unavailable(reply: FastifyReply, request: FastifyRequest) {
  return problem(reply, request, 503, 'PRACTICE_SYNC_UNAVAILABLE', 'Practice sync is unavailable.');
}

function unauthorized(reply: FastifyReply, request: FastifyRequest) {
  return problem(reply, request, 401, 'PRACTICE_UNAUTHENTICATED', 'A verified account is required.');
}

function parseEnvelope(input: unknown): PracticeWrite {
  try {
    if (input === null || typeof input !== 'object' || Array.isArray(input)) throw new Error();
    const fields = Object.keys(input);
    if (fields.length !== 4 || fields.some(field => !['schemaVersion', 'mutationId', 'baseRevision', 'progress'].includes(field))) throw new Error();
    const body = input as Record<string, unknown>;
    if (body['schemaVersion'] !== 1) throw new Error();
    // The wrapper has its own raw body limit; progress also has a UTF-8 limit.
    const progressJson = JSON.stringify(body['progress']);
    if (progressJson === undefined || Buffer.byteLength(progressJson, 'utf8') > 32_768) throw new Error();
    return parsePracticeWrite({mutationId: body['mutationId'], baseRevision: body['baseRevision'], progress: body['progress']});
  } catch {
    throw new PracticeRepositoryError('PRACTICE_INVALID_INPUT', 'Practice request is invalid.');
  }
}

/** Project a validated snapshot, never arbitrary repository fields, into the response. */
function snapshotBody(snapshot: PracticeSnapshot) {
  try {
    if (!Number.isSafeInteger(snapshot.revision) || snapshot.revision < 0) throw new Error();
    if (snapshot.revision === 0) {
      if (snapshot.progress !== null || snapshot.updatedAt !== null) throw new Error();
      return {schemaVersion: 1, revision: 0, progress: null, updatedAt: null};
    }
    if (typeof snapshot.updatedAt !== 'string' || new Date(snapshot.updatedAt).toISOString() !== snapshot.updatedAt) throw new Error();
    return {schemaVersion: 1, revision: snapshot.revision, progress: parsePracticeProgress(snapshot.progress), updatedAt: snapshot.updatedAt};
  } catch {
    throw new PracticeRepositoryError('PRACTICE_STORAGE_INVALID', 'Stored practice progress is unavailable.');
  }
}

function repositoryFailure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  if (!(error instanceof PracticeRepositoryError)) {
    request.log.error({errorCode: 'PRACTICE_SYNC_FAILED'}, 'practice request failed');
    return unavailable(reply, request);
  }
  // Error.message can originate in a provider: only fixed messages leave this layer.
  switch (error.code) {
    case 'PRACTICE_INVALID_INPUT':
      return problem(reply, request, 400, error.code, 'Practice request is invalid.');
    case 'PRACTICE_ACCOUNT_NOT_FOUND':
      return problem(reply, request, 404, error.code, 'The practice account is unavailable.');
    case 'PRACTICE_IDEMPOTENCY_CONFLICT':
      return problem(reply, request, 409, error.code, 'This mutation ID was already used for a different request.');
    case 'PRACTICE_VERSION_DOWNGRADE':
      return problem(reply, request, 409, error.code, 'A newer practice payload has already been saved. Update this client before saving.');
    case 'PRACTICE_HISTORY_CONFLICT':
      return problem(reply, request, 409, error.code, 'Saved first-completion history cannot be replaced.');
    case 'PRACTICE_REVISION_CONFLICT': {
      if (error.currentSnapshot) {
        try {
          return reply.code(409).send({
            error: {code: error.code, message: 'Practice progress changed. Use the current revision before retrying.', requestId: request.id},
            currentSnapshot: snapshotBody(error.currentSnapshot),
          });
        } catch {
          return problem(reply, request, 500, 'PRACTICE_STORAGE_INVALID', 'Stored practice progress is unavailable.');
        }
      }
      return problem(reply, request, 500, 'PRACTICE_STORAGE_INVALID', 'Stored practice progress is unavailable.');
    }
    case 'PRACTICE_REVISION_EXHAUSTED':
      return problem(reply, request, 503, error.code, 'Practice progress cannot accept another revision.');
    case 'PRACTICE_STORAGE_INVALID':
    case 'PRACTICE_RUNTIME_ROLE_INVALID':
      request.log.error({errorCode: error.code}, 'practice storage rejected the request');
      return problem(reply, request, 500, error.code, 'Practice storage is unavailable.');
    default:
      return unavailable(reply, request);
  }
}

/** Always register the exact routes; absent infrastructure remains an explicit 503. */
export function registerPracticeRoutes(app: FastifyInstance, options?: PracticeSyncAdapters): void {
  const adapters = practiceSyncEnabled(options) ? options : undefined;
  const verifiedUsers = new WeakMap<FastifyRequest, string>();
  const authenticate = async (request: FastifyRequest, reply: FastifyReply) => {
    if (!adapters) return unavailable(reply, request);
    try {
      const identity = await adapters.authenticate(request);
      if (!identity) return unauthorized(reply, request);
      verifiedUsers.set(request, parsePracticeUserId(identity.userId));
    } catch (error) {
      if (error instanceof PracticeAuthenticationUnavailable) return unavailable(reply, request);
      return unauthorized(reply, request);
    }
  };

  app.get(PRACTICE_PROGRESS_ROUTE, {schema: {querystring: noQuery}, onRequest: authenticate}, async (request, reply) => {
    const userId = verifiedUsers.get(request);
    if (!adapters) return unavailable(reply, request);
    if (!userId) return unauthorized(reply, request);
    try {
      return snapshotBody(await adapters.repository.get(userId));
    } catch (error) {
      return repositoryFailure(error, request, reply);
    }
  });

  app.put(PRACTICE_PROGRESS_ROUTE, {
    bodyLimit: 36_864,
    schema: {querystring: noQuery},
    onRequest: authenticate,
  }, async (request, reply) => {
    const userId = verifiedUsers.get(request);
    if (!adapters) return unavailable(reply, request);
    if (!userId) return unauthorized(reply, request);
    try {
      const command = parseEnvelope(request.body);
      return snapshotBody(await adapters.repository.put(userId, command));
    } catch (error) {
      return repositoryFailure(error, request, reply);
    }
  });
}
