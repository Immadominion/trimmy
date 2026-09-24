import {randomUUID} from 'node:crypto';
import type {CanonicalRedDayReader, RedDayRequestAudit} from './career-red-day-market.js';
import {RED_DAY_PROVIDER, RED_DAY_VERIFIER_VERSION, RedDayMarketError} from './career-red-day-market.js';
import type {RedDayFailureCode} from './career-red-day-market.js';
import type {CareerRedDayRepository, RedDayFailureObservation} from './career-red-day-repository.js';

const assetPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const symbolPattern = /^[A-Z][A-Z0-9.-]{0,14}$/u;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

export type RedDayAssetCatalog = ReadonlyMap<string, string>;

export function parseRedDayAssetCatalog(raw: string): RedDayAssetCatalog {
  if (typeof raw !== 'string' || raw.length < 2 || raw.length > 16_384 || raw.trim() !== raw) {
    throw new TypeError('TRIMMY_RED_DAY_ASSET_CATALOG_JSON is invalid.');
  }
  let value: unknown;
  try { value = JSON.parse(raw); } catch { throw new TypeError('TRIMMY_RED_DAY_ASSET_CATALOG_JSON is invalid.'); }
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.getPrototypeOf(value) !== Object.prototype) {
    throw new TypeError('TRIMMY_RED_DAY_ASSET_CATALOG_JSON is invalid.');
  }
  const entries = Object.entries(value as Record<string, unknown>);
  const encodedKeys = [...raw.matchAll(/[,{]\s*"([^"\\]*)"\s*:/gu)];
  if (encodedKeys.length !== entries.length) throw new TypeError('TRIMMY_RED_DAY_ASSET_CATALOG_JSON is invalid.');
  if (entries.length < 1 || entries.length > 100) throw new TypeError('TRIMMY_RED_DAY_ASSET_CATALOG_JSON is invalid.');
  const catalog = new Map<string, string>();
  for (const [assetId, symbol] of entries) {
    if (!assetPattern.test(assetId) || assetId.length > 100 || typeof symbol !== 'string' || !symbolPattern.test(symbol)) {
      throw new TypeError('TRIMMY_RED_DAY_ASSET_CATALOG_JSON is invalid.');
    }
    catalog.set(assetId, symbol);
  }
  return catalog;
}

export interface RedDayWorkerResult {
  readonly pendingSessions: number;
  readonly sessionBatchesProcessed: number;
  readonly sessionsCompleted: number;
  readonly candidates: number;
  readonly providerReads: number;
  readonly sessionsObserved: number;
  readonly observationsRecorded: number;
  readonly observationsAlreadyRecorded: number;
  readonly correctionReviews: number;
  readonly evidenceRecorded: number;
  readonly missionsCompleted: number;
  readonly providerFailures: number;
  readonly unknownAssets: number;
  readonly failureCodes: readonly (RedDayFailureCode | 'asset-not-in-catalog')[];
}

export interface CareerRedDayWorkerOptions {
  readonly repository: CareerRedDayRepository;
  readonly market: CanonicalRedDayReader;
  readonly assets: RedDayAssetCatalog;
  readonly candidateLimit?: number;
  readonly evidenceBatchLimit?: number;
  readonly uuid?: () => string;
  readonly now?: () => number;
}

/** One bounded, resumable pass. Scheduling and process lifetime stay outside. */
export class CareerRedDayWorker {
  readonly #repository: CareerRedDayRepository;
  readonly #market: CanonicalRedDayReader;
  readonly #assets: RedDayAssetCatalog;
  readonly #candidateLimit: number;
  readonly #evidenceBatchLimit: number;
  readonly #uuidFactory: () => string;
  readonly #now: () => number;

