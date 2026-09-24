import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {formatRawTokenUnits, parseStockEstimate, parseStockEstimateRequest, parseStockResearchConfig, parseStockSearchPage,
  parseStockVariantsPage, readStockResearchConfig, researchNeedsRefresh, RESEARCH_AAPLX_MINT, RESEARCH_USDC_MINT} from './index.js';
import {estimateFixture, searchFixture, variantFixture, variantsFixture} from './fixtures.test-support.js';

const buy = {assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, side: 'buy', amountRaw: '10000000'} as const;

test('separate public stock configuration is optional and independent from account IDs', () => {
  assert.equal(readStockResearchConfig({VITE_PRIVY_APP_ID: 'irrelevant', VITE_TRIMMY_API_URL: 'https://account.example'}).kind, 'disabled');
  assert.deepEqual(parseStockResearchConfig(''), {kind: 'disabled', apiOrigin: null});
  assert.deepEqual(readStockResearchConfig({VITE_TRIMMY_STOCK_API_URL: 'https://stocks.example/'}), {kind: 'enabled', apiOrigin: 'https://stocks.example'});
  assert.equal(parseStockResearchConfig('https://stocks.example:8443').kind, 'enabled');
  for (const value of [null, ' ', ' https://stocks.example', 'https://stocks.example\n', 'HTTPS://STOCKS.EXAMPLE', 'https://stocks.example:443',
    'http://stocks.example', 'https://secret@stocks.example', 'https://stocks.example/path', 'https://stocks.example?key=x',
    'https://stocks.example#hash', 'https://stocks.example:0', 'https://stocks.example:65536', 'https://stocks.example\\evil']) {
    assert.equal(parseStockResearchConfig(value).kind, 'invalid', String(value));
  }
});

test('HTTP is allowed only for canonical explicitly injected loopback test origins', () => {
  for (const origin of ['http://127.0.0.1:8080', 'http://localhost:8080', 'http://[::1]:8080']) {
    assert.equal(parseStockResearchConfig(origin).kind, 'invalid');
    assert.equal(parseStockResearchConfig(origin, {allowLoopbackForTests: true}).kind, 'enabled');
  }
  for (const origin of ['http://127.1:8080', 'http://127.0.0.1.example', 'http://192.168.1.2:8080']) {
    assert.equal(parseStockResearchConfig(origin, {allowLoopbackForTests: true}).kind, 'invalid');
  }
});

test('discovery is deeply immutable and preserves undeclared timestamp units and provenance', () => {
  const data = searchFixture(), page = parseStockSearchPage(data), row = page.results[0]!.variants[0]!;
  assert.equal(row.issuer, 'Backed'); assert.equal(row.providerRedemptionTier, 'provider_description_only');
  assert.deepEqual(row.market!.providerTimestamps, {asOf: 1789400000, lastFetchedAt: 1789400000000, lastTradeAt: null, unit: 'not_declared'});
  assert.equal(page.mintVerification, 'not_checked'); assert.equal(page.providerFreshness, 'not_verified');
  assert.equal(page.executionEnabled, false); assert.equal(page.completeCatalog, false);
  data.results.length = 0; assert.equal(page.results[0]!.assetId, 'apple');
  assert.throws(() => (page.results as unknown[]).push({}), TypeError);
  assert.throws(() => Object.assign(row.market!.providerTimestamps, {asOf: 0}), TypeError);
});

test('future advisory status stays unknown and visible alongside omitted siblings', () => {
  const data = searchFixture(), asset = data.results[0]!;
  const flag = {status: 'future_restriction', providerStatus: 'future_restriction', reason: 'New provider restriction.', since: '2026-09-14T17:00:00.000Z'};
  asset.variants[0]!.advisory = {...flag};
  asset.advisories = [{...flag, mint: RESEARCH_AAPLX_MINT, variantId: 'apple-xstock'}, {...flag, mint: RESEARCH_USDC_MINT, variantId: 'omitted-sibling'}];
  const parsed = parseStockSearchPage(data).results[0]!;
  assert.equal(parsed.variants[0]!.advisory!.status, 'unknown'); assert.equal(parsed.variants[0]!.advisory!.wireStatus, 'future_restriction');
  assert.equal(parsed.advisories[1]!.variantId, 'omitted-sibling');
  asset.advisories[0] = {...flag, mint: RESEARCH_AAPLX_MINT, variantId: 'wrong-id'};
  assert.throws(() => parseStockSearchPage(data), {code: 'STOCK_RESPONSE_INVALID'});
});

