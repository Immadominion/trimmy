import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { TokensPaperPriceReader, PaperPriceError, paperPriceMicrosFromProvider } from '../src/paper-price-reader.js';
import { StockDiscoveryError } from '../src/stock-discovery.js';
import type { StockDiscovery, StockVariantsPage } from '../src/stock-discovery.js';

const mint = 'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H';
const now = Date.parse('2026-09-20T12:00:00.000Z');
function page(overrides: Partial<StockVariantsPage> = {}): StockVariantsPage {
  return {
    schemaVersion: 1, provider: 'tokens-xyz-v1', sourceUrl: 'https://api.tokens.xyz/v1/assets/apple/variants',
    requestedAt: '2026-09-20T11:59:59.900Z', observedAt: '2026-09-20T12:00:00.000Z', providerAsOf: null,
    providerFreshness: 'not_verified', refreshAfter: '2026-09-20T12:01:00.000Z', executionEnabled: false,
    eligibility: 'unverified', mintVerification: 'not_checked', assetId: 'apple',
    variants: [{variantId: 'apple-xstocks', mint, chain: 'solana', kind: 'tokenized-stock', issuer: 'xStocks',
      label: 'Apple xStock', name: 'Apple', symbol: 'AAPLx', providerRedemptionTier: null, advisory: null,
      market: {displayOnly: true, priceUsd: 231.1234567, liquidityUsd: 10, volume24hUsd: 5, decimals: 8,
        source: 'provider-market', metricsSource: 'provider-metrics',
        providerTimestamps: {asOf: 1234, lastFetchedAt: 1235, lastTradeAt: null, unit: 'not_declared'}}}],
    ...overrides,
  };
}
function discovery(result: StockVariantsPage | Error): StockDiscovery {
  return {search: async () => { throw new Error('unused'); }, variants: async () => {
    if (result instanceof Error) throw result;
    return result;
  }};
}
const fails = (code: string) => (error: unknown) => error instanceof PaperPriceError && error.code === code;

describe('paper price acceptance', () => {
  test('turns a display number into one exact six-decimal accepted snapshot', async () => {
    assert.equal(paperPriceMicrosFromProvider(231.1234567), '231123457');
    const reader = new TokensPaperPriceReader(discovery(page()), {now: () => now, validForMs: 30_000});
    const result = await reader.read({assetId: 'apple', variantMint: mint});
    assert.equal(result.pricePaperMicros, '231123457');
    assert.equal(result.symbol, 'AAPLx');
    assert.equal(result.source.provider, 'tokens-xyz-v1');
    assert.deepEqual(result.source.providerTimestamps,
      {asOf: '1234', lastFetchedAt: '1235', lastTradeAt: null, unit: 'not_declared'});
    assert.equal(result.expiresAt, '2026-09-20T12:00:30.000Z');
    assert.equal(JSON.stringify(result).includes('$'), false);
  });

  test('accepts after a paced provider wait and starts validity from the actual acceptance time', async () => {
    let clock = now;
    const delayed: StockDiscovery = {search: async () => { throw new Error('unused'); }, variants: async () => {
      clock += 7_000;
      return page({requestedAt: new Date(now).toISOString(), observedAt: new Date(clock).toISOString()});
    }};
    const result = await new TokensPaperPriceReader(delayed, {now: () => clock, validForMs: 30_000})
      .read({assetId: 'apple', variantMint: mint});
    assert.equal(result.source.acceptedAt, '2026-09-20T12:00:07.000Z');
    assert.equal(result.expiresAt, '2026-09-20T12:00:37.000Z');
  });

  test('fails closed on cancellation while discovery keeps its independently bounded lifecycle', async () => {
    let calls = 0;
    let finish!: (value: StockVariantsPage) => void;
    const pending = new Promise<StockVariantsPage>(resolve => { finish = resolve; });
    const delayed: StockDiscovery = {
      search: async () => { throw new Error('unused'); },
      variants: async () => { calls++; return pending; },
    };
    const reader = new TokensPaperPriceReader(delayed, {now: () => now});

    const alreadyAborted = new AbortController();
    alreadyAborted.abort();
    await assert.rejects(reader.read({assetId: 'apple', variantMint: mint,
      signal: alreadyAborted.signal}), error =>
      error instanceof PaperPriceError && error.failureKind === 'timeout');
    assert.equal(calls, 0);

    const controller = new AbortController();
    const read = reader.read({assetId: 'apple', variantMint: mint, signal: controller.signal});
    controller.abort();
    await assert.rejects(read, error =>
      error instanceof PaperPriceError && error.failureKind === 'timeout');
    assert.equal(calls, 1);

    // The injected discovery boundary has no caller-owned signal. Resolving it
    // proves the canceled caller is detached without claiming its work vanished.
    finish(page());
    await pending;
  });

  test('refuses flagged, absent, stale and malformed provider prices', async () => {
    const flagged = page({variants: [{...page().variants[0]!, advisory: {
      status: 'caution', providerStatus: 'caution', reason: 'test', since: '2026-09-20T00:00:00.000Z'}}]});
    await assert.rejects(new TokensPaperPriceReader(discovery(flagged), {now: () => now}).read({assetId: 'apple', variantMint: mint}),
      fails('PAPER_ASSET_UNAVAILABLE'));
    await assert.rejects(new TokensPaperPriceReader(discovery(page({variants: []})), {now: () => now}).read({assetId: 'apple', variantMint: mint}),
      fails('PAPER_ASSET_UNAVAILABLE'));
    await assert.rejects(new TokensPaperPriceReader(discovery(page({observedAt: '2026-09-20T11:59:40.000Z'})), {now: () => now}).read({assetId: 'apple', variantMint: mint}),
      fails('PAPER_PRICE_STALE'));
    for (const value of [null, 0, -1, Infinity, 1_000_000_000]) {
      assert.throws(() => paperPriceMicrosFromProvider(value), fails('PAPER_PRICE_UNAVAILABLE'));
    }
  });

  test('keeps provider failures opaque', async () => {
    const reader = new TokensPaperPriceReader(discovery(new Error('secret provider body')), {now: () => now});
    await assert.rejects(reader.read({assetId: 'apple', variantMint: mint}), error => {
      assert.ok(error instanceof PaperPriceError);
      assert.equal(error.code, 'PAPER_PRICE_UNAVAILABLE');
      assert.equal(error.message.includes('secret'), false);
      return true;
    });
  });

  test('maps provider saturation and deadlines to safe actionable paper price errors', async () => {
    for (const [providerCode, failureKind] of [
      ['STOCK_RATE_LIMITED', 'rate_limited'],
      ['STOCK_TIMEOUT', 'timeout'],
      ['STOCK_PROVIDER_AUTH_FAILED', 'default'],
    ] as const) {
      const reader = new TokensPaperPriceReader(discovery(new StockDiscoveryError(providerCode)), {now: () => now});
      await assert.rejects(reader.read({assetId: 'apple', variantMint: mint}), error => {
        assert.ok(error instanceof PaperPriceError);
        assert.equal(error.code, 'PAPER_PRICE_UNAVAILABLE');
        assert.equal(error.failureKind, failureKind);
        assert.equal(error.message.includes('provider'), false);
        return true;
      });
    }
  });
});
