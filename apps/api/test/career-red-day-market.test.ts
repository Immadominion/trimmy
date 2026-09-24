import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {describe, it} from 'node:test';
import {
  RedDayMarketError,
  TokensCanonicalRedDayReader,
} from '../src/career-red-day-market.js';

const now = Date.parse('2026-09-20T04:30:00.000Z');
const day = (value: string): number => Date.parse(`${value}T00:00:00.000Z`) / 1000;

function detail(changes: Record<string, unknown> = {}): string {
  return JSON.stringify({asset: {
    assetId: 'apple', name: 'Apple', symbol: 'AAPL', description: 'Apple Inc.', category: 'equity',
    aliases: [], symbols: ['AAPL'], imageUrl: 'https://example.test/apple.png', stats: {},
    primaryVariantStrategy: 'stock_redeemability', primaryVariant: null, advisories: [], variantGroups: {},
    canonicalMarket: {
      source: 'clickhouse_stock', symbol: 'AAPL', price: 334.79, marketCap: 1,
      volume24hUSD: 0, priceChange24hPercent: -0.5,
      lastFetchedAt: now - 1_000,
      providerLastUpdatedAt: Math.floor(Date.parse('2026-09-18T21:00:00.000Z') / 1000),
      asOf: Math.floor(Date.parse('2026-09-18T21:00:00.000Z') / 1000),
      ...(changes['canonicalMarket'] as object | undefined),
    },
    ...Object.fromEntries(Object.entries(changes).filter(([key]) => key !== 'canonicalMarket')),
  }});
}

function chart(url: URL, closes: readonly [string, number][] = [
  ['2026-09-17', 337], ['2026-09-18', 334.79],
]): string {
  return JSON.stringify({assetId: 'apple', interval: '1D',
    from: Number(url.searchParams.get('from')), to: Number(url.searchParams.get('to')),
    candles: closes.map(([date, close]) => ({time: day(date), open: close + 1,
      high: close + 2, low: close - 1, close, volume: 100}))});
}

function response(body: string, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(body, {status, headers: {'content-type': 'application/json', ...headers}});
}

function reader(fetch: typeof globalThis.fetch, clock = now): TokensCanonicalRedDayReader {
  return new TokensCanonicalRedDayReader({apiKey: 'test-server-key', fetch, now: () => clock,
    paceMs: 0, timeoutMs: 100, wait: async () => {}, requestId: randomUUID});
}

const input = {assetId: 'apple', listedSymbol: 'AAPL', afterMarketDate: null} as const;

