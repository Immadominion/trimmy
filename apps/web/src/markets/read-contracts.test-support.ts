import {RESEARCH_AAPLX_MINT, RESEARCH_USDC_MINT} from './estimate.js';
import type {StockHistoryRequest} from './history.js';

export const FIXED_NOW = Date.parse('2026-09-14T18:00:02.000Z');
export const historyRequest = Object.freeze({assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, interval: '1H',
  fromUnixSeconds: '1789344000', toUnixSeconds: '1789351200'} as const satisfies StockHistoryRequest);

export const raydiumQuoteFixture = (side: 'buy' | 'sell' = 'buy', amountRaw = '10000000') => {
  const buying = side === 'buy';
  return {schemaVersion: 1, kind: 'indicative', comparisonOnly: true, network: 'solana:mainnet-beta',
    provider: 'raydium-trade-api', providerResponseVersion: 'V1', providerEndpoint: 'compute/swap-base-in',
    quoteMode: 'BaseIn', transactionVersionRequested: 'V0', assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT,
    side, executionEnabled: false, executable: false, eligibility: 'unverified', walletChecked: false,
    networkFees: null, amountUnits: 'raw_token_units',
    input: {symbol: buying ? 'USDC' : 'AAPLx', mint: buying ? RESEARCH_USDC_MINT : RESEARCH_AAPLX_MINT,
      decimals: buying ? 6 : 8, amountRaw, providerActualAmountRaw: amountRaw},
    output: {symbol: buying ? 'AAPLx' : 'USDC', mint: buying ? RESEARCH_AAPLX_MINT : RESEARCH_USDC_MINT,
      decimals: buying ? 8 : 6, estimatedAmountRaw: '2976495', quotedMinimumAmountRaw: '2961612'},
    slippageBps: 50, priceImpactPct: 0.0125, referralAmountRaw: '0',
    route: {hopCount: 1, hops: [{poolId: 'ApniVWuZbZoruTAJdyJcLBA4AVw4DKGdV5fHxo6qrAZT',
      inputMint: buying ? RESEARCH_USDC_MINT : RESEARCH_AAPLX_MINT,
      outputMint: buying ? RESEARCH_AAPLX_MINT : RESEARCH_USDC_MINT,
      fee: {amountRaw: '0', mint: buying ? RESEARCH_USDC_MINT : RESEARCH_AAPLX_MINT,
        providerRateRaw: 25, rateUnit: 'provider_integer_unverified'}}]},
    requestedAt: '2026-09-14T18:00:00.000Z', receivedAt: '2026-09-14T18:00:01.000Z',
    refreshAfter: '2026-09-14T18:00:10.000Z', providerExpiresAt: null};
};

export const stockHistoryFixture = () => ({schemaVersion: 1, provider: 'tokens-xyz-v1',
  providerContract: 'observed_not_execution_qualified', historyKind: 'solana_mint_variant',
  canonicalEquityHistory: false, assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, interval: '1H',
  fromUnixSeconds: historyRequest.fromUnixSeconds, toUnixSeconds: historyRequest.toUnixSeconds,
  candles: [
    {startUnixSeconds: '1789344000', openRaw: '2.005e2', highRaw: '201', lowRaw: '199.50',
      closeRaw: '200.75', volumeRaw: '1.25e3'},
    {startUnixSeconds: '1789347600', openRaw: '200.75', highRaw: '202', lowRaw: '2.0e2',
      closeRaw: '201.5', volumeRaw: '0'},
  ],
  dataStatus: 'observed', numericEncoding: 'exact_provider_json_number_lexemes',
  priceUnit: 'provider_not_declared', volumeUnit: 'provider_not_declared',
  provenance: {sourceUrl: `https://api.tokens.xyz/v1/assets/apple/ohlcv?mint=${RESEARCH_AAPLX_MINT}&interval=1H&from=1789344000&to=1789351200`,
    requestedAt: '2026-09-14T18:00:00.000Z', observedAt: '2026-09-14T18:00:01.000Z',
    providerAsOf: null, providerFreshness: 'not_reported', providerCandleSource: 'not_exposed',
    refreshAfter: '2026-09-14T18:00:16.000Z', cachedUpstreamData: true},
  executionEnabled: false, eligibility: 'unverified'});
