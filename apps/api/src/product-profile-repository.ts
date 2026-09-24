export const PRODUCT_GOALS = Object.freeze(['learn', 'practice', 'trade', 'beat-friends'] as const);
export const PRODUCT_KNOWLEDGE = Object.freeze(
  ['nothing', 'basics', 'practice', 'traded-before', 'daily-trader'] as const,
);
export const PRODUCT_PERSONAS = Object.freeze(['wolf', 'oracle', 'shark'] as const);
export const PRODUCT_DAILY_GOALS = Object.freeze(['show-up', 'one-mission', 'three-missions'] as const);
export const PRODUCT_LAUNCH_CHECKPOINTS = Object.freeze(
  ['first-trade', 'first-position', 'streak', 'save-desk', 'app'] as const,
);
export const PRODUCT_LAUNCH_ACTIONS = Object.freeze([
  'paper-trade-confirmed',
  'first-position-collected',
  'day-one-seen',
  'save-desk-later',
  'save-desk-saved',
  'introduction-skipped',
  'introduction-completed',
] as const);

export type ProductGoal = typeof PRODUCT_GOALS[number];
export type ProductKnowledge = typeof PRODUCT_KNOWLEDGE[number];
export type ProductPersona = typeof PRODUCT_PERSONAS[number];
export type ProductDailyGoal = typeof PRODUCT_DAILY_GOALS[number];
export type ProductLaunchCheckpoint = typeof PRODUCT_LAUNCH_CHECKPOINTS[number];
export type ProductLaunchAction = typeof PRODUCT_LAUNCH_ACTIONS[number];

export type ProductProfilePrincipal =
  | {readonly kind: 'account'; readonly userId: string}
  | {readonly kind: 'guest'; readonly userId: string; readonly guestId: string};

export interface ProductOnboardingProfile {
  readonly goal: ProductGoal | null;
  readonly knowledge: ProductKnowledge | null;
  readonly persona: ProductPersona | null;
  readonly dailyGoal: ProductDailyGoal | null;
  readonly handle: string | null;
}

export interface ProductProfileSnapshot {
  readonly revision: number;
  readonly onboarding: ProductOnboardingProfile;
  readonly launchCheckpoint: ProductLaunchCheckpoint;
  readonly hasConfirmedPaperTrade: boolean;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface ProductProfileWrite {
  readonly mutationId: string;
  readonly baseRevision: number;
  readonly onboarding: ProductOnboardingProfile;
  readonly launchCheckpoint: ProductLaunchCheckpoint;
}

export interface ProductLaunchWrite {
  readonly mutationId: string;
  readonly baseRevision: number;
  readonly action: ProductLaunchAction;
}

export interface ProductProfileRepository {
  get(userId: string): Promise<ProductProfileSnapshot | null>;
  put(userId: string, command: ProductProfileWrite): Promise<ProductProfileSnapshot>;
  advance(principal: ProductProfilePrincipal, command: ProductLaunchWrite): Promise<ProductProfileSnapshot>;
}

export type ProductProfileRepositoryErrorCode =
  | 'PRODUCT_PROFILE_INVALID_INPUT'
  | 'PRODUCT_PROFILE_ACCOUNT_NOT_FOUND'
  | 'PRODUCT_PROFILE_IDEMPOTENCY_CONFLICT'
  | 'PRODUCT_PROFILE_REVISION_CONFLICT'
  | 'PRODUCT_PROFILE_REVISION_EXHAUSTED'
  | 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT'
  | 'PRODUCT_PROFILE_PAPER_TRADE_REQUIRED'
  | 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED'
  | 'PRODUCT_PROFILE_PRINCIPAL_CONFLICT'
  | 'PRODUCT_PROFILE_MISSING'
  | 'PRODUCT_PROFILE_HANDLE_TAKEN'
  | 'PRODUCT_PROFILE_STORAGE_INVALID'
  | 'PRODUCT_PROFILE_RUNTIME_ROLE_INVALID';

export class ProductProfileRepositoryError extends Error {
  constructor(
    readonly code: ProductProfileRepositoryErrorCode,
    message: string,
    readonly currentProfile?: ProductProfileSnapshot | null,
  ) {
    super(message);
    this.name = 'ProductProfileRepositoryError';
  }
}

function invalid(): never {
  throw new ProductProfileRepositoryError('PRODUCT_PROFILE_INVALID_INPUT', 'Product profile input is invalid.');
}

function fields(input: unknown, expected: readonly string[]): Readonly<Record<string, unknown>> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
  const prototype: unknown = Object.getPrototypeOf(input);
  if (prototype !== Object.prototype && prototype !== null) invalid();
  const keys = Reflect.ownKeys(input);
  if (keys.length !== expected.length ||
      keys.some(key => typeof key !== 'string' || !expected.includes(key))) invalid();
  const result: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(input, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    result[key as string] = descriptor.value;
  }
  return Object.freeze(result);
}

