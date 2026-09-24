import type {FastifyInstance, FastifyReply, FastifyRequest} from 'fastify';
import {PracticeAuthenticationUnavailable} from './practice-session-routes.js';
import {parsePracticeUserId} from './practice-repository.js';
import {
  SocialRelationshipError, parseSocialHandle, parseSocialInstant, parseSocialLimit,
  parseSocialPersona, parseSocialRank, parseSocialReportCategory, parseSocialRevision,
  parseSocialUuid, socialFields, socialRankLabel,
} from './social-relationships.js';
import type {
  SocialBlockCursor, SocialFriendCursor, SocialRelationshipsRepository,
} from './social-relationships.js';

export const SOCIAL_FRIENDS_ROUTE = '/v1/social/friends';
export const SOCIAL_FRIEND_ACTION_ROUTE = '/v1/social/friends/:friendshipId/actions';
export const SOCIAL_BLOCKS_ROUTE = '/v1/social/blocks';
export const SOCIAL_BLOCK_ROUTE = '/v1/social/blocks/:socialId';
export const SOCIAL_REASON_REPORTS_ROUTE = '/v1/social/reason-reports';

type Authenticate = (request: FastifyRequest) =>
  Promise<Readonly<{readonly userId: string}> | null>;

export interface SocialRelationshipAdapters {
  readonly repository: SocialRelationshipsRepository;
  readonly authenticate: Authenticate;
}

export function socialRelationshipsEnabled(
  adapters?: SocialRelationshipAdapters,
): adapters is SocialRelationshipAdapters {
  return typeof adapters?.authenticate === 'function' &&
    typeof adapters.repository?.listFriends === 'function' &&
    typeof adapters.repository.removeFriend === 'function' &&
    typeof adapters.repository.listBlocks === 'function' &&
    typeof adapters.repository.getBlock === 'function' &&
    typeof adapters.repository.putBlock === 'function' &&
    typeof adapters.repository.reportReason === 'function';
}

function problem(reply: FastifyReply, request: FastifyRequest, status: number,
  code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}

function unavailable(reply: FastifyReply, request: FastifyRequest) {
  return problem(reply, request, 503, 'SOCIAL_UNAVAILABLE', 'Social controls are unavailable.');
}

function invalid(): never {
  throw new SocialRelationshipError('SOCIAL_INVALID_INPUT', 'Social request is invalid.');
}

function outputInvalid(): never {
  throw new SocialRelationshipError('SOCIAL_STORAGE_INVALID', 'Stored social data is unavailable.');
}

function responseFields(input: unknown, allowed: readonly string[]): Record<string, unknown> {
  try { return socialFields(input, allowed); }
  catch { return outputInvalid(); }
}

function responseUuid(value: unknown): string {
  try { return parseSocialUuid(value); } catch { return outputInvalid(); }
}

function responseInstant(value: unknown): string {
  try { return parseSocialInstant(value); } catch { return outputInvalid(); }
}

function responseRevision(value: unknown, allowZero = false): number {
  try { return parseSocialRevision(value, allowZero); } catch { return outputInvalid(); }
}

function friendResponse(input: unknown) {
  const fields = responseFields(input, ['friendshipId', 'revision', 'connectedAt', 'person']);
  const person = responseFields(fields['person'], ['socialId', 'handle', 'persona', 'rank']);
  const rank = responseFields(person['rank'], ['id', 'label']);
  try {
    const rankId = parseSocialRank(rank['id']);
    if (rank['label'] !== socialRankLabel(rankId)) outputInvalid();
    return {
      friendshipId: responseUuid(fields['friendshipId']),
      revision: responseRevision(fields['revision']),
      connectedAt: responseInstant(fields['connectedAt']),
      person: {
        socialId: responseUuid(person['socialId']),
        handle: parseSocialHandle(person['handle']),
        persona: parseSocialPersona(person['persona']),
        rank: {id: rankId, label: socialRankLabel(rankId)},
      },
    };
  } catch (error) {
    if (error instanceof SocialRelationshipError && error.code === 'SOCIAL_STORAGE_INVALID') throw error;
    return outputInvalid();
  }
}

