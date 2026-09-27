import assert from 'node:assert/strict';
import test from 'node:test';
import Fastify from 'fastify';
import {getAddressDecoder} from '@solana/kit';
import {generateKeyPairSync} from 'node:crypto';
import {LEGACY_STOCK_ISSUER, STOCK_ISSUERS, STOCK_ISSUER_IDS, acceptsIssuerTerms} from '../src/stock-issuers.js';
import {STOCK_TRADING_ASSETS} from '../src/stock-trading-catalog.js';
import type {StockTradingAsset} from '../src/stock-trading-catalog.js';
import {LiveStockOrders, PostgresLiveOrderStore, registerLiveStockRoutes, transferFeeWithinDisclosure} from '../src/live-stock-orders.js';
import type {LiveOrderStore, LiveStockAdapters} from '../src/live-stock-orders.js';
import type {ReviewedStockOrderIntent} from '../src/stock-order-review.js';
import type {Pool} from 'pg';

const wallet = getAddressDecoder().decode(
  generateKeyPairSync('ed25519').publicKey.export({type: 'spki', format: 'der'}).subarray(-32));
const current = (asset: StockTradingAsset) =>
  ({issuerId: asset.issuerId, version: STOCK_ISSUERS[asset.issuerId].disclosure.attestation.version});
const noStore: LiveOrderStore = {read: async () => null, create: async () => {throw Error('unexpected write');},
  begin: async () => {throw Error('unexpected dispatch');}, resolve: async () => {throw Error('unexpected write');}};

test('every issuer publishes a complete, plain disclosure and a dated attestation', () => {
  assert.deepEqual([...STOCK_ISSUER_IDS].sort(), ['backpack', 'ondo', 'prestocks', 'tessera', 'xstocks']);
  for (const id of STOCK_ISSUER_IDS) {
    const {disclosure, identity} = STOCK_ISSUERS[id];
    assert.ok(Object.isFrozen(disclosure) && Object.isFrozen(disclosure.attestation) && Object.isFrozen(identity));
    assert.equal(disclosure.issuerId, id);
    for (const text of [disclosure.name, disclosure.legalName, disclosure.productType, disclosure.summary,
      disclosure.holderRights, disclosure.warning, disclosure.attestation.text, ...disclosure.excludedRegions]) {
      assert.ok(typeof text === 'string' && text.trim() === text && text.length > 0 && text.length <= 400);
      // Product copy rule: no em or en dashes.
      assert.doesNotMatch(text, /[–—]/);
    }
    assert.ok(disclosure.excludedRegions.length > 0);
    assert.equal(new URL(disclosure.termsUrl).protocol, 'https:');
    assert.match(disclosure.attestation.version, /^\d{4}-\d{2}-\d{2}$/);
    for (const prefix of identity.metadataUriPrefixes) assert.equal(new URL(prefix).protocol, 'https:');
    assert.equal(identity.tokenProgram, 'token_2022');
    const offer = STOCK_ISSUERS[id].offer;
    assert.ok(Object.isFrozen(offer));
    if (offer.status === 'not_offered') {
      assert.ok(offer.reason.length > 20 && offer.reason.length <= 200);
      assert.doesNotMatch(offer.reason, /[\u2013\u2014]/);
    }
  }
  // Offer decisions recorded 2026-09-27 from the issuers' own terms (see stock-issuers.ts).
  assert.deepEqual(STOCK_ISSUER_IDS.filter(id => STOCK_ISSUERS[id].offer.status === 'offered').sort(), ['backpack', 'xstocks']);
});

test('terms acceptance must name the exact issuer and current version; only xStocks has a legacy path', () => {
  for (const id of STOCK_ISSUER_IDS) {
    const version = STOCK_ISSUERS[id].disclosure.attestation.version;
    assert.equal(acceptsIssuerTerms(id, undefined), id === LEGACY_STOCK_ISSUER);
    assert.equal(acceptsIssuerTerms(id, {issuerId: id, version}), true);
    assert.equal(acceptsIssuerTerms(id, {issuerId: id, version: '2000-01-01'}), false);
    for (const other of STOCK_ISSUER_IDS.filter(item => item !== id)) {
      assert.equal(acceptsIssuerTerms(id, {issuerId: other, version}), false);
    }
  }
});

test('preview refuses missing or stale terms before reading a wallet or provider', async () => {
  let reads = 0;
  const service = new LiveStockOrders({rpcUrl: 'https://rpc.example', store: noStore,
    fetch: async () => {reads++; throw Error('unexpected');}});
  for (const asset of STOCK_TRADING_ASSETS) {
    const input = {assetId: asset.assetId, variantMint: asset.mint, side: 'buy' as const, amountRaw: '1000000'};
    await assert.rejects(service.preview('user', wallet, {...input, termsAccepted: {issuerId: asset.issuerId, version: '2000-01-01'}}),
      {code: 'TERMS_REQUIRED'});
    const other = STOCK_ISSUER_IDS.find(id => id !== asset.issuerId)!;
    await assert.rejects(service.preview('user', wallet, {...input,
      termsAccepted: {issuerId: other, version: STOCK_ISSUERS[other].disclosure.attestation.version}}), {code: 'TERMS_REQUIRED'});
    if (asset.issuerId !== LEGACY_STOCK_ISSUER) await assert.rejects(service.preview('user', wallet, input), {code: 'TERMS_REQUIRED'});
  }
  assert.equal(reads, 0);
});

