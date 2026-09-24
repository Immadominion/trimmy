import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { PracticeAuthenticationUnavailable } from './practice-session-routes.js';
import {
  WatchlistRepositoryError, parseWatchlistSnapshot,
  parseWatchlistUserId, parseWatchlistWrite, watchlistCatalog, watchlistFields,
} from './watchlist-repository.js';
import type { WatchlistCatalog, WatchlistRepository, WatchlistSnapshot, WatchlistWrite } from './watchlist-repository.js';

/** The fictional sample list. Only the eight sample IDs are storable. */
export const WATCHLIST_ROUTE = '/v1/watchlist';
/** The real list: assets a person looked up through discovery and kept. */
export const FOLLOWING_ROUTE = '/v1/following';
const ROUTES: readonly string[] = [WATCHLIST_ROUTE, FOLLOWING_ROUTE];
const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;

export interface WatchlistAdapters {
  readonly repository: WatchlistRepository;
  readonly authenticate: (request: FastifyRequest) => Promise<{readonly userId: string} | null>;
  readonly allowedAssetIds: ReadonlySet<string> | WatchlistCatalog;
  /**
   * Which list this is. Only the two known paths are registrable, so a caller
   * cannot mount this handler somewhere unintended. Defaults to the sample
   * watchlist so every existing caller is unchanged.
   *
   * Both lists keep one error vocabulary, because the codes describe list
   * semantics (revision conflict, idempotency conflict) rather than the product
   * label, and one storage engine serves both.
   */
  readonly route?: string;
}

/**
 * Whether this list will actually serve at `route`.
 *
 * The route is part of the answer so `GET /v1/config` cannot report a list as
 * enabled while the path refuses every request: adapters that name a different
 * list than they are mounted on fail closed, and the reported capability says
 * so.
 */
export function watchlistEnabled(
  adapters: WatchlistAdapters | undefined,
  route: string = WATCHLIST_ROUTE,
): adapters is WatchlistAdapters {
  if (typeof adapters?.authenticate !== 'function' || typeof adapters.repository?.get !== 'function' ||
      typeof adapters.repository?.put !== 'function' ||
      !ROUTES.includes(route) || (adapters.route ?? route) !== route) return false;
  try { watchlistCatalog(adapters.allowedAssetIds); return true; }
  catch { return false; }
}

function problem(reply: FastifyReply, request: FastifyRequest, status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}
const unavailable = (reply: FastifyReply, request: FastifyRequest) =>
  problem(reply, request, 503, 'WATCHLIST_UNAVAILABLE', 'Watchlist sync is unavailable.');
const unauthorized = (reply: FastifyReply, request: FastifyRequest) =>
  problem(reply, request, 401, 'WATCHLIST_UNAUTHENTICATED', 'A verified account is required.');

function envelope(input: unknown, allowlist: WatchlistCatalog): WatchlistWrite {
  try {
    const fields = watchlistFields(input, ['schemaVersion', 'mutationId', 'baseRevision', 'assetIds']);
    if (fields['schemaVersion'] !== 1) throw new Error();
    return parseWatchlistWrite({mutationId: fields['mutationId'], baseRevision: fields['baseRevision'], assetIds: fields['assetIds']}, allowlist);
  } catch {
    throw new WatchlistRepositoryError('WATCHLIST_INVALID_INPUT', 'Watchlist request is invalid.');
  }
}

function snapshotBody(input: WatchlistSnapshot, allowlist: WatchlistCatalog) {
  return {schemaVersion: 1, ...parseWatchlistSnapshot(input, allowlist)};
}

