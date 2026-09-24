import { PRACTICE_ASSET_IDS } from '@trimmy/domain';

export type WatchlistStatus = 'local' | 'syncing' | 'saved' | 'offline' | 'conflict' | 'protected' | 'loginRequired' | 'closed';
export interface WatchlistSnapshot { readonly schemaVersion: 1; readonly revision: number; readonly assetIds: readonly string[]; readonly updatedAt: string | null }
interface Mutation { readonly schemaVersion: 1; readonly mutationId: string; readonly baseRevision: number; readonly assetIds: readonly string[] }
interface Durable { readonly schemaVersion: 1; readonly accountId: string; readonly local: readonly string[]; readonly base: WatchlistSnapshot | null; readonly pending: Mutation | null; readonly conflict: WatchlistSnapshot | null }
export interface WatchlistView { readonly accountId: string; readonly assetIds: readonly string[]; readonly conflictAssetIds: readonly string[] | null; readonly status: WatchlistStatus; readonly errorCode: string | null; readonly pending: boolean }
export interface WatchlistStorage { getItem(key: string): string | null; setItem(key: string, value: string): void }
export interface WatchlistStorageEvents { addEventListener(type: 'storage', listener: (event: StorageEvent) => void): void; removeEventListener(type: 'storage', listener: (event: StorageEvent) => void): void }
export interface WatchlistOptions {
  readonly subject: string;
  readonly currentSubject: () => string | null;
  readonly accessToken: (expectedSubject: string) => Promise<string | null>;
  /** Explicit trusted API origin from application configuration; never saved data. */
  readonly apiBaseUrl: string | URL;
  readonly storage: WatchlistStorage;
  readonly storageEvents?: WatchlistStorageEvents;
  readonly fetch?: typeof fetch;
  readonly mutationId?: () => string;
  readonly timeoutMs?: number;
  readonly allowLoopbackForTests?: boolean;
}
export class WatchlistSyncError extends Error {
  constructor(readonly code: string, readonly currentSnapshot?: WatchlistSnapshot) { super(code); this.name = 'WatchlistSyncError'; }
}
function fail(code = 'WATCHLIST_INVALID_PROTOCOL'): never { throw new WatchlistSyncError(code); }
const EMPTY = Object.freeze([]) as readonly string[];
const allowed = new Set<string>(PRACTICE_ASSET_IDS);
const owners = new WeakMap<WatchlistStorage, Map<string, WatchlistSession>>();
const encoder = new TextEncoder();
const limit = 16_384;
const equal = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

