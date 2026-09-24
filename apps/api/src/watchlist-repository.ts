export interface WatchlistSnapshot {
  readonly revision: number;
  readonly assetIds: readonly string[];
  readonly updatedAt: string | null;
}

export interface WatchlistWrite {
  readonly mutationId: string;
  readonly baseRevision: number;
  readonly assetIds: readonly string[];
}

export interface WatchlistRepository {
  get(userId: string): Promise<WatchlistSnapshot>;
  put(userId: string, command: WatchlistWrite): Promise<WatchlistSnapshot>;
}

export type WatchlistRepositoryErrorCode =
  | 'WATCHLIST_INVALID_INPUT'
  | 'WATCHLIST_ACCOUNT_NOT_FOUND'
  | 'WATCHLIST_IDEMPOTENCY_CONFLICT'
  | 'WATCHLIST_REVISION_CONFLICT'
  | 'WATCHLIST_REVISION_EXHAUSTED'
  | 'WATCHLIST_STORAGE_INVALID'
  | 'WATCHLIST_RUNTIME_ROLE_INVALID';

/** Provider errors, identity tokens and payloads must never be attached. */
export class WatchlistRepositoryError extends Error {
  constructor(
    readonly code: WatchlistRepositoryErrorCode,
    message: string,
    readonly currentSnapshot?: WatchlistSnapshot,
  ) {
    super(message);
    this.name = 'WatchlistRepositoryError';
  }
}

export const EMPTY_WATCHLIST_SNAPSHOT: WatchlistSnapshot = Object.freeze({
  revision: 0, assetIds: Object.freeze([]), updatedAt: null,
});
export const WATCHLIST_MAX_ASSETS = 50;

function invalid(): never {
  throw new WatchlistRepositoryError('WATCHLIST_INVALID_INPUT', 'Watchlist request is invalid.');
}

export function parseWatchlistUserId(input: unknown): string {
  if (typeof input !== 'string' || input.length !== 36 ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input)) invalid();
  return input.toLowerCase();
}

/** Inspect data descriptors rather than invoking getters on direct callers. */
export function watchlistFields(input: unknown, fields: readonly string[]): Readonly<Record<string, unknown>> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
  const prototype: unknown = Object.getPrototypeOf(input);
  if (prototype !== Object.prototype && prototype !== null) invalid();
  const keys = Reflect.ownKeys(input);
  if (keys.length !== fields.length || keys.some(key => typeof key !== 'string' || !fields.includes(key))) invalid();
  const result: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(input, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    result[key as string] = descriptor.value;
  }
  return Object.freeze(result);
}

function assetId(input: unknown): string {
  if (typeof input !== 'string' || input.length > 64 ||
      /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.exec(input)?.[0] !== input) invalid();
  return input;
}

/**
 * Which identifiers a list may hold.
 *
 * `fixed` is the fictional sample catalog: only those eight IDs are storable,
 * so a sample list can never come to contain a real asset.
 *
 * `provider` accepts any identifier shaped like one a discovery provider
 * returns. It is **not** an approval: nothing reads a stored identifier as
 * evidence that an asset is verified, eligible or tradeable, and the live
 * catalog route still returns an empty, unverified list. It exists so a person
 * can keep the name of something they looked up.
 */
export type WatchlistCatalog =
  | {readonly kind: 'fixed'; readonly allowedAssetIds: ReadonlySet<string>}
  | {readonly kind: 'provider'; readonly reservedAssetIds?: ReadonlySet<string>};

/** A catalog is configuration, not data supplied by the request. Copy it once. */
export function copyWatchlistAllowlist(input: ReadonlySet<string>): ReadonlySet<string> {
  try {
    if (!(input instanceof Set)) invalid();
    return new Set([...input].map(assetId));
  } catch {
    return invalid();
  }
}