function member<T extends string>(input: unknown, values: readonly T[]): T {
  if (typeof input !== 'string' || !values.includes(input as T)) invalid();
  return input as T;
}

function uuid(input: unknown): string {
  if (typeof input !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(input)) invalid();
  return input.toLowerCase();
}

function handle(input: unknown): string {
  if (typeof input !== 'string' || !/^[a-z][a-z0-9_]{2,17}$/.test(input)) invalid();
  return input;
}

function timestamp(input: unknown): string {
  if (typeof input !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(input) ||
      new Date(input).toISOString() !== input) invalid();
  return input;
}

export function parseProductProfileUserId(input: unknown): string { return uuid(input); }

export function parseProductProfilePrincipal(input: unknown): ProductProfilePrincipal {
  if (input !== null && typeof input === 'object' && !Array.isArray(input) &&
      Object.getOwnPropertyDescriptor(input, 'kind')?.value === 'account') {
    const value = fields(input, ['kind', 'userId']);
    return Object.freeze({kind: member(value['kind'], ['account'] as const), userId: uuid(value['userId'])});
  }
  const value = fields(input, ['kind', 'userId', 'guestId']);
  return Object.freeze({
    kind: member(value['kind'], ['guest'] as const),
    userId: uuid(value['userId']),
    guestId: uuid(value['guestId']),
  });
}

export function parseProductOnboarding(input: unknown): ProductOnboardingProfile {
  const value = fields(input, ['goal', 'knowledge', 'persona', 'dailyGoal', 'handle']);
  return Object.freeze({
    goal: value['goal'] === null ? null : member(value['goal'], PRODUCT_GOALS),
    knowledge: value['knowledge'] === null ? null : member(value['knowledge'], PRODUCT_KNOWLEDGE),
    persona: value['persona'] === null ? null : member(value['persona'], PRODUCT_PERSONAS),
    dailyGoal: value['dailyGoal'] === null ? null : member(value['dailyGoal'], PRODUCT_DAILY_GOALS),
    handle: value['handle'] === null ? null : handle(value['handle']),
  });
}

export function parseProductProfileWrite(input: unknown): ProductProfileWrite {
  const value = fields(input, ['mutationId', 'baseRevision', 'onboarding', 'launchCheckpoint']);
  const baseRevision = value['baseRevision'];
  if (typeof baseRevision !== 'number' || !Number.isSafeInteger(baseRevision) || baseRevision < 0) invalid();
  return Object.freeze({
    mutationId: uuid(value['mutationId']),
    baseRevision,
    onboarding: parseProductOnboarding(value['onboarding']),
    launchCheckpoint: member(value['launchCheckpoint'], PRODUCT_LAUNCH_CHECKPOINTS),
  });
}

export function parseProductLaunchWrite(input: unknown): ProductLaunchWrite {
  const value = fields(input, ['mutationId', 'baseRevision', 'action']);
  const baseRevision = value['baseRevision'];
  if (typeof baseRevision !== 'number' || !Number.isSafeInteger(baseRevision) || baseRevision < 1) invalid();
  return Object.freeze({
    mutationId: uuid(value['mutationId']),
    baseRevision,
    action: member(value['action'], PRODUCT_LAUNCH_ACTIONS),
  });
}

export function parseProductProfileSnapshot(input: unknown): ProductProfileSnapshot {
  try {
    const value = fields(input, ['revision', 'onboarding', 'launchCheckpoint', 'hasConfirmedPaperTrade', 'createdAt', 'updatedAt']);
    const revision = value['revision'];
    if (typeof revision !== 'number' || !Number.isSafeInteger(revision) || revision < 1) invalid();
    const createdAt = timestamp(value['createdAt']);
    const updatedAt = timestamp(value['updatedAt']);
    if (updatedAt < createdAt) invalid();
    if (typeof value['hasConfirmedPaperTrade'] !== 'boolean') invalid();
    return Object.freeze({
      revision,
      onboarding: parseProductOnboarding(value['onboarding']),
      launchCheckpoint: member(value['launchCheckpoint'], PRODUCT_LAUNCH_CHECKPOINTS),
      hasConfirmedPaperTrade: value['hasConfirmedPaperTrade'],
      createdAt,
      updatedAt,
    });
  } catch {
    throw new ProductProfileRepositoryError(
      'PRODUCT_PROFILE_STORAGE_INVALID',
      'Stored product profile could not be read safely.',
    );
  }
}
