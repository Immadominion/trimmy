import {integer, invalid, list, mint, rawAmount, record, schema, timestamp} from './validation.js';
import {parseStockEstimateRequest, RESEARCH_AAPLX_MINT, RESEARCH_USDC_MINT} from './estimate.js';
import type {StockEstimateRequest} from './estimate.js';

export type RaydiumStockQuoteRequest = StockEstimateRequest;

export interface RaydiumStockQuoteHop {
  readonly poolId: string;
  readonly inputMint: string;
  readonly outputMint: string;
  readonly fee: Readonly<{
    readonly amountRaw: string;
    readonly mint: string;
    /** Raydium's integer feeRate unit is not defined by the inspected public schema. */
    readonly providerRateRaw: number;
    readonly rateUnit: 'provider_integer_unverified';
  }>;
}

export interface RaydiumStockQuote {
  readonly schemaVersion: 1;
  readonly kind: 'indicative';
  readonly comparisonOnly: true;
  readonly network: 'solana:mainnet-beta';
  readonly provider: 'raydium-trade-api';
  readonly providerResponseVersion: 'V1';
  readonly providerEndpoint: 'compute/swap-base-in';
  readonly quoteMode: 'BaseIn';
  readonly transactionVersionRequested: 'V0';
  readonly assetId: 'apple';
  readonly variantMint: typeof RESEARCH_AAPLX_MINT;
  readonly side: 'buy' | 'sell';
  readonly executionEnabled: false;
  readonly executable: false;
  readonly eligibility: 'unverified';
  readonly walletChecked: false;
  readonly networkFees: null;
  readonly amountUnits: 'raw_token_units';
  readonly input: Readonly<{
    readonly symbol: 'USDC' | 'AAPLx';
    readonly mint: string;
    readonly decimals: 6 | 8;
    readonly amountRaw: string;
    readonly providerActualAmountRaw: string | null;
  }>;
  readonly output: Readonly<{
    readonly symbol: 'USDC' | 'AAPLx';
    readonly mint: string;
    readonly decimals: 6 | 8;
    readonly estimatedAmountRaw: string;
    readonly quotedMinimumAmountRaw: string;
  }>;
  readonly slippageBps: 50;
  readonly priceImpactPct: number;
  readonly referralAmountRaw: '0';
  readonly route: Readonly<{readonly hopCount: number; readonly hops: readonly RaydiumStockQuoteHop[]}>;
  readonly requestedAt: string;
  readonly receivedAt: string;
  readonly refreshAfter: string;
  readonly providerExpiresAt: null;
}

const zeroAddress = '11111111111111111111111111111111';
const quoteKeys = ['schemaVersion', 'kind', 'comparisonOnly', 'network', 'provider', 'providerResponseVersion',
  'providerEndpoint', 'quoteMode', 'transactionVersionRequested', 'assetId', 'variantMint', 'side',
  'executionEnabled', 'executable', 'eligibility', 'walletChecked', 'networkFees', 'amountUnits', 'input',
  'output', 'slippageBps', 'priceImpactPct', 'referralAmountRaw', 'route', 'requestedAt', 'receivedAt',
  'refreshAfter', 'providerExpiresAt'] as const;

export const parseRaydiumStockQuoteRequest = (value: unknown): RaydiumStockQuoteRequest =>
  parseStockEstimateRequest(value);

function nonnegativeRawAmount(value: unknown): string {
  if (value === '0') return value;
  return rawAmount(value);
}

function address(value: unknown): string {
  const result = mint(value);
  if (result === zeroAddress) invalid();
  return result;
}

function hop(value: unknown): RaydiumStockQuoteHop {
  const data = record(value, ['poolId', 'inputMint', 'outputMint', 'fee']);
  const fee = record(data['fee'], ['amountRaw', 'mint', 'providerRateRaw', 'rateUnit']);
  if (fee['rateUnit'] !== 'provider_integer_unverified') invalid();
  return Object.freeze({
    poolId: address(data['poolId']), inputMint: address(data['inputMint']), outputMint: address(data['outputMint']),
    fee: Object.freeze({amountRaw: nonnegativeRawAmount(fee['amountRaw']), mint: address(fee['mint']),
      providerRateRaw: integer(fee['providerRateRaw'], 0, 10_000), rateUnit: 'provider_integer_unverified'}),
  });
}

