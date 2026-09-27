import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {amountRaw, formatRawUnits, groupedDecimal, percentFromBps, rawDecimal, ShareScale, signedLamports, usdcDollars} from '../src/product/money/amounts.js';
import {parseTradingCapabilities, type DiscoveryVariantRef} from '../src/product/money/live-trading.js';
import {base58Decode, base58Encode, base64ToBytes, bytesToBase64, checkSignedTransaction, MAX_SIGNED_TRANSACTION_BASE64,
  parseTransaction, planSigning, TransactionCheckError} from '../src/product/money/solana-wire.js';
import {parseHoldings} from '../src/product/money/wallet-models.js';
import {explorerUrl, LiveOrderError, parseLiveOrder, parseTradeHistory} from '../src/product/money/live-order-client.js';
import {ACCOUNT_ID, AAPLX, ONDO_AAPL as ONDO, holdingsJson, message, orderJson, signer, signSlot, stockHolding, unsigned} from './support/money-fixtures.js';

const fixture = (name: string) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8')) as Record<string, unknown>;
const capabilities = () => parseTradingCapabilities(fixture('trading-capabilities-v2-2026-09-27.json'));
const discovery = (name: string): DiscoveryVariantRef[] => (fixture(name)['variants'] as {mint: string; issuer: string | null; label: string | null; symbol: string | null; market: {liquidityUsd: number | null} | null}[])
  .map(variant => ({mint: variant.mint, issuer: variant.issuer, label: variant.label, symbol: variant.symbol, liquidityUsd: variant.market?.liquidityUsd ?? null}));

test('recorded capabilities v2 list every tradeable token, issuer and refusal from the API', () => {
  const caps = capabilities();
  assert.equal(caps.schemaVersion, 2); assert.equal(caps.enabled, true);
  assert.equal(caps.assets.length, 60); assert.equal(caps.issuers.size, 5); assert.equal(caps.unavailable.size, 447);
  assert.equal(caps.tradeableAssets.length, 60);
  assert.equal(caps.issuers.get('xstocks')?.attestation.version, '2026-09-27');
  assert.match(caps.issuers.get('prestocks')?.warning ?? '', /void/);
  assert.equal(caps.issuers.get('ondo')?.route, 'rfq');
  assert.deepEqual(caps.assets.filter(asset => asset.transferFeeBps > 0).map(asset => asset.transferFeeBps), [300, 300, 300, 300]);
  // No hard-coded list: a new token in the response becomes tradeable without a code change.
  const raw = fixture('trading-capabilities-v2-2026-09-27.json') as {assets: Record<string, unknown>[]};
  const grown = parseTradingCapabilities({...raw, assets: [...raw.assets, {...raw.assets[0], assetId: 'newco', mint: 'NewCo1111111111111111111111111111111111111', symbol: 'NEWx', name: 'NewCo xStock'}]});
  assert.equal(grown.assets.length, 61); assert.equal(grown.companyTradeable('newco'), true);
});

test('SpaceX shows every Market version: two tradeable issuers first, the rest with honest reasons', () => {
  const caps = capabilities(), options = caps.optionsFor('spacex', discovery('market-variants-spacex-2026-09-27.json'), 'SPCX');
  assert.deepEqual(options.map(option => [option.label, option.tradeable]), [
    ['xStocks · SPCXx', true], ['Backpack · SPCX', true], ['Tessera · TSPX', false], ['PreStocks · SPACEX', false], ['Ondo · SPCXon', false]]);
  assert.equal(options[2]?.reason, 'Its price is too far from the real share price.');
  assert.equal(options[4]?.reason, 'Trades only while US markets are open.');
  assert.equal(caps.variantsFor('spacex', discovery('market-variants-spacex-2026-09-27.json'))[0]?.symbol, 'SPCXx', 'most liquid first');
  const apple = caps.optionsFor('apple', discovery('market-variants-apple-2026-09-27.json'), 'AAPL');
  assert.deepEqual(apple.map(option => option.tradeable), [true, false]);
  assert.equal(caps.companyTradeable('apple'), true);
  assert.equal(caps.companyTradeable('apple', [{mint: 'Other1111111111111111111111111111111111111'}]), false, 'discovery must list the same token');
});

