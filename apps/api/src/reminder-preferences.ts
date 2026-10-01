import type {FastifyInstance, FastifyRequest} from 'fastify';
import type {Pool} from 'pg';
import {hashGuestCredential, requestGuestAuthorization} from './guest-session-routes.js';
import {requestPracticeBearerToken} from './practice-session-routes.js';
import {GuestSessionError, type GuestSessionRepository} from './guest-session-repository.js';

export const REMINDER_PREFERENCES_ROUTE = '/v1/notifications/reminder-preferences';
type Frequency = 'daily' | 'occasional' | 'off';
export interface ReminderPrincipal {userId: string; guestId?: string}
export interface ReminderSnapshot {
  schemaVersion: 1;
  revision: number;
  frequency: Frequency | null;
  claimedGuestId: string | null;
  conflict?: boolean;
}
export interface ReminderWrite {mutationId: string; baseRevision: number; frequency: Frequency}
export interface ReminderStore {
  get(principal: ReminderPrincipal): Promise<ReminderSnapshot>;
  put(principal: ReminderPrincipal, write: ReminderWrite): Promise<ReminderSnapshot>;
}
export interface ReminderAdapters {
  authenticate(request: FastifyRequest): Promise<ReminderPrincipal | null>;
  store: ReminderStore;
}

export function reminderAuthenticator(
  account: ReminderAdapters['authenticate'], guests: GuestSessionRepository,
): ReminderAdapters['authenticate'] {
  return async request => {
    if (requestPracticeBearerToken(request)) return account(request);
    const token = requestGuestAuthorization(request);
    if (!token || request.routeOptions.url !== REMINDER_PREFERENCES_ROUTE ||
        !['GET', 'PUT'].includes(request.method)) return null;
    const scope = await guests.authorize(hashGuestCredential(token),
      request.method === 'GET' ? 'profile_read' : 'profile_write');
    return {userId: scope.userId, guestId: scope.guestId};
  };
}

export function postgresReminders(pool: Pick<Pool, 'connect'>): ReminderStore {
  async function call(principal: ReminderPrincipal, write?: ReminderWrite): Promise<ReminderSnapshot> {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [principal.userId]);
      const result = write
        ? await client.query('SELECT trimmy.reminder_preference_put($1,$2,$3,$4,$5) AS value',
          [principal.userId, principal.guestId ?? null, write.mutationId, write.baseRevision, write.frequency])
        : await client.query('SELECT trimmy.reminder_preference_get($1,$2) AS value',
          [principal.userId, principal.guestId ?? null]);
      const value = result.rows[0]?.value as ReminderSnapshot;
      if (!value || value.schemaVersion !== 1 || !Number.isSafeInteger(value.revision) || value.revision < 0 ||
          ![null, 'daily', 'occasional', 'off'].includes(value.frequency) ||
          (value.revision === 0) !== (value.frequency === null) ||
          (value.claimedGuestId !== null && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value.claimedGuestId)) ||
          (write !== undefined && typeof value.conflict !== 'boolean')) {
        throw Error('PREFERENCE_STORAGE_INVALID');
      }
      await client.query('COMMIT');
      return value;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }
  return {get: principal => call(principal), put: (principal, write) => call(principal, write)};
}

export function registerReminderRoutes(app: FastifyInstance, adapters?: ReminderAdapters) {
  const noQuery = {type: 'object', additionalProperties: false, properties: {}};
  const schema = {
    type: 'object', additionalProperties: false, required: ['mutationId', 'baseRevision', 'frequency'],
    properties: {
      mutationId: {type: 'string', format: 'uuid'},
      baseRevision: {type: 'integer', minimum: 0, maximum: 9007199254740990},
      frequency: {enum: ['daily', 'occasional', 'off']},
    },
  };
  for (const method of ['GET', 'PUT'] as const) app.route({
    method, url: REMINDER_PREFERENCES_ROUTE,
    schema: {querystring: noQuery, ...(method === 'PUT' ? {body: schema} : {})},
    handler: async (request, reply) => {
      reply.header('cache-control', 'no-store');
      if (!adapters) return reply.code(503).send({code: 'REMINDERS_UNAVAILABLE'});
      try {
        const principal = await adapters.authenticate(request);
        if (!principal) return reply.code(401).send({code: 'ACCOUNT_REQUIRED'});
        const result = method === 'GET' ? await adapters.store.get(principal)
          : await adapters.store.put(principal, request.body as ReminderWrite);
        return reply.code(result.conflict ? 409 : 200).send(result);
      } catch (error) {
        if (error instanceof GuestSessionError) {
          if (error.code === 'GUEST_SESSION_RATE_LIMITED') {
            if (error.retryAfterSeconds !== undefined) reply.header('retry-after', String(error.retryAfterSeconds));
            return reply.code(429).send({code: error.code});
          }
          if (['GUEST_SESSION_UNAUTHENTICATED', 'GUEST_SESSION_EXPIRED', 'GUEST_SESSION_REVOKED'].includes(error.code)) {
            return reply.code(401).send({code: error.code});
          }
        }
        if (error instanceof Error && error.message === 'ACCOUNT_REQUIRED') {
          return reply.code(401).send({code: 'ACCOUNT_REQUIRED'});
        }
        return reply.code(503).send({code: 'REMINDERS_UNAVAILABLE'});
      }
    },
  });
}
