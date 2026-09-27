/**
 * Read-only admission of tokenized stocks into the execution registry
 * (apps/api/src/stock-trading-registry.generated.ts). Never signs, submits or
 * persists an order: every Jupiter call is a GET quote/order request and every
 * RPC call is a read or an unsigned simulation (sigVerify false).
 *
 * A candidate is admitted only when ALL of these pass:
 *  1. identity: the finalized mint carries the issuer's pinned metadata update,
 *     mint, freeze and permanent-delegate authorities and metadata host, and the
 *     issuer's official source lists it (xStocks and Backpack by mint address,
 *     Ondo by symbol plus a clear pause status, PreStocks/Tessera by their
 *     pinned metadata document);
 *  2. mint policy: Token-2022, initialized default account state, not paused, no
 *     transfer hook program, not non-transferable, transfer fee within the issuer cap;
 *  3. market: Jupiter (metis) quotes a $2 buy, sells it back within the round-trip
 *     limit, quotes a $100 buy and a full sell cap without excessive price impact,
 *     and the quoted price is close to Jupiter's reference price and, where Jupiter
 *     reports one, to the underlying share price;
 *  4. review: the production preview pipeline (structure, lookup tables, lifetime,
 *     semantics, reconciliation and simulation) accepts an unsigned $1 buy and an
 *     unsigned ~$1 sell for real public wallets.
 * Existing registry entries are kept verbatim and in order; new ones are appended.
 * Issuers Trimmy does not offer (stock-issuers.ts) and held-back mints are never
 * quoted. Every other Market variant gets a refusal reason in
 * stock-market-attribution.generated.ts, which the app shows instead of a buy button.
 *
 * Usage (the buy taker is any public wallet holding at least 1 USDC and a little SOL;
 * sells use a large public holder found through Trimmy's holders read):
 *   npm run admit:stocks -- --buy-taker PUBLIC_WALLET [--write]
 *   node --import tsx tool/testing/stock-admission.mjs --read-only --buy-taker PUBLIC_WALLET
 *     [--issuers ondo,backpack,prestocks,tessera,xstocks] [--max N] [--write]
 * Without --write the registry file is restored after the run (dry run). --write
 * needs a full run (no --issuers or --max) because it regenerates the attribution.
 */
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {setTimeout as pause} from 'node:timers/promises';
import {randomUUID} from 'node:crypto';
import {address, getAddressEncoder, getProgramDerivedAddress} from '@solana/kit';

const REGISTRY_PATH = new URL('../../apps/api/src/stock-trading-registry.generated.ts', import.meta.url);
const ATTRIBUTION_PATH = new URL('../../apps/api/src/stock-market-attribution.generated.ts', import.meta.url);
/** Mints kept out regardless of checks, with the reason recorded in evidence. */
const HELD_BACK = Object.freeze({
  // Empty since 27 Sept 2026: Backpack's own API lists BABA with deposits and
  // withdrawals enabled, so the catalog's "not redeemable" label was not upheld.
});
const RPC_URL = 'https://api.mainnet-beta.solana.com';
const MAINNET_GENESIS = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
const USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const TOKEN_2022 = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
const ASSOCIATED_TOKEN_PROGRAM = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const SYSTEM_PROGRAM = '11111111111111111111111111111111';
const JUPITER_ORDER = 'https://api.jup.ag/swap/v2/order';
const LIMITS = Object.freeze({
  minimumCatalogLiquidityUsd: 25_000,
  /** Buy $2 then sell the proceeds: total loss (fees + spread) excluding issuer transfer fees. */
  maximumRoundTripLossBps: 250,
  /** Price at $100 (the per-order buy cap) versus at $2. */
  maximumBuyImpactBps: 150,
  /** Price when selling the full per-order sell cap versus the $2 price. */
  maximumSellCapImpactBps: 300,
  sellCapUsd: 250,
  /** Quoted price versus Jupiter's reference price for the same token. */
  maximumReferenceDeviationBps: 300,
  /** Quoted per-token price versus the underlying share price, where Jupiter reports one. */
  maximumUnderlyingDeviationBps: 1000,
});
const now = () => new Date();

// ---------- guarded read-only network access ----------
const allowedRpc = new Set(['getGenesisHash', 'getBlockHeight', 'getBalance', 'getMultipleAccounts', 'getAccountInfo',
  'isBlockhashValid', 'simulateTransaction']);
