import {RESEARCH_AAPLX_MINT, RESEARCH_USDC_MINT} from './estimate.js';
export const provenance = () => ({schemaVersion: 1, provider: 'tokens-xyz-v1', sourceUrl: 'https://api.tokens.xyz/v1/assets/search?q=Apple',
  requestedAt: '2026-09-14T18:00:00.000Z', observedAt: '2026-09-14T18:00:01.000Z', refreshAfter: '2026-09-14T18:01:00.000Z',
  providerAsOf: null, providerFreshness: 'not_verified', executionEnabled: false, eligibility: 'unverified', mintVerification: 'not_checked'});
export const variantFixture = () => ({variantId: 'apple-xstock', mint: RESEARCH_AAPLX_MINT, chain: 'solana', kind: 'xstock',
  issuer: 'Backed', label: 'Apple xStock', name: 'Apple xStock', symbol: 'AAPLx', providerRedemptionTier: 'provider_description_only', advisory: null as unknown,
  market: {displayOnly: true, priceUsd: 200.5, liquidityUsd: 100000, volume24hUsd: 15000, decimals: 8, source: 'provider', metricsSource: null,
    providerTimestamps: {asOf: 1789400000, lastFetchedAt: 1789400000000, lastTradeAt: null, unit: 'not_declared'}}});
export const searchFixture = (query = 'Apple', limit = 10) => ({...provenance(), query, limit, completeCatalog: false,
  results: [{assetId: 'apple', name: 'Apple', symbol: 'AAPL', category: 'equity', providerPrimaryVariantMint: RESEARCH_AAPLX_MINT,
    variants: [variantFixture()], advisories: [] as unknown[]}]});
export const variantsFixture = (assetId = 'apple') => ({...provenance(), assetId, variants: [variantFixture()]});
export const estimateFixture = (side: 'buy' | 'sell' = 'buy', amountRaw = '10000000') => {
  const buy = side === 'buy';
  return {schemaVersion: 1, kind: 'indicative', network: 'solana:mainnet-beta', provider: 'jupiter-swap-v2', executable: false, walletChecked: false, networkFees: null,
    input: {symbol: buy ? 'USDC' : 'AAPLx', mint: buy ? RESEARCH_USDC_MINT : RESEARCH_AAPLX_MINT, decimals: buy ? 6 : 8, amountRaw},
    output: {symbol: buy ? 'AAPLx' : 'USDC', mint: buy ? RESEARCH_AAPLX_MINT : RESEARCH_USDC_MINT, decimals: buy ? 8 : 6,
      estimatedAmountRaw: '18446744073709551615', quotedMinimumAmountRaw: '18446744073709551614'},
    slippageBps: 50, swapFee: {basisPoints: 0, mint: RESEARCH_USDC_MINT}, router: 'metis',
    requestedAt: '2026-09-14T18:00:00.000Z', receivedAt: '2026-09-14T18:00:01.000Z', refreshAfter: '2026-09-14T18:00:10.000Z', providerExpiresAt: null,
    assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, side, executionEnabled: false, eligibility: 'unverified', amountUnits: 'raw_token_units'};
};
