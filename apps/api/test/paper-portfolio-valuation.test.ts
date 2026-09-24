import assert from 'node:assert/strict';
import {describe, test} from 'node:test';
import type {AcceptedPaperPrice, PaperPriceReader} from '../src/paper-price-reader.js';
import {
  acceptsPaperPortfolioV2,
  PAPER_PORTFOLIO_V2_MEDIA_TYPE,
  valuePaperPortfolio,
} from '../src/paper-portfolio-valuation.js';
import type {PaperPortfolio, PaperPosition} from '../src/paper-trading-repository.js';

const now = Date.parse('2026-09-20T12:00:10.000Z');
const mintA = 'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H';
const mintB = '4'.repeat(44);

function position(input: Partial<PaperPosition> = {}): PaperPosition {
  return Object.freeze({
    assetId: 'apple',
    variantMint: mintA,
    symbol: 'AAPLx',
    quantityMicros: '500000',
    costBasisPaperMicros: '100000000',
    averageCostPricePaperMicros: '200000000',
    realizedGainPaperMicros: '0',
    lockedGainPaperMicros: '0',
    updatedAt: '2026-09-20T11:59:00.000Z',
    ...input,
  });
}

function portfolio(positions: readonly PaperPosition[], cashPaperMicros = '9000000000'): PaperPortfolio {
  return Object.freeze({
    revision: positions.length === 0 ? 0 : 2,
    scaleDigits: 6,
    startingCashPaperMicros: '10000000000',
    cashPaperMicros,
    openedAt: positions.length === 0 ? null : '2026-09-20T11:50:00.000Z',
    updatedAt: positions.length === 0 ? null : '2026-09-20T11:59:00.000Z',
    positions: Object.freeze(positions),
    recentOrders: Object.freeze([]),
  });
}

function accepted(
  assetId: string,
  variantMint: string,
  pricePaperMicros = '250000000',
  times: Partial<{observedAt: string; acceptedAt: string; expiresAt: string}> = {},
): AcceptedPaperPrice {
  const observedAt = times.observedAt ?? '2026-09-20T12:00:09.000Z';
  const acceptedAt = times.acceptedAt ?? '2026-09-20T12:00:10.000Z';
  return Object.freeze({
    assetId,
    variantMint,
    symbol: assetId === 'apple' ? 'AAPLx' : 'MSFTx',
    pricePaperMicros,
    source: Object.freeze({
      provider: 'tokens-xyz-v1' as const,
      providerReference: `/v1/assets/${assetId}/variants#fixture`,
      marketSource: 'fixture',
      metricsSource: null,
      providerTimestamps: Object.freeze({
        asOf: null,
        lastFetchedAt: null,
        lastTradeAt: null,
        unit: 'not_declared' as const,
      }),
      observedAt,
      acceptedAt,
    }),
    expiresAt: times.expiresAt ?? '2026-09-20T12:00:40.000Z',
  });
}