let lastJupiter = 0;
/** fetch for every provider call in this tool and in the preview child: read-only and rate-spaced. */
async function readOnlyFetch(url, options = {}) {
  const selected = new URL(String(url));
  if (selected.origin === 'https://lite-api.jup.ag') {
    if (selected.pathname !== '/price/v3' || (options.method ?? 'GET') !== 'GET') throw Error('SUBMISSION_FORBIDDEN');
  } else if (selected.origin === 'https://api.jup.ag') {
    if (selected.pathname !== '/swap/v2/order' || (options.method ?? 'GET') !== 'GET') throw Error('SUBMISSION_FORBIDDEN');
    const wait = lastJupiter + 2600 - Date.now();
    if (wait > 0) await pause(wait);
    lastJupiter = Date.now();
  } else if (selected.origin === new URL(RPC_URL).origin) {
    const body = JSON.parse(String(options.body));
    if (!allowedRpc.has(body.method)) throw Error('RPC_WRITE_FORBIDDEN');
    if (body.method === 'simulateTransaction' && body.params?.[1]?.sigVerify !== false) throw Error('RPC_WRITE_FORBIDDEN');
  } else if (!['https://api.xstocks.fi', 'https://api.backpack.exchange', 'https://app.ondo.finance', 'https://prestocks.com',
    'https://cdn.tesseralab.co', 'https://api-production-b3f8.up.railway.app'].includes(selected.origin)) {
    throw Error('UNKNOWN_PROVIDER ' + selected.origin);
  }
  for (let attempt = 0; ; attempt++) {
    const response = await fetch(url, options);
    if ((response.status === 429 || response.status >= 500) && attempt < 5) {
      await response.body?.cancel().catch(() => {});
      await pause(3000 * (attempt + 1));
      continue;
    }
    return response;
  }
}
async function getJson(url, limit = 8 * 1024 * 1024) {
  const response = await readOnlyFetch(url, {redirect: 'error', signal: AbortSignal.timeout(30000), headers: {accept: 'application/json'}});
  if (!response.ok) {
    const body = (await response.text().catch(() => '')).slice(0, 300);
    throw Object.assign(Error(`HTTP_${response.status} ${new URL(url).origin}`), {status: response.status, body});
  }
  const bytes = await response.arrayBuffer();
  if (bytes.byteLength > limit) throw Error('RESPONSE_TOO_LARGE');
  return JSON.parse(new TextDecoder().decode(bytes));
}
async function rpc(method, params = []) {
  const response = await readOnlyFetch(RPC_URL, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30000),
    headers: {'content-type': 'application/json'}, body: JSON.stringify({jsonrpc: '2.0', id: 1, method, params})});
  if (!response.ok) throw Error(`RPC_HTTP_${response.status}`);
  const result = await response.json();
  if (result.error) throw Error(`RPC_ERROR ${method} ${result.error.code}`);
  return result.result;
}
async function associatedAddress(owner, mint, tokenProgram = TOKEN_2022) {
  const encoder = getAddressEncoder();
  const [pda] = await getProgramDerivedAddress({programAddress: address(ASSOCIATED_TOKEN_PROGRAM),
    seeds: [encoder.encode(address(owner)), encoder.encode(address(tokenProgram)), encoder.encode(address(mint))]});
  return pda;
}

// ---------- child mode: run the real preview pipeline against a candidate registry ----------
if (process.argv[2] === '--simulate') {
  const [planPath, resultPath] = process.argv.slice(3);
  const {LiveStockOrders} = await import('../../apps/api/src/live-stock-orders.ts');
  const {STOCK_ISSUERS} = await import('../../apps/api/src/stock-issuers.ts');
  const {findStockTradingAsset} = await import('../../apps/api/src/stock-trading-catalog.ts');
  const plan = JSON.parse(await readFile(planPath, 'utf8'));
  const store = {
    read: async () => null,
    create: async (user, id, wallet, review) => ({id, user_id: user, wallet, review, unsignedTransaction: '',
      expires_at: review.expiresAt, status: 'reviewed', signature: null}),
    begin: async () => {throw Error('SUBMISSION_FORBIDDEN');},
    resolve: async () => {throw Error('PERSISTENCE_FORBIDDEN');},
  };
  const service = new LiveStockOrders({rpcUrl: RPC_URL, store, fetch: readOnlyFetch});
  const results = [];
  for (const item of plan) {
    const asset = findStockTradingAsset(item.assetId, item.mint);
    const started = Date.now();
    let result;
    // Jupiter picks routes per request and some routes fall outside the review, so a
    // refusal is retried later (and a sell with another public holder). Every
    // attempt is kept in the evidence; one fully reviewed attempt is required.
    const attempts = [];
    const takers = item.takers ?? [item.taker];
    for (let attempt = 0; attempt < 4 && result?.status !== 'reviewed'; attempt++) {
      if (attempt > 0) await pause(15000);
      const taker = takers[attempt % takers.length];
      try {
        if (!asset) throw Object.assign(Error('NOT_IN_CANDIDATE_REGISTRY'), {code: 'NOT_IN_CANDIDATE_REGISTRY'});
        const version = STOCK_ISSUERS[asset.issuerId].disclosure.attestation.version;
        const order = await service.preview(randomUUID(), taker, {assetId: item.assetId, variantMint: item.mint, side: item.side,
          amountRaw: item.amountRaw, termsAccepted: {issuerId: asset.issuerId, version}});
        result = {...item, taker, status: order.status, terms: order.review.terms, reviewFlags: order.review.reviewFlags,
          observationSlot: order.review.evidence.observationSlot, simulationSlot: order.review.evidence.simulationSlot};
      } catch (error) {
        result = {...item, taker, status: 'failed', code: error.code ?? error.message, failure: error.failure ?? null};
        if (!asset) break;
      }
      attempts.push({taker, status: result.status, code: result.code ?? null});
      // A closed market will not reopen within these retries.
      if (result.code === 'MARKET_CLOSED') break;
    }
    result.attempts = attempts;
    result.durationMs = Date.now() - started;
    results.push(result);
    console.log(JSON.stringify({symbol: item.symbol, side: item.side, status: result.status, code: result.code ?? null}));
    await pause(1500);
  }
  await writeFile(resultPath, JSON.stringify(results, null, 2) + '\n');
  process.exit(0);
}

