import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { STOCK_ISSUERS } from '../src/stock-issuers.js';
import { orderPriceAcceptable } from '../src/stock-order-price.js';
import { StockTokenDirectory, checkStockMint } from '../src/stock-token-directory.js';
import { findStockTradingAsset, findStockTradingAssetByMint, stockTradingAssets } from '../src/stock-trading-catalog.js';
import type { StockDiscovery } from '../src/stock-discovery.js';

const xstocks = STOCK_ISSUERS.xstocks.identity;
const ondo = STOCK_ISSUERS.ondo.identity;
// Fixture mints: valid base58, not real tokens.
const MINT_A = 'Xs1111111111111111111111111111111111111111';
const MINT_B = 'on11111111111111111111111111111111111111ondo'.slice(0, 44);
const MINT_C = 'Fake111111111111111111111111111111111111111';
const now = Date.parse('2026-09-28T10:00:00Z');

/** A mint as `getMultipleAccounts` returns it with jsonParsed encoding. */
function mintAccount(options: {identity?: typeof xstocks; symbol?: string; updateAuthority?: string; freeze?: string;
  feeBps?: number; transferHook?: string | null; owner?: string} = {}) {
  const identity = options.identity ?? xstocks;
  const extensions: unknown[] = [
    {extension: 'tokenMetadata', state: {updateAuthority: options.updateAuthority ?? identity.metadataUpdateAuthority,
      name: 'Example Stock', symbol: options.symbol ?? 'EXMx', uri: `${identity.metadataUriPrefixes[0]}EXMx.json`}},
  ];
  if (identity.permanentDelegate) extensions.push({extension: 'permanentDelegate', state: {delegate: identity.permanentDelegate}});
  if (options.feeBps) extensions.push({extension: 'transferFeeConfig', state: {newerTransferFee: {transferFeeBasisPoints: options.feeBps}}});
  if (options.transferHook !== undefined) extensions.push({extension: 'transferHook', state: {programId: options.transferHook}});
  return {owner: options.owner ?? 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb', executable: false, lamports: 1, data: {program: 'spl-token-2022',
    parsed: {type: 'mint', info: {decimals: identity.decimals, isInitialized: true, supply: '1',
      mintAuthority: identity.mintAuthority ?? 'Mint111111111111111111111111111111111111111',
      freezeAuthority: options.freeze ?? identity.freezeAuthorities[0], extensions}}}};
}

describe('order market price', () => {
  const base = {buying: true, inputRaw: '10000000', outputRaw: '100000000', decimals: 8, transferFeeBps: 0, swapFeeBps: 10,
    priceImpactPct: '0'} as const;
  it('accepts a price near the market and refuses one far worse, allowing the token fees', () => {
    // $10 for 1 token.
    assert.equal(orderPriceAcceptable({...base, referenceUsd: 10}), true);
    assert.equal(orderPriceAcceptable({...base, referenceUsd: 9.75}), true); // 2.6% worse
    assert.equal(orderPriceAcceptable({...base, referenceUsd: 9.5}), false); // 5.3% worse
    assert.equal(orderPriceAcceptable({...base, referenceUsd: 9.5, transferFeeBps: 300}), true);
    // A better price is always fine; for a sell, receiving less is worse.
    assert.equal(orderPriceAcceptable({...base, referenceUsd: 20}), true);
    assert.equal(orderPriceAcceptable({...base, buying: false, inputRaw: '100000000', outputRaw: '9000000', referenceUsd: 10}), false);
    assert.equal(orderPriceAcceptable({...base, buying: false, inputRaw: '100000000', outputRaw: '9800000', referenceUsd: 10}), true);
  });
  it('falls back to Jupiter price impact without a market price', () => {
    assert.equal(orderPriceAcceptable({...base, referenceUsd: null, priceImpactPct: '0.01'}), true);
    assert.equal(orderPriceAcceptable({...base, referenceUsd: null, priceImpactPct: '0.2'}), false);
    assert.equal(orderPriceAcceptable({...base, referenceUsd: null, priceImpactPct: undefined}), false);
    assert.equal(orderPriceAcceptable({...base, outputRaw: '0', referenceUsd: 10}), false);
  });
});