describe('Tokens canonical red-day reader', () => {
  it('requires two agreeing canonical responses and emits exact red-day evidence without a mint', async () => {
    const urls: URL[] = [];
    const result = await reader(async requested => {
      const url = new URL(String(requested)); urls.push(url);
      if (url.pathname.endsWith('/price-chart')) {
        return response(chart(url), 200, {'x-request-id': 'provider-chart-1'});
      }
      return response(detail(), 200, {'x-request-id': 'provider-detail-1'});
    }).read(input);
    assert.equal(urls.length, 2);
    assert.equal(urls[0]?.href, 'https://api.tokens.xyz/v1/assets/apple');
    assert.equal(urls[1]?.pathname, '/v1/assets/apple/price-chart');
    assert.equal(urls[1]?.searchParams.get('interval'), '1D');
    assert.equal(urls[1]?.searchParams.has('mint'), false);
    assert.equal(Number(urls[1]?.searchParams.get('to')) - Number(urls[1]?.searchParams.get('from')), 35 * 86_400);
    assert.equal(result.sessions.length, 1);
    assert.deepEqual(result.sessions[0], {
      provider: 'tokens-xyz-v1', source: 'clickhouse_stock',
      verifierVersion: 'tokens-canonical-red-day-v1', assetId: 'apple', listedSymbol: 'AAPL',
      previousMarketDate: '2026-09-17', marketDate: '2026-09-18',
      previousCloseText: '337', currentCloseText: '334.79', outcome: 'verified-red',
      providerAsOf: '2026-09-18T21:00:00.000Z',
      providerLastFetchedAt: '2026-09-20T04:29:59.000Z',
      observedAt: '2026-09-20T04:30:00.000Z', audit: result.audit,
    });
    assert.equal(result.audit.detailProviderRequestId, 'provider-detail-1');
    assert.equal(result.audit.chartProviderRequestId, 'provider-chart-1');
    assert.match(result.audit.detailResponseSha256 ?? '', /^[a-f0-9]{64}$/u);
    assert.match(result.audit.chartResponseSha256 ?? '', /^[a-f0-9]{64}$/u);
  });

  it('preserves a non-red close as a terminal verified-not-red observation', async () => {
    const result = await reader(async requested => {
      const url = new URL(String(requested));
      return response(url.pathname.endsWith('/price-chart')
        ? chart(url, [['2026-09-17', 330], ['2026-09-18', 334.79]]) : detail());
    }).read(input);
    assert.equal(result.sessions[0]?.outcome, 'verified-not-red');
    assert.equal(result.sessions[0]?.previousCloseText, '330');
  });

  it('returns only sessions later than the last canonical database session', async () => {
    const result = await reader(async requested => {
      const url = new URL(String(requested));
      return response(url.pathname.endsWith('/price-chart') ? chart(url, [
        ['2026-09-16', 332], ['2026-09-17', 337], ['2026-09-18', 334.79],
      ]) : detail());
    }).read({...input, afterMarketDate: '2026-09-17'});
    assert.deepEqual(result.sessions.map(value => value.marketDate), ['2026-09-18']);
  });

  it('uses a full chart window but emits only closed sessions inside the database freshness window', async () => {
    const closes: [string, number][] = [];
    for (let offset = 34; offset >= 0; offset--) {
      const instant = new Date(Date.parse('2026-09-20T00:00:00.000Z') - offset * 86_400_000);
      if (instant.getUTCDay() === 0 || instant.getUTCDay() === 6) continue;
      const date = instant.toISOString().slice(0, 10);
      closes.push([date, 400 - offset]);
    }
    const result = await reader(async requested => {
      const url = new URL(String(requested));
      return response(url.pathname.endsWith('/price-chart') ? chart(url, closes) : detail());
    }).read(input);
    assert.deepEqual(result.sessions.map(value => value.marketDate), [
      '2026-09-07', '2026-09-08', '2026-09-09', '2026-09-10', '2026-09-11',
      '2026-09-14', '2026-09-15', '2026-09-16', '2026-09-17', '2026-09-18',
    ]);
    assert.equal(result.sessions.at(-1)?.marketDate, '2026-09-18');
  });

  it('uses adjacent canonical candles across a weekday exchange-holiday gap', async () => {
    // Labor Day 2026 fell on Monday 7 September. Pin the reader close enough
    // to the resumed Tuesday session that the provider freshness contract is
    // exercised independently from the calendar-gap assertion.
    const holidayNow = Date.parse('2026-09-10T04:30:00.000Z');
    const holidayAsOf = Math.floor(Date.parse('2026-09-08T21:00:00.000Z') / 1000);
    const result = await reader(async requested => {
      const url = new URL(String(requested));
      return response(url.pathname.endsWith('/price-chart')
        ? chart(url, [['2026-09-04', 340], ['2026-09-08', 338]])
        : detail({canonicalMarket: {lastFetchedAt: holidayNow - 1_000,
          providerLastUpdatedAt: holidayAsOf, asOf: holidayAsOf}}));
    }, holidayNow).read(input);
    assert.deepEqual(result.sessions.map(value => [value.previousMarketDate, value.marketDate]),
      [['2026-09-04', '2026-09-08']]);
  });

  it('rejects Saturday and Sunday provider candles', async () => {
    for (const weekendDate of ['2026-09-19', '2026-09-20']) {
      await assert.rejects(reader(async requested => {
        const url = new URL(String(requested));
        return response(url.pathname.endsWith('/price-chart')
          ? chart(url, [['2026-09-18', 340], [weekendDate, 338]]) : detail());
      }).read(input), error => error instanceof RedDayMarketError && error.code === 'response-invalid');
    }
  });

  it('fails closed on identity, source, freshness and unclosed sessions', async () => {
    const cases: readonly [string, string][] = [
      ['identity-mismatch', detail({symbol: 'TSLA'})],
      ['source-mismatch', detail({canonicalMarket: {source: 'birdeye'}})],
      ['stale-provider-data', detail({canonicalMarket: {lastFetchedAt: now - 31 * 60_000}})],
    ];
    for (const [code, detailBody] of cases) {
      await assert.rejects(reader(async requested => {
        const url = new URL(String(requested));
        return response(url.pathname.endsWith('/price-chart') ? chart(url) : detailBody);
      }).read(input), error => error instanceof RedDayMarketError && error.status === 'rejected' && error.code === code);
    }
    const beforeClose = Date.parse('2026-09-18T18:00:00.000Z');
    const beforeCloseDetail = detail({canonicalMarket: {lastFetchedAt: beforeClose - 1_000,
      providerLastUpdatedAt: Math.floor((beforeClose - 1_000) / 1000),
      asOf: Math.floor((beforeClose - 1_000) / 1000)}});
    await assert.rejects(reader(async requested => {
      const url = new URL(String(requested));
      return response(url.pathname.endsWith('/price-chart') ? chart(url) : beforeCloseDetail);
    }, beforeClose).read(input),
    error => error instanceof RedDayMarketError && error.status === 'rejected' && error.code === 'response-invalid');
  });

  it('rejects extra decision-layer keys, duplicate or reordered candles and malformed prices', async () => {
    const extra = JSON.parse(detail()) as {asset: Record<string, unknown>};
    extra.asset['unexpected'] = true;
    const chartCases = [
      (url: URL) => chart(url, [['2026-09-18', 334], ['2026-09-17', 337]]),
      (url: URL) => chart(url, [['2026-09-18', 334], ['2026-09-18', 337]]),
      (url: URL) => JSON.stringify({...JSON.parse(chart(url)) as object,
        candles: [{time: day('2026-09-17'), open: 1, high: 2, low: 1, close: -1, volume: 2},
          {time: day('2026-09-18'), open: 1, high: 2, low: 1, close: 1, volume: 2}]}),
    ];
    await assert.rejects(reader(async () => response(JSON.stringify(extra))).read(input),
      error => error instanceof RedDayMarketError && error.code === 'response-invalid');
    for (const makeChart of chartCases) {
      await assert.rejects(reader(async requested => {
        const url = new URL(String(requested));
        return response(url.pathname.endsWith('/price-chart') ? makeChart(url) : detail());
      }).read(input), error => error instanceof RedDayMarketError && error.code === 'response-invalid');
    }
  });

  it('type-checks every display block while isolating bounded provider-owned nested keys', async () => {
    for (const changes of [
      {aliases: 123}, {stats: []}, {primaryVariant: 'not-an-object'},
      {advisories: ['not-an-object']}, {imageUrl: 'http://example.test/apple.png'},
    ]) {
      await assert.rejects(reader(async () => response(detail(changes))).read(input),
        error => error instanceof RedDayMarketError && error.code === 'response-invalid');
    }
    const result = await reader(async requested => {
      const url = new URL(String(requested));
      return response(url.pathname.endsWith('/price-chart') ? chart(url) : detail({
        stats: {providerOwnedFutureField: {bounded: true}},
      }));
    }).read(input);
    assert.equal(result.sessions.length, 1);
  });

  it('classifies bounded provider failures and records no response body or credential', async () => {
    for (const [status, code] of [[401, 'provider-auth-failed'], [403, 'provider-auth-failed'],
      [429, 'provider-rate-limited'], [503, 'provider-unavailable']] as const) {
      await assert.rejects(reader(async () => response('{}', status)).read(input), error => {
        assert.ok(error instanceof RedDayMarketError);
        assert.equal(error.status, 'unavailable');
        assert.equal(error.code, code);
        assert.equal(error.audit.detailResponseSha256, null);
        assert.equal(JSON.stringify(error).includes('test-server-key'), false);
        return true;
      });
    }
  });

  it('times out a provider that never answers', async () => {
    const stalled = new Promise<Response>(() => {});
    await assert.rejects(reader(async () => stalled, now).read(input),
      error => error instanceof RedDayMarketError && error.code === 'provider-timeout');
  });
});