function uuid(input: unknown): string {
  if (typeof input !== 'string' || input.length !== 36 || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input)) fail();
  return input.toLowerCase();
}
function object(input: unknown, fields: readonly string[]): Record<string, unknown> {
  if (!input || typeof input !== 'object' || Array.isArray(input) || ![Object.prototype, null].includes(Object.getPrototypeOf(input))) fail();
  const keys = Reflect.ownKeys(input);
  if (keys.length !== fields.length || keys.some(key => typeof key !== 'string' || !fields.includes(key))) fail();
  const copy: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  for (const key of fields) {
    const entry = Object.getOwnPropertyDescriptor(input, key);
    if (!entry?.enumerable || !Object.hasOwn(entry, 'value')) fail();
    copy[key] = entry.value;
  }
  return copy;
}
function ids(input: unknown): readonly string[] {
  if (!Array.isArray(input) || input.length > 50 || Reflect.ownKeys(input).length !== input.length + 1) fail();
  const result: string[] = [];
  for (let i = 0; i < input.length; i++) {
    const entry = Object.getOwnPropertyDescriptor(input, String(i));
    if (!entry?.enumerable || !Object.hasOwn(entry, 'value') || typeof entry.value !== 'string' || !allowed.has(entry.value) || result.includes(entry.value)) fail();
    result.push(entry.value);
  }
  return Object.freeze(result);
}
function revision(input: unknown): number {
  if (typeof input !== 'number' || !Number.isSafeInteger(input) || input < 0) fail();
  return input;
}
function snapshot(input: unknown): WatchlistSnapshot {
  const data = object(input, ['schemaVersion', 'revision', 'assetIds', 'updatedAt']);
  if (data['schemaVersion'] !== 1) fail();
  const rev = revision(data['revision']); const assets = ids(data['assetIds']); const time = data['updatedAt'];
  if (rev === 0) { if (assets.length || time !== null) fail(); }
  else if (typeof time !== 'string' || time.length !== 24 || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(time) || new Date(time).toISOString() !== time) fail();
  return Object.freeze({schemaVersion: 1, revision: rev, assetIds: assets, updatedAt: time as string | null});
}
function mutation(input: unknown): Mutation {
  const data = object(input, ['schemaVersion', 'mutationId', 'baseRevision', 'assetIds']);
  if (data['schemaVersion'] !== 1) fail();
  return Object.freeze({schemaVersion: 1, mutationId: uuid(data['mutationId']), baseRevision: revision(data['baseRevision']), assetIds: ids(data['assetIds'])});
}
function futureVersion(input: unknown): void {
  if (!input || typeof input !== 'object') return;
  const version = Object.getOwnPropertyDescriptor(input, 'schemaVersion')?.value as unknown;
  if (typeof version === 'number' && version > 1) fail('WATCHLIST_UNSUPPORTED_VERSION');
}
function durable(raw: string, accountId: string): Durable {
  try {
    if (encoder.encode(raw).length > 32_768) fail();
    const input: unknown = JSON.parse(raw); futureVersion(input);
    const data = object(input, ['schemaVersion', 'accountId', 'local', 'base', 'pending', 'conflict']);
    if (data['schemaVersion'] !== 1 || data['accountId'] !== accountId) fail();
    for (const name of ['base', 'pending', 'conflict']) futureVersion(data[name]);
    const base = data['base'] === null ? null : snapshot(data['base']);
    const pending = data['pending'] === null ? null : mutation(data['pending']);
    const conflict = data['conflict'] === null ? null : snapshot(data['conflict']);
    if (pending && (!base || conflict || pending.baseRevision !== base.revision)) fail();
    return Object.freeze({schemaVersion: 1, accountId, local: ids(data['local']), base, pending, conflict});
  } catch (error) {
    if (error instanceof WatchlistSyncError && error.code === 'WATCHLIST_UNSUPPORTED_VERSION') throw error;
    return fail('WATCHLIST_LOCAL_CORRUPT');
  }
}

/** Exactly the options the transport itself needs. The followed list reuses
 * this hardened request path without the cross-tab session around it. */
export type BoundHttpOptions = Pick<WatchlistOptions,
  'subject' | 'currentSubject' | 'accessToken' | 'apiBaseUrl' | 'fetch' | 'timeoutMs' | 'allowLoopbackForTests'>;