test('accepted terms (and the legacy xStocks request) proceed to the reviewed route request', async () => {
  const cases = [...STOCK_TRADING_ASSETS.map(asset => ({asset, terms: current(asset)})),
    ...STOCK_TRADING_ASSETS.filter(asset => asset.issuerId === LEGACY_STOCK_ISSUER).slice(0, 1).map(asset => ({asset, terms: undefined}))];
  for (const {asset, terms} of cases) {
    let orderRequests = 0;
    const fake = async (rawUrl: URL | RequestInfo, options?: RequestInit) => {
      if (new URL(String(rawUrl)).pathname.endsWith('/order')) {orderRequests++; return Response.json({error: 'Failed to get quotes'}, {status: 400});}
      const request = JSON.parse(String(options?.body));
      const result = request.method === 'getGenesisHash' ? '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d'
        : request.method === 'getBlockHeight' ? 100 : {context: {slot: 501}, value: 9_435_303};
      return Response.json({jsonrpc: '2.0', id: 1, result});
    };
    const service = new LiveStockOrders({rpcUrl: 'https://rpc.example', store: noStore, fetch: fake as typeof fetch});
    await assert.rejects(service.preview('user', wallet, {assetId: asset.assetId, variantMint: asset.mint, side: 'buy', amountRaw: '1000000',
      ...(terms ? {termsAccepted: terms} : {})}), {code: 'NO_ROUTE'});
    assert.equal(orderRequests, 1);
  }
});

test('preview HTTP boundary validates the terms field shape and reports TERMS_REQUIRED as a conflict', async () => {
  let reads = 0;
  const service = new LiveStockOrders({rpcUrl: 'https://rpc.example', store: noStore, fetch: async () => {reads++; throw Error('unexpected');}});
  const adapters = {authenticate: async () => ({userId: 'user', identity: {subject: 'did:privy:test'}}),
    identities: {resolveFresh: async () => ({subject: 'did:privy:test', embeddedSolanaWallet: {status: 'candidate', address: wallet}})}, service,
  } as unknown as LiveStockAdapters;
  // Production validation (app.ts) rejects unknown fields instead of stripping them.
  const app = Fastify({ajv: {customOptions: {removeAdditional: false, coerceTypes: false, useDefaults: false}}});
  registerLiveStockRoutes(app, adapters);
  try {
    const asset = STOCK_TRADING_ASSETS[0]!;
    const base = {assetId: asset.assetId, variantMint: asset.mint, side: 'buy', amountRaw: '1000000'};
    for (const termsAccepted of [{issuerId: 'nasdaq', version: '2026-09-27'}, {issuerId: asset.issuerId, version: 'latest'},
      {issuerId: asset.issuerId}, {...current(asset), extra: true}, 'yes']) {
      const response = await app.inject({method: 'POST', url: '/v1/trading/preview', payload: {...base, termsAccepted}});
      assert.equal(response.statusCode, 400);
    }
    const stale = await app.inject({method: 'POST', url: '/v1/trading/preview',
      payload: {...base, termsAccepted: {issuerId: asset.issuerId, version: '2000-01-01'}}});
    assert.equal(stale.statusCode, 409);
    assert.deepEqual(stale.json(), {code: 'TERMS_REQUIRED'});
    assert.equal(reads, 0);
  } finally {await app.close();}
});

test('the stored review records the acceptance without changing the reviewed intent', async () => {
  const queries: {sql: string; params: unknown[]}[] = [];
  const pool = {connect: async () => ({
    query: async (sql: string, params: unknown[] = []) => {queries.push({sql, params}); return {rows: [{value: {id: 'stored'}}]};},
    release: () => {},
  })} as unknown as Pool;
  const store = new PostgresLiveOrderStore(pool);
  const review = {userId: 'user', taker: wallet, reviewDigestSha256: 'a'.repeat(64), expiresAt: new Date().toISOString()} as unknown as ReviewedStockOrderIntent;
  const acceptance = Object.freeze({issuerId: 'ondo' as const, version: '2026-09-27', acceptedAt: '2026-09-27T10:00:00.000Z'});
  await store.create('user', 'id', wallet, review, new Uint8Array([1]), acceptance);
  const insert = queries.find(item => item.sql.includes('live_order_create'))!;
  assert.deepEqual(JSON.parse(String(insert.params[3])), {...review, termsAcceptance: acceptance});
  assert.equal((review as unknown as Record<string, unknown>)['termsAcceptance'], undefined);
});

test('a transfer fee raised above the admitted disclosure blocks new buys but never traps a seller', () => {
  for (const [fee, disclosed, buy] of [[null, 0, true], [20, 20, true], [300, 300, true], [301, 300, false], [300, 100, false], [1, 0, false]] as const) {
    assert.equal(transferFeeWithinDisclosure('buy', {transferFeeMaxBasisPoints: fee}, disclosed), buy);
    assert.equal(transferFeeWithinDisclosure('sell', {transferFeeMaxBasisPoints: fee}, disclosed), true);
  }
});
