import assert from 'node:assert/strict';
import {describe, it} from 'node:test';
import type {CanonicalRedDayRead, CanonicalRedDayReader, CanonicalRedDaySession,
  RedDayRequestAudit} from '../src/career-red-day-market.js';
import {RedDayMarketError} from '../src/career-red-day-market.js';
import type {CareerRedDayRepository, RedDayObservation, RedDayProcessResult,
  RedDayRecordResult} from '../src/career-red-day-repository.js';
import {PostgresCareerRedDayRepository} from '../src/career-red-day-repository.js';
import {CareerRedDayWorker, parseRedDayAssetCatalog} from '../src/career-red-day-worker.js';

const audit: RedDayRequestAudit = Object.freeze({
  detailRequestId: '91000000-0000-4000-8000-000000000001',
  chartRequestId: '91000000-0000-4000-8000-000000000002',
  detailProviderRequestId: null, chartProviderRequestId: null,
  detailPath: '/v1/assets/apple',
  chartPath: '/v1/assets/apple/price-chart?interval=1D&from=1786854600&to=1789878600',
  detailResponseSha256: 'a'.repeat(64), chartResponseSha256: 'b'.repeat(64),
});

function session(changes: Partial<CanonicalRedDaySession> = {}): CanonicalRedDaySession {
  return Object.freeze({provider: 'tokens-xyz-v1', source: 'clickhouse_stock',
    verifierVersion: 'tokens-canonical-red-day-v1', assetId: 'apple', listedSymbol: 'AAPL',
    previousMarketDate: '2026-09-17', marketDate: '2026-09-18', previousCloseText: '337',
    currentCloseText: '334.79', outcome: 'verified-red',
    providerAsOf: '2026-09-18T21:00:00.000Z',
    providerLastFetchedAt: '2026-09-20T04:29:59.000Z',
    observedAt: '2026-09-20T04:30:00.000Z', audit, ...changes});
}

class MemoryRepository implements CareerRedDayRepository {
  readonly observations: RedDayObservation[] = [];
  readonly processed: string[] = [];
  readonly events: string[] = [];
  constructor(readonly assets: readonly {assetId: string; afterMarketDate: string | null}[] =
    [{assetId: 'apple', afterMarketDate: null}],
  readonly pending: readonly {observationId: string; assetId: string; marketDate: string}[] = [],
  private readonly beforeRecord: (value: RedDayObservation) => void = () => {},
  private readonly afterProcess: () => void = () => {}) {}
  async pendingSessions(): Promise<typeof this.pending> { return this.pending; }
  async candidates(): Promise<readonly {assetId: string; afterMarketDate: string | null}[]> { return this.assets; }
  async record(value: RedDayObservation): Promise<RedDayRecordResult> {
    this.beforeRecord(value);
    this.observations.push(value);
    this.events.push(`record:${'session' in value ? value.session.marketDate : value.reasonCode}`);
    return {outcome: 'recorded', observationId: value.observationId,
      evidenceCount: 0, completedCount: 0};
  }
  async processSession(observationId: string): Promise<RedDayProcessResult> {
    this.processed.push(observationId);
    this.events.push(`process:${observationId}`);
    this.afterProcess();
    return {outcome: 'complete', observationId, evidenceCount: 2,
      completedCount: 1, processingComplete: true};
  }
}

class MemoryMarket implements CanonicalRedDayReader {
  readonly reads: {assetId: string; listedSymbol: string; afterMarketDate: string | null}[] = [];
  constructor(private readonly result: CanonicalRedDayRead | Error) {}
  async read(input: {assetId: string; listedSymbol: string;
    afterMarketDate: string | null}): Promise<CanonicalRedDayRead> {
    this.reads.push(input);
    if (this.result instanceof Error) throw this.result;
    return this.result;
  }
}

function ids(): () => string {
  let next = 10;
  return () => `91000000-0000-4000-8000-${String(next++).padStart(12, '0')}`;
}

