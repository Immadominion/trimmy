import type {FastifyInstance, FastifyRequest, FastifyReply} from 'fastify';
import type {Pool} from 'pg';
import {GuestSessionError} from './guest-session-repository.js';

export interface WorkdayWrite {
  assignmentId: string; revision: number; step: number;
  answer: {ids: string[]} | {value: string}; draft?: string;
}
export interface WorkdayAdapters {
  authenticate(request: FastifyRequest): Promise<{readonly userId: string} | null>;
  read(userId: string): Promise<Record<string, unknown>>;
  save(userId: string, input: WorkdayWrite): Promise<Record<string, unknown>>;
}
export function postgresWorkdays(pool: Pool): Pick<WorkdayAdapters, 'read' | 'save'> {
  async function scoped(userId: string, input?: WorkdayWrite) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [userId]);
      const result = input
        ? await client.query('SELECT trimmy.workday_save($1,$2,$3,$4,$5,$6) AS journey',
          [userId,input.assignmentId,input.revision,input.step,JSON.stringify(input.answer),input.draft ?? null])
        : await client.query('SELECT trimmy.workday_read($1) AS journey',[userId]);
      await client.query('COMMIT');
      return result.rows[0].journey as Record<string, unknown>;
    } catch(error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  return {read: userId => scoped(userId), save: (userId,input) => scoped(userId,input)};
}
const slug = {type:'string',pattern:'^[a-z][a-z0-9-]*$',maxLength:80} as const;
const noQuery = {type:'object',additionalProperties:false,properties:{}} as const;
const base = {assignmentId:slug,revision:{type:'integer',minimum:0,maximum:2147483646}};
export function registerWorkdayRoutes(app: FastifyInstance, adapters?: WorkdayAdapters) {
  async function run(request: FastifyRequest, reply: FastifyReply, input?: WorkdayWrite) {
    reply.header('cache-control','no-store');
    if(!adapters) return reply.code(503).send({code:'WORK_UNAVAILABLE'});
    try {
      const account = await adapters.authenticate(request);
      if(!account) return reply.code(401).send({code:'ACCOUNT_REQUIRED'});
      return {journey: input ? await adapters.save(account.userId,input) : await adapters.read(account.userId)};
    } catch(error) {
      if(error instanceof GuestSessionError) {
        const rate = error.code==='GUEST_SESSION_RATE_LIMITED';
        if(rate) reply.header('retry-after','60');
        return reply.code(rate?429:error.code.includes('UNAVAILABLE')?503:401).send({code:error.code});
      }
      const code = error instanceof Error ? error.message : '';
      const status = ['WORK_CHANGED','WORK_LOCKED'].includes(code)?409:
        ['INVALID_WORK','CHECK_EVIDENCE','CHECK_DECISION'].includes(code)?400:code==='ACCOUNT_REQUIRED'?401:503;
      return reply.code(status).send({code:status===503?'WORK_UNAVAILABLE':code});
    }
  }
  app.get('/v1/career/workdays',{schema:{querystring:noQuery}},(request,reply)=>run(request,reply));
  app.post<{Body:WorkdayWrite}>('/v1/career/workdays/step',{
    bodyLimit:4096,schema:{querystring:noQuery,body:{type:'object',additionalProperties:false,
      required:['assignmentId','revision','step','answer'],properties:{...base,step:{type:'integer',minimum:0,maximum:2},
        answer:{oneOf:[{type:'object',additionalProperties:false,required:['ids'],properties:{ids:{type:'array',items:slug,minItems:1,maxItems:6,uniqueItems:true}}},
          {type:'object',additionalProperties:false,required:['value'],properties:{value:{type:'string',minLength:1,maxLength:80}}}]},
        draft:{type:'string',maxLength:280}}}}},(request,reply)=>run(request,reply,request.body));
  app.post<{Body:{assignmentId:string;revision:number;draft:string}}>('/v1/career/workdays/draft',{
    bodyLimit:4096,schema:{querystring:noQuery,body:{type:'object',additionalProperties:false,
      required:['assignmentId','revision','draft'],properties:{...base,draft:{type:'string',maxLength:280}}}}},
    (request,reply)=>run(request,reply,{...request.body,step:-1,answer:{ids:[]}}));
}