// ---------- parent mode ----------
const args = process.argv.slice(2);
const flag = name => args.includes(name);
const option = name => {const index = args.indexOf(name); return index >= 0 ? args[index + 1] : undefined;};
if (!flag('--read-only') || !option('--buy-taker')) {
  throw Error('Use --read-only --buy-taker PUBLIC_WALLET [--issuers a,b] [--max N] [--write]. Nothing is signed or sent.');
}
const buyTaker = address(option('--buy-taker'));
const {STOCK_ISSUERS, STOCK_ISSUER_IDS} = await import('../../apps/api/src/stock-issuers.ts');
const {STOCK_TRADING_REGISTRY} = await import('../../apps/api/src/stock-trading-registry.generated.ts');
const issuerFilter = (option('--issuers') ?? STOCK_ISSUER_IDS.join(',')).split(',');
assert.ok(issuerFilter.every(id => STOCK_ISSUER_IDS.includes(id)), 'unknown issuer');
const maxCandidates = Number(option('--max') ?? 1000);
if (flag('--write') && (option('--issuers') !== undefined || option('--max') !== undefined)) {
  throw Error('--write regenerates the attribution for every Market variant; run without --issuers or --max.');
}
/** Recheck only these mints (for example earlier review refusals). With --write, new
 * admissions are appended and only these mints' attribution rows are replaced. */
const onlyMints = option('--only-mints')?.split(',') ?? null;
assert.ok(onlyMints === null || (onlyMints.length > 0 && onlyMints.every(mint => /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(mint))), 'bad --only-mints');
const apiBase = option('--api') ?? 'https://api-production-b3f8.up.railway.app';
const observedAt = now().toISOString();
const evidence = {observedAt, tool: 'stock-admission', signed: false, transactionBroadcast: false, persisted: false,
  limits: LIMITS, buyTaker, candidates: [], admitted: [], rejected: []};
/** Stable, user-facing refusal codes (stock-market-availability.ts). */
function attributionReason(stage, reason) {
  if (reason === 'ISSUER_NOT_OFFERED') return 'issuer_not_offered';
  if (reason === 'HELD_BACK') return 'held_back';
  if (/MARKET_CLOSED/.test(reason)) return 'market_closed';
  if (reason === 'NO_MARKET_MAKER_QUOTE') return 'no_market_maker_quote';
  if (['DEFAULT_FROZEN', 'PAUSED', 'TRANSFER_HOOK_PROGRAM', 'NON_TRANSFERABLE', 'TRANSFER_FEE_ABOVE_ISSUER_CAP',
    'ONDO_ASSET_PAUSED'].includes(reason)) return 'token_restricted';
  if (stage === 'identity' || stage === 'issuer_source') return 'identity_unverified';
  if (['LIQUIDITY_BELOW_FLOOR', 'ROUND_TRIP_LOSS', 'BUY_IMPACT', 'SELL_CAP_IMPACT', 'PRICE_UNAVAILABLE'].includes(reason)) return 'low_liquidity';
  if (['PRICE_REFERENCE_DEVIATION', 'PRICE_UNDERLYING_DEVIATION'].includes(reason)) return 'price_off_market';
  if (stage === 'registry') return 'not_reviewed';
  return 'no_reviewed_route';
}
const attribution = new Map();
const reject = (candidate, stage, reason, detail = null) => {
  evidence.rejected.push({mint: candidate.mint, symbol: candidate.symbol ?? null, issuerId: candidate.issuerId ?? null, stage, reason, detail});
  // The symbol lets the API match a token to its issuer's live status (Ondo's is keyed by symbol).
  attribution.set(candidate.mint, {mint: candidate.mint, issuerId: candidate.issuerId ?? null, reason: attributionReason(stage, reason),
    symbol: candidate.symbol ?? candidate.catalogSymbol ?? catalogSymbols.get(candidate.mint) ?? null});
  console.log(`reject ${candidate.symbol ?? candidate.mint} (${candidate.issuerId ?? '?'}): ${stage} ${reason}`);
};

assert.equal(await rpc('getGenesisHash'), MAINNET_GENESIS);

// 1. Candidates: every Market variant not already admitted, above the catalog liquidity floor.
const existingMints = new Set(STOCK_TRADING_REGISTRY.map(entry => entry.mint));
const existingSymbols = new Set(STOCK_TRADING_REGISTRY.map(entry => entry.symbol.toLowerCase()));
const rows = [];
// Schema 2 adds exchange-traded funds and commodities (SPY, QQQ, gold); an older
// server answers 400 to it and keeps the equities-only list.
let catalogSchema = '&schema=2';
for (let offset = 0; offset !== null && offset !== undefined;) {
  let page;
  try { page = await getJson(`${apiBase}/v1/markets/stocks/catalog?offset=${offset}${catalogSchema}`); }
  catch (error) {
    if (error.status !== 400 || !catalogSchema || offset !== 0) throw error;
    catalogSchema = '';
    continue;
  }
  rows.push(...page.discovery.results);
  offset = page.nextOffset;
}
const variants = new Map();
/** Every Market variant's symbol, including admitted and skipped ones. */
const catalogSymbols = new Map();
for (const row of rows) for (const variant of row.variants ?? []) {
  if (typeof variant.symbol === 'string' && /^[A-Za-z0-9.-]{1,32}$/.test(variant.symbol)) catalogSymbols.set(variant.mint, variant.symbol);
}
for (const row of rows) for (const variant of row.variants ?? []) {
  if (variants.has(variant.mint) || existingMints.has(variant.mint) || (onlyMints && !onlyMints.includes(variant.mint))) continue;
  variants.set(variant.mint, {assetId: row.assetId, companyName: row.name, mint: variant.mint,
    catalogSymbol: variant.symbol ?? null, liquidityUsd: variant.market?.liquidityUsd ?? 0,
    catalogPriceUsd: typeof variant.market?.priceUsd === 'number' ? variant.market.priceUsd : null});
}
console.log(`catalog: ${rows.length} companies, ${variants.size} unadmitted variants`);

