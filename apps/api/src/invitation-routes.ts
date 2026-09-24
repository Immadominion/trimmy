import type {FastifyInstance, FastifyReply, FastifyRequest} from 'fastify';
import {parsePracticeIdentity} from './practice-identity.js';
import type {PracticeIdentity} from './practice-identity.js';
import {parsePracticeUserId} from './practice-repository.js';
import {PracticeAuthenticationUnavailable} from './practice-session-routes.js';
import type {ExistingPracticeAccountAuthentication} from './practice-session-routes.js';
import {PrivyLinkedIdentityError} from './privy-linked-identities.js';
import type {PrivyLinkedIdentityErrorCode, PrivyLinkedIdentityResolution} from './privy-linked-identities.js';
import {parseXPublicProfile, XProfileLookupError} from './x-profile-lookup.js';
import type {XProfileLookupErrorCode, XProfileResolver} from './x-profile-lookup.js';
import {
  InvitationRepositoryError,
  invitationFields,
  invitationV2Body,
  parseInvitationAction,
  parseInvitationBox,
  parseInvitationId,
  parseInvitationInstant,
  parseInvitationLimit,
  parseInvitationMutationId,
  parseInvitationRecipient,
  parseInvitationV2Cursor,
  parseInvitationVersion,
  parseInvitationXHandle,
  parseXSubject,
} from './invitations-repository.js';
import type {
  InvitationBox,
  InvitationCommand,
  InvitationsRepository,
  InvitationsV2Repository,
  InvitationV2Cursor,
  InvitationV2ListInput,
} from './invitations-repository.js';
import {relationshipSafetyAvailable} from './relationship-safety-config.js';
import type {RelationshipSafetyReadiness} from './relationship-safety-config.js';

export const INVITATIONS_ROUTE = '/v1/invitations';
export const INVITATION_ACTION_ROUTE = '/v1/invitations/:invitationId/actions';