  constructor(options: CareerRedDayWorkerOptions) {
    if (!options || !options.repository || !options.market || !(options.assets instanceof Map)) {
      throw new TypeError('Red-day worker configuration is invalid.');
    }
    this.#repository = options.repository;
    this.#market = options.market;
    this.#assets = new Map(options.assets);
    this.#candidateLimit = options.candidateLimit ?? 20;
    this.#evidenceBatchLimit = options.evidenceBatchLimit ?? 50;
    this.#uuidFactory = options.uuid ?? randomUUID;
    this.#now = options.now ?? Date.now;
    if (!Number.isInteger(this.#candidateLimit) || this.#candidateLimit < 1 || this.#candidateLimit > 100) {
      throw new TypeError('Red-day worker candidate limit is invalid.');
    }
    if (!Number.isInteger(this.#evidenceBatchLimit) || this.#evidenceBatchLimit < 1 ||
        this.#evidenceBatchLimit > 100) {
      throw new TypeError('Red-day worker evidence batch limit is invalid.');
    }
  }

  async runOnce(): Promise<RedDayWorkerResult> {
    const pending = await this.#repository.pendingSessions(this.#candidateLimit);
    let sessionBatchesProcessed = 0;
    let sessionsCompleted = 0;
    let evidence = 0;
    let completed = 0;
    for (const session of pending) {
      const result = await this.#repository.processSession(session.observationId, this.#evidenceBatchLimit);
      sessionBatchesProcessed++;
      if (result.processingComplete) sessionsCompleted++;
      evidence += result.evidenceCount;
      completed += result.completedCount;
    }
    const candidates = await this.#repository.candidates(this.#candidateLimit);
    let providerReads = 0;
    let sessionsObserved = 0;
    let recorded = 0;
    let alreadyRecorded = 0;
    let correctionReviews = 0;
    let providerFailures = 0;
    let unknownAssets = 0;
    const failureCodes: (RedDayFailureCode | 'asset-not-in-catalog')[] = [];
    for (const candidate of candidates) {
      const listedSymbol = this.#assets.get(candidate.assetId);
      if (!listedSymbol) {
        unknownAssets++;
        failureCodes.push('asset-not-in-catalog');
        const observedAt = this.#timestamp();
        const detailRequestId = this.#uuid();
        const audit: RedDayRequestAudit = Object.freeze({detailRequestId, chartRequestId: null,
          detailProviderRequestId: null, chartProviderRequestId: null,
          detailPath: `/v1/assets/${encodeURIComponent(candidate.assetId)}`, chartPath: null,
          detailResponseSha256: null, chartResponseSha256: null});
        const failure: RedDayFailureObservation = Object.freeze({observationId: this.#uuid(),
          provider: RED_DAY_PROVIDER, verifierVersion: RED_DAY_VERIFIER_VERSION,
          assetId: candidate.assetId, listedSymbol: null, status: 'rejected',
          reasonCode: 'asset-not-in-catalog', observedAt, audit});
        const result = await this.#repository.record(failure);
        if (result.outcome === 'idempotency-conflict') throw new Error('Red-day observation UUID was rebound.');
        if (result.outcome === 'recorded') recorded++;
        else if (result.outcome === 'correction-review') correctionReviews++;
        else alreadyRecorded++;
        continue;
      }
      providerReads++;
      try {
        const read = await this.#market.read({assetId: candidate.assetId, listedSymbol,
          afterMarketDate: candidate.afterMarketDate});
        sessionsObserved += read.sessions.length;
        const newRedSessions: string[] = [];
        for (const session of read.sessions) {
          const observationId = this.#uuid();
          const result = await this.#repository.record(Object.freeze({observationId, session}));
          if (result.outcome === 'idempotency-conflict') throw new Error('Red-day observation UUID was rebound.');
          if (result.outcome === 'recorded') recorded++;
          else if (result.outcome === 'correction-review') correctionReviews++;
          else alreadyRecorded++;
          evidence += result.evidenceCount;
          completed += result.completedCount;
          if (result.outcome === 'recorded' && session.outcome === 'verified-red') newRedSessions.push(observationId);
        }
        // Persist the whole provider response while its shared observation
        // timestamp is fresh. Evidence reconstruction starts only afterward.
        for (const observationId of newRedSessions) {
          const processed = await this.#repository.processSession(observationId, this.#evidenceBatchLimit);
          sessionBatchesProcessed++;
          if (processed.processingComplete) sessionsCompleted++;
          evidence += processed.evidenceCount;
          completed += processed.completedCount;
        }
      } catch (error) {
        if (!(error instanceof RedDayMarketError)) throw error;
        providerFailures++;
        failureCodes.push(error.code);
        const failure: RedDayFailureObservation = Object.freeze({observationId: this.#uuid(),
          provider: RED_DAY_PROVIDER, verifierVersion: RED_DAY_VERIFIER_VERSION,
          assetId: candidate.assetId, listedSymbol, status: error.status,
          reasonCode: error.code, observedAt: error.observedAt, audit: error.audit});
        const result = await this.#repository.record(failure);
        if (result.outcome === 'idempotency-conflict') throw new Error('Red-day observation UUID was rebound.');
        if (result.outcome === 'recorded') recorded++;
        else if (result.outcome === 'correction-review') correctionReviews++;
        else alreadyRecorded++;
        // Authentication and provider throttling apply to the whole key. One
        // audited attempt ends this bounded pass instead of hot-looping the
        // remaining assets; the external scheduler decides when to try again.
        if (error.code === 'provider-auth-failed' || error.code === 'provider-rate-limited') break;
      }
    }
    return Object.freeze({pendingSessions: pending.length, sessionBatchesProcessed, sessionsCompleted,
      candidates: candidates.length, providerReads, sessionsObserved,
      observationsRecorded: recorded, observationsAlreadyRecorded: alreadyRecorded,
      correctionReviews,
      evidenceRecorded: evidence, missionsCompleted: completed, providerFailures, unknownAssets,
      failureCodes: Object.freeze(failureCodes)});
  }

  #uuid(): string {
    const value = this.#uuidFactory();
    if (!uuidPattern.test(value)) throw new TypeError('Red-day worker UUID factory returned an invalid UUID.');
    return value.toLowerCase();
  }

  #timestamp(): string {
    const value = this.#now();
    if (!Number.isSafeInteger(value) || value < 0 || value > 8_639_999_999_000_000) {
      throw new TypeError('Red-day worker clock is invalid.');
    }
    return new Date(value).toISOString();
  }
}