// 2. Finalized mint state and pinned issuer identity.
const byUpdateAuthority = new Map(STOCK_ISSUER_IDS.map(id => [STOCK_ISSUERS[id].identity.metadataUpdateAuthority, id]));
const mints = [...variants.keys()];
const mintInfo = new Map();
let identitySlot = 0;
for (let index = 0; index < mints.length; index += 100) {
  const batch = mints.slice(index, index + 100);
  const result = await rpc('getMultipleAccounts', [batch, {encoding: 'jsonParsed', commitment: 'finalized'}]);
  identitySlot = Math.max(identitySlot, result.context.slot);
  batch.forEach((mint, position) => mintInfo.set(mint, result.value[position]));
  await pause(400);
}
const extensionMap = info => Object.fromEntries((info.extensions ?? []).map(item => [item.extension, item.state ?? {}]));
const candidates = [];
for (const variant of variants.values()) {
  const account = mintInfo.get(variant.mint);
  const info = account?.data?.parsed?.info;
  const ext = info ? extensionMap(info) : {};
  const metadata = ext.tokenMetadata ?? {};
  const issuerId = byUpdateAuthority.get(metadata.updateAuthority);
  const candidate = {...variant, issuerId, symbol: metadata.symbol, name: metadata.name, metadataUri: metadata.uri};
  if (!issuerId) {reject(candidate, 'identity', 'NO_ISSUER_FINGERPRINT'); continue;}
  if (!issuerFilter.includes(issuerId)) continue;
  const identity = STOCK_ISSUERS[issuerId].identity;
  const fee = ext.transferFeeConfig;
  const feeBps = fee ? Math.max(fee.newerTransferFee?.transferFeeBasisPoints ?? 0, fee.olderTransferFee?.transferFeeBasisPoints ?? 0) : 0;
  const checks = [
    [account?.owner === TOKEN_2022, 'TOKEN_PROGRAM'],
    [info?.isInitialized === true, 'NOT_INITIALIZED'],
    [info?.decimals === identity.decimals, 'DECIMALS'],
    [identity.mintAuthority === null || info?.mintAuthority === identity.mintAuthority, 'MINT_AUTHORITY'],
    [identity.freezeAuthorities.includes(info?.freezeAuthority), 'FREEZE_AUTHORITY'],
    [(ext.permanentDelegate?.delegate ?? null) === identity.permanentDelegate, 'PERMANENT_DELEGATE'],
    [typeof metadata.uri === 'string' && identity.metadataUriPrefixes.some(prefix => metadata.uri.startsWith(prefix)), 'METADATA_HOST'],
    [typeof metadata.symbol === 'string' && /^[A-Za-z0-9.]{1,32}$/.test(metadata.symbol), 'SYMBOL_FORMAT'],
    [typeof metadata.name === 'string' && metadata.name.trim().length > 0 && metadata.name.length <= 160 &&
      !/[\u0000-\u001f\u007f\u2028\u2029]/.test(metadata.name), 'NAME_FORMAT'],
    [!['sol', 'usdc'].includes(String(metadata.symbol).toLowerCase()), 'SYMBOL_RESERVED'],
    [/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(variant.assetId) && variant.assetId.length <= 100, 'ASSET_ID_FORMAT'],
    [!('defaultAccountState' in ext) || ext.defaultAccountState.accountState === 'initialized', 'DEFAULT_FROZEN'],
    [ext.pausableConfig?.paused !== true, 'PAUSED'],
    [!('transferHook' in ext) || ext.transferHook.programId === null, 'TRANSFER_HOOK_PROGRAM'],
    [!('nonTransferable' in ext), 'NON_TRANSFERABLE'],
    [feeBps <= identity.maxTransferFeeBps, 'TRANSFER_FEE_ABOVE_ISSUER_CAP'],
  ];
  const failed = checks.find(([ok]) => !ok);
  if (failed) {reject(candidate, 'identity', failed[1]); continue;}
  const scaled = ext.scaledUiAmountConfig;
  candidates.push({...candidate, decimals: info.decimals, transferFeeBps: feeBps,
    mintPolicy: {extensions: Object.keys(ext).sort(), mintAuthority: info.mintAuthority, freezeAuthority: info.freezeAuthority,
      permanentDelegate: ext.permanentDelegate?.delegate ?? null, transferFeeBps: feeBps,
      scaledUiMultiplier: scaled ? {multiplier: scaled.multiplier, newMultiplier: scaled.newMultiplier,
        newMultiplierEffectiveTimestamp: scaled.newMultiplierEffectiveTimestamp} : null}});
}
console.log(`identity: ${candidates.length} candidates with pinned issuer authorities`);

