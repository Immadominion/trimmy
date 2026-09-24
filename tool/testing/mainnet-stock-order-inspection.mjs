/** Fixed mainnet research wallet reads. No transaction-sign/simulate/send methods. */
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { address } from '@solana/kit';
import { findAssociatedTokenPda } from '@solana-program/token-2022';
import { openStockResearchWallet, assertStockResearchWallet, STOCK_WALLET_GENESIS } from './stock-order-wallet.mjs';
import { bindStockOrderDraft, StockOrderDraftError } from '../../apps/api/src/stock-order-draft.ts';
import { validateStockEstimateInput, STOCK_ESTIMATE_ASSET } from '../../apps/api/src/stock-estimates.ts';

export const MAINNET_STOCK_RPC = 'https://api.mainnet-beta.solana.com';
export const USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
/** One USDC. The smallest amount that still exercises a real route and a real
 * minimum-output floor; the operator funds this wallet by hand. */
export const REQUIRED_USDC_RAW = '1000000';
/** Conservative admission reserve (0.01 SOL), not a quoted cost or spending
 * authorization. A live order's own fee fields are read separately: one
 * signature costs 5000 lamports and a new Token-2022 account for the AAPLx
 * mint's extension set needs roughly 0.0022 SOL of rent. */
export const SOL_RESERVE_LAMPORTS = '10000000';
const TOKEN_PROGRAM = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const ORDER_URL = 'https://api.jup.ag/swap/v2/order';
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const integer = value => Number.isSafeInteger(value) && value >= 0;
export class StockInspectionError extends Error { constructor(code) { super(code); this.name = 'StockInspectionError'; this.code = code; } }
const fail = code => { throw new StockInspectionError(code); };
function raw(value) {
  if (typeof value !== 'string' || /^(?:0|[1-9][0-9]{0,19})$/.exec(value)?.[0] !== value || BigInt(value) > 18446744073709551615n) fail('STOCK_BALANCE_INVALID');
  return BigInt(value);
}
const deficit = (required, actual) => (BigInt(required) > actual ? BigInt(required) - actual : 0n).toString();

