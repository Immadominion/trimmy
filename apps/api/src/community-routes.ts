import type {FastifyInstance, FastifyRequest} from 'fastify';
import type {Pool} from 'pg';

export interface CommunityAdapters {
  authenticate: (request: FastifyRequest) => Promise<{readonly userId: string} | null>;
  read: (userId: string, scope: string, at: string | null, id: string | null) => Promise<Record<string, unknown>[]>;
  follow: (userId: string, target: string, following: boolean, notifications: boolean) => Promise<boolean>;
}
export function postgresCommunity(pool: Pool): Pick<CommunityAdapters, 'read' | 'follow'> {
  async function scoped<T>(userId: string, work: (query: (sql: string, values: unknown[]) => Promise<any>) => Promise<T>): Promise<T> {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [userId]);
      const result = await work((sql, values) => client.query(sql, values));
      await client.query('COMMIT');
      return result;
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  return {
    read: (userId, scope, at, id) => scoped(userId, async query =>
      (await query('SELECT * FROM trimmy.community_feed_get($1,$2,$3,$4)', [userId,scope,at,id])).rows),
    follow: (userId, target, following, notifications) => scoped(userId, async query =>
      (await query('SELECT trimmy.community_follow_set($1,$2,$3,$4) AS following', [userId,target,following,notifications])).rows[0].following),
  };
}
const uuid = {type: 'string', format: 'uuid'} as const;
export function registerCommunityRoutes(app: FastifyInstance, adapters?: CommunityAdapters) {
  app.get<{Querystring: {scope?: string; at?: string; id?: string}}>('/v1/community', {
    schema: {querystring: {type: 'object', additionalProperties: false, properties: {
      scope: {type: 'string', enum: ['everyone','following','notifications']},
      at: {type: 'string', format: 'date-time'}, id: uuid,
    }, dependencies: {at: ['id'], id: ['at']}}},
  }, async (request, reply) => {
    reply.header('cache-control', 'no-store');
    if (!adapters) return reply.code(503).send({code: 'COMMUNITY_UNAVAILABLE'});
    try {
      const account = await adapters.authenticate(request);
      if (!account) return reply.code(401).send({code: 'ACCOUNT_REQUIRED'});
      const rows = await adapters.read(account.userId, request.query.scope ?? 'everyone', request.query.at ?? null, request.query.id ?? null);
      const items = rows.slice(0,20).map(row => ({
        reasonId: row.reason_id, socialId: row.social_id, handle: row.handle,
        persona: row.persona, assetId: row.asset_id, variantMint: row.variant_mint,
        symbol: row.symbol, note: row.note, savedAt: row.saved_at,
        following: row.following, notifications: row.notifications, isViewer: row.is_viewer,
      }));
      const last = items.at(-1);
      return {items, next: rows.length>20 && last ? {at: last.savedAt, id: last.reasonId} : null};
    } catch { return reply.code(503).send({code: 'COMMUNITY_UNAVAILABLE'}); }
  });
  app.put<{Params: {socialId: string}; Body: {following: boolean; notifications: boolean}}>('/v1/community/following/:socialId', {
    schema: {params: {type: 'object', required: ['socialId'], additionalProperties: false, properties: {socialId: uuid}},
      body: {type: 'object', required: ['following','notifications'], additionalProperties: false,
        properties: {following: {type:'boolean'}, notifications: {type:'boolean'}}}},
  }, async(request, reply) => {
    reply.header('cache-control','no-store');
    if (!adapters) return reply.code(503).send({code:'COMMUNITY_UNAVAILABLE'});
    try {
      const account = await adapters.authenticate(request);
      if (!account) return reply.code(401).send({code:'ACCOUNT_REQUIRED'});
      return {following: await adapters.follow(account.userId, request.params.socialId, request.body.following, request.body.notifications)};
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      return reply.code(message==='AUTHOR_UNAVAILABLE' || message==='FOLLOW_LIMIT' ? 409 : 503)
        .send({code: message==='FOLLOW_LIMIT' ? 'FOLLOW_LIMIT' : 'FOLLOW_UNAVAILABLE'});
    }
  });
}