// 3. Official issuer sources.
const sources = {};
const official = [];
for (const candidate of candidates) {
  const registry = STOCK_ISSUERS[candidate.issuerId].identity.registry;
  try {
    if (registry.kind === 'xstocks_api') {
      const asset = await getJson(registry.url + encodeURIComponent(candidate.symbol), 512 * 1024);
      const deployments = (asset.deployments ?? []).filter(row => row.network === 'Solana');
      if (asset.symbol !== candidate.symbol || deployments.length !== 1 || deployments[0].address !== candidate.mint) {
        reject(candidate, 'issuer_source', 'XSTOCKS_API_MISMATCH'); continue;
      }
      candidate.issuerProof = {source: registry.url + candidate.symbol, symbol: asset.symbol};
    } else if (registry.kind === 'backpack_assets_api') {
      sources.backpack ??= await getJson(registry.url, 16 * 1024 * 1024);
      const match = sources.backpack.find(asset => (asset.tokens ?? []).some(token =>
        token.blockchain === 'Solana' && token.contractAddress === candidate.mint && token.nativeDecimals === candidate.decimals));
      if (!match) {reject(candidate, 'issuer_source', 'BACKPACK_API_MISSING'); continue;}
      // The disclosed way to redeem is depositing into a verified Backpack account.
      const token = match.tokens.find(item => item.contractAddress === candidate.mint);
      if (token.depositEnabled !== true) {reject(candidate, 'issuer_source', 'BACKPACK_DEPOSITS_DISABLED'); continue;}
      candidate.issuerProof = {source: registry.url, symbol: match.symbol};
    } else if (registry.kind === 'ondo_assets_api') {
      sources.ondo ??= await getJson(registry.url, 16 * 1024 * 1024);
      const match = (sources.ondo.assets ?? []).find(asset => asset.symbol === candidate.symbol);
      if (!match) {reject(candidate, 'issuer_source', 'ONDO_API_MISSING'); continue;}
      const pauseReason = match.assetTradingStatus?.assetPauseReason ?? null;
      if (pauseReason !== null) {reject(candidate, 'issuer_source', 'ONDO_ASSET_PAUSED', pauseReason); continue;}
      candidate.issuerProof = {source: registry.url, symbol: match.symbol, ticker: match.ticker};
      // Ondo's own session status: its market makers fill only while its market is open.
      const status = match.assetTradingStatus ?? {};
      candidate.issuerSession = {isMarketOpen: status.isMarketOpen === true, currentSession: status.currentSession ?? null,
        nextMarketOpen: status.nextMarketOpen ?? null, isOffhoursTradable: status.isOffhoursTradable === true};
    } else {
      const document = await getJson(candidate.metadataUri, 256 * 1024);
      if (document.symbol !== candidate.symbol) {reject(candidate, 'issuer_source', 'METADATA_SYMBOL_MISMATCH'); continue;}
      candidate.issuerProof = {source: candidate.metadataUri, symbol: document.symbol, name: document.name ?? null};
    }
  } catch (error) {
    reject(candidate, 'issuer_source', 'SOURCE_UNAVAILABLE', String(error.message).slice(0, 120)); continue;
  }
  official.push(candidate);
}
console.log(`issuer sources: ${official.length} confirmed`);

// Issuer policy and holds come before any market request.
const offered = [];
for (const candidate of official) {
  if (STOCK_ISSUERS[candidate.issuerId].offer.status !== 'offered') {reject(candidate, 'policy', 'ISSUER_NOT_OFFERED'); continue;}
  if (Object.hasOwn(HELD_BACK, candidate.mint)) {reject(candidate, 'policy', 'HELD_BACK', HELD_BACK[candidate.mint]); continue;}
  offered.push(candidate);
}
console.log(`policy: ${offered.length} candidates from offered issuers`);