/** Strict projection of the read-only Raydium comparison response. */
export function parseRaydiumStockQuote(value: unknown): RaydiumStockQuote {
  const data = record(value, quoteKeys);
  schema(data['schemaVersion']);
  if (data['kind'] !== 'indicative' || data['comparisonOnly'] !== true || data['network'] !== 'solana:mainnet-beta' ||
      data['provider'] !== 'raydium-trade-api' || data['providerResponseVersion'] !== 'V1' ||
      data['providerEndpoint'] !== 'compute/swap-base-in' || data['quoteMode'] !== 'BaseIn' ||
      data['transactionVersionRequested'] !== 'V0' || data['assetId'] !== 'apple' ||
      data['variantMint'] !== RESEARCH_AAPLX_MINT || data['executionEnabled'] !== false ||
      data['executable'] !== false || data['eligibility'] !== 'unverified' || data['walletChecked'] !== false ||
      data['networkFees'] !== null || data['amountUnits'] !== 'raw_token_units' || data['slippageBps'] !== 50 ||
      data['referralAmountRaw'] !== '0' || data['providerExpiresAt'] !== null) invalid();

  const side = data['side'];
  if (side !== 'buy' && side !== 'sell') invalid();
  const buying = side === 'buy';
  const inputMint = buying ? RESEARCH_USDC_MINT : RESEARCH_AAPLX_MINT;
  const outputMint = buying ? RESEARCH_AAPLX_MINT : RESEARCH_USDC_MINT;
  const inputSymbol = buying ? 'USDC' : 'AAPLx';
  const outputSymbol = buying ? 'AAPLx' : 'USDC';
  const inputDecimals = buying ? 6 : 8;
  const outputDecimals = buying ? 8 : 6;

  const input = record(data['input'], ['symbol', 'mint', 'decimals', 'amountRaw', 'providerActualAmountRaw']);
  const output = record(data['output'], ['symbol', 'mint', 'decimals', 'estimatedAmountRaw', 'quotedMinimumAmountRaw']);
  if (input['symbol'] !== inputSymbol || input['mint'] !== inputMint || input['decimals'] !== inputDecimals ||
      output['symbol'] !== outputSymbol || output['mint'] !== outputMint || output['decimals'] !== outputDecimals) invalid();
  const amountRaw = rawAmount(input['amountRaw']);
  if (BigInt(amountRaw) > 100_000_000n) invalid();
  const providerActualAmountRaw = input['providerActualAmountRaw'] === null ? null : rawAmount(input['providerActualAmountRaw']);
  if (providerActualAmountRaw !== null && BigInt(providerActualAmountRaw) > BigInt(amountRaw)) invalid();
  const estimatedAmountRaw = rawAmount(output['estimatedAmountRaw']);
  const quotedMinimumAmountRaw = rawAmount(output['quotedMinimumAmountRaw']);
  if (BigInt(quotedMinimumAmountRaw) > BigInt(estimatedAmountRaw) ||
      BigInt(quotedMinimumAmountRaw) < BigInt(estimatedAmountRaw) * 9_950n / 10_000n) invalid();
  const priceImpactPct = data['priceImpactPct'];
  if (typeof priceImpactPct !== 'number' || !Number.isFinite(priceImpactPct) || priceImpactPct < 0 || priceImpactPct > 100) invalid();

  const route = record(data['route'], ['hopCount', 'hops']);
  const hops = list(route['hops'], 4, hop);
  if (hops.length < 1 || integer(route['hopCount'], 1, 4) !== hops.length) invalid();
  const pools = new Set<string>();
  const visitedMints = new Set<string>([inputMint]);
  let expectedInputMint = inputMint;
  for (const [index, current] of hops.entries()) {
    if (pools.has(current.poolId) || current.inputMint !== expectedInputMint || current.inputMint === current.outputMint ||
        visitedMints.has(current.outputMint) ||
        current.fee.mint !== current.inputMint && current.fee.mint !== current.outputMint ||
        index === 0 && current.fee.mint === current.inputMint && BigInt(current.fee.amountRaw) > BigInt(amountRaw)) invalid();
    pools.add(current.poolId); visitedMints.add(current.outputMint); expectedInputMint = current.outputMint;
  }
  if (expectedInputMint !== outputMint) invalid();

  const requestedAt = timestamp(data['requestedAt']);
  const receivedAt = timestamp(data['receivedAt']);
  const refreshAfter = timestamp(data['refreshAfter']);
  const requested = Date.parse(requestedAt), received = Date.parse(receivedAt), refresh = Date.parse(refreshAfter);
  if (received < requested || received >= requested + 10_000 || refresh !== requested + 10_000 || refresh <= received) invalid();

  return Object.freeze({schemaVersion: 1, kind: 'indicative', comparisonOnly: true, network: 'solana:mainnet-beta',
    provider: 'raydium-trade-api', providerResponseVersion: 'V1', providerEndpoint: 'compute/swap-base-in',
    quoteMode: 'BaseIn', transactionVersionRequested: 'V0', assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT,
    side, executionEnabled: false, executable: false, eligibility: 'unverified', walletChecked: false,
    networkFees: null, amountUnits: 'raw_token_units',
    input: Object.freeze({symbol: inputSymbol, mint: inputMint, decimals: inputDecimals, amountRaw, providerActualAmountRaw}),
    output: Object.freeze({symbol: outputSymbol, mint: outputMint, decimals: outputDecimals,
      estimatedAmountRaw, quotedMinimumAmountRaw}),
    slippageBps: 50, priceImpactPct, referralAmountRaw: '0',
    route: Object.freeze({hopCount: hops.length, hops}), requestedAt, receivedAt, refreshAfter, providerExpiresAt: null});
}