/** A bare set stays accepted so every existing caller keeps its exact meaning. */
export function watchlistCatalog(input: ReadonlySet<string> | WatchlistCatalog): WatchlistCatalog {
  if (input === null || typeof input !== 'object') invalid();
  // A set carries no discriminant, so its absence is what identifies one.
  // copyWatchlistAllowlist still refuses anything that is not a real Set.
  if (!('kind' in input)) {
    return Object.freeze({kind: 'fixed', allowedAssetIds: copyWatchlistAllowlist(input)});
  }
  if (input.kind === 'provider') {
    // The fictional sample slugs are shaped like provider identifiers, so
    // without this a sample ID could be stored in the real list and read as a
    // real asset. Reserving them keeps the two lists genuinely disjoint.
    return Object.freeze(input.reservedAssetIds === undefined
      ? {kind: 'provider'}
      : {kind: 'provider', reservedAssetIds: copyWatchlistAllowlist(input.reservedAssetIds)});
  }
  if (input.kind === 'fixed') {
    return Object.freeze({kind: 'fixed', allowedAssetIds: copyWatchlistAllowlist(input.allowedAssetIds)});
  }
  return invalid();
}

/** Provider identifiers are wider than the sample slugs: discovery may return a
 * leading digit and up to 100 characters, so this accepts exactly that. */
function providerAssetId(input: unknown): string {
  if (typeof input !== 'string' || input.length > 100 ||
      /^[a-z0-9]+(?:-[a-z0-9]+)*$/.exec(input)?.[0] !== input) invalid();
  return input;
}

export function parseWatchlistAssetIds(
  input: unknown,
  catalog: ReadonlySet<string> | WatchlistCatalog,
): readonly string[] {
  const rules = watchlistCatalog(catalog);
  if (!Array.isArray(input) || input.length > WATCHLIST_MAX_ASSETS ||
      Reflect.ownKeys(input).length !== input.length + 1) invalid();
  const result: string[] = [];
  for (let index = 0; index < input.length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(input, String(index));
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    const id = rules.kind === 'fixed' ? assetId(descriptor.value) : providerAssetId(descriptor.value);
    if (rules.kind === 'fixed' && !rules.allowedAssetIds.has(id)) invalid();
    if (rules.kind === 'provider' && rules.reservedAssetIds?.has(id)) invalid();
    if (result.includes(id)) invalid();
    result.push(id);
  }
  return Object.freeze(result);
}

export function parseWatchlistWrite(input: unknown, allowedAssetIds: ReadonlySet<string> | WatchlistCatalog): WatchlistWrite {
  try {
    const values = watchlistFields(input, ['mutationId', 'baseRevision', 'assetIds']);
    const mutationId = parseWatchlistUserId(values['mutationId']);
    const baseRevision = values['baseRevision'];
    if (typeof baseRevision !== 'number' || !Number.isSafeInteger(baseRevision) || baseRevision < 0) invalid();
    return Object.freeze({mutationId, baseRevision, assetIds: parseWatchlistAssetIds(values['assetIds'], allowedAssetIds)});
  } catch {
    return invalid();
  }
}

/** Exact immutable storage projection. Catalog changes never silently drop IDs. */
export function parseWatchlistSnapshot(input: unknown, allowedAssetIds: ReadonlySet<string> | WatchlistCatalog): WatchlistSnapshot {
  try {
    const values = watchlistFields(input, ['revision', 'assetIds', 'updatedAt']);
    const revision = values['revision'];
    if (typeof revision !== 'number' || !Number.isSafeInteger(revision) || revision < 0) invalid();
    const assetIds = parseWatchlistAssetIds(values['assetIds'], allowedAssetIds);
    const updatedAt = values['updatedAt'];
    if (revision === 0) {
      if (assetIds.length !== 0 || updatedAt !== null) invalid();
      return EMPTY_WATCHLIST_SNAPSHOT;
    }
    if (typeof updatedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(updatedAt) ||
        new Date(updatedAt).toISOString() !== updatedAt) invalid();
    return Object.freeze({revision, assetIds, updatedAt});
  } catch {
    throw new WatchlistRepositoryError('WATCHLIST_STORAGE_INVALID', 'Stored watchlist could not be read safely.');
  }
}