export class BoundHttp {
  readonly base: URL;
  private closed = false;
  private readonly active = new Set<AbortController>();
  /**
   * `parseConflictSnapshot` is false for lists whose identifiers are not the
   * fixed sample catalog: the snapshot parser here validates against that
   * catalog, so parsing a real followed list with it would reject valid data.
   * Such a caller re-reads after a conflict instead of trusting the payload.
   */
  constructor(
    private readonly options: BoundHttpOptions,
    private readonly parseConflictSnapshot = true,
  ) {
    try {
      this.base = new URL(options.apiBaseUrl);
      const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(this.base.hostname);
      if (this.base.username || this.base.password || this.base.search || this.base.hash || this.base.pathname !== '/' ||
          (this.base.protocol !== 'https:' && !(options.allowLoopbackForTests && loopback && this.base.protocol === 'http:')) ||
          !options.subject || (options.timeoutMs !== undefined && (!Number.isFinite(options.timeoutMs) || options.timeoutMs <= 0 || options.timeoutMs > 60_000))) fail();
    } catch { fail('WATCHLIST_INVALID_CONFIGURATION'); }
  }
  check(): void {
    if (this.closed) fail('WATCHLIST_CLOSED');
    if (this.options.currentSubject() !== this.options.subject) fail('WATCHLIST_SESSION_CHANGED');
  }
  close(): void { this.closed = true; for (const controller of this.active) controller.abort(); }
  async request(method: 'GET' | 'POST' | 'PUT', path: string, body?: unknown): Promise<unknown> {
    this.check();
    const controller = new AbortController(); this.active.add(controller);
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let timeout = false;
    const timer = setTimeout(() => { timeout = true; controller.abort(); }, this.options.timeoutMs ?? 10_000);
    let abortListener: (() => void) | undefined;
    const aborted = new Promise<never>((_, reject) => {
      abortListener = () => reject(new WatchlistSyncError(timeout ? 'WATCHLIST_TIMEOUT' : 'WATCHLIST_CLOSED'));
      controller.signal.addEventListener('abort', abortListener, {once: true});
    });
    const work = (async () => {
      let response: Response | undefined;
      try {
        let token: string | null;
        try { token = await this.options.accessToken(this.options.subject); }
        catch { return fail('WATCHLIST_TOKEN_UNAVAILABLE'); }
        this.check();
        if (controller.signal.aborted) fail(timeout ? 'WATCHLIST_TIMEOUT' : 'WATCHLIST_CLOSED');
        if (typeof token !== 'string' || token.length > 8192 || /^[A-Za-z0-9._~+/-]+=*$/.exec(token)?.[0] !== token) fail('WATCHLIST_TOKEN_UNAVAILABLE');
        const text = body === undefined ? undefined : JSON.stringify(body);
        if (text !== undefined && encoder.encode(text).length > 8192) fail();
        response = await (this.options.fetch ?? globalThis.fetch)(new URL(path, this.base), {
          method, headers: {authorization: `Bearer ${token}`, accept: 'application/json', ...(text === undefined ? {} : {'content-type': 'application/json'})},
          ...(text === undefined ? {} : {body: text}), signal: controller.signal, redirect: 'error', credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer',
        });
        this.check();
        if (controller.signal.aborted) fail(timeout ? 'WATCHLIST_TIMEOUT' : 'WATCHLIST_CLOSED');
        if (response.redirected || response.type === 'opaqueredirect' || (response.status >= 300 && response.status < 400)) fail('WATCHLIST_REDIRECT_REJECTED');
        if (!/^application\/json(?:\s*;.*)?$/i.test(response.headers.get('content-type') ?? '') || !response.body) fail('WATCHLIST_INVALID_RESPONSE');
        const length = response.headers.get('content-length');
        if (length && (!/^\d+$/.test(length) || Number(length) > limit)) fail('WATCHLIST_RESPONSE_TOO_LARGE');
        reader = response.body.getReader();
        const chunks: Uint8Array[] = []; let size = 0;
        while (true) {
          const chunk = await reader.read();
          if (chunk.done) break;
          size += chunk.value.byteLength;
          if (size > limit) fail('WATCHLIST_RESPONSE_TOO_LARGE');
          chunks.push(chunk.value);
        }
        const bytes = new Uint8Array(size); let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
        let parsed: unknown;
        try { parsed = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)); }
        catch { return fail('WATCHLIST_INVALID_RESPONSE'); }
        this.check();
        if (response.status !== 200) this.failure(response.status, parsed);
        return parsed;
      } finally {
        if (reader) { void reader.cancel().catch(() => {}); }
        else if (response?.body) { void response.body.cancel().catch(() => {}); }
      }
    })();
    try { return await Promise.race([work, aborted]); }
    catch (error) {
      if (error instanceof WatchlistSyncError) throw error;
      if (error instanceof SyntaxError || error instanceof RangeError) return fail('WATCHLIST_INVALID_RESPONSE');
      return fail('WATCHLIST_NETWORK_ERROR');
    } finally {
      clearTimeout(timer);
      if (abortListener) controller.signal.removeEventListener('abort', abortListener);
      controller.abort(); this.active.delete(controller);
      if (reader) void reader.cancel().catch(() => {});
    }
  }
  private failure(status: number, input: unknown): never {
    const hasConflict = status === 409 && input !== null && typeof input === 'object' && Object.hasOwn(input, 'currentSnapshot');
    const body = object(input, hasConflict ? ['error', 'currentSnapshot'] : ['error']);
    const error = object(body['error'], ['code', 'message', 'requestId']);
    if (typeof error['message'] !== 'string' || error['message'].length > 1024 || typeof error['requestId'] !== 'string' || !error['requestId'] || error['requestId'].length > 128) fail('WATCHLIST_INVALID_RESPONSE');
    const code = error['code'];
    if (hasConflict) {
      if (code !== 'WATCHLIST_REVISION_CONFLICT') fail('WATCHLIST_INVALID_RESPONSE');
      if (!this.parseConflictSnapshot) throw new WatchlistSyncError(code);
      throw new WatchlistSyncError(code, snapshot(body['currentSnapshot']));
    }
    const allowedCodes: Record<number, readonly string[]> = {
      400: ['WATCHLIST_INVALID_INPUT', 'INVALID_REQUEST'], 401: ['WATCHLIST_UNAUTHENTICATED', 'PRACTICE_UNAUTHENTICATED'],
      403: ['PRACTICE_ACCOUNT_UNAVAILABLE'], 404: ['WATCHLIST_ACCOUNT_NOT_FOUND'],
      409: ['WATCHLIST_IDEMPOTENCY_CONFLICT'], 413: ['PAYLOAD_TOO_LARGE'], 415: ['UNSUPPORTED_MEDIA_TYPE'],
      500: ['WATCHLIST_STORAGE_INVALID', 'WATCHLIST_RUNTIME_ROLE_INVALID'],
      503: ['WATCHLIST_UNAVAILABLE', 'WATCHLIST_REVISION_EXHAUSTED', 'PRACTICE_SYNC_UNAVAILABLE'],
    };
    if (typeof code === 'string' && allowedCodes[status]?.includes(code)) throw new WatchlistSyncError(code);
    return fail(status === 429 ? 'WATCHLIST_RATE_LIMITED' : 'WATCHLIST_HTTP_ERROR');
  }
}