// 4. Market quality through the route orders will use. Each token tries its
// issuer's route first, then the other one: Jupiter's aggregator (needs catalog
// liquidity above the floor) or JupiterZ market makers (RFQ). Makers quote many
// tokens only during US market hours, so their refusals are recorded as such.
function classifyQuoteFailure(text) {
  if (/market hours/i.test(text)) return 'MARKET_CLOSED';
  if (/market maker|failed to get quotes/i.test(text)) return 'NO_MARKET_MAKER_QUOTE';
  return 'NO_ROUTE';
}
async function quote(inputMint, outputMint, amount, route) {
  const query = new URLSearchParams({inputMint, outputMint, amount: String(amount), slippageBps: '50',
    excludeRouters: route === 'rfq' ? 'metis,dflow,okx' : 'jupiterz,dflow,okx'});
  const result = await getJson(`${JUPITER_ORDER}?${query}`, 512 * 1024).catch(error => {
    // Jupiter answers 400 when it has no route or no maker quote for the pair or size.
    throw error.status === 400 ? Object.assign(Error(classifyQuoteFailure(error.body ?? '')), {detail: error.body ?? 'HTTP_400'}) : error;
  });
  const expected = route === 'rfq' ? 'jupiterz' : 'metis';
  if (result.router !== expected || !/^[1-9][0-9]*$/.test(String(result.outAmount ?? ''))) {
    const text = String(result.errorMessage ?? result.error ?? '');
    throw Object.assign(Error(text ? classifyQuoteFailure(text) : 'NO_ROUTE'), {detail: text || result.router || null});
  }
  return {inAmount: String(amount), outAmount: String(result.outAmount), router: result.router, feeBps: result.feeBps ?? null};
}
const marketReady = [];
const prices = new Map();
for (let index = 0; index < offered.length; index += 50) {
  const ids = offered.slice(index, index + 50).map(candidate => candidate.mint);
  const page = await getJson(`https://lite-api.jup.ag/price/v3?ids=${ids.join(',')}`, 2 * 1024 * 1024);
  for (const id of ids) if (page[id]) prices.set(id, page[id]);
  await pause(1100);
}
/** Current scaled-UI multiplier from the finalized mint read (1 without the extension). */
function uiMultiplier(candidate) {
  const scaled = candidate.mintPolicy.scaledUiMultiplier;
  if (!scaled) return 1;
  const effective = Date.now() / 1000 >= Number(scaled.newMultiplierEffectiveTimestamp) ? Number(scaled.newMultiplier) : Number(scaled.multiplier);
  return effective > 0 ? effective : 1;
}
async function marketCheck(candidate, route) {
  const fail = (stage, reason, detail = null) => ({ok: false, route, stage, reason, detail});
  if (route === 'aggregator' && candidate.liquidityUsd < LIMITS.minimumCatalogLiquidityUsd) {
    return fail('catalog', 'LIQUIDITY_BELOW_FLOOR', candidate.liquidityUsd);
  }
  if (route === 'rfq' && candidate.issuerSession && !candidate.issuerSession.isMarketOpen) {
    return fail('market', 'MARKET_CLOSED', `issuer session ${candidate.issuerSession.currentSession}; next open ${candidate.issuerSession.nextMarketOpen}`);
  }
  try {
    const buy2 = await quote(USDC_MINT, candidate.mint, 2_000_000, route);
    const sellBack = await quote(candidate.mint, USDC_MINT, buy2.outAmount, route);
    const buy100 = await quote(USDC_MINT, candidate.mint, 100_000_000, route);
    const rawPerUsd = BigInt(buy2.outAmount) / 2n;
    const oneShare = 10n ** BigInt(candidate.decimals);
    const byValue = rawPerUsd * BigInt(LIMITS.sellCapUsd);
    const sellCapRaw = byValue > oneShare ? byValue : oneShare;
    const sellCap = await quote(candidate.mint, USDC_MINT, sellCapRaw, route);
    // Losses in basis points. Issuer transfer fees are charged on both legs and disclosed separately.
    const roundTripLossBps = Number(10_000n - BigInt(sellBack.outAmount) * 10_000n / 2_000_000n);
    const allowedRoundTrip = LIMITS.maximumRoundTripLossBps + 2 * candidate.transferFeeBps;
    const buyImpactBps = Number(10_000n - (BigInt(buy100.outAmount) * 2n * 10_000n) / (BigInt(buy2.outAmount) * 100n));
    const expectedSellUsdc = sellCapRaw * 1_000_000n / rawPerUsd;
    const sellCapImpactBps = Number(10_000n - BigInt(sellCap.outAmount) * 10_000n / expectedSellUsdc);
    const market = {route, buy2, sellBack, buy100, sellCap, roundTripLossBps, allowedRoundTripLossBps: allowedRoundTrip,
      buyImpactBps, sellCapImpactBps, sellCapRaw: sellCapRaw.toString(), rawPerUsd: rawPerUsd.toString()};
    if (roundTripLossBps > allowedRoundTrip) return fail('market', 'ROUND_TRIP_LOSS', roundTripLossBps);
    if (buyImpactBps > LIMITS.maximumBuyImpactBps) return fail('market', 'BUY_IMPACT', buyImpactBps);
    if (sellCapImpactBps > LIMITS.maximumSellCapImpactBps + 2 * candidate.transferFeeBps) return fail('market', 'SELL_CAP_IMPACT', sellCapImpactBps);
    // Fair price: the $2 quote per unscaled token against Jupiter's reference (or, when
    // Jupiter has none, the catalog price in either unit), and the per-display-token
    // price against the underlying share where Jupiter reports it. A transfer fee
    // lowers what arrives, so it widens the allowance by its own size.
    const quotedPrescaled = 2 / (Number(buy2.outAmount) / 10 ** candidate.decimals);
    const quotedDisplay = quotedPrescaled / uiMultiplier(candidate);
    const reference = prices.get(candidate.mint);
    const prescaled = reference?.scaledUiConfig?.usdPricePrescaled ?? reference?.usdPrice;
    let referenceDeviationBps;
    let referenceSource;
    if (prescaled > 0) {
      referenceDeviationBps = Math.round(Math.abs(quotedPrescaled / prescaled - 1) * 10_000);
      referenceSource = 'jupiter_price_v3';
    } else if (candidate.catalogPriceUsd > 0) {
      referenceDeviationBps = Math.round(Math.min(Math.abs(quotedPrescaled / candidate.catalogPriceUsd - 1),
        Math.abs(quotedDisplay / candidate.catalogPriceUsd - 1)) * 10_000);
      referenceSource = 'catalog_price';
    } else {
      return fail('market', 'PRICE_UNAVAILABLE');
    }
    const underlying = reference?.stockData?.price;
    const displayForUnderlying = reference?.usdPrice > 0 && prescaled > 0 ? quotedPrescaled * reference.usdPrice / prescaled : quotedDisplay;
    const underlyingDeviationBps = underlying > 0 ? Math.round(Math.abs(displayForUnderlying / underlying - 1) * 10_000) : null;
    Object.assign(market, {quotedPrescaledUsd: quotedPrescaled, referencePrescaledUsd: prescaled ?? null, referenceSource,
      referenceDeviationBps, underlyingUsd: underlying ?? null, underlyingDeviationBps});
    if (referenceDeviationBps > LIMITS.maximumReferenceDeviationBps + candidate.transferFeeBps) {
      return fail('market', 'PRICE_REFERENCE_DEVIATION', referenceDeviationBps);
    }
    if (underlyingDeviationBps !== null && underlyingDeviationBps > LIMITS.maximumUnderlyingDeviationBps + candidate.transferFeeBps) {
      return fail('market', 'PRICE_UNDERLYING_DEVIATION', underlyingDeviationBps);
    }
    return {ok: true, market};
  } catch (error) {
    const known = ['NO_ROUTE', 'MARKET_CLOSED', 'NO_MARKET_MAKER_QUOTE'];
    return fail('market', known.includes(error.message) ? error.message : 'QUOTE_UNAVAILABLE', error.detail ?? String(error.message).slice(0, 160));
  }
}
// When both routes fail, report the most informative refusal.
const FAILURE_PRIORITY = ['PRICE_REFERENCE_DEVIATION', 'PRICE_UNDERLYING_DEVIATION', 'ROUND_TRIP_LOSS', 'BUY_IMPACT', 'SELL_CAP_IMPACT',
  'PRICE_UNAVAILABLE', 'MARKET_CLOSED', 'NO_MARKET_MAKER_QUOTE', 'LIQUIDITY_BELOW_FLOOR', 'NO_ROUTE', 'QUOTE_UNAVAILABLE'];