describe('paper portfolio valuation', () => {
  test('prices an exact asset and mint with fixed-point floor rounding', async () => {
    const rows = [
      position({quantityMicros: '333333', costBasisPaperMicros: '70000000'}),
      position({variantMint: mintB, quantityMicros: '2000000',
        costBasisPaperMicros: '600000000', averageCostPricePaperMicros: '300000000'}),
    ];
    const reads: string[] = [];
    const prices: PaperPriceReader = {read: async input => {
      reads.push(`${input.assetId}:${input.variantMint}`);
      return accepted(input.assetId, input.variantMint,
        input.variantMint === mintA ? '200000001' : '250000000');
    }};
    const result = await valuePaperPortfolio(portfolio(rows), prices, {now: () => now});
    const firstValue = 333333n * 200000001n / 1000000n;

    assert.equal(result.status, 'complete');
    assert.equal(result.portfolioRevision, 2);
    assert.equal(result.openPositionCount, 2);
    assert.equal(result.pricedPositionCount, 2);
    assert.deepEqual(reads, [`apple:${mintA}`, `apple:${mintB}`]);
    assert.deepEqual(result.positions[0], {
      assetId: 'apple', variantMint: mintA, status: 'priced',
      pricePaperMicros: '200000001', marketValuePaperMicros: firstValue.toString(),
      unrealizedGainPaperMicros: (firstValue - 70000000n).toString(),
      observedAt: '2026-09-20T12:00:09.000Z', acceptedAt: '2026-09-20T12:00:10.000Z',
      expiresAt: '2026-09-20T12:00:40.000Z',
    });
    assert.equal(result.positions[1]?.marketValuePaperMicros, '500000000');
    assert.equal(result.positions[1]?.unrealizedGainPaperMicros, '-100000000');
    assert.equal(result.knownValuePaperMicros,
      (9000000000n + firstValue + 500000000n).toString());
    assert.equal(result.totalPaperMicros, result.knownValuePaperMicros);
  });

  test('coalesces a repeated exact asset and mint while valuing each ledger row independently', async () => {
    let reads = 0;
    const prices: PaperPriceReader = {read: async input => {
      reads++;
      return accepted(input.assetId, input.variantMint, '200000001');
    }};
    const result = await valuePaperPortfolio(portfolio([
      position({quantityMicros: '1000000', costBasisPaperMicros: '150000000'}),
      position({quantityMicros: '250000', costBasisPaperMicros: '60000000'}),
    ]), prices, {now: () => now, maxPriceReads: 1});

    assert.equal(reads, 1);
    assert.equal(result.status, 'complete');
    assert.equal(result.pricedPositionCount, 2);
    assert.equal(result.positions[0]?.marketValuePaperMicros, '200000001');
    assert.equal(result.positions[0]?.unrealizedGainPaperMicros, '50000001');
    assert.equal(result.positions[1]?.marketValuePaperMicros, '50000000');
    assert.equal(result.positions[1]?.unrealizedGainPaperMicros, '-10000000');
  });

  test('returns cash as a complete valuation without making a market read', async () => {
    let reads = 0;
    const prices: PaperPriceReader = {read: async input => {
      reads++;
      return accepted(input.assetId, input.variantMint);
    }};
    const result = await valuePaperPortfolio(portfolio([]), prices, {now: () => now});

    assert.equal(reads, 0);
    assert.deepEqual(result, {
      status: 'complete', portfolioRevision: 0, openPositionCount: 0,
      pricedPositionCount: 0, cashPaperMicros: '9000000000',
      knownValuePaperMicros: '9000000000', totalPaperMicros: '9000000000', positions: [],
    });
  });

  test('bounds provider fanout, skips closed rows and reports an honest partial value', async () => {
    const rows = [
      position({quantityMicros: '0', costBasisPaperMicros: '0', averageCostPricePaperMicros: '0'}),
      position({assetId: 'apple-one', variantMint: mintA}),
      position({assetId: 'apple-two', variantMint: mintB}),
      position({assetId: 'apple-three', variantMint: '5'.repeat(44)}),
    ];
    const reads: string[] = [];
    const prices: PaperPriceReader = {read: async input => {
      reads.push(input.assetId);
      if (input.assetId === 'apple-two') throw new Error('private provider failure');
      return accepted(input.assetId, input.variantMint);
    }};
    const result = await valuePaperPortfolio(portfolio(rows), prices,
      {now: () => now, maxPriceReads: 2});

    assert.deepEqual(reads.sort(), ['apple-one', 'apple-two']);
    assert.equal(result.status, 'partial');
    assert.equal(result.openPositionCount, 3);
    assert.equal(result.pricedPositionCount, 1);
    assert.equal(result.totalPaperMicros, null);
    assert.equal(result.knownValuePaperMicros, '9125000000');
    assert.deepEqual(result.positions.map(row => row.status), ['priced', 'unavailable', 'unavailable']);
    for (const row of result.positions.filter(row => row.status === 'unavailable')) {
      assert.equal(row.pricePaperMicros, null);
      assert.equal(row.marketValuePaperMicros, null);
      assert.equal(row.unrealizedGainPaperMicros, null);
      assert.equal(row.observedAt, null);
      assert.equal(row.acceptedAt, null);
      assert.equal(row.expiresAt, null);
    }
  });

  test('runs eight unique healthy reads through no more than six workers', async () => {
    const rows = Array.from({length: 8}, (_value, index) =>
      position({assetId: `asset-${index + 1}`}));
    let active = 0;
    let maximumActive = 0;
    let reads = 0;
    const prices: PaperPriceReader = {read: async input => {
      reads++;
      active++;
      maximumActive = Math.max(maximumActive, active);
      await new Promise(resolve => setTimeout(resolve, 5));
      active--;
      return accepted(input.assetId, input.variantMint);
    }};

    const result = await valuePaperPortfolio(portfolio(rows), prices, {now: () => now});

    assert.equal(reads, 8);
    assert.equal(maximumActive, 6);
    assert.equal(result.status, 'complete');
    assert.equal(result.pricedPositionCount, 8);
  });

  test('rejects mismatched, expired and implausibly timed prices without failing the ledger read', async () => {
    for (const price of [
      accepted('other-asset', mintA),
      accepted('apple', mintA, '250000000', {
        observedAt: '2026-09-20T12:00:09Z',
      }),
      accepted('apple', mintA, '250000000', {
        acceptedAt: '2026-09-20T13:00:10.000+01:00',
      }),
      accepted('apple', mintA, '250000000', {expiresAt: '2026-09-20T12:00:10.000Z'}),
      accepted('apple', mintA, '250000000', {
        observedAt: '2026-09-20T12:00:20.000Z', acceptedAt: '2026-09-20T12:00:10.000Z',
      }),
      accepted('apple', mintA, '250000000', {
        acceptedAt: '2026-09-20T12:00:16.000Z', expiresAt: '2026-09-20T12:00:30.000Z',
      }),
    ]) {
      const prices: PaperPriceReader = {read: async () => price};
      const result = await valuePaperPortfolio(portfolio([position()]), prices, {now: () => now});
      assert.equal(result.status, 'unavailable');
      assert.equal(result.knownValuePaperMicros, '9000000000');
      assert.equal(result.totalPaperMicros, null);
      assert.equal(result.positions[0]?.status, 'unavailable');
    }
  });

  test('invalidates every display price when the valuation clock regresses at completion', async () => {
    const ticks = [now, now + 1_000, now + 1_500, now + 500];
    let index = 0;
    const prices: PaperPriceReader = {read: async input =>
      accepted(input.assetId, input.variantMint)};
    const result = await valuePaperPortfolio(portfolio([
      position(), position({assetId: 'microsoft'}),
    ]), prices,
      {now: () => ticks[index++] ?? ticks.at(-1)!});

    assert.equal(result.status, 'unavailable');
    assert.equal(result.pricedPositionCount, 0);
    assert.equal(result.knownValuePaperMicros, '9000000000');
    assert.deepEqual(result.positions.map(row => row.status), ['unavailable', 'unavailable']);
  });

  test('rechecks an early price after a sibling delay and drops it when it expires', async () => {
    let clock = now;
    const later = now + 3_000;
    const rows = [position(), position({assetId: 'microsoft'})];
    const prices: PaperPriceReader = {read: async input => {
      if (input.assetId === 'apple') {
        return accepted(input.assetId, input.variantMint, '250000000', {
          expiresAt: new Date(now + 2_000).toISOString(),
        });
      }
      await new Promise(resolve => setTimeout(resolve, 5));
      clock = later;
      return accepted(input.assetId, input.variantMint, '250000000', {
        observedAt: new Date(later).toISOString(), acceptedAt: new Date(later).toISOString(),
        expiresAt: new Date(later + 30_000).toISOString(),
      });
    }};

    const result = await valuePaperPortfolio(portfolio(rows), prices,
      {now: () => clock, deadlineMs: 100});

    assert.equal(result.status, 'partial');
    assert.equal(result.pricedPositionCount, 1);
    assert.equal(result.positions[0]?.status, 'unavailable');
    assert.equal(result.positions[1]?.status, 'priced');
  });

  test('ends a hung read at its deadline, signals it and leaves an unavailable projection', async () => {
    let signal: AbortSignal | undefined;
    const prices: PaperPriceReader = {read: async input => {
      signal = input.signal;
      return new Promise<AcceptedPaperPrice>(() => {});
    }};
    const started = Date.now();
    const result = await valuePaperPortfolio(portfolio([position()]), prices,
      {now: () => now, deadlineMs: 15});
    const elapsed = Date.now() - started;

    assert.ok(elapsed >= 5 && elapsed < 500, `deadline completed in ${elapsed}ms`);
    assert.equal(signal?.aborted, true);
    assert.equal(result.status, 'unavailable');
    assert.equal(result.positions[0]?.status, 'unavailable');
  });

  test('negotiates v2 only through one exact vendor range and strict positive q value', () => {
    assert.equal(acceptsPaperPortfolioV2(undefined), false);
    assert.equal(acceptsPaperPortfolioV2('*/*'), false);
    assert.equal(acceptsPaperPortfolioV2('application/json'), false);
    for (const value of [
      PAPER_PORTFOLIO_V2_MEDIA_TYPE,
      `application/json, ${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=0.001`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE.toUpperCase()}; q=0.8`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=1`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=1.000`,
    ]) assert.equal(acceptsPaperPortfolioV2(value), true, value);
    for (const value of [
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=0`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=0.000`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=+1`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=01`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=1e0`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=.8`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=0.1234`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=1.001`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q="1"`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};charset=utf-8`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=0.8;q=0.9`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE}, ${PAPER_PORTFOLIO_V2_MEDIA_TYPE};q=1`,
      `application/json;note="safe, ${PAPER_PORTFOLIO_V2_MEDIA_TYPE}"`,
      `application/json;note=safe\\, ${PAPER_PORTFOLIO_V2_MEDIA_TYPE}`,
      `${PAPER_PORTFOLIO_V2_MEDIA_TYPE},,application/json`,
    ]) assert.equal(acceptsPaperPortfolioV2(value), false, value);
  });
});