export class MainnetStockOrderInspection {
  #wallet; #fetch; #now; #timeout; #id = 0; #access; #orderAttempted = false;
  constructor({wallet, fetchImpl = fetch, now = Date.now, timeoutMs = 6000, jupiterAccess} = {}) {
    assertStockResearchWallet(wallet);
    if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 8000) fail('STOCK_INSPECTION_CONFIGURATION_INVALID');
    if (jupiterAccess !== undefined && (!['keyless_research', 'api_key'].includes(jupiterAccess.kind) ||
      (jupiterAccess.kind === 'api_key' && (typeof jupiterAccess.apiKey !== 'string' || /^[A-Za-z0-9._~-]{8,512}$/.exec(jupiterAccess.apiKey)?.[0] !== jupiterAccess.apiKey)))) fail('STOCK_INSPECTION_CONFIGURATION_INVALID');
    this.#wallet = wallet; this.#fetch = fetchImpl; this.#now = now; this.#timeout = timeoutMs;
    this.#access = jupiterAccess === undefined ? undefined : Object.freeze({...jupiterAccess});
  }
  async #json(url, options) {
    const controller = new AbortController(); let reader; let response; let timer;
    const deadline = new Promise((_, reject) => { timer = setTimeout(() => {
      controller.abort(); reject(new StockInspectionError('STOCK_READ_TIMEOUT'));
    }, this.#timeout); });
    try {
      const pending = this.#fetch(url, {...options, redirect: 'error', signal: controller.signal});
      void pending.then(late => { if (controller.signal.aborted) void late.body?.cancel().catch(() => {}); }, () => {});
      response = await Promise.race([pending, deadline]);
      if (!response.ok) fail(response.status === 429 ? 'STOCK_READ_RATE_LIMITED' : 'STOCK_READ_UNAVAILABLE');
      if (response.redirected || !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body) fail('STOCK_READ_INVALID');
      const length = response.headers.get('content-length');
      if (length !== null && (!/^\d+$/.test(length) || Number(length) > 262144)) fail('STOCK_READ_TOO_LARGE');
      reader = response.body.getReader(); const chunks = []; let size = 0;
      for (;;) {
        const part = await Promise.race([reader.read(), deadline]); if (part.done) break;
        size += part.value.byteLength; if (size > 262144) fail('STOCK_READ_TOO_LARGE'); chunks.push(part.value);
      }
      return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
    } catch (error) {
      if (error instanceof StockInspectionError) throw error;
      fail(controller.signal.aborted ? 'STOCK_READ_TIMEOUT' : 'STOCK_READ_FAILED');
    } finally {
      clearTimeout(timer); controller.abort();
      if (reader) void reader.cancel().catch(() => {}); else void response?.body?.cancel().catch(() => {});
    }
  }
  async #rpc(method, params = []) {
    if (!['getGenesisHash', 'getBalance', 'getTokenAccountsByOwner', 'getBlockHeight'].includes(method)) fail('STOCK_RPC_METHOD_DENIED');
    const id = ++this.#id;
    const body = await this.#json(MAINNET_STOCK_RPC, {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({jsonrpc: '2.0', id, method, params})});
    if (!object(body) || body.jsonrpc !== '2.0' || body.id !== id || Object.hasOwn(body, 'error') || !Object.hasOwn(body, 'result')) fail('STOCK_RPC_INVALID');
    return body.result;
  }
  async readFunding() {
    const wallet = this.#wallet;
    if (await this.#rpc('getGenesisHash') !== STOCK_WALLET_GENESIS) fail('STOCK_WRONG_NETWORK');
    const sol = await this.#rpc('getBalance', [wallet.publicAddress, {commitment: 'confirmed'}]);
    if (!object(sol) || !object(sol.context) || !integer(sol.context.slot) || !integer(sol.value)) fail('STOCK_BALANCE_INVALID');
    const tokens = await this.#rpc('getTokenAccountsByOwner', [wallet.publicAddress, {mint: USDC_MINT}, {encoding: 'jsonParsed', commitment: 'confirmed', minContextSlot: sol.context.slot}]);
    if (!object(tokens) || !object(tokens.context) || !integer(tokens.context.slot) || tokens.context.slot < sol.context.slot || !Array.isArray(tokens.value) || tokens.value.length > 32) fail('STOCK_BALANCE_INVALID');
    const [ata] = await findAssociatedTokenPda({owner: address(wallet.publicAddress), mint: address(USDC_MINT), tokenProgram: address(TOKEN_PROGRAM)});
    let total = 0n; let associated = 0n; const seen = new Set();
    for (const entry of tokens.value) {
      const account = entry?.account; const data = account?.data; const parsed = data?.parsed; const info = parsed?.info;
      if (!object(entry) || typeof entry.pubkey !== 'string' || seen.has(entry.pubkey) || address(entry.pubkey) !== entry.pubkey ||
        !object(account) || account.owner !== TOKEN_PROGRAM || account.executable !== false || data?.program !== 'spl-token' || parsed?.type !== 'account' ||
        !object(info) || info.owner !== wallet.publicAddress || info.mint !== USDC_MINT || info.state !== 'initialized' || info.isNative !== false ||
        info.tokenAmount?.decimals !== 6) fail('STOCK_BALANCE_INVALID');
      seen.add(entry.pubkey); const amount = raw(info.tokenAmount.amount); total += amount;
      if (entry.pubkey === ata) associated = amount;
    }
    if (total > 18446744073709551615n) fail('STOCK_BALANCE_INVALID');
    const solShortfall = deficit(SOL_RESERVE_LAMPORTS, BigInt(sol.value)); const usdcShortfall = deficit(REQUIRED_USDC_RAW, associated);
    return Object.freeze({publicAddress: wallet.publicAddress, network: 'mainnet-beta', genesisHash: STOCK_WALLET_GENESIS,
      observedAt: new Date(this.#now()).toISOString(), solContextSlot: sol.context.slot, usdcContextSlot: tokens.context.slot,
      solLamports: String(sol.value), usdcTotalRaw: total.toString(), usdcAssociatedRaw: associated.toString(), usdcAssociatedAddress: ata,
      requiredUsdcRaw: REQUIRED_USDC_RAW, solReserveLamports: SOL_RESERVE_LAMPORTS, solShortfallLamports: solShortfall,
      usdcShortfallRaw: usdcShortfall, fundingReady: solShortfall === '0' && usdcShortfall === '0'});
  }
  /** verifyAccount is a future trusted server adapter, never a CLI UUID/boolean.
   * Must authenticate Privy, resolve the real account, verify its taker ownership,
   * and supply a freshly accepted server estimate. No such adapter ships here.
   */
  async inspectFunded({verifyAccount} = {}) {
    const funding = await this.readFunding();
    const base = {schemaVersion: 1, funding, publicAddress: this.#wallet.publicAddress, applicationAuthenticationVerified: false,
      orderRequested: false, transactionSigned: false, simulationRun: false, transactionBroadcast: false, readyForExecution: false};
    if (!funding.fundingReady) return {...base, status: 'funding_required'};
    if (typeof verifyAccount !== 'function') return {...base, status: 'verified_app_account_required'};
    const account = await verifyAccount(this.#wallet.publicAddress);
    if (!object(account) || account.provider !== 'privy' || typeof account.userId !== 'string' ||
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.exec(account.userId)?.[0] !== account.userId ||
        account.userId === this.#wallet.localResearchPrincipalId || account.verifiedTaker !== this.#wallet.publicAddress || account.walletOwnershipVerified !== true) fail('STOCK_APP_ACCOUNT_REQUIRED');
    const expected = account.expectedEstimate;
    try { validateStockEstimateInput({assetId: expected.assetId, variantMint: expected.variantMint, side: expected.side, amountRaw: expected.input.amountRaw}); }
    catch { fail('STOCK_ACCEPTED_ESTIMATE_REQUIRED'); }
    if (expected.side !== 'buy' || expected.input.amountRaw !== REQUIRED_USDC_RAW || expected.input.mint !== USDC_MINT ||
        expected.output.mint !== STOCK_ESTIMATE_ASSET.variantMint || !Number.isInteger(expected.slippageBps) || expected.slippageBps < 0 || expected.slippageBps > 10000 ||
        !Number.isFinite(Date.parse(expected.receivedAt)) || !Number.isFinite(Date.parse(expected.refreshAfter)) ||
        Date.parse(expected.receivedAt) > this.#now() || Date.parse(expected.refreshAfter) <= this.#now()) fail('STOCK_ACCEPTED_ESTIMATE_REQUIRED');
    if (this.#access === undefined) fail('STOCK_ORDER_ACCESS_DISABLED');
    if (this.#orderAttempted) fail('STOCK_ORDER_ALREADY_ATTEMPTED');
    const height = await this.#rpc('getBlockHeight', [{commitment: 'confirmed', minContextSlot: funding.usdcContextSlot}]);
    if (!integer(height) || this.#now() - Date.parse(funding.observedAt) > 10000) fail('STOCK_FUNDING_OBSERVATION_STALE');
    const started = this.#now();
    if (Date.parse(expected.refreshAfter) <= started) fail('STOCK_ACCEPTED_ESTIMATE_REQUIRED');
    const url = new URL(ORDER_URL);
    url.search = new URLSearchParams({inputMint: USDC_MINT, outputMint: STOCK_ESTIMATE_ASSET.variantMint,
      amount: REQUIRED_USDC_RAW, taker: this.#wallet.publicAddress, slippageBps: String(expected.slippageBps)}).toString();
    const headers = {accept: 'application/json'};
    if (this.#access.kind === 'api_key') headers['x-api-key'] = this.#access.apiKey;
    this.#orderAttempted = true;
    const response = await this.#json(url, {method: 'GET', headers});
    const draft = bindStockOrderDraft(response, {authenticatedUserId: account.userId, verifiedTaker: this.#wallet.publicAddress,
      expected, requestStartedAt: new Date(started).toISOString(),
      chainObservation: {genesisHash: STOCK_WALLET_GENESIS, blockHeight: String(height), observedAt: new Date(started).toISOString()},
      validityAuthority: {now: this.#now, readChainObservation: async () => {
        const observedAt = this.#now();
        if (await this.#rpc('getGenesisHash') !== STOCK_WALLET_GENESIS) fail('STOCK_WRONG_NETWORK');
        const currentHeight = await this.#rpc('getBlockHeight', [{commitment: 'confirmed'}]);
        if (!integer(currentHeight)) fail('STOCK_RPC_INVALID');
        return {genesisHash: STOCK_WALLET_GENESIS, blockHeight: String(currentHeight), observedAt: new Date(observedAt).toISOString()};
      }}});
    return {...base, status: 'draft_unreviewed', applicationAuthenticationVerified: true, orderRequested: true, draft: draft.summary};
  }
  get orderAttempted() { return this.#orderAttempted; }
}

export async function runStockInspectionCli(args) {
  if (args.length !== 1 || !['--create-wallet', '--balances', '--inspect-funded'].includes(args[0])) fail('STOCK_INSPECTION_ARGUMENTS_INVALID');
  const wallet = await openStockResearchWallet({mode: args[0] === '--create-wallet' ? 'create' : 'reopen'});
  let report = {schemaVersion: 1, observedAt: new Date().toISOString(), wallet, applicationAuthenticationVerified: false,
    orderRequested: false, transactionSigned: false, simulationRun: false, transactionBroadcast: false};
  if (args[0] !== '--create-wallet') {
    const reader = new MainnetStockOrderInspection({wallet});
    if (args[0] === '--inspect-funded') report = {...report, ...await reader.inspectFunded()};
    else report = {...report, funding: await reader.readFunding(), status: 'balance_only'};
  } else report.status = 'created';
  const sourcePaths = ['tool/testing/stock-order-wallet.mjs', 'tool/testing/mainnet-stock-order-inspection.mjs', 'apps/api/src/stock-order-draft.ts'];
  report.sourceSha256 = {};
  for (const path of sourcePaths) report.sourceSha256[path] = createHash('sha256').update(await readFile(new URL('../../' + path, import.meta.url))).digest('hex');
  await writeFile(new URL('../../artifacts/verification/STOCK_ORDER_FUNDING.json', import.meta.url), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({publicAddress: wallet.publicAddress, readyForOrder: false,
    solShortfallLamports: report.funding?.solShortfallLamports ?? null, usdcShortfallRaw: report.funding?.usdcShortfallRaw ?? null,
    status: report.status, applicationAuthenticationVerified: false}));
  return report;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { await runStockInspectionCli(process.argv.slice(2)); }
  catch (error) { console.log(JSON.stringify({readyForOrder: false, errorCode: error instanceof StockInspectionError || error instanceof StockOrderDraftError ? error.code : 'STOCK_INSPECTION_FAILED'})); process.exitCode = 1; }
}