test('capabilities read the nested disclosure shape, market state and offer status leniently but fail closed', () => {
  const raw = fixture('trading-capabilities-v2-2026-09-27.json') as {issuers: Record<string, unknown>[]; assets: Record<string, unknown>[]};
  const nested = raw.issuers.map(({issuerId, offered, notOfferedReason, route, ...disclosure}) =>
    ({issuerId, offered, notOfferedReason, route, disclosure: {issuerId, ...disclosure, attestation: {version: '2026-10-01', text: 'I accept.'}}}));
  const assets = raw.assets.map((asset, index) => index === 0 ? {...asset, market: {status: 'closed', nextOpenAt: new Date(Date.now() + 3_600_000).toISOString()}}
    : index === 1 ? {...asset, market: {status: 'halted-by-provider'}} : index === 2 ? {...asset, market: {status: 'open', session: 'regular'}} : asset);
  const caps = parseTradingCapabilities({...raw, issuers: nested, assets});
  assert.equal(caps.issuers.get('backpack')?.attestation.version, '2026-10-01');
  assert.equal(caps.tradeableNow(caps.assets[0]!), false); assert.match(caps.reasonFor(caps.assets[0]!.mint), /US markets are open\. Opens/);
  assert.equal(caps.assets[1]!.market?.status, 'unknown'); assert.equal(caps.tradeableNow(caps.assets[1]!), false, 'unknown status never trades');
  assert.equal(caps.tradeableNow(caps.assets[2]!), true);
  const withdrawn = parseTradingCapabilities({...raw, issuers: raw.issuers.map(issuer => issuer['issuerId'] === 'prestocks'
    ? {...issuer, offered: false, notOfferedReason: 'PreStocks is paused for review.'} : issuer)});
  const pre = withdrawn.assets.find(asset => asset.issuerId === 'prestocks')!;
  assert.equal(withdrawn.tradeableNow(pre), false); assert.equal(withdrawn.reasonFor(pre.mint), 'PreStocks is paused for review.');
  assert.equal(withdrawn.tradeableAssets.some(asset => asset.issuerId === 'prestocks'), false);
  const paused = parseTradingCapabilities({...raw, enabled: false});
  assert.equal(paused.tradeableNow(paused.assets[0]!), false); assert.equal(paused.companyTradeable('apple'), false);
  for (const broken of [{...raw, network: 'solana:devnet'}, {...raw, schemaVersion: 3},
    {...raw, assets: [...raw.assets, raw.assets[0]]}, {...raw, assets: [{...raw.assets[0], issuerId: 'unknown'}]},
    {...raw, issuers: [{...raw.issuers[0], termsUrl: 'http://example.com/terms'}]}]) {
    assert.throws(() => parseTradingCapabilities(broken));
  }
  const legacy = parseTradingCapabilities({enabled: true, network: 'solana:mainnet-beta', maxBuyUsdc: '100', minimumSolBalanceLamports: '5000',
    assets: [{assetId: 'apple', mint: AAPLX, symbol: 'AAPLx', name: 'Apple xStock', decimals: 8, maxBuyInputRaw: '100000000', maxSellInputRaw: '100000000'}]});
  assert.equal(legacy.legacy, true); assert.equal(legacy.issuerFor(legacy.assets[0]!).attestation.version, 'legacy');
});

test('amounts stay exact from typed text to raw units and back, with scaled shares', () => {
  assert.equal(amountRaw('5', 6), '5000000'); assert.equal(amountRaw('0.1234567', 6), null); assert.equal(amountRaw('0', 6), null);
  assert.equal(amountRaw('1e3', 6), null); assert.equal(amountRaw(' 12.50 ', 6), '12500000');
  assert.equal(formatRawUnits('1234567890', 6), '1,234.56789'); assert.equal(rawDecimal('1500000', 6), '1.5');
  assert.equal(usdcDollars('25009999'), '$25.00'); assert.equal(usdcDollars('1234567890000'), '$1,234,567.89');
  assert.equal(percentFromBps(300), '3%'); assert.equal(percentFromBps(20), '0.2%'); assert.equal(groupedDecimal('12345.6700'), '12,345.67');
  assert.deepEqual(signedLamports('-2039280'), {negative: true, lamports: '2039280'}); assert.equal(signedLamports('1.5'), null);
  const scale = ShareScale.fromMultiplier(8, '1.0009180758490996');
  assert.equal(scale.scaled, true); assert.equal(scale.approx(scale.raw('0.5')!), '0.5');
  assert.equal(ShareScale.fromMultiplier(8, 'garbage').scaled, false);
  const held = ShareScale.fromDisplay(8, '150000000', '1.5013771');
  assert.equal(held.label('150000000'), '1.501377'); assert.equal(held.exact('150000000'), '1.5013771');
  assert.equal(ShareScale.plain(6).label('1'), '0.000001', 'dust keeps full precision');
});