test('malformed claims, duplicate identities and missing or unsafe data cannot become a catalog', () => {
  for (const data of [{...searchFixture(), executionEnabled: true}, {...searchFixture(), eligibility: 'approved'},
    {...searchFixture(), completeCatalog: true}, {...searchFixture(), observedAt: '2026-02-30T18:00:00.000Z'},
    {...searchFixture(), refreshAfter: '2026-09-15T18:00:00.000Z'}, {...searchFixture(), sourceUrl: 'https://secret@example.com'},
    {...searchFixture(), results: new Array(1)}, Object.assign(Object.create({inherited: true}), searchFixture())]) {
    assert.throws(() => parseStockSearchPage(data), {code: 'STOCK_RESPONSE_INVALID'});
  }
  const duplicate = variantsFixture(); duplicate.variants.push(variantFixture());
  assert.throws(() => parseStockVariantsPage(duplicate), {code: 'STOCK_RESPONSE_INVALID'});
  const wrongPrimary = searchFixture(); wrongPrimary.results[0]!.providerPrimaryVariantMint = RESEARCH_USDC_MINT;
  assert.throws(() => parseStockSearchPage(wrongPrimary), {code: 'STOCK_RESPONSE_INVALID'});
  let invoked = false;
  const getter = searchFixture(); Object.defineProperty(getter, 'results', {get() { invoked = true; return []; }});
  assert.throws(() => parseStockSearchPage(getter), {code: 'STOCK_RESPONSE_INVALID'}); assert.equal(invoked, false);
});

test('estimate raw strings preserve u64 precision without representing displayed shares', () => {
  for (const side of ['buy', 'sell'] as const) {
    const result = parseStockEstimate(estimateFixture(side));
    assert.equal(result.output.estimatedAmountRaw, '18446744073709551615'); assert.equal(result.output.quotedMinimumAmountRaw, '18446744073709551614');
    assert.equal(result.amountUnits, 'raw_token_units'); assert.equal(result.executionEnabled, false); assert.equal(result.networkFees, null);
    assert.throws(() => Object.assign(result.output, {estimatedAmountRaw: '1'}), TypeError);
  }
  assert.equal(formatRawTokenUnits('18446744073709551615', 8), '184467440737.09551615');
  assert.equal(formatRawTokenUnits('1', 8), '0.00000001');
});

test('estimate validates pair identity, bounds, thresholds and freshness rather than trusting labels', () => {
  for (const raw of ['0', '01', '-1', '1e3', '100\n', '100000001', '18446744073709551616']) {
    assert.throws(() => parseStockEstimateRequest({...buy, amountRaw: raw}), {code: 'MARKET_INPUT_INVALID'});
  }
  for (const raw of [100, 1.5, '01', '100000001']) {
    const data = estimateFixture(); Object.assign(data.input, {amountRaw: raw});
    assert.throws(() => parseStockEstimate(data), {code: 'STOCK_RESPONSE_INVALID'});
  }
  const low = estimateFixture(); low.output.quotedMinimumAmountRaw = '1';
  const badDecimals = estimateFixture(); badDecimals.output.decimals = 6;
  for (const data of [low, badDecimals, {...estimateFixture(), refreshAfter: '2026-09-15T18:00:00.000Z'}, {...estimateFixture(), executable: true}]) {
    assert.throws(() => parseStockEstimate(data), {code: 'STOCK_RESPONSE_INVALID'});
  }
});

test('future schema and unmodeled token extensions are rejected, not silently dropped', () => {
  assert.throws(() => parseStockEstimate({...estimateFixture(), schemaVersion: 2}), {code: 'STOCK_UNSUPPORTED_SCHEMA'});
  assert.throws(() => parseStockEstimate({...estimateFixture(), extensions: [{kind: 'FutureRestriction'}]}), {code: 'STOCK_RESPONSE_INVALID'});
  const variants = variantsFixture(); Object.assign(variants.variants[0]!, {extensions: ['UnknownTransferPolicy']});
  assert.throws(() => parseStockVariantsPage(variants), {code: 'STOCK_RESPONSE_INVALID'});
});

test('frozen real backend buy and sell responses match mobile contract and are stale', () => {
  const fixture = JSON.parse(readFileSync(new URL('../../../mobile/test/support/stock_estimates_2026_09_14.json', import.meta.url), 'utf8'));
  const buy = parseStockEstimate(fixture.buy), sell = parseStockEstimate(fixture.sell);
  assert.equal(buy.output.estimatedAmountRaw, sell.input.amountRaw); assert.equal(buy.output.estimatedAmountRaw, '2972350');
  assert.equal(sell.output.estimatedAmountRaw, '9967990');
  for (const result of [buy, sell]) { assert.equal(researchNeedsRefresh(result, Date.parse('2026-09-15T00:00:00Z')), true); assert.equal(result.executable, false); }
  assert.equal(researchNeedsRefresh({refreshAfter: 'invalid'}, Date.now()), true);
});
