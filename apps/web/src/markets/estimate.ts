import {assetId, integer, invalid, mint, rawAmount, record, schema, text, timestamp, StockResearchError} from './validation.js';

export const RESEARCH_AAPLX_MINT = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
export const RESEARCH_USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
export interface StockEstimateRequest {
  readonly assetId: 'apple'; readonly variantMint: typeof RESEARCH_AAPLX_MINT;
  readonly side: 'buy' | 'sell'; readonly amountRaw: string;
}
export interface StockEstimate {
  readonly schemaVersion: 1; readonly kind: 'indicative'; readonly network: 'solana:mainnet-beta';
  readonly provider: 'jupiter-swap-v2'; readonly executable: false; readonly walletChecked: false; readonly networkFees: null;
  readonly input: Readonly<{symbol: 'USDC' | 'AAPLx'; mint: string; decimals: 6 | 8; amountRaw: string}>;
  readonly output: Readonly<{symbol: 'USDC' | 'AAPLx'; mint: string; decimals: 6 | 8; estimatedAmountRaw: string; quotedMinimumAmountRaw: string}>;
  readonly slippageBps: number; readonly swapFee: Readonly<{basisPoints: number; mint: string}>;
  readonly router: 'metis' | 'jupiterz' | 'dflow' | 'okx';
  readonly requestedAt: string; readonly receivedAt: string; readonly refreshAfter: string; readonly providerExpiresAt: string | null;
  readonly assetId: 'apple'; readonly variantMint: typeof RESEARCH_AAPLX_MINT; readonly side: 'buy' | 'sell';
  readonly executionEnabled: false; readonly eligibility: 'unverified'; readonly amountUnits: 'raw_token_units';
}
export function parseStockEstimateRequest(value: unknown): StockEstimateRequest {
  try {
    const data = record(value, ['assetId', 'variantMint', 'side', 'amountRaw']);
    if (data['assetId'] !== 'apple' || data['variantMint'] !== RESEARCH_AAPLX_MINT || (data['side'] !== 'buy' && data['side'] !== 'sell')) invalid();
    const amountRaw = rawAmount(data['amountRaw']); if (BigInt(amountRaw) > 100000000n) invalid();
    return Object.freeze({assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, side: data['side'], amountRaw});
  } catch { throw new StockResearchError('MARKET_INPUT_INVALID'); }
}
export function parseStockEstimate(value: unknown): StockEstimate {
  const data = record(value, ['schemaVersion', 'kind', 'network', 'provider', 'executable', 'walletChecked', 'networkFees',
    'input', 'output', 'slippageBps', 'swapFee', 'router', 'requestedAt', 'receivedAt', 'refreshAfter', 'providerExpiresAt',
    'assetId', 'variantMint', 'side', 'executionEnabled', 'eligibility', 'amountUnits']);
  schema(data['schemaVersion']);
  if (data['kind'] !== 'indicative' || data['network'] !== 'solana:mainnet-beta' || data['provider'] !== 'jupiter-swap-v2' ||
      data['executable'] !== false || data['walletChecked'] !== false || data['networkFees'] !== null ||
      data['executionEnabled'] !== false || data['eligibility'] !== 'unverified' || data['amountUnits'] !== 'raw_token_units') invalid();
  const input = record(data['input'], ['symbol', 'mint', 'decimals', 'amountRaw']);
  const output = record(data['output'], ['symbol', 'mint', 'decimals', 'estimatedAmountRaw', 'quotedMinimumAmountRaw']);
  const side = data['side']; if (side !== 'buy' && side !== 'sell') invalid();
  if (assetId(data['assetId']) !== 'apple' || data['variantMint'] !== RESEARCH_AAPLX_MINT) invalid();
  const amountRaw = rawAmount(input['amountRaw']); if (BigInt(amountRaw) > 100000000n) invalid();
  const buying = side === 'buy';
  const inputMint = buying ? RESEARCH_USDC_MINT : RESEARCH_AAPLX_MINT;
  const outputMint = buying ? RESEARCH_AAPLX_MINT : RESEARCH_USDC_MINT;
  const inputSymbol = buying ? 'USDC' : 'AAPLx'; const outputSymbol = buying ? 'AAPLx' : 'USDC';
  const inputDecimals = buying ? 6 : 8; const outputDecimals = buying ? 8 : 6;
  if (input['symbol'] !== inputSymbol || input['mint'] !== inputMint || input['decimals'] !== inputDecimals ||
      output['symbol'] !== outputSymbol || output['mint'] !== outputMint || output['decimals'] !== outputDecimals) invalid();
  const estimatedAmountRaw = rawAmount(output['estimatedAmountRaw']), quotedMinimumAmountRaw = rawAmount(output['quotedMinimumAmountRaw']);
  const slippageBps = integer(data['slippageBps'], 0, 10000);
  if (BigInt(quotedMinimumAmountRaw) > BigInt(estimatedAmountRaw) ||
      BigInt(quotedMinimumAmountRaw) < BigInt(estimatedAmountRaw) * BigInt(10000 - slippageBps) / 10000n) invalid();
  const fee = record(data['swapFee'], ['basisPoints', 'mint']); const feeMint = mint(fee['mint']);
  if (feeMint !== inputMint && feeMint !== outputMint) invalid();
  const router = text(data['router'], 40); if (!['metis', 'jupiterz', 'dflow', 'okx'].includes(router)) invalid();
  const requestedAt = timestamp(data['requestedAt']), receivedAt = timestamp(data['receivedAt']), refreshAfter = timestamp(data['refreshAfter']);
  const providerExpiresAt = data['providerExpiresAt'] === null ? null : timestamp(data['providerExpiresAt']);
  if (Date.parse(receivedAt) < Date.parse(requestedAt) || Date.parse(refreshAfter) <= Date.parse(receivedAt) ||
      Date.parse(refreshAfter) - Date.parse(requestedAt) > 10000 ||
      providerExpiresAt !== null && Date.parse(refreshAfter) > Date.parse(providerExpiresAt)) invalid();
  return Object.freeze({schemaVersion: 1, kind: 'indicative', network: 'solana:mainnet-beta', provider: 'jupiter-swap-v2',
    executable: false, walletChecked: false, networkFees: null,
    input: Object.freeze({symbol: inputSymbol, mint: inputMint, decimals: inputDecimals, amountRaw}),
    output: Object.freeze({symbol: outputSymbol, mint: outputMint, decimals: outputDecimals, estimatedAmountRaw, quotedMinimumAmountRaw}),
    slippageBps, swapFee: Object.freeze({basisPoints: integer(fee['basisPoints'], 0, 10000), mint: feeMint}), router: router as StockEstimate['router'],
    requestedAt, receivedAt, refreshAfter, providerExpiresAt, assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT,
    side, executionEnabled: false, eligibility: 'unverified', amountUnits: 'raw_token_units'});
}