export interface InvitationIdentityResolver {
  resolve(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution>;
  resolveFresh(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution>;
}

export interface InvitationXLookupBudget {
  run<T>(userId: string, operation: () => Promise<T>): Promise<T>;
}

export interface InvitationAdapters {
  readonly repository: Partial<InvitationsRepository & InvitationsV2Repository>;
  /** Retained only for non-production callers that still compose the old shape. */
  readonly authenticate?: (request: FastifyRequest) => Promise<{readonly userId: string} | null>;
  readonly newId?: () => string;
  readonly authenticateContext?: (request: FastifyRequest) =>
    Promise<ExistingPracticeAccountAuthentication | null>;
  readonly linkedIdentities?: InvitationIdentityResolver;
  readonly xProfiles?: XProfileResolver;
  readonly xLookupBudget?: InvitationXLookupBudget;
}

function invitationsV2Enabled(adapters: InvitationAdapters | undefined): adapters is InvitationAdapters & Readonly<{
  repository: InvitationsV2Repository;
  authenticateContext: NonNullable<InvitationAdapters['authenticateContext']>;
  linkedIdentities: InvitationIdentityResolver;
  xProfiles: XProfileResolver;
  xLookupBudget: InvitationXLookupBudget;
}> {
  return typeof adapters?.authenticateContext === 'function' &&
    typeof adapters.linkedIdentities?.resolve === 'function' &&
    typeof adapters.linkedIdentities.resolveFresh === 'function' &&
    typeof adapters.xProfiles?.lookup === 'function' && typeof adapters.xLookupBudget?.run === 'function' &&
    typeof adapters.repository.listV2 === 'function' && typeof adapters.repository.createV2 === 'function' &&
    typeof adapters.repository.senderActionV2 === 'function' && typeof adapters.repository.answerV2 === 'function';
}

/** Only function-backed v2 composition is production invitation authority. */
export function invitationsEnabled(adapters: InvitationAdapters | undefined): adapters is InvitationAdapters {
  return invitationsV2Enabled(adapters);
}

function problem(reply: FastifyReply, request: FastifyRequest, status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}
const unavailable = (reply: FastifyReply, request: FastifyRequest) =>
  problem(reply, request, 503, 'INVITATION_UNAVAILABLE', 'Invitations are unavailable.');
const unauthorized = (reply: FastifyReply, request: FastifyRequest) =>
  problem(reply, request, 401, 'INVITATION_UNAUTHENTICATED', 'A verified account is required.');

function providerFailure(error: unknown, request: FastifyRequest, reply: FastifyReply): FastifyReply | undefined {
  const privyStatuses: Readonly<Record<PrivyLinkedIdentityErrorCode, number>> = Object.freeze({
    PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED: 503,
    PRIVY_VERIFIED_IDENTITY_INVALID: 503,
    PRIVY_USER_RESPONSE_INVALID: 502,
    PRIVY_USER_UNAVAILABLE: 502,
    PRIVY_USER_TIMEOUT: 504,
    PRIVY_USER_RATE_LIMITED: 429,
  });
  if (error instanceof PrivyLinkedIdentityError && Object.hasOwn(privyStatuses, error.code)) {
    const safe = new PrivyLinkedIdentityError(error.code);
    if (privyStatuses[safe.code] === 429) reply.header('retry-after', '60');
    return problem(reply, request, privyStatuses[safe.code], safe.code, safe.message);
  }
  const xStatuses: Readonly<Record<XProfileLookupErrorCode, number>> = Object.freeze({
    X_HANDLE_INVALID: 400,
    X_PROFILE_NOT_FOUND: 404,
    X_LOOKUP_RATE_LIMITED: 429,
    X_PROVIDER_RATE_LIMITED: 429,
    X_LOOKUP_TIMEOUT: 504,
    X_LOOKUP_NOT_CONFIGURED: 503,
    X_LOOKUP_BUDGET_UNAVAILABLE: 503,
    X_PROVIDER_AUTH_FAILED: 503,
    X_PROVIDER_ACCESS_DENIED: 503,
    X_PROVIDER_PAYMENT_REQUIRED: 503,
    X_PROVIDER_UNAVAILABLE: 502,
    X_RESPONSE_INVALID: 502,
  });
  if (error instanceof XProfileLookupError && Object.hasOwn(xStatuses, error.code)) {
    const safe = new XProfileLookupError(error.code);
    if (xStatuses[safe.code] === 429) reply.header('retry-after', '60');
    return problem(reply, request, xStatuses[safe.code], safe.code, safe.message);
  }
  return undefined;
}

function failure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  if (error instanceof PracticeAuthenticationUnavailable) return unavailable(reply, request);
  const provider = providerFailure(error, request, reply);
  if (provider) return provider;
  if (!(error instanceof InvitationRepositoryError)) {
    request.log.error({errorCode: 'INVITATION_REQUEST_FAILED'}, 'invitation request failed');
    return unavailable(reply, request);
  }
  switch (error.code) {
    case 'INVITATION_INVALID_INPUT':
      return problem(reply, request, 400, error.code, 'Invitation request is invalid.');
    case 'INVITATION_FORBIDDEN':
      return problem(reply, request, 403, error.code, 'This account cannot perform that invitation action.');
    case 'INVITATION_NOT_FOUND':
    case 'SOCIAL_PAIR_UNAVAILABLE':
      return problem(reply, request, 404, error.code, 'That invitation is unavailable.');
    case 'INVITATION_ACCOUNT_NOT_FOUND':
    case 'SOCIAL_PROFILE_MISSING':
      return problem(reply, request, 404, error.code, 'The invitation account is unavailable.');
    case 'INVITATION_VERSION_CONFLICT':
      return problem(reply, request, 409, error.code, 'The invitation changed. Reload it before retrying.');
    case 'INVITATION_INVALID_TRANSITION':
      return problem(reply, request, 409, error.code, 'That invitation action is not available now.');
    case 'INVITATION_EXPIRED':
      return problem(reply, request, 409, error.code, 'The invitation has expired.');
    case 'INVITATION_LIMIT_REACHED':
      return problem(reply, request, 409, error.code, 'This account has too many open invitations.');
    case 'SOCIAL_INVITATION_IDEMPOTENCY_CONFLICT':
      return problem(reply, request, 409, error.code, 'That mutation identifier is already in use.');
    case 'SOCIAL_IDENTITY_UNAVAILABLE':
      return problem(reply, request, 409, error.code, 'Link exactly one X account before answering.');
    case 'SOCIAL_IDENTITY_CONFLICT':
      return problem(reply, request, 409, error.code, 'That X account is already linked elsewhere.');
    case 'SOCIAL_FRIEND_LIMIT_REACHED':
      return problem(reply, request, 409, error.code, 'A friendship limit has been reached.');
    case 'SOCIAL_RATE_LIMITED':
      reply.header('retry-after', String(error.retryAfterSeconds ?? 60));
      return problem(reply, request, 429, error.code, 'Too many social requests.');
    case 'INVITATION_STORAGE_INVALID':
      request.log.error({errorCode: error.code}, 'invitation storage invalid');
      return problem(reply, request, 500, error.code, 'Stored invitation data is unavailable.');
    default:
      return unavailable(reply, request);
  }
}

function invalidInput(): never {
  throw new InvitationRepositoryError('INVITATION_INVALID_INPUT', 'Invitation request is invalid.');
}

function createEnvelopeV2(input: unknown): Readonly<{
  mutationId: string;
  expiresAt: string;
}> {
  const fields = invitationFields(input, ['schemaVersion', 'mutationId', 'expiresAt']);
  if (fields['schemaVersion'] !== 2) invalidInput();
  return Object.freeze({
    mutationId: parseInvitationMutationId(fields['mutationId']),
    expiresAt: parseInvitationInstant(fields['expiresAt']),
  });
}

function actionEnvelopeV1(input: unknown): InvitationCommand {
  const keys = input && typeof input === 'object' && !Array.isArray(input) ? Reflect.ownKeys(input) : [];
  const withRecipient = keys.includes('recipient');
  const fields = invitationFields(input, withRecipient
    ? ['schemaVersion', 'action', 'expectedVersion', 'recipient']
    : ['schemaVersion', 'action', 'expectedVersion']);
  if (fields['schemaVersion'] !== 1) invalidInput();
  const action = parseInvitationAction(fields['action']);
  if ((action === 'address') !== withRecipient) invalidInput();
  return Object.freeze({
    action,
    expectedVersion: parseInvitationVersion(fields['expectedVersion']),
    recipient: withRecipient ? parseInvitationRecipient(fields['recipient']) : null,
  });
}

type V2ActionEnvelope = Readonly<{
  action: 'address' | 'offer' | 'accept' | 'decline' | 'cancel';
  expectedVersion: number;
  xHandle: string | null;
}>;

function actionEnvelopeV2(input: unknown): V2ActionEnvelope {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) invalidInput();
  const schemaVersion = Object.getOwnPropertyDescriptor(input, 'schemaVersion')?.value;
  if (schemaVersion === 1) {
    const legacy = actionEnvelopeV1(input);
    // Staged compatibility deliberately ignores the caller's subject. The
    // handle snapshot is resolved again through X before an address write.
    return Object.freeze({
      action: legacy.action,
      expectedVersion: legacy.expectedVersion,
      xHandle: legacy.action === 'address' ? parseInvitationXHandle(legacy.recipient?.handleSnapshot) : null,
    });
  }
  const action = Object.getOwnPropertyDescriptor(input, 'action')?.value;
  const withHandle = action === 'address';
  const fields = invitationFields(input, withHandle
    ? ['schemaVersion', 'action', 'expectedVersion', 'xHandle']
    : ['schemaVersion', 'action', 'expectedVersion']);
  if (fields['schemaVersion'] !== 2 ||
      !['address', 'offer', 'accept', 'decline', 'cancel'].includes(fields['action'] as string)) invalidInput();
  return Object.freeze({
    action: fields['action'] as V2ActionEnvelope['action'],
    expectedVersion: parseInvitationVersion(fields['expectedVersion']),
    xHandle: withHandle ? parseInvitationXHandle(fields['xHandle']) : null,
  });
}

