import { US_SESSIONS } from './us-equity-calendar.js';
import type { UsSession } from './us-equity-calendar.js';

/**
 * Ondo's live trading status, read from its public status page
 * (https://status.ondo.finance/market): whether its market is open, closed or
 * paused, and the sessions each token trades in. The page embeds the JSON of
 * Ondo's GM status API in its server-rendered payload. Parsing is strict and
 * never throws to callers: anything unexpected reads as no status, and callers
 * fall back to the published session calendar.
 */
export interface OndoMarketStatus {
  readonly observedAt: number;
  /** When Ondo produced this status. */
  readonly timestamp: number;
  readonly isOpen: boolean;
  /** 'MARKET_CLOSED', 'MARKET_PAUSED' or another Ondo code while not open. */
  readonly reasonCode: string | null;
  readonly nextOpen: number | null;
  readonly offhoursOpen: boolean;
  /** Ondo symbol (for example 'NVDAon') to the sessions it trades in. */
  readonly sessions: ReadonlyMap<string, ReadonlySet<UsSession>>;
}

export const ONDO_STATUS_URL = 'https://status.ondo.finance/market';
const MAX_BYTES = 2 * 1024 * 1024;
const MAX_AGE_MS = 10 * 60_000;
const SYMBOL = /^[A-Za-z0-9.-]{1,24}$/;
const CODE = /^[A-Z_]{1,40}$/;

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;
}
const time = (value: unknown): number | null => {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'string' || value.length > 40) return Number.NaN;
  return Date.parse(value);
};

/** The JSON object that starts at `start`, by brace matching outside strings. */
function objectAt(text: string, start: number): string | null {
  let depth = 0;
  let inString = false;
  for (let index = start; index < text.length; index += 1) {
    const char = text[index];
    if (inString) {
      if (char === '\\') index += 1;
      else if (char === '"') inString = false;
    } else if (char === '"') inString = true;
    else if (char === '{') depth += 1;
    else if (char === '}' && --depth === 0) return text.slice(start, index + 1);
  }
  return null;
}

/** Parses the status page; null when it does not carry a current, well-formed status. */
export function parseOndoStatusPage(html: string, observedAt: number): OndoMarketStatus | null {
  if (typeof html !== 'string' || html.length > MAX_BYTES) return null;
  let payload: Record<string, unknown> | null = null;
  for (const match of html.matchAll(/self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)/g)) {
    let text: unknown;
    try { text = JSON.parse(match[1]!); } catch { continue; }
    if (typeof text !== 'string') continue;
    const start = text.indexOf('{"assets":[');
    if (start < 0) continue;
    const body = objectAt(text, start);
    if (body === null) return null;
    try { payload = record(JSON.parse(body)); } catch { return null; }
    break;
  }
  const assets = payload?.['assets'];
  const market = record(payload?.['marketStatus']);
  if (!Array.isArray(assets) || assets.length === 0 || assets.length > 5_000 || market === null) return null;
  const sessions = new Map<string, ReadonlySet<UsSession>>();
  for (const item of assets) {
    const asset = record(item);
    const symbol = asset?.['symbol'];
    const listed = asset?.['tradableSessions'];
    if (typeof symbol !== 'string' || !SYMBOL.test(symbol) || !Array.isArray(listed) || listed.length > 10 || sessions.has(symbol)) return null;
    // Sessions Trimmy does not know yet grant nothing; the known ones still count.
    sessions.set(symbol, new Set(listed.filter((value): value is UsSession => (US_SESSIONS as readonly unknown[]).includes(value))));
  }
  const timestamp = time(market['timestamp']);
  const nextOpen = time(market['nextOpen']);
  const reason = record(market['reason']);
  const reasonCode = reason === null ? null : reason['code'];
  const offhours = record(market['offhours']);
  if (timestamp === null || !Number.isFinite(timestamp) || Math.abs(observedAt - timestamp) > MAX_AGE_MS ||
      typeof market['isOpen'] !== 'boolean' || (nextOpen !== null && !Number.isFinite(nextOpen)) ||
      (reasonCode !== null && (typeof reasonCode !== 'string' || !CODE.test(reasonCode))) ||
      (offhours !== null && typeof offhours['isOpen'] !== 'boolean')) return null;
  return Object.freeze({observedAt, timestamp, isOpen: market['isOpen'], reasonCode: reasonCode as string | null, nextOpen,
    offhoursOpen: offhours?.['isOpen'] === true, sessions});
}

export interface OndoMarketStatusReaderOptions {
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly ttlMs?: number;
  readonly timeoutMs?: number;
}

/** Cached, single-flight reads of Ondo's status page. `read` never throws. */
export class OndoMarketStatusReader {
  readonly #fetch: typeof globalThis.fetch;
  readonly #now: () => number;
  readonly #ttlMs: number;
  readonly #timeoutMs: number;
  #value: OndoMarketStatus | null = null;
  #checkedAt = Number.NEGATIVE_INFINITY;
  #inflight: Promise<OndoMarketStatus | null> | null = null;

  constructor(options: OndoMarketStatusReaderOptions = {}) {
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#now = options.now ?? Date.now;
    this.#ttlMs = options.ttlMs ?? 120_000;
    this.#timeoutMs = options.timeoutMs ?? 8_000;
  }

  /** The latest status no older than the cache window, or null. */
  async read(): Promise<OndoMarketStatus | null> {
    const now = this.#now();
    if (now - this.#checkedAt < this.#ttlMs) return this.#fresh(now);
    this.#inflight ??= this.#load().finally(() => { this.#inflight = null; });
    return this.#inflight;
  }

  /** The cached status without waiting for a refresh. */
  peek(): OndoMarketStatus | null {
    return this.#fresh(this.#now());
  }

  #fresh(now: number): OndoMarketStatus | null {
    return this.#value !== null && now - this.#value.observedAt <= MAX_AGE_MS ? this.#value : null;
  }

  async #load(): Promise<OndoMarketStatus | null> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeoutMs);
    try {
      const response = await this.#fetch(ONDO_STATUS_URL, {signal: controller.signal, redirect: 'error',
        headers: {accept: 'text/html', 'user-agent': 'Trimmy/1 (+https://trimmy.xyz)'}});
      if (!response.ok || response.body === null) return this.#fresh(this.#now());
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      for (;;) {
        const {done, value} = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_BYTES) { await reader.cancel(); return this.#fresh(this.#now()); }
        chunks.push(value);
      }
      const parsed = parseOndoStatusPage(Buffer.concat(chunks).toString('utf8'), this.#now());
      if (parsed !== null) this.#value = parsed;
      return this.#fresh(this.#now());
    } catch {
      return this.#fresh(this.#now());
    } finally {
      clearTimeout(timer);
      this.#checkedAt = this.#now();
    }
  }
}