function listedBlockResponse(input: unknown) {
  const fields = responseFields(input,
    ['socialId', 'handle', 'revision', 'blocked', 'updatedAt']);
  try {
    if (fields['handle'] !== null) parseSocialHandle(fields['handle']);
    if (fields['blocked'] !== true) outputInvalid();
    return {
      socialId: responseUuid(fields['socialId']),
      handle: fields['handle'] as string | null,
      revision: responseRevision(fields['revision']),
      updatedAt: responseInstant(fields['updatedAt']),
    };
  } catch (error) {
    if (error instanceof SocialRelationshipError && error.code === 'SOCIAL_STORAGE_INVALID') throw error;
    return outputInvalid();
  }
}

function blockSnapshotResponse(input: unknown) {
  const fields = responseFields(input, ['socialId', 'revision', 'blocked', 'updatedAt']);
  const revision = responseRevision(fields['revision'], true);
  if (typeof fields['blocked'] !== 'boolean' ||
      revision === 0 && (fields['blocked'] || fields['updatedAt'] !== null) ||
      revision > 0 && fields['updatedAt'] === null) outputInvalid();
  return {
    socialId: responseUuid(fields['socialId']),
    revision,
    blocked: fields['blocked'],
    updatedAt: revision === 0 ? null : responseInstant(fields['updatedAt']),
  };
}

function reportResponse(input: unknown) {
  const fields = responseFields(input, ['reportId', 'reasonId', 'category', 'receivedAt']);
  try {
    return {
      reportId: responseUuid(fields['reportId']),
      reasonId: responseUuid(fields['reasonId']),
      category: parseSocialReportCategory(fields['category']),
      receivedAt: responseInstant(fields['receivedAt']),
    };
  } catch (error) {
    if (error instanceof SocialRelationshipError && error.code === 'SOCIAL_STORAGE_INVALID') throw error;
    return outputInvalid();
  }
}

function responseArray(input: unknown, maximum: number): readonly unknown[] {
  if (!Array.isArray(input) || input.length > maximum ||
      Reflect.ownKeys(input).length !== input.length + 1) outputInvalid();
  for (let index = 0; index < input.length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(input, String(index));
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) outputInvalid();
  }
  return input;
}

function mutationBlockResponse(input: unknown) {
  const fields = responseFields(input,
    ['socialId', 'handle', 'revision', 'blocked', 'updatedAt']);
  if (fields['handle'] !== null || typeof fields['blocked'] !== 'boolean') outputInvalid();
  return {
    socialId: responseUuid(fields['socialId']),
    revision: responseRevision(fields['revision']),
    blocked: fields['blocked'],
    updatedAt: responseInstant(fields['updatedAt']),
  };
}

function failure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  if (error instanceof PracticeAuthenticationUnavailable) return unavailable(reply, request);
  if (!(error instanceof SocialRelationshipError)) {
    request.log.error({errorCode: 'SOCIAL_REQUEST_FAILED'}, 'social request failed');
    return unavailable(reply, request);
  }
  switch (error.code) {
    case 'SOCIAL_INVALID_INPUT':
      return problem(reply, request, 400, error.code, 'Social request is invalid.');
    case 'SOCIAL_RELATIONSHIP_FORBIDDEN':
      return problem(reply, request, 403, error.code, 'This account cannot change that relationship.');
    case 'SOCIAL_ACCOUNT_NOT_FOUND':
    case 'SOCIAL_RELATIONSHIP_NOT_FOUND':
    case 'SOCIAL_PAIR_UNAVAILABLE':
      return problem(reply, request, 404, error.code, 'That social item is unavailable.');
    case 'SOCIAL_RELATIONSHIP_REVISION_CONFLICT':
    case 'SOCIAL_RELATIONSHIP_NOT_ACTIVE':
      return problem(reply, request, 409, error.code, 'That relationship changed. Reload it before retrying.');
    case 'SOCIAL_RELATIONSHIP_IDEMPOTENCY_CONFLICT':
    case 'SOCIAL_BLOCK_IDEMPOTENCY_CONFLICT':
    case 'SOCIAL_REPORT_IDEMPOTENCY_CONFLICT':
      return problem(reply, request, 409, error.code, 'That mutation identifier is already in use.');
    case 'SOCIAL_BLOCK_REVISION_CONFLICT':
      return problem(reply, request, 409, error.code, 'That block changed. Reload it before retrying.');
    case 'SOCIAL_RATE_LIMITED':
      reply.header('retry-after', String(error.retryAfterSeconds ?? 60));
      return problem(reply, request, 429, error.code, 'Too many social requests.');
    case 'SOCIAL_STORAGE_INVALID':
      request.log.error({errorCode: error.code}, 'social storage invalid');
      return problem(reply, request, 500, error.code, 'Stored social data is unavailable.');
    case 'SOCIAL_RUNTIME_ROLE_INVALID':
    case 'SOCIAL_UNAVAILABLE':
      return unavailable(reply, request);
  }
}