for (const candidate of offered.slice(0, maxCandidates)) {
  const issuerRoute = STOCK_ISSUERS[candidate.issuerId].identity.route;
  const failures = [];
  for (const route of issuerRoute === 'rfq' ? ['rfq', 'aggregator'] : ['aggregator', 'rfq']) {
    const result = await marketCheck(candidate, route);
    if (result.ok) {
      candidate.route = route;
      candidate.market = result.market;
      break;
    }
    failures.push(result);
  }
  if (candidate.route) {
    marketReady.push(candidate);
    const m = candidate.market;
    console.log(`market ok ${candidate.symbol} (${candidate.issuerId}, ${candidate.route}) round trip ${m.roundTripLossBps} bps, $100 impact ${m.buyImpactBps} bps`);
  } else {
    const chosen = failures.sort((a, b) => FAILURE_PRIORITY.indexOf(a.reason) - FAILURE_PRIORITY.indexOf(b.reason))[0];
    candidate.marketAttempts = failures;
    reject(candidate, chosen.stage, chosen.reason, chosen.detail);
  }
}
console.log(`market: ${marketReady.length} candidates quote both ways`);

// 5. Sell-side taker: a large public holder (from Trimmy's public holders read)
// whose tokens sit in its own associated account, verified here on-chain.
const issuerWallets = new Set(STOCK_ISSUER_IDS.flatMap(id => {
  const identity = STOCK_ISSUERS[id].identity;
  return [identity.metadataUpdateAuthority, identity.mintAuthority, identity.permanentDelegate, ...identity.freezeAuthorities].filter(Boolean);
}));
async function sellTakers(candidate, amountRaw) {
  const page = await getJson(`${apiBase}/v1/markets/stocks/holders?mint=${candidate.mint}`, 256 * 1024);
  await pause(1100);
  const owners = [...new Set((page.holders ?? []).map(holder => holder.owner))].filter(owner => !issuerWallets.has(owner)).slice(0, 20);
  if (!owners.length) return [];
  const atas = await Promise.all(owners.map(owner => associatedAddress(owner, candidate.mint)));
  const ownerAccounts = await rpc('getMultipleAccounts', [owners, {encoding: 'base64', commitment: 'confirmed'}]);
  const ataAccounts = await rpc('getMultipleAccounts', [atas, {encoding: 'jsonParsed', commitment: 'confirmed'}]);
  const found = [];
  for (const [index, owner] of owners.entries()) {
    const state = ownerAccounts.value[index];
    const ata = ataAccounts.value[index];
    const info = ata?.data?.parsed?.info;
    if (!state || state.owner !== SYSTEM_PROGRAM || state.executable || state.lamports < 10_000_000) continue;
    if (!info || ata.owner !== TOKEN_2022 || info.owner !== owner || info.mint !== candidate.mint || info.state !== 'initialized' ||
        BigInt(info.tokenAmount?.amount ?? '0') < BigInt(amountRaw)) continue;
    found.push(owner);
    if (found.length === 3) break;
  }
  return found;
}