function failure(error: unknown, request: FastifyRequest, reply: FastifyReply, allowlist: WatchlistCatalog) {
  if (!(error instanceof WatchlistRepositoryError)) {
    request.log.error({errorCode: 'WATCHLIST_REQUEST_FAILED'}, 'watchlist request failed');
    return unavailable(reply, request);
  }
  switch (error.code) {
    case 'WATCHLIST_INVALID_INPUT':
      return problem(reply, request, 400, error.code, 'Watchlist request is invalid.');
    case 'WATCHLIST_ACCOUNT_NOT_FOUND':
      return problem(reply, request, 404, error.code, 'The watchlist account is unavailable.');
    case 'WATCHLIST_IDEMPOTENCY_CONFLICT':
      return problem(reply, request, 409, error.code, 'This mutation ID was already used for a different request.');
    case 'WATCHLIST_REVISION_CONFLICT':
      try {
        if (!error.currentSnapshot) throw new Error();
        return reply.code(409).send({
          error: {code: error.code, message: 'Watchlist changed. Use the current revision before retrying.', requestId: request.id},
          currentSnapshot: snapshotBody(error.currentSnapshot, allowlist),
        });
      } catch {
        return problem(reply, request, 500, 'WATCHLIST_STORAGE_INVALID', 'Stored watchlist is unavailable.');
      }
    case 'WATCHLIST_REVISION_EXHAUSTED':
      return problem(reply, request, 503, error.code, 'Watchlist cannot accept another revision.');
    case 'WATCHLIST_STORAGE_INVALID':
    case 'WATCHLIST_RUNTIME_ROLE_INVALID':
      request.log.error({errorCode: error.code}, 'watchlist storage rejected the request');
      return problem(reply, request, 500, error.code, 'Watchlist storage is unavailable.');
    default:
      return unavailable(reply, request);
  }
}

/** Missing infrastructure is explicit; no fixture session or storage fallback. */
export function registerWatchlistRoutes(
  app: FastifyInstance,
  options?: WatchlistAdapters,
  route: string = WATCHLIST_ROUTE,
): void {
  // The path is the caller's decision, not the adapters'. Both lists register
  // even when unconfigured, so an unconfigured list answers an explicit 503
  // rather than a 404 that looks like a client mistake.
  if (!ROUTES.includes(route)) throw new Error('Unknown list route.');
  const adapters = watchlistEnabled(options, route) ? options : undefined;
  const allowlist: WatchlistCatalog = adapters
    ? watchlistCatalog(adapters.allowedAssetIds)
    : Object.freeze({kind: 'fixed', allowedAssetIds: new Set<string>()});
  const verifiedUsers = new WeakMap<FastifyRequest, string>();
  const authenticate = async (request: FastifyRequest, reply: FastifyReply) => {
    reply.header('cache-control', 'no-store');
    if (!adapters) return unavailable(reply, request);
    try {
      const identity = await adapters.authenticate(request);
      if (!identity) return unauthorized(reply, request);
      verifiedUsers.set(request, parseWatchlistUserId(identity.userId));
    } catch (error) {
      if (error instanceof PracticeAuthenticationUnavailable) return unavailable(reply, request);
      return unauthorized(reply, request);
    }
  };

  app.get(route, {schema: {querystring: noQuery}, onRequest: authenticate}, async (request, reply) => {
    if (!adapters) return unavailable(reply, request);
    const userId = verifiedUsers.get(request);
    if (!userId) return unauthorized(reply, request);
    try { return snapshotBody(await adapters.repository.get(userId), allowlist); }
    catch (error) { return failure(error, request, reply, allowlist); }
  });

  app.put(route, {bodyLimit: 8192, schema: {querystring: noQuery}, onRequest: authenticate}, async (request, reply) => {
    if (!adapters) return unavailable(reply, request);
    const userId = verifiedUsers.get(request);
    if (!userId) return unauthorized(reply, request);
    try {
      const command = envelope(request.body, allowlist);
      const saved = parseWatchlistSnapshot(await adapters.repository.put(userId, command), allowlist);
      if (command.baseRevision === Number.MAX_SAFE_INTEGER || saved.revision !== command.baseRevision + 1 ||
          JSON.stringify(saved.assetIds) !== JSON.stringify(command.assetIds)) {
        throw new WatchlistRepositoryError('WATCHLIST_STORAGE_INVALID', 'Stored watchlist receipt is invalid.');
      }
      return {schemaVersion: 1, ...saved};
    } catch (error) { return failure(error, request, reply, allowlist); }
  });
}