function queryObject(input: unknown): Readonly<Record<string, unknown>> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) invalidInput();
  // Fastify's query parser supplies its own safe object prototype. Read only
  // own data descriptors, so no inherited property or accessor is trusted.
  const allowed = ['box', 'limit', 'cursor'];
  const result: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  for (const key of Reflect.ownKeys(input)) {
    if (typeof key !== 'string' || !allowed.includes(key)) invalidInput();
    const descriptor = Object.getOwnPropertyDescriptor(input, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalidInput();
    result[key] = descriptor.value;
  }
  return result;
}

function decodeCursor(value: unknown, box: InvitationBox): InvitationV2Cursor | null {
  if (value === undefined) return null;
  if (typeof value !== 'string' || value.length < 1 || value.length > 512 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    invalidInput();
  }
  try {
    const raw = Buffer.from(value, 'base64url');
    if (raw.length > 384 || raw.toString('base64url') !== value) invalidInput();
    const decoded: unknown = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(raw));
    if (!Array.isArray(decoded) || decoded.length !== 6 || decoded[0] !== 2 ||
        decoded[1] !== 'invitations' || decoded[3] !== box) invalidInput();
    const cursor = parseInvitationV2Cursor({
      principalSocialId: decoded[2], createdAt: decoded[4], invitationId: decoded[5],
    });
    if (encodeCursor(cursor.principalSocialId, box, cursor.createdAt, cursor.invitationId) !== value) invalidInput();
    return cursor;
  } catch (error) {
    if (error instanceof InvitationRepositoryError) throw error;
    return invalidInput();
  }
}