describe('automatic token identity', () => {
  const source = {assetId: 'example', slot: 1, now};
  it('accepts a mint carrying a supported issuer identity', () => {
    const result = checkStockMint(MINT_A, mintAccount(), source);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.identity.issuerId, 'xstocks');
    assert.equal(result.identity.symbol, 'EXMx');
    assert.equal(result.identity.route, xstocks.route);
    assert.equal(result.identity.maxBuyInputRaw, '100000000');
    const ondoToken = checkStockMint(MINT_B, mintAccount({identity: ondo, symbol: 'EXMon'}), source);
    assert.equal(ondoToken.ok && ondoToken.identity.route, 'rfq');
  });
  it('refuses unknown makers, copied keys that do not all match, and restrictive rules', () => {
    const reason = (value: unknown) => {
      const result = checkStockMint(MINT_C, value, source);
      return result.ok ? 'ok' : `${result.refused.reason}:${result.refused.detail}`;
    };
    assert.equal(reason(mintAccount({updateAuthority: 'Other111111111111111111111111111111111111111'})), 'identity_unverified:NO_ISSUER_FINGERPRINT');
    assert.equal(reason(mintAccount({freeze: 'Other111111111111111111111111111111111111111'})), 'identity_unverified:FREEZE_AUTHORITY');
    assert.equal(reason(mintAccount({owner: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'})), 'identity_unverified:TOKEN_PROGRAM');
    assert.equal(reason(mintAccount({symbol: 'USDC'})), 'identity_unverified:SYMBOL_FORMAT');
    assert.equal(reason(mintAccount({feeBps: 50})), 'token_restricted:TRANSFER_FEE_ABOVE_ISSUER_CAP');
    assert.equal(reason(mintAccount({transferHook: 'Hook111111111111111111111111111111111111111'})), 'token_restricted:TRANSFER_HOOK_PROGRAM');
    assert.equal(reason(null), 'identity_unverified:NO_ISSUER_FINGERPRINT');
    assert.equal(checkStockMint(MINT_C, mintAccount(), {...source, assetId: 'Not A Slug'}).ok, false);
  });
});

describe('token directory', () => {
  const page = (variants: {mint: string; assetId: string}[]) => ({
    discovery: {results: [...new Set(variants.map(item => item.assetId))].map(assetId => ({assetId, category: 'equity',
      variants: variants.filter(item => item.assetId === assetId).map(item => ({mint: item.mint}))}))},
    cards: [], offset: 0, total: variants.length, nextOffset: null,
  });
  function rpc(accounts: Record<string, unknown>) {
    let calls = 0;
    const fetch = (async (_url: string | URL, init?: {body?: string}) => {
      calls += 1;
      const request = JSON.parse(String(init?.body)) as {id: string; params: [string[]]};
      return Response.json({jsonrpc: '2.0', id: request.id, result: {context: {slot: 7}, value: request.params[0].map(mint => accounts[mint] ?? null)}});
    }) as unknown as typeof globalThis.fetch;
    return {fetch, calls: () => calls};
  }

  it('makes every listed token from a supported issuer tradeable and explains the rest', async () => {
    const listed = 'Dir1111111111111111111111111111111111111111';
    const stranger = 'Dir2111111111111111111111111111111111111111';
    const discovery = {search: async () => { throw new Error('unused'); }, variants: async () => { throw new Error('unused'); },
      catalog: async () => page([{mint: listed, assetId: 'directory-one'}, {mint: stranger, assetId: 'directory-two'}])} as unknown as StockDiscovery;
    const transport = rpc({[listed]: mintAccount({symbol: 'DIRx'}), [stranger]: mintAccount({updateAuthority: 'Other111111111111111111111111111111111111111'})});
    const directory = new StockTokenDirectory({rpcUrl: 'https://rpc.example', discovery, fetch: transport.fetch, now: () => now});
    await directory.refresh();
    assert.equal(findStockTradingAsset('directory-one', listed)?.symbol, 'DIRx');
    assert.ok(stockTradingAssets().some(asset => asset.mint === listed));
    assert.equal(findStockTradingAsset('directory-two', stranger), undefined);
    assert.deepEqual(directory.refusals().find(item => item.mint === stranger)?.reason, 'identity_unverified');
    // Known tokens are not read again.
    const calls = transport.calls();
    await directory.refresh();
    assert.equal(transport.calls(), calls);
  });

  it('checks a token the moment an order names it, only if the curated source lists it for that company', async () => {
    const fresh = 'Dir3111111111111111111111111111111111111111';
    const unlisted = 'Dir4111111111111111111111111111111111111111';
    const discovery = {search: async () => { throw new Error('unused'); },
      variants: async ({assetId}: {assetId: string}) => ({variants: assetId === 'directory-three' ? [{mint: fresh}] : []}),
      catalog: async () => page([])} as unknown as StockDiscovery;
    const transport = rpc({[fresh]: mintAccount({symbol: 'DIRTx'}), [unlisted]: mintAccount({symbol: 'DIRFx'})});
    const directory = new StockTokenDirectory({rpcUrl: 'https://rpc.example', discovery, fetch: transport.fetch, now: () => now});
    assert.equal((await directory.ensure('directory-three', fresh))?.symbol, 'DIRTx');
    // A lookalike carrying copied keys but not listed by the source never trades.
    assert.equal(await directory.ensure('directory-four', unlisted), undefined);
    assert.equal(findStockTradingAssetByMint(unlisted), undefined);
    // History can still show a past order's token, never as tradeable.
    await directory.recall([unlisted]);
    assert.equal(findStockTradingAssetByMint(unlisted)?.status, 'suspended');
    assert.equal(findStockTradingAsset('unlisted', unlisted), undefined);
  });
});
