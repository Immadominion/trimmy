import assert from 'node:assert/strict';
import test from 'node:test';
import {parseRaydiumStockQuote, parseRaydiumStockQuoteRequest, parseStockHistoryPage, parseStockHistoryRequest,
  RESEARCH_AAPLX_MINT, RESEARCH_USDC_MINT} from './index.js';
import {FIXED_NOW, historyRequest, raydiumQuoteFixture, stockHistoryFixture} from './read-contracts.test-support.js';

const buy = {assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, side: 'buy', amountRaw: '10000000'} as const;

test('Raydium remains a deeply immutable comparison quote with disclosed fee units', () => {
  for (const side of ['buy', 'sell'] as const) {
    const raw = raydiumQuoteFixture(side), quote = parseRaydiumStockQuote(raw);
    assert.equal(quote.provider, 'raydium-trade-api'); assert.equal(quote.comparisonOnly, true);
    assert.equal(quote.executionEnabled, false); assert.equal(quote.executable, false); assert.equal(quote.eligibility, 'unverified');
    assert.equal(quote.route.hops[0]!.fee.rateUnit, 'provider_integer_unverified');
    assert.equal(quote.route.hops[0]!.fee.amountRaw, '0'); assert.equal(quote.networkFees, null);
    raw.route.hops.length = 0; assert.equal(quote.route.hops.length, 1);
    assert.throws(() => Object.assign(quote.route.hops[0]!.fee, {providerRateRaw: 1}), TypeError);
  }
});

test('Raydium binds the pinned pair, raw u64 amounts, threshold and route continuity', () => {
  for (const amountRaw of ['0', '01', '-1', '1e3', '100000001', '18446744073709551616']) {
    assert.throws(() => parseRaydiumStockQuoteRequest({...buy, amountRaw}), {code: 'MARKET_INPUT_INVALID'});
  }
  const twoHop = raydiumQuoteFixture();
  twoHop.route = {hopCount: 2, hops: [
    {poolId: 'ApniVWuZbZoruTAJdyJcLBA4AVw4DKGdV5fHxo6qrAZT', inputMint: RESEARCH_USDC_MINT,
      outputMint: 'So11111111111111111111111111111111111111112',
      fee: {amountRaw: '25', mint: RESEARCH_USDC_MINT, providerRateRaw: 25, rateUnit: 'provider_integer_unverified'}},
    {poolId: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA', inputMint: 'So11111111111111111111111111111111111111112',
      outputMint: RESEARCH_AAPLX_MINT,
      fee: {amountRaw: '0', mint: RESEARCH_AAPLX_MINT, providerRateRaw: 1, rateUnit: 'provider_integer_unverified'}},
  ]};
  assert.equal(parseRaydiumStockQuote(twoHop).route.hopCount, 2);

  const failures: unknown[] = [];
  const wrongPair = raydiumQuoteFixture(); wrongPair.output.mint = RESEARCH_USDC_MINT; failures.push(wrongPair);
  const low = raydiumQuoteFixture(); low.output.quotedMinimumAmountRaw = '1'; failures.push(low);
  const extra = raydiumQuoteFixture(); Object.assign(extra.route.hops[0]!, {transaction: 'forbidden'}); failures.push(extra);
  const badFeeUnit = raydiumQuoteFixture(); badFeeUnit.route.hops[0]!.fee.rateUnit = 'bps'; failures.push(badFeeUnit);
  const broken = structuredClone(twoHop); broken.route.hops[1]!.inputMint = RESEARCH_USDC_MINT; failures.push(broken);
  const duplicate = structuredClone(twoHop); duplicate.route.hops[1]!.poolId = duplicate.route.hops[0]!.poolId; failures.push(duplicate);
  const tooMany = raydiumQuoteFixture(); tooMany.route.hopCount = 5; tooMany.route.hops = new Array(5).fill(tooMany.route.hops[0]); failures.push(tooMany);
  const badActual = raydiumQuoteFixture(); badActual.input.providerActualAmountRaw = '10000001'; failures.push(badActual);
  const badImpact = raydiumQuoteFixture(); badImpact.priceImpactPct = Number.NaN; failures.push(badImpact);
  const staleShape = raydiumQuoteFixture(); staleShape.refreshAfter = '2026-09-14T18:00:11.000Z'; failures.push(staleShape);
  for (const failure of failures) assert.throws(() => parseRaydiumStockQuote(failure), {code: 'STOCK_RESPONSE_INVALID'});
});

test('mint history preserves exact number strings and refuses canonical or execution claims', () => {
  const raw = stockHistoryFixture(), page = parseStockHistoryPage(raw, historyRequest);
  assert.equal(page.historyKind, 'solana_mint_variant'); assert.equal(page.canonicalEquityHistory, false);
  assert.equal(page.candles[0]!.openRaw, '2.005e2'); assert.equal(page.candles[1]!.volumeRaw, '0');
  assert.equal(page.priceUnit, 'provider_not_declared'); assert.equal(page.provenance.providerFreshness, 'not_reported');
  assert.equal(page.executionEnabled, false); assert.equal(page.eligibility, 'unverified');
  raw.candles.length = 0; assert.equal(page.candles.length, 2);
  assert.throws(() => Object.assign(page.provenance, {providerAsOf: 'invented'}), TypeError);
});

