import type {FastifyInstance, FastifyRequest} from 'fastify';
import type {Pool} from 'pg';
import {GuestSessionError} from './guest-session-repository.js';

export interface DailyDeskChoice {date: string; caseId: string; choiceId: string}
export interface DailyDeskAdapters {
  authenticate: (request: FastifyRequest) => Promise<{readonly userId: string} | null>;
  read: (userId: string) => Promise<Record<string, unknown>>;
  complete: (userId: string, choice: DailyDeskChoice) => Promise<Record<string, unknown>>;
}
export function postgresDailyDesk(pool: Pool): Pick<DailyDeskAdapters, 'read' | 'complete'> {
  async function scoped(userId: string, choice?: DailyDeskChoice) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [userId]);
      const result = choice
        ? await client.query('SELECT trimmy.daily_desk_complete($1,$2,$3,$4) AS shift', [userId,choice.date,choice.caseId,choice.choiceId])
        : await client.query('SELECT trimmy.daily_desk_get($1) AS shift', [userId]);
      await client.query('COMMIT');
      return result.rows[0].shift as Record<string, unknown>;
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  return {read: userId => scoped(userId), complete: (userId, choice) => scoped(userId, choice)};
}
const noQuery = {type:'object', additionalProperties:false, properties:{}} as const;
const slug = {type:'string', pattern:'^[a-z][a-z0-9-]*$', maxLength:80} as const;
export function registerDailyDeskRoutes(app: FastifyInstance, adapters?: DailyDeskAdapters) {
  async function run(request: FastifyRequest, reply: import('fastify').FastifyReply, choice?: DailyDeskChoice) {
    reply.header('cache-control','no-store');
    if (!adapters) return reply.code(503).send({code:'DAILY_DESK_UNAVAILABLE'});
    try {
      const account = await adapters.authenticate(request);
      if (!account) return reply.code(401).send({code:'ACCOUNT_REQUIRED'});
      return {shift: choice ? await adapters.complete(account.userId,choice) : await adapters.read(account.userId)};
    } catch (error) {
      if (error instanceof GuestSessionError) {
        const rate = error.code==='GUEST_SESSION_RATE_LIMITED';
        if (rate) reply.header('retry-after','60');
        const unavailable = error.code.includes('UNAVAILABLE') || error.code.includes('INVALID');
        return reply.code(rate ? 429 : unavailable ? 503 : 401).send({code:error.code});
      }
      const message = error instanceof Error ? error.message : '';
      const status = message==='DAY_CHANGED' || message==='SHIFT_ALREADY_COMPLETE' ? 409 : message==='INVALID_CHOICE' ? 400 : message==='ACCOUNT_REQUIRED' ? 401 : 503;
      return reply.code(status).send({code:status===503 ? 'DAILY_DESK_UNAVAILABLE' : message});
    }
  }
  app.get('/v1/career/daily-desk', {schema:{querystring:noQuery}}, (request,reply)=>run(request,reply));
  app.post<{Body:DailyDeskChoice}>('/v1/career/daily-desk/complete', {
    bodyLimit:512,
    schema:{querystring:noQuery, body:{type:'object', additionalProperties:false, required:['date','caseId','choiceId'], properties:{date:{type:'string',format:'date'},caseId:slug,choiceId:slug}}},
  }, (request,reply)=>run(request,reply,request.body));
}