describe('Career red-day worker', () => {
  it('strictly parses an explicit canonical asset catalog', () => {
    const catalog = parseRedDayAssetCatalog('{"apple":"AAPL","3m-company":"MMM"}');
    assert.deepEqual([...catalog], [['apple', 'AAPL'], ['3m-company', 'MMM']]);
    for (const raw of ['', '{}', '[]', '{"Apple":"AAPL"}', '{"apple":"aapl"}',
      '{"apple":"AAPL","apple":"AAPL"}']) {
      assert.throws(() => parseRedDayAssetCatalog(raw), TypeError);
    }
  });

  it('records every verified session and reports only DB-confirmed evidence and completions', async () => {
    const repository = new MemoryRepository([{assetId: 'apple', afterMarketDate: '2026-09-16'}]);
    const market = new MemoryMarket(Object.freeze({sessions: Object.freeze([
      session({marketDate: '2026-09-17', previousMarketDate: '2026-09-16'}), session(),
    ]), audit, observedAt: '2026-09-20T04:30:00.000Z'}));
    const result = await new CareerRedDayWorker({repository, market,
      assets: parseRedDayAssetCatalog('{"apple":"AAPL"}'), uuid: ids()}).runOnce();
    assert.deepEqual(market.reads, [{assetId: 'apple', listedSymbol: 'AAPL',
      afterMarketDate: '2026-09-16'}]);
    assert.equal(repository.observations.length, 2);
    assert.deepEqual(result, {pendingSessions: 0, sessionBatchesProcessed: 2, sessionsCompleted: 2,
      candidates: 1, providerReads: 1, sessionsObserved: 2,
      observationsRecorded: 2, observationsAlreadyRecorded: 0,
      correctionReviews: 0, evidenceRecorded: 4, missionsCompleted: 2,
      providerFailures: 0, unknownAssets: 0, failureCodes: []});
  });

  it('resumes bounded pending evidence batches before reading new market sessions', async () => {
    const pendingId = '91000000-0000-4000-8000-000000000099';
    const repository = new MemoryRepository([], [
      {observationId: pendingId, assetId: 'apple', marketDate: '2026-09-18'},
    ]);
    const market = new MemoryMarket(new Error('must not run'));
    const result = await new CareerRedDayWorker({repository, market,
      assets: parseRedDayAssetCatalog('{"apple":"AAPL"}'), evidenceBatchLimit: 3}).runOnce();
    assert.deepEqual(repository.processed, [pendingId]);
    assert.equal(result.pendingSessions, 1);
    assert.equal(result.sessionBatchesProcessed, 1);
    assert.equal(result.sessionsCompleted, 1);
    assert.equal(result.evidenceRecorded, 2);
  });

  it('records every fetched session before slow evidence processing can stale the shared read', async () => {
    let clock = Date.parse('2026-09-20T04:30:00.000Z');
    const repository = new MemoryRepository([{assetId: 'apple', afterMarketDate: null}], [], value => {
      if ('session' in value && Date.parse(value.session.observedAt) < clock - 120_000) {
        throw new Error('observation-stale');
      }
    }, () => { clock += 180_001; });
    const market = new MemoryMarket(Object.freeze({sessions: Object.freeze([
      session({marketDate: '2026-09-17', previousMarketDate: '2026-09-16'}), session(),
    ]), audit, observedAt: '2026-09-20T04:30:00.000Z'}));
    await new CareerRedDayWorker({repository, market,
      assets: parseRedDayAssetCatalog('{"apple":"AAPL"}'), uuid: ids()}).runOnce();
    assert.deepEqual(repository.events.map(value => value.split(':')[0]),
      ['record', 'record', 'process', 'process']);
  });

  it('audits an unknown asset without making a provider request', async () => {
    const repository = new MemoryRepository([{assetId: 'tesla', afterMarketDate: null}]);
    const market = new MemoryMarket(new Error('must not run'));
    const result = await new CareerRedDayWorker({repository, market,
      assets: parseRedDayAssetCatalog('{"apple":"AAPL"}'), uuid: ids(),
      now: () => Date.parse('2026-09-20T04:30:00.000Z')}).runOnce();
    assert.equal(market.reads.length, 0);
    assert.equal(result.unknownAssets, 1);
    assert.deepEqual(result.failureCodes, ['asset-not-in-catalog']);
    const observation = repository.observations[0];
    assert.ok(observation && !('session' in observation));
    assert.equal(observation.reasonCode, 'asset-not-in-catalog');
    assert.equal(observation.listedSymbol, null);
  });

  it('records an auth or rate-limit failure once and ends the pass', async () => {
    for (const code of ['provider-auth-failed', 'provider-rate-limited'] as const) {
      const repository = new MemoryRepository([
        {assetId: 'apple', afterMarketDate: null}, {assetId: 'tesla', afterMarketDate: null},
      ]);
      const market = new MemoryMarket(new RedDayMarketError('unavailable', code, audit,
        '2026-09-20T04:30:00.000Z'));
      const result = await new CareerRedDayWorker({repository, market,
        assets: parseRedDayAssetCatalog('{"apple":"AAPL","tesla":"TSLA"}'), uuid: ids()}).runOnce();
      assert.equal(market.reads.length, 1);
      assert.equal(repository.observations.length, 1);
      assert.equal(result.providerFailures, 1);
      assert.deepEqual(result.failureCodes, [code]);
    }
  });

  it('continues a bounded pass after an asset-local unavailable response', async () => {
    const repository = new MemoryRepository([
      {assetId: 'apple', afterMarketDate: null}, {assetId: 'tesla', afterMarketDate: null},
    ]);
    const market = new MemoryMarket(new RedDayMarketError('unavailable', 'provider-unavailable', audit,
      '2026-09-20T04:30:00.000Z'));
    const result = await new CareerRedDayWorker({repository, market,
      assets: parseRedDayAssetCatalog('{"apple":"AAPL","tesla":"TSLA"}'), uuid: ids()}).runOnce();
    assert.equal(market.reads.length, 2);
    assert.equal(result.providerFailures, 2);
    assert.deepEqual(result.failureCodes, ['provider-unavailable', 'provider-unavailable']);
  });
});