test('long decimal and scientific history lexemes survive without binary-number conversion', () => {
  const raw = stockHistoryFixture();
  const exact = '1234567890123456789012345678901234567890.12345678901234567890e-50';
  Object.assign(raw.candles[0]!, {openRaw: exact, highRaw: exact, lowRaw: exact, closeRaw: exact,
    volumeRaw: '9.999999999999999999999999999999999999e+100'});
  const candle = parseStockHistoryPage(raw, historyRequest).candles[0]!;
  assert.equal(candle.openRaw, exact); assert.equal(candle.highRaw, exact);
  assert.equal(candle.volumeRaw, '9.999999999999999999999999999999999999e+100');
  for (const malformed of ['-0', '00', 'NaN', 'Infinity', '1e101', '0.0']) {
    const failure = stockHistoryFixture(); failure.candles[0]!.openRaw = malformed;
    assert.throws(() => parseStockHistoryPage(failure, historyRequest), {code: 'STOCK_HISTORY_RESPONSE_INVALID'});
  }
});

test('history requests are pinned and bounded before any HTTP read', () => {
  assert.deepEqual(parseStockHistoryRequest(historyRequest, Math.floor(FIXED_NOW / 1000)), historyRequest);
  const failures = [
    {...historyRequest, assetId: 'tesla'}, {...historyRequest, variantMint: RESEARCH_USDC_MINT},
    {...historyRequest, interval: '5m'}, {...historyRequest, fromUnixSeconds: '01789344000'},
    {...historyRequest, fromUnixSeconds: historyRequest.toUnixSeconds},
    {...historyRequest, toUnixSeconds: String(Number(historyRequest.fromUnixSeconds) + 3599)},
    {...historyRequest, toUnixSeconds: String(Number(historyRequest.fromUnixSeconds) + 31 * 86400 + 1)},
    {...historyRequest, wallet: 'must-not-send'},
  ];
  for (const failure of failures) assert.throws(() => parseStockHistoryRequest(failure, Math.floor(FIXED_NOW / 1000)),
    {code: 'STOCK_HISTORY_INPUT_INVALID'});
});

test('history enforces OHLC, range, UTC alignment, ordering, status and exact provenance', () => {
  const failures: unknown[] = [];
  const badHigh = stockHistoryFixture(); badHigh.candles[0]!.highRaw = '200'; failures.push(badHigh);
  const negative = stockHistoryFixture(); negative.candles[0]!.volumeRaw = '-1'; failures.push(negative);
  const number = stockHistoryFixture(); number.candles[0]!.openRaw = 200 as unknown as string; failures.push(number);
  const unaligned = stockHistoryFixture(); unaligned.candles[0]!.startUnixSeconds = '1789344001'; failures.push(unaligned);
  const descending = stockHistoryFixture(); descending.candles.reverse(); failures.push(descending);
  const duplicate = stockHistoryFixture(); duplicate.candles[1]!.startUnixSeconds = duplicate.candles[0]!.startUnixSeconds; failures.push(duplicate);
  const status = stockHistoryFixture(); status.dataStatus = 'empty_provider_cache_or_no_trades'; failures.push(status);
  const source = stockHistoryFixture(); source.provenance.sourceUrl = source.provenance.sourceUrl.replace('api.tokens.xyz', 'evil.example'); failures.push(source);
  const query = stockHistoryFixture(); query.provenance.sourceUrl += '&extra=1'; failures.push(query);
  const unit = stockHistoryFixture(); unit.priceUnit = 'USD'; failures.push(unit);
  const refresh = stockHistoryFixture(); refresh.provenance.refreshAfter = '2026-09-14T18:00:17.000Z'; failures.push(refresh);
  const canonical = stockHistoryFixture(); canonical.canonicalEquityHistory = true; failures.push(canonical);
  const extra = stockHistoryFixture(); Object.assign(extra.provenance, {providerName: 'invented'}); failures.push(extra);
  for (const failure of failures) assert.throws(() => parseStockHistoryPage(failure, historyRequest),
    {code: 'STOCK_HISTORY_RESPONSE_INVALID'});
});

test('empty history has one explicit ambiguous status and future schemas fail closed', () => {
  const empty = stockHistoryFixture(); empty.candles = []; empty.dataStatus = 'empty_provider_cache_or_no_trades';
  assert.equal(parseStockHistoryPage(empty, historyRequest).dataStatus, 'empty_provider_cache_or_no_trades');
  assert.throws(() => parseStockHistoryPage({...stockHistoryFixture(), schemaVersion: 2}, historyRequest),
    {code: 'STOCK_UNSUPPORTED_SCHEMA'});
  assert.throws(() => parseRaydiumStockQuote({...raydiumQuoteFixture(), schemaVersion: 2}),
    {code: 'STOCK_UNSUPPORTED_SCHEMA'});
  assert.throws(() => parseStockHistoryPage(stockHistoryFixture(), {...historyRequest, interval: '5m'} as never),
    {code: 'STOCK_HISTORY_RESPONSE_INVALID'});
});