/** A browser Web Locks lease must be held by the host for this provider subject.
 * Raw comparisons and storage events detect out-of-band edits; localStorage is
 * not a cross-tab compare-and-swap primitive. No guest data is read here. */
export class WatchlistSession {
  static async open(options: WatchlistOptions): Promise<WatchlistSession> {
    options = Object.freeze({...options});
    const transport = new BoundHttp(options);
    try {
      const body = object(await transport.request('POST', '/v1/practice/session', {}), ['schemaVersion', 'userId']);
      if (body['schemaVersion'] !== 1) fail();
      const account = uuid(body['userId']); transport.check();
      const currentOwners = owners.get(options.storage) ?? new Map<string, WatchlistSession>();
      if (currentOwners.has(account)) fail('WATCHLIST_OWNER_EXISTS');
      const session = new WatchlistSession(account, options, transport);
      currentOwners.set(account, session); owners.set(options.storage, currentOwners);
      session.reload();
      return session;
    } catch (error) { transport.close(); throw error; }
  }
  static storageKey(accountId: string): string { return `trimmy.watchlist-sync.v1.${uuid(accountId)}`; }
  readonly storageKey: string;
  private record: Durable | null = null;
  private raw: string | null = null;
  private status: WatchlistStatus = 'local';
  private errorCode: string | null = null;
  private view!: WatchlistView;
  private closed = false;
  private syncing: Promise<void> | null = null;
  private readonly listeners = new Set<() => void>();
  private constructor(readonly accountId: string, private readonly options: WatchlistOptions, private readonly http: BoundHttp) {
    this.storageKey = WatchlistSession.storageKey(accountId);
    options.storageEvents?.addEventListener('storage', this.storageChanged);
  }
  readonly getSnapshot = (): WatchlistView => this.view;
  readonly subscribe = (listener: () => void): (() => void) => { this.listeners.add(listener); return () => this.listeners.delete(listener); };
  private publish(): void {
    this.view = Object.freeze({accountId: this.accountId, assetIds: this.record?.local ?? EMPTY,
      conflictAssetIds: this.record?.conflict?.assetIds ?? null, status: this.status, errorCode: this.errorCode, pending: this.record?.pending !== null && this.record?.pending !== undefined});
    for (const listener of this.listeners) { try { listener(); } catch { /* A subscriber cannot undo acknowledged storage. */ } }
  }
  private readonly storageChanged = (event: StorageEvent): void => {
    if (!this.closed && (event.key === this.storageKey || event.key === null) && event.newValue !== this.raw) this.protect('WATCHLIST_STORAGE_CHANGED');
  };
  private protect(code: string): void { this.status = 'protected'; this.errorCode = code; this.publish(); }
  private usable(): Durable {
    if (this.closed) fail('WATCHLIST_CLOSED');
    this.http.check();
    if (this.status === 'protected' || !this.record) fail(this.errorCode ?? 'WATCHLIST_LOCAL_UNAVAILABLE');
    this.checkStorage();
    return this.record;
  }
  private checkStorage(): void {
    let raw: string | null;
    try { raw = this.options.storage.getItem(this.storageKey); }
    catch { this.protect('WATCHLIST_LOCAL_UNAVAILABLE'); return fail('WATCHLIST_LOCAL_UNAVAILABLE'); }
    if (raw !== this.raw) { this.protect('WATCHLIST_STORAGE_CHANGED'); fail('WATCHLIST_STORAGE_CHANGED'); }
  }
  private persist(next: Durable): void {
    this.http.check(); this.checkStorage();
    const raw = JSON.stringify(next);
    if (raw === this.raw) { this.record = next; return; }
    try { this.options.storage.setItem(this.storageKey, raw); }
    catch { return fail('WATCHLIST_LOCAL_SAVE_FAILED'); }
    this.raw = raw; this.record = next;
  }
  reload(): void {
    if (this.closed || this.syncing) fail(this.closed ? 'WATCHLIST_CLOSED' : 'WATCHLIST_BUSY');
    this.http.check();
    try {
      this.raw = this.options.storage.getItem(this.storageKey);
      if (this.raw === null) this.persist(Object.freeze({schemaVersion: 1, accountId: this.accountId, local: EMPTY, base: null, pending: null, conflict: null}));
      else this.record = durable(this.raw, this.accountId);
      this.status = this.record!.conflict ? 'conflict' : 'local'; this.errorCode = null; this.publish();
    } catch (error) { this.protect(error instanceof WatchlistSyncError ? error.code : 'WATCHLIST_LOCAL_UNAVAILABLE'); }
  }
  setAssetIds(assetIds: readonly string[]): void {
    const current = this.usable(); const local = ids(assetIds);
    this.persist(Object.freeze({...current, local}));
    if (!current.conflict && this.status !== 'loginRequired') this.status = this.syncing ? 'syncing' : 'local';
    this.publish();
  }
  useLocal(): void { this.resolve(false); }
  useRemote(): void { this.resolve(true); }
  private resolve(remote: boolean): void {
    const current = this.usable();
    if (!current.conflict || this.syncing) fail('WATCHLIST_NO_CONFLICT');
    this.persist(Object.freeze({...current, local: remote ? current.conflict.assetIds : current.local, base: current.conflict, conflict: null, pending: null}));
    this.status = remote ? 'saved' : 'local'; this.errorCode = null; this.publish();
  }
  synchronize(): Promise<void> {
    if (this.syncing) return this.syncing;
    let run: Promise<void>;
    run = this.runSync().finally(() => { if (this.syncing === run) this.syncing = null; });
    this.syncing = run;
    return run;
  }
  private async runSync(): Promise<void> {
    try {
      let current = this.usable();
      if (current.conflict) fail('WATCHLIST_REVISION_CONFLICT');
      this.status = 'syncing'; this.errorCode = null; this.publish();
      let pending = current.pending;
      if (!pending) {
        const remote = snapshot(await this.http.request('GET', '/v1/watchlist'));
        current = this.usable();
        const unchanged = current.base !== null && equal(current.base, remote);
        if (current.base && (remote.revision < current.base.revision || (remote.revision === current.base.revision && !unchanged))) this.conflict(current, remote);
        if (equal(current.local, remote.assetIds)) {
          this.persist(Object.freeze({...current, base: remote})); this.status = 'saved'; this.publish(); return;
        }
        if ((!current.base && current.local.length === 0) || (current.base && equal(current.local, current.base.assetIds))) {
          this.persist(Object.freeze({...current, local: remote.assetIds, base: remote})); this.status = 'saved'; this.publish(); return;
        }
        if (!unchanged && !(current.base === null && remote.revision === 0)) this.conflict(current, remote);
        pending = mutation({schemaVersion: 1, mutationId: (this.options.mutationId ?? (() => crypto.randomUUID()))(), baseRevision: remote.revision, assetIds: current.local});
        this.persist(Object.freeze({...current, base: remote, pending}));
      }
      let ack: WatchlistSnapshot;
      try { ack = snapshot(await this.http.request('PUT', '/v1/watchlist', pending)); }
      catch (error) {
        if (error instanceof WatchlistSyncError && error.currentSnapshot) {
          current = this.usable(); this.persist(Object.freeze({...current, pending: null, conflict: error.currentSnapshot}));
        }
        throw error;
      }
      if (pending.baseRevision === Number.MAX_SAFE_INTEGER || ack.revision !== pending.baseRevision + 1 || !equal(ack.assetIds, pending.assetIds)) fail('WATCHLIST_ACK_MISMATCH');
      current = this.usable();
      if (!equal(current.pending, pending)) fail('WATCHLIST_PENDING_CHANGED');
      this.persist(Object.freeze({...current, base: ack, pending: null}));
      this.status = equal(current.local, ack.assetIds) ? 'saved' : 'local'; this.publish();
    } catch (error) {
      const safe = error instanceof WatchlistSyncError ? error : new WatchlistSyncError('WATCHLIST_INVALID_RESPONSE');
      if (!this.closed) {
        this.errorCode = safe.code;
        if (this.status !== 'protected') this.status = safe.code.includes('CONFLICT') ? 'conflict'
          : /TOKEN|UNAUTHENTICATED|SESSION_CHANGED|ACCOUNT_NOT_FOUND/.test(safe.code) ? 'loginRequired'
          : /INVALID|CORRUPT|UNSUPPORTED|MISMATCH|STORAGE_CHANGED|OWNER/.test(safe.code) ? 'protected' : 'offline';
        this.publish();
      }
      throw safe;
    }
  }
  private conflict(current: Durable, remote: WatchlistSnapshot): never {
    this.persist(Object.freeze({...current, conflict: remote, pending: null}));
    return fail('WATCHLIST_REVISION_CONFLICT');
  }
  close(): void {
    if (this.closed) return;
    this.closed = true; this.http.close();
    this.options.storageEvents?.removeEventListener('storage', this.storageChanged);
    const currentOwners = owners.get(this.options.storage);
    if (currentOwners?.get(this.accountId) === this) currentOwners.delete(this.accountId);
    this.status = 'closed'; this.publish(); this.listeners.clear();
  }
}