// 6. Real unsigned previews through the production pipeline with a candidate registry.
const originalRegistry = await readFile(REGISTRY_PATH, 'utf8');
const today = observedAt.slice(0, 10);
const quoted = value => `'${String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
const entryLine = candidate => `  {assetId: ${quoted(candidate.assetId)}, symbol: ${quoted(candidate.symbol)}, ` +
  `name: ${quoted(candidate.name.trim())}, mint: ${quoted(candidate.mint)}, issuerId: ${quoted(candidate.issuerId)}, ` +
  `decimals: ${candidate.decimals}, maxSellInputRaw: ${quoted(candidate.market.sellCapRaw)}, transferFeeBps: ${candidate.transferFeeBps}, ` +
  `status: 'active', admittedAt: ${quoted(today)}, admissionSlot: ${identitySlot}, route: ${quoted(candidate.route)}},`;
function registryWith(entries) {
  const marker = '] as const;';
  const at = originalRegistry.lastIndexOf(marker);
  assert.ok(at > 0, 'registry end marker');
  return originalRegistry.slice(0, at) + entries.map(entryLine).join('\n') + (entries.length ? '\n' : '') + originalRegistry.slice(at);
}
const unique = [];
const seenSymbols = new Set(existingSymbols);
for (const candidate of marketReady) {
  const key = candidate.symbol.toLowerCase();
  if (seenSymbols.has(key)) {reject(candidate, 'registry', 'SYMBOL_COLLISION'); continue;}
  seenSymbols.add(key);
  unique.push(candidate);
}
const plan = [];
for (const candidate of unique) {
  // Ondo's market makers refuse trades under $1 after fees, with the same message
  // they use outside market hours, so market-maker routes are tested at $2.
  const usd = candidate.route === 'rfq' ? 2n : 1n;
  plan.push({assetId: candidate.assetId, mint: candidate.mint, symbol: candidate.symbol, side: 'buy', taker: buyTaker,
    amountRaw: (usd * 1_000_000n).toString()});
  const sellAmount = BigInt(candidate.market.rawPerUsd) > 0n ? BigInt(candidate.market.rawPerUsd) * usd : 1n;
  let takers = [];
  try {takers = await sellTakers(candidate, sellAmount);} catch (error) {candidate.sellTakerError = String(error.message).slice(0, 120);}
  if (takers.length) plan.push({assetId: candidate.assetId, mint: candidate.mint, symbol: candidate.symbol, side: 'sell', takers, amountRaw: sellAmount.toString()});
  else candidate.sellTaker = null;
}
// One evidence set per run: a later recheck the same day never overwrites an earlier one.
const scratch = `artifacts/verification/stock-admission-${observedAt.replace(/[:.]/g, '-')}${onlyMints ? '-recheck' : ''}`;
await mkdir('artifacts/verification', {recursive: true});
let previews = [];
try {
  await writeFile(REGISTRY_PATH, registryWith(unique));
  await writeFile(`${scratch}-plan.json`, JSON.stringify(plan, null, 2) + '\n');
  await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['--import', 'tsx', new URL(import.meta.url).pathname, '--simulate', `${scratch}-plan.json`, `${scratch}-previews.json`],
      {stdio: 'inherit'});
    child.on('exit', code => code === 0 ? resolve() : reject(Error(`SIMULATION_CHILD_${code}`)));
  });
  previews = JSON.parse(await readFile(`${scratch}-previews.json`, 'utf8'));
} finally {
  await writeFile(REGISTRY_PATH, originalRegistry);
}

// 7. Admit only candidates whose buy and sell both reviewed and simulated.
for (const candidate of unique) {
  const mine = previews.filter(item => item.mint === candidate.mint);
  const buy = mine.find(item => item.side === 'buy');
  const sell = mine.find(item => item.side === 'sell');
  candidate.previews = mine;
  evidence.candidates.push(candidate);
  if (buy?.status !== 'reviewed') {reject(candidate, 'review', 'BUY_' + (buy?.code ?? 'NOT_RUN'), buy?.failure ?? null); continue;}
  if (!sell) {reject(candidate, 'review', 'SELL_NO_PUBLIC_HOLDER'); continue;}
  if (sell.status !== 'reviewed') {reject(candidate, 'review', 'SELL_' + (sell.code ?? 'NOT_RUN'), sell.failure ?? null); continue;}
  evidence.admitted.push({assetId: candidate.assetId, symbol: candidate.symbol, name: candidate.name, mint: candidate.mint,
    issuerId: candidate.issuerId, decimals: candidate.decimals, transferFeeBps: candidate.transferFeeBps,
    maxSellInputRaw: candidate.market.sellCapRaw});
}
const admitted = unique.filter(candidate => evidence.admitted.some(item => item.mint === candidate.mint));
// Every unadmitted Market variant, sorted for a stable diff. Kept in the evidence too.
const attributionRows = [...attribution.values()].filter(row => !admitted.some(item => item.mint === row.mint))
  .sort((a, b) => a.mint < b.mint ? -1 : a.mint > b.mint ? 1 : 0);
evidence.attribution = attributionRows;
if (flag('--write')) {
  const registrySource = registryWith(admitted);
  const currentAttribution = await readFile(ATTRIBUTION_PATH, 'utf8');
  const header = currentAttribution.split('export const')[0];
  if (onlyMints) {
    // Keep every other row verbatim; replace or drop only the rechecked mints.
    const {STOCK_MARKET_ATTRIBUTION} = await import('../../apps/api/src/stock-market-attribution.generated.ts');
    const kept = STOCK_MARKET_ATTRIBUTION.filter(row => !onlyMints.includes(row.mint))
      .map(row => ({...row, symbol: row.symbol ?? catalogSymbols.get(row.mint) ?? null}));
    attributionRows.splice(0, attributionRows.length, ...[...kept, ...attributionRows]
      .sort((a, b) => a.mint < b.mint ? -1 : a.mint > b.mint ? 1 : 0));
  }
  const attributionSource = header + 'export const STOCK_MARKET_ATTRIBUTION: readonly {readonly mint: string; ' +
    'readonly issuerId: string | null; readonly reason: string; readonly symbol?: string}[] = [\n' +
    attributionRows.map(row => `  {mint: ${quoted(row.mint)}, issuerId: ${row.issuerId === null ? 'null' : quoted(row.issuerId)}, ` +
      `reason: ${quoted(row.reason)}${row.symbol ? `, symbol: ${quoted(row.symbol)}` : ''}},`).join('\n') + (attributionRows.length ? '\n' : '') + '];\n';
  await writeFile(REGISTRY_PATH, registrySource);
  await writeFile(ATTRIBUTION_PATH, attributionSource);
}
evidence.identitySlot = identitySlot;
evidence.registryWritten = flag('--write');
await writeFile(`${scratch}.json`, JSON.stringify(evidence, (key, value) => typeof value === 'bigint' ? value.toString() : value, 2) + '\n');
const byIssuer = admitted.reduce((out, item) => ({...out, [item.issuerId]: (out[item.issuerId] ?? 0) + 1}), {});
console.log(`admitted ${admitted.length} ${JSON.stringify(byIssuer)}; rejected ${evidence.rejected.length}; evidence ${scratch}.json` +
  (flag('--write') ? '; registry written' : '; dry run, registry unchanged'));