function queryFields(input: unknown): Record<string, unknown> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
  const result: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  for (const key of Reflect.ownKeys(input)) {
    if (typeof key !== 'string' || !['limit', 'cursor'].includes(key)) invalid();
    const descriptor = Object.getOwnPropertyDescriptor(input, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    result[key] = descriptor.value;
  }
  return result;
}

function pageLimit(value: unknown): number {
  if (value === undefined) return 20;
  if (typeof value !== 'string' || !/^(?:[1-9]|[1-4][0-9]|50)$/u.test(value)) invalid();
  return parseSocialLimit(Number(value));
}

function decodeCursor(value: unknown, kind: 'friends'): SocialFriendCursor | null;
function decodeCursor(value: unknown, kind: 'blocks'): SocialBlockCursor | null;
function decodeCursor(value: unknown, kind: 'friends' | 'blocks'):
  SocialFriendCursor | SocialBlockCursor | null {
  if (value === undefined) return null;
  if (typeof value !== 'string' || value.length < 1 || value.length > 512 ||
      !/^[A-Za-z0-9_-]+$/u.test(value)) invalid();
  try {
    const raw = Buffer.from(value, 'base64url');
    if (raw.length > 384 || raw.toString('base64url') !== value) invalid();
    const decoded: unknown = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(raw));
    if (!Array.isArray(decoded) || decoded.length !== 5 || decoded[0] !== 1 || decoded[1] !== kind) invalid();
    const principalSocialId = parseSocialUuid(decoded[2]);
    const at = parseSocialInstant(decoded[3]);
    const id = parseSocialUuid(decoded[4]);
    if (encodeCursor(kind, principalSocialId, at, id) !== value) invalid();
    return kind === 'friends'
      ? Object.freeze({principalSocialId, connectedAt: at, friendshipId: id})
      : Object.freeze({principalSocialId, updatedAt: at, socialId: id});
  } catch (error) {
    if (error instanceof SocialRelationshipError) throw error;
    return invalid();
  }
}

function encodeCursor(kind: 'friends' | 'blocks', principalSocialId: string,
  at: string, id: string): string {
  return Buffer.from(JSON.stringify([1, kind, principalSocialId, at, id]), 'utf8').toString('base64url');
}

function friendRemovalBody(input: unknown) {
  const fields = socialFields(input,
    ['schemaVersion', 'action', 'mutationId', 'expectedRevision']);
  if (fields['schemaVersion'] !== 1 || fields['action'] !== 'remove') invalid();
  return Object.freeze({
    mutationId: parseSocialUuid(fields['mutationId']),
    expectedRevision: parseSocialRevision(fields['expectedRevision']),
  });
}

function blockPutBody(input: unknown) {
  const fields = socialFields(input,
    ['schemaVersion', 'mutationId', 'baseRevision', 'blocked']);
  if (fields['schemaVersion'] !== 1 || typeof fields['blocked'] !== 'boolean') invalid();
  return Object.freeze({
    mutationId: parseSocialUuid(fields['mutationId']),
    baseRevision: parseSocialRevision(fields['baseRevision'], true),
    blocked: fields['blocked'],
  });
}