test('holdings v2 keep total and spendable apart and bind to the account and wallet', async () => {
  const wallet = (await signer()).address;
  const snapshot = parseHoldings(holdingsJson(wallet, {usdc: '30000000', usdcAvailable: '25000000',
    tokens: [stockHolding({amountRaw: '250000000', availableToTradeRaw: '150000000', accountCount: 2, accountTopology: 'associated_with_ancillary'})]}), ACCOUNT_ID);
  assert.equal(snapshot.usdc.amountRaw, '30000000'); assert.equal(snapshot.usdc.availableToTradeRaw, '25000000');
  assert.equal(snapshot.stockTokens[0]?.availableToTradeRaw, '150000000'); assert.equal(snapshot.walletAddress, wallet);
  const v1 = parseHoldings(holdingsJson(wallet, {version: 1}), ACCOUNT_ID);
  assert.equal(v1.usdc.availableToTradeRaw, '25000000'); assert.deepEqual(v1.stockTokens, []);
  assert.throws(() => parseHoldings(holdingsJson(wallet, {userId: '22222222-2222-4222-8222-222222222222'}), ACCOUNT_ID), /ACCOUNT_CHANGED/);
  assert.throws(() => parseHoldings(holdingsJson(wallet, {usdc: '1', usdcAvailable: '2'}), ACCOUNT_ID), /RESPONSE_INVALID/);
  assert.throws(() => parseHoldings(holdingsJson(wallet, {tokens: [stockHolding({accountTopology: 'ancillary_only'})]}), ACCOUNT_ID),
    /RESPONSE_INVALID/, 'tokens outside the canonical account are never spendable');
});

test('Solana wire checks accept exactly the reviewed transaction for one signer and for an RFQ taker slot', async () => {
  const user = await signer(), maker = await signer();
  assert.equal(base58Encode(base58Decode(user.address, 32)), user.address);
  for (const version of ['legacy', 0] as const) {
    const single = unsigned(message([user.address], {version}), 1);
    const plan = planSigning(bytesToBase64(single), user.address, 'aggregator');
    assert.equal(plan.slot, 0); assert.equal(parseTransaction(single).version, version);
    const signed = await checkSignedTransaction(plan, await signSlot(single, 0, user), user.address);
    assert.equal(parseTransaction(base64ToBytes(signed)).signatures[0]!.some(byte => byte !== 0), true);
  }
  const rfq = unsigned(message([maker.address, user.address], {version: 0}), 2);
  const plan = planSigning(bytesToBase64(rfq), user.address, 'rfq');
  assert.equal(plan.slot, 1);
  const signed = await checkSignedTransaction(plan, await signSlot(rfq, 1, user), user.address);
  const parsed = parseTransaction(base64ToBytes(signed));
  assert.equal(parsed.signatures[0]!.every(byte => byte === 0), true, 'the market maker slot stays empty');
  assert.ok(signed.length <= MAX_SIGNED_TRANSACTION_BASE64);
});

test('Solana wire checks refuse wrong signers, pre-signed slots, maker signatures, tampering and bad signatures', async () => {
  const user = await signer(), maker = await signer(), other = await signer();
  const rfq = unsigned(message([maker.address, user.address], {version: 0}), 2);
  const code = (run: () => unknown) => {try {run(); return null;} catch (error) {return (error as TransactionCheckError).code;}};
  assert.equal(code(() => planSigning(bytesToBase64(rfq), other.address, 'rfq')), 'WALLET_NOT_SIGNER');
  assert.equal(code(() => planSigning(bytesToBase64(rfq), user.address, 'aggregator')), 'ROUTE_MISMATCH');
  assert.equal(code(() => planSigning(bytesToBase64(unsigned(message([user.address, maker.address]), 2)), user.address, 'rfq')), 'ROUTE_MISMATCH',
    'the user is never the RFQ fee payer');
  const presigned = await signSlot(rfq, 0, maker);
  assert.equal(code(() => planSigning(bytesToBase64(presigned), user.address, 'rfq')), 'INVALID_TRANSACTION');
  assert.equal(code(() => planSigning(bytesToBase64(new Uint8Array(1300)), user.address, null)), 'INVALID_TRANSACTION');
  assert.equal(code(() => planSigning('not base64!', user.address, null)), 'INVALID_TRANSACTION');
  const plan = planSigning(bytesToBase64(rfq), user.address, 'rfq');
  const reject = (promise: Promise<unknown>) => assert.rejects(promise, (error: TransactionCheckError) => error.code === 'SIGNATURE_MISMATCH');
  await reject(checkSignedTransaction(plan, await signSlot(await signSlot(rfq, 1, user), 0, maker), user.address));
  await reject(checkSignedTransaction(plan, rfq, user.address));
  const tampered = await signSlot(rfq, 1, user); tampered[tampered.length - 1] = tampered.at(-1)! ^ 1;
  await reject(checkSignedTransaction(plan, tampered, user.address));
  await reject(checkSignedTransaction(plan, await signSlot(rfq, 1, other), user.address));
});