describe('PostgreSQL red-day repository adapter', () => {
  it('uses only fixed database functions and parses exact results', async () => {
    const queries: {text: string; values: readonly unknown[]}[] = [];
    const pool = {query: async (text: string, values: readonly unknown[]) => {
      queries.push({text, values});
      if (text.includes('career_red_day_candidates')) {
        return {rows: [{asset_id: 'apple', after_market_date: '2026-09-18'}]};
      }
      return {rows: [{outcome: 'recorded', observation_id: values[0], evidence_count: '1', completed_count: '1'}]};
    }};
    const repository = new PostgresCareerRedDayRepository(pool as never);
    assert.deepEqual(await repository.candidates(20), [{assetId: 'apple', afterMarketDate: '2026-09-18'}]);
    const observationId = '91000000-0000-4000-8000-000000000099';
    assert.deepEqual(await repository.record({observationId, session: session()}),
      {outcome: 'recorded', observationId, evidenceCount: 1, completedCount: 1});
    assert.equal(queries.length, 2);
    assert.match(queries[0]?.text ?? '', /trimmy\.career_red_day_candidates/u);
    assert.match(queries[1]?.text ?? '', /trimmy\.career_red_day_record_observation/u);
    assert.equal(queries[1]?.values.length, 23);
    assert.equal(queries[1]?.values[4], 'AAPL');
    assert.equal(queries[1]?.values[5], 'verified-red');
  });

  it('parses exact pending and bounded processing results', async () => {
    const observationId = '91000000-0000-4000-8000-000000000099';
    const queries: {text: string; values: readonly unknown[]}[] = [];
    const pool = {query: async (text: string, values: readonly unknown[]) => {
      queries.push({text, values});
      if (text.includes('pending_sessions')) return {rows: [{observation_id: observationId,
        asset_id: 'apple', market_date: '2026-09-18'}]};
      return {rows: [{outcome: 'processed', observation_id: observationId,
        evidence_count: '3', completed_count: '1', processing_complete: false}]};
    }};
    const repository = new PostgresCareerRedDayRepository(pool as never);
    assert.deepEqual(await repository.pendingSessions(4), [
      {observationId, assetId: 'apple', marketDate: '2026-09-18'},
    ]);
    assert.deepEqual(await repository.processSession(observationId, 3), {
      outcome: 'processed', observationId, evidenceCount: 3, completedCount: 1,
      processingComplete: false,
    });
    assert.match(queries[1]?.text ?? '', /career_red_day_process_session/u);
    assert.deepEqual(queries[1]?.values, [observationId, 3]);
  });
});