function listInput(input: unknown): InvitationV2ListInput {
  const query = queryObject(input);
  const box = parseInvitationBox(query['box'] ?? 'open');
  let limit = 20;
  if (query['limit'] !== undefined) {
    if (typeof query['limit'] !== 'string' || !/^(?:[1-9]|[1-4][0-9]|50)$/.test(query['limit'])) invalidInput();
    limit = parseInvitationLimit(Number(query['limit']));
  }
  return Object.freeze({box, limit, cursor: decodeCursor(query['cursor'], box), freshXSubject: null});
}

function encodeCursor(principalSocialId: string, box: InvitationBox, createdAt: string, invitationId: string): string {
  return Buffer.from(JSON.stringify([2, 'invitations', principalSocialId, box, createdAt, invitationId]), 'utf8')
    .toString('base64url');
}

function ownData(value: Record<string, unknown>, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(value, key);
  return descriptor?.enumerable && Object.hasOwn(descriptor, 'value') ? descriptor.value : undefined;
}

function plainObject(value: unknown): Record<string, unknown> | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const prototype: unknown = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null ? value as Record<string, unknown> : null;
}

type ProjectedX = Readonly<{subject: string; handleSnapshot: string; verifiedAt: string}>;

function projectXResolution(value: unknown, identity: PracticeIdentity): ProjectedX | null {
  const resolution = plainObject(value);
  const twitter = resolution && plainObject(ownData(resolution, 'twitter'));
  if (!resolution || ownData(resolution, 'provider') !== 'privy' ||
      ownData(resolution, 'subject') !== identity.subject || !twitter) {
    throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID');
  }
  const status = ownData(twitter, 'status');
  if (status === 'missing' || status === 'ambiguous') return null;
  const subject = ownData(twitter, 'subject');
  const username = ownData(twitter, 'usernameSnapshot');
  const verifiedAtUnixSeconds = ownData(twitter, 'verifiedAtUnixSeconds');
  if (status !== 'verified' || typeof username !== 'string' ||
      /^[a-z0-9_]{1,15}$/.exec(username)?.[0] !== username ||
      typeof verifiedAtUnixSeconds !== 'number' || !Number.isSafeInteger(verifiedAtUnixSeconds) ||
      verifiedAtUnixSeconds < 1 || verifiedAtUnixSeconds > 8_640_000_000_000) {
    throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID');
  }
  let verifiedAt: string;
  try { verifiedAt = new Date(verifiedAtUnixSeconds * 1000).toISOString(); }
  catch { throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID'); }
  let parsedSubject: string;
  try { parsedSubject = parseXSubject(subject); }
  catch { throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID'); }
  return Object.freeze({subject: parsedSubject, handleSnapshot: username, verifiedAt});
}

/**
 * Unfunded invitation intent. All storage calls use the function-backed v2
 * repository. A staged v1 action body may be translated into that authority,
 * but no route can fall back to direct-table invitation methods.
 */
export function registerInvitationRoutes(
  app: FastifyInstance,
  options?: InvitationAdapters,
  relationshipSafetyEnabled = false,
  relationshipSafetyReadiness?: RelationshipSafetyReadiness,
): void {
  const v2 = invitationsV2Enabled(options) ? options : undefined;
  const v2Account = async (request: FastifyRequest, reply: FastifyReply):
    Promise<ExistingPracticeAccountAuthentication | null> => {
    if (!v2) { await unavailable(reply, request); return null; }
    const verified = await v2.authenticateContext(request);
    if (!verified) { await unauthorized(reply, request); return null; }
    return Object.freeze({
      userId: parsePracticeUserId(verified.userId),
      identity: parsePracticeIdentity(verified.identity),
    });
  };

  app.get(INVITATIONS_ROUTE, {
    exposeHeadRoute: false,
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
    schema: {querystring: {type: 'object', additionalProperties: false, properties: {
      box: {type: 'string'}, limit: {type: 'string'}, cursor: {type: 'string'},
    }}},
  }, async (request, reply) => {
    try {
      if (!v2) return unavailable(reply, request);
      const account = await v2Account(request, reply);
      if (!account) return reply;
      const parsed = listInput(request.query);
      const linked = projectXResolution(await v2.linkedIdentities.resolve(account.identity), account.identity);
      const page = await v2.repository.listV2(account.userId, Object.freeze({
        ...parsed,
        freshXSubject: linked?.subject ?? null,
      }));
      if (parsed.cursor !== null && parsed.cursor.principalSocialId !== page.principalSocialId) invalidInput();
      if (page.incomingInvitations !== (linked === null ? 'x_link_required' : 'available')) {
        throw new InvitationRepositoryError('INVITATION_STORAGE_INVALID', 'Stored invitation data is unavailable.');
      }
      if (page.hasMore && page.invitations.length === 0) {
        throw new InvitationRepositoryError('INVITATION_STORAGE_INVALID', 'Stored invitation data is unavailable.');
      }
      const last = page.invitations.at(-1);
      return {
        schemaVersion: 2,
        incomingInvitations: linked === null ? 'x_link_required' : 'available',
        invitations: page.invitations.map(invitationV2Body),
        nextCursor: page.hasMore && last
          ? encodeCursor(page.principalSocialId, parsed.box, last.createdAt, last.id)
          : null,
      };
    } catch (error) { return failure(error, request, reply); }
  });

  app.post(INVITATIONS_ROUTE, {
    bodyLimit: 2048,
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
    schema: {querystring: {type: 'object', additionalProperties: false, properties: {}}, body: {type: 'object'}},
  }, async (request, reply) => {
    try {
      if (!v2) return unavailable(reply, request);
      const account = await v2Account(request, reply);
      if (!account) return reply;
      if (!await relationshipSafetyAvailable(relationshipSafetyEnabled,
        relationshipSafetyReadiness)) return unavailable(reply, request);
      const command = createEnvelopeV2(request.body);
      const result = await v2.repository.createV2(account.userId, command);
      return reply.code(result.created ? 201 : 200).send(invitationV2Body(result.invitation));
    } catch (error) { return failure(error, request, reply); }
  });

  app.post(INVITATION_ACTION_ROUTE, {
    bodyLimit: 2048,
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
    schema: {
      querystring: {type: 'object', additionalProperties: false, properties: {}},
      body: {type: 'object'},
      params: {
        type: 'object', additionalProperties: false, required: ['invitationId'],
        properties: {invitationId: {type: 'string', maxLength: 64}},
      },
    },
  }, async (request, reply) => {
    try {
      const {invitationId: rawId} = request.params as {invitationId: unknown};
      if (!v2) return unavailable(reply, request);
      const account = await v2Account(request, reply);
      if (!account) return reply;
      const invitationId = parseInvitationId(rawId);
      const command = actionEnvelopeV2(request.body);
      if ((command.action === 'address' || command.action === 'offer' || command.action === 'accept') &&
          !await relationshipSafetyAvailable(relationshipSafetyEnabled,
            relationshipSafetyReadiness)) {
        return unavailable(reply, request);
      }
      if (command.action === 'accept' || command.action === 'decline') {
        const linked = projectXResolution(
          await v2.linkedIdentities.resolveFresh(account.identity), account.identity,
        );
        if (linked === null) {
          throw new InvitationRepositoryError('SOCIAL_IDENTITY_UNAVAILABLE', 'A verified X link is required.');
        }
        const answered = await v2.repository.answerV2(account.userId, invitationId, {
          action: command.action,
          expectedVersion: command.expectedVersion,
          identity: linked,
        });
        return invitationV2Body(answered);
      }
      if (command.action === 'address') {
        const profile = await v2.xLookupBudget.run(account.userId, async () =>
          parseXPublicProfile(await v2.xProfiles.lookup(command.xHandle!), command.xHandle!));
        const addressed = await v2.repository.senderActionV2(account.userId, invitationId, {
          action: 'address',
          expectedVersion: command.expectedVersion,
          recipient: Object.freeze({subject: profile.id, handleSnapshot: profile.username.toLowerCase()}),
        });
        return invitationV2Body(addressed);
      }
      const updated = await v2.repository.senderActionV2(account.userId, invitationId, {
        action: command.action,
        expectedVersion: command.expectedVersion,
        recipient: null,
      });
      return invitationV2Body(updated);
    } catch (error) { return failure(error, request, reply); }
  });
}