function reasonReportBody(input: unknown) {
  const fields = socialFields(input,
    ['schemaVersion', 'mutationId', 'reasonId', 'category']);
  if (fields['schemaVersion'] !== 1) invalid();
  return Object.freeze({
    mutationId: parseSocialUuid(fields['mutationId']),
    reasonId: parseSocialUuid(fields['reasonId']),
    category: parseSocialReportCategory(fields['category']),
  });
}

const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;
const listQuery = {type: 'object', additionalProperties: false, properties: {
  limit: {type: 'string'}, cursor: {type: 'string'},
}} as const;

/**
 * Relationship exits and safety controls deliberately remain mounted while the
 * activation flag is off. The flag gates invitation activation and friends
 * reason reads elsewhere, never removal, blocking, unblocking or reporting.
 */
export function registerSocialRelationshipRoutes(
  app: FastifyInstance,
  options?: SocialRelationshipAdapters,
): void {
  const adapters = socialRelationshipsEnabled(options) ? options : undefined;

  const account = async (request: FastifyRequest, reply: FastifyReply): Promise<string | null> => {
    if (!adapters) { await unavailable(reply, request); return null; }
    const authenticated = await adapters.authenticate(request);
    if (!authenticated) {
      await problem(reply, request, 401, 'SOCIAL_UNAUTHENTICATED', 'A verified account is required.');
      return null;
    }
    return parsePracticeUserId(authenticated.userId);
  };

  app.get(SOCIAL_FRIENDS_ROUTE, {
    exposeHeadRoute: false,
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
    schema: {querystring: listQuery},
  }, async (request, reply) => {
    try {
      const userId = await account(request, reply);
      if (!adapters || !userId) return reply;
      const query = queryFields(request.query);
      const limit = pageLimit(query['limit']);
      const cursor = decodeCursor(query['cursor'], 'friends');
      const page = await adapters.repository.listFriends(userId, {limit, cursor});
      const pageFields = responseFields(page, ['principalSocialId', 'friends', 'hasMore']);
      const principalSocialId = responseUuid(pageFields['principalSocialId']);
      if (typeof pageFields['hasMore'] !== 'boolean') outputInvalid();
      const friends = responseArray(pageFields['friends'], limit).map(friendResponse);
      if (cursor !== null && cursor.principalSocialId !== principalSocialId) invalid();
      if (pageFields['hasMore'] && friends.length === 0) outputInvalid();
      const last = friends.at(-1);
      return {
        schemaVersion: 1,
        friends,
        nextCursor: pageFields['hasMore'] && last
          ? encodeCursor('friends', principalSocialId, last.connectedAt, last.friendshipId)
          : null,
      };
    } catch (error) { return failure(error, request, reply); }
  });

  app.post(SOCIAL_FRIEND_ACTION_ROUTE, {
    bodyLimit: 2048,
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
    schema: {
      querystring: noQuery, body: {type: 'object'},
      params: {type: 'object', additionalProperties: false, required: ['friendshipId'],
        properties: {friendshipId: {type: 'string', maxLength: 64}}},
    },
  }, async (request, reply) => {
    try {
      const userId = await account(request, reply);
      if (!adapters || !userId) return reply;
      const friendshipId = parseSocialUuid(
        (request.params as {friendshipId: unknown}).friendshipId,
      );
      const command = friendRemovalBody(request.body);
      const removal = await adapters.repository.removeFriend(userId, friendshipId, command);
      const fields = responseFields(removal,
        ['mutationId', 'friendshipId', 'appliedRevision', 'state', 'occurredAt']);
      if (responseUuid(fields['mutationId']) !== command.mutationId ||
          responseUuid(fields['friendshipId']) !== friendshipId || fields['state'] !== 'removed') {
        outputInvalid();
      }
      return {
        schemaVersion: 1,
        mutationId: command.mutationId,
        friendshipId,
        appliedRevision: responseRevision(fields['appliedRevision']),
        state: 'removed',
        occurredAt: responseInstant(fields['occurredAt']),
      };
    } catch (error) { return failure(error, request, reply); }
  });

  app.get(SOCIAL_BLOCKS_ROUTE, {
    exposeHeadRoute: false,
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
    schema: {querystring: listQuery},
  }, async (request, reply) => {
    try {
      const userId = await account(request, reply);
      if (!adapters || !userId) return reply;
      const query = queryFields(request.query);
      const limit = pageLimit(query['limit']);
      const cursor = decodeCursor(query['cursor'], 'blocks');
      const page = await adapters.repository.listBlocks(userId, {limit, cursor});
      const pageFields = responseFields(page, ['principalSocialId', 'blocks', 'hasMore']);
      const principalSocialId = responseUuid(pageFields['principalSocialId']);
      if (typeof pageFields['hasMore'] !== 'boolean') outputInvalid();
      const blocks = responseArray(pageFields['blocks'], limit).map(listedBlockResponse);
      if (cursor !== null && cursor.principalSocialId !== principalSocialId) invalid();
      if (pageFields['hasMore'] && blocks.length === 0) outputInvalid();
      const last = blocks.at(-1);
      return {
        schemaVersion: 1,
        blocks,
        nextCursor: pageFields['hasMore'] && last
          ? encodeCursor('blocks', principalSocialId, last.updatedAt, last.socialId)
          : null,
      };
    } catch (error) { return failure(error, request, reply); }
  });

  app.get(SOCIAL_BLOCK_ROUTE, {
    exposeHeadRoute: false,
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
    schema: {
      querystring: noQuery,
      params: {type: 'object', additionalProperties: false, required: ['socialId'],
        properties: {socialId: {type: 'string', maxLength: 64}}},
    },
  }, async (request, reply) => {
    try {
      const userId = await account(request, reply);
      if (!adapters || !userId) return reply;
      const socialId = parseSocialUuid((request.params as {socialId: unknown}).socialId);
      const block = blockSnapshotResponse(await adapters.repository.getBlock(userId, socialId));
      if (block.socialId !== socialId) outputInvalid();
      return {schemaVersion: 1, block};
    } catch (error) { return failure(error, request, reply); }
  });

  app.put(SOCIAL_BLOCK_ROUTE, {
    bodyLimit: 2048,
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
    schema: {
      querystring: noQuery, body: {type: 'object'},
      params: {type: 'object', additionalProperties: false, required: ['socialId'],
        properties: {socialId: {type: 'string', maxLength: 64}}},
    },
  }, async (request, reply) => {
    try {
      const userId = await account(request, reply);
      if (!adapters || !userId) return reply;
      const socialId = parseSocialUuid((request.params as {socialId: unknown}).socialId);
      const command = blockPutBody(request.body);
      const result = await adapters.repository.putBlock(userId, socialId, command);
      const fields = responseFields(result, ['mutationId', 'appliedRevision', 'block']);
      const block = mutationBlockResponse(fields['block']);
      const appliedRevision = responseRevision(fields['appliedRevision']);
      if (responseUuid(fields['mutationId']) !== command.mutationId ||
          block.socialId !== socialId || appliedRevision > block.revision) outputInvalid();
      return {
        schemaVersion: 1,
        mutationId: command.mutationId,
        appliedRevision,
        block,
      };
    } catch (error) { return failure(error, request, reply); }
  });

  app.post(SOCIAL_REASON_REPORTS_ROUTE, {
    bodyLimit: 2048,
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
    schema: {querystring: noQuery, body: {type: 'object'}},
  }, async (request, reply) => {
    try {
      const userId = await account(request, reply);
      if (!adapters || !userId) return reply;
      const command = reasonReportBody(request.body);
      const result = await adapters.repository.reportReason(userId, command);
      const fields = responseFields(result, ['report', 'created']);
      if (typeof fields['created'] !== 'boolean') outputInvalid();
      const report = reportResponse(fields['report']);
      if (report.reasonId !== command.reasonId || fields['created'] && report.category !== command.category) {
        outputInvalid();
      }
      return reply.code(fields['created'] ? 202 : 200).send({schemaVersion: 1, report});
    } catch (error) { return failure(error, request, reply); }
  });
}
