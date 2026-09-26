/** Server-owned execution identities, checked against the xStocks issuer API and
 * finalized Solana mint accounts on 2026-09-25 (slot 450355321); MSTRx, CRCLx
 * and PLTRx were additionally verified on 2026-09-26 (slot 450695517).
 * Discovery metadata never adds an executable asset. Every order independently
 * re-reads mint/account state and must pass transaction reconciliation + simulation.
 * Sources: https://api.xstocks.fi/api/v2/public/assets/{symbol}
 * Verification: tool/testing/stock-trading-catalog.mjs --read-only
 */
export const STOCK_TOKEN_PROGRAM = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
const identities = [
  {assetId: 'apple', symbol: 'AAPLx', name: 'Apple xStock', mint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp'},
  {assetId: 'tesla', symbol: 'TSLAx', name: 'Tesla xStock', mint: 'XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB'},
  {assetId: 'nvidia', symbol: 'NVDAx', name: 'NVIDIA xStock', mint: 'Xsc9qvGR1efVDFGLrVsmkzv3qi45LTBjeUKSPmx9qEh'},
  {assetId: 'microsoft', symbol: 'MSFTx', name: 'Microsoft xStock', mint: 'XspzcW1PRtgf6Wj92HCiZdjzKCyFekVD8P5Ueh3dRMX'},
  {assetId: 'amazon', symbol: 'AMZNx', name: 'Amazon.com xStock', mint: 'Xs3eBt7uRfJX8QUs4suhyU8p2M6DoUDrJyWBa8LLZsg'},
  {assetId: 'alphabet', symbol: 'GOOGLx', name: 'Alphabet xStock', mint: 'XsCPL9dNWBMvFtTmwcCA5v3xWPSMEBCszbQdiLLq6aN'},
  {assetId: 'meta', symbol: 'METAx', name: 'Meta xStock', mint: 'Xsa62P5mvPszXL1krVUnU5ar38bBSVcWAB6fmPCo5Zu'},
  {assetId: 'coinbase', symbol: 'COINx', name: 'Coinbase xStock', mint: 'Xs7ZdzSHLU9ftNJsii5fCeJhoRWSC32SQGzGQtePxNu'},
  {assetId: 'robinhood', symbol: 'HOODx', name: 'Robinhood xStock', mint: 'XsvNBAYkrDRNhA7wPHQfX3ZUXZyZLdnCQDfHZ56bzpg'},
  {assetId: 'netflix', symbol: 'NFLXx', name: 'Netflix xStock', mint: 'XsEH7wWfJJu2ZT3UCFeVfALnVA6CP5ur7Ee11KmzVpL'},
  {assetId: 'amd', symbol: 'AMDx', name: 'AMD xStock', mint: 'XsXcJ6GZ9kVnjqGsjBnktRcuwMBmvKWh8S93RefZ1rF'},
  {assetId: 'microstrategy', symbol: 'MSTRx', name: 'MicroStrategy xStock', mint: 'XsP7xzNPvEHS1m6qfanPUGjNmdnmsLKEoNAnHjdxxyZ'},
  {assetId: 'circle', symbol: 'CRCLx', name: 'Circle xStock', mint: 'XsueG8BtpquVJX9LVLLEGuViXUungE6WmK5YZ3p3bd1'},
  {assetId: 'palantir', symbol: 'PLTRx', name: 'Palantir xStock', mint: 'XsoBhf2ufR8fTyNSjqfU71DYGaE6Z3SUGAidpzriAA4'},
] as const;
export const STOCK_TRADING_ASSETS = Object.freeze(identities.map(asset => Object.freeze({
  ...asset, decimals: 8 as const, tokenProgram: 'token_2022' as const,
  tokenProgramAddress: STOCK_TOKEN_PROGRAM, maxBuyInputRaw: '100000000', maxSellInputRaw: '100000000',
  issuerUrl: 'https://api.xstocks.fi/api/v2/public/assets/' + asset.symbol,
})));
export type StockTradingAsset = (typeof STOCK_TRADING_ASSETS)[number];
export type StockTradingAssetId = StockTradingAsset['assetId'];
export type StockTradingSymbol = StockTradingAsset['symbol'];
export function findStockTradingAsset(assetId: unknown, mint: unknown): StockTradingAsset | undefined {
  return STOCK_TRADING_ASSETS.find(asset => asset.assetId === assetId && asset.mint === mint);
}
export function findStockTradingAssetByMint(mint: unknown): StockTradingAsset | undefined {
  return STOCK_TRADING_ASSETS.find(asset => asset.mint === mint);
}