test('the web-signed RFQ and aggregator transactions pass the API’s own reviewed-signature verifier', async () => {
  // Read-only use of the API's contract code; the web never edits apps/api.
  const source = new URL('../../api/src/live-stock-orders.ts', import.meta.url).href;
  const {verifyReviewedSignature} = await import(source) as {verifyReviewedSignature(order: {wallet: string; unsignedTransaction: string}, signed: string): string};
  const user = await signer(), maker = await signer();
  for (const [bytes, route] of [[unsigned(message([user.address], {version: 0}), 1), 'aggregator'], [unsigned(message([maker.address, user.address], {version: 0}), 2), 'rfq']] as const) {
    const plan = planSigning(bytesToBase64(bytes), user.address, route);
    const signed = await checkSignedTransaction(plan, await signSlot(bytes, plan.slot, user), user.address);
    const order = {wallet: user.address, unsignedTransaction: bytesToBase64(bytes)};
    assert.match(verifyReviewedSignature(order, signed), /^[1-9A-HJ-NP-Za-km-z]{64,88}$/);
  }
});

test('live orders and history parse the API contract and reject shapes that could mislead a signature', async () => {
  const wallet = (await signer()).address;
  const order = parseLiveOrder(orderJson({wallet, transaction: 'AQID', route: 'rfq', terms: {takerLamportsReturnUpperBound: '2039280', simulatedTakerLamportsSpent: '-2034280'},
    reviewFlags: ['closes_existing_wrapped_sol', 'rfq_market_maker_fill']}));
  assert.equal(order.terms.route, 'rfq'); assert.equal(order.terms.takerLamportsReturnUpperBound, '2039280');
  assert.equal(order.terms.simulatedTakerLamportsSpent, '-2034280'); assert.equal(order.transaction, 'AQID');
  assert.throws(() => parseLiveOrder(orderJson({wallet})), LiveOrderError, 'a reviewed order must carry its transaction');
  assert.throws(() => parseLiveOrder(orderJson({wallet, transaction: 'AQID', terms: {inputMint: AAPLX}})), LiveOrderError);
  assert.equal(parseLiveOrder(orderJson({wallet, status: 'confirmed', signature: '5'.repeat(88), confirmedSlot: 9})).transaction, null);
  const row = {id: '55555555-5555-4555-8555-555555555555', wallet, status: 'pending', signature: '4'.repeat(88), createdAt: '2026-09-27T10:00:00.123456Z',
    updatedAt: '2026-09-27T10:00:01.123456Z', asset: {assetId: 'apple', mint: ONDO, symbol: 'AAPLon', name: 'Apple (Ondo)', decimals: 9, route: 'rfq'},
    terms: {side: 'buy', inputMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', outputMint: ONDO, inputAmountRaw: '5000000', quotedOutputAmountRaw: '19000000', minimumOutputAmountRaw: '18900000'},
    amountUnits: 'raw_token_units', amountsStatus: 'reviewed_quote'};
  const page = parseTradeHistory({schemaVersion: 1, network: 'solana:mainnet-beta', orders: [row], nextCursor: 'abc'});
  assert.equal(page.orders[0]?.rfq, true); assert.equal(explorerUrl(page.orders[0]!), `https://solscan.io/account/${wallet}`);
  assert.equal(explorerUrl({...page.orders[0]!, rfq: false}), `https://solscan.io/tx/${'4'.repeat(88)}`);
  assert.throws(() => parseTradeHistory({schemaVersion: 1, network: 'solana:mainnet-beta', orders: [row, row], nextCursor: null}));
  assert.throws(() => parseTradeHistory({schemaVersion: 1, network: 'solana:mainnet-beta', orders: [], nextCursor: 'abc'}));
});
