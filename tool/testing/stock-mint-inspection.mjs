/** Read-only publisher provenance + mint inspection. No wallet or transaction API. */
import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { address, unwrapOption } from '@solana/kit';
import { getMintDecoder, getMintEncoder, TOKEN_2022_PROGRAM_ADDRESS } from '@solana-program/token-2022';
import { getSysvarClockDecoder, SYSVAR_CLOCK_ADDRESS } from '@solana/sysvars';

export const ISSUER_URL = 'https://api.xstocks.fi/api/v2/public/assets/AAPLx';
export const MAINNET_RPC_URL = 'https://api.mainnet-beta.solana.com';
export const MAINNET_GENESIS = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
export const LEGACY_TOKEN_PROGRAM = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const SYSVAR_OWNER = 'Sysvar1111111111111111111111111111111111111';
const MAX_JSON_BYTES = 262_144;
const MAX_ACCOUNT_BYTES = 65_536;
const MINT_EXTENSIONS = new Set([
  'TransferFeeConfig', 'MintCloseAuthority', 'ConfidentialTransferMint', 'DefaultAccountState',
  'NonTransferable', 'InterestBearingConfig', 'PermanentDelegate', 'TransferHook',
  'ConfidentialTransferFee', 'MetadataPointer', 'TokenMetadata', 'GroupPointer', 'TokenGroup',
  'GroupMemberPointer', 'TokenGroupMember', 'ConfidentialMintBurn', 'ScaledUiAmountConfig', 'PausableConfig',
]);
const DISPLAY_INSPECTED = new Set(['MetadataPointer', 'TokenMetadata', 'ScaledUiAmountConfig']);
export class MintInspectionError extends Error {
  constructor(code) { super(code); this.name = 'MintInspectionError'; this.code = code; }
}
const fail = code => { throw new MintInspectionError(code); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && Object.getPrototypeOf(value) === Object.prototype;
function validAddress(value) {
  if (typeof value !== 'string') fail('INVALID_ADDRESS');
  try { return address(value); } catch { fail('INVALID_ADDRESS'); }
}
function frozen(value) {
  if (value !== null && typeof value === 'object') {
    for (const item of Object.values(value)) frozen(item);
    Object.freeze(value);
  }
  return value;
}
function publicValue(value) {
  if (typeof value === 'bigint') return value.toString();
  if (typeof value === 'number' && !Number.isFinite(value)) fail('INVALID_EXTENSION_VALUE');
  if (value instanceof Map) return [...value].map(([key, item]) => [key, publicValue(item)]);
  if (Array.isArray(value)) return value.map(publicValue);
  if (object(value)) {
    if (value.__option === 'None') return null;
    if (value.__option === 'Some') return publicValue(value.value);
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, publicValue(item)]));
  }
  return value;
}

export function parseIssuerAsset(value) {
  if (!object(value) || value.symbol !== 'AAPLx' || value.name !== 'Apple xStock'
      || typeof value.id !== 'string' || value.id.length > 128
      || typeof value.isin !== 'string' || !/^CH[A-Z0-9]{10}$/.test(value.isin)
      || !Array.isArray(value.deployments) || value.deployments.length > 50) fail('INVALID_ISSUER_ASSET');
  const solana = value.deployments.filter(item => object(item) && item.network === 'Solana');
  if (solana.length !== 1) fail('AMBIGUOUS_ISSUER_DEPLOYMENT');
  return frozen({ sourceUrl: ISSUER_URL, assetId: value.id, symbol: value.symbol, name: value.name,
    isin: value.isin, network: 'Solana', mint: validAddress(solana[0].address),
    provenance: 'publisher_listed', eligibility: 'unverified' });
}

function accountBytes(account) {
  if (!object(account) || account.executable !== false || !Array.isArray(account.data)
      || account.data.length !== 2 || account.data[1] !== 'base64' || typeof account.data[0] !== 'string'
      || account.data[0].length > Math.ceil(MAX_ACCOUNT_BYTES / 3) * 4) fail('INVALID_ACCOUNT');
  const bytes = Buffer.from(account.data[0], 'base64');
  if (bytes.length > MAX_ACCOUNT_BYTES || bytes.toString('base64') !== account.data[0]) fail('INVALID_ACCOUNT');
  if (account.space !== undefined && account.space !== bytes.length) fail('INVALID_ACCOUNT');
  return bytes;
}

/** All TLV discriminators and layouts come from the pinned official generated decoder. */
export function inspectMintAccount({ mint, account, chainUnixTimestamp }) {
  mint = validAddress(mint);
  if (typeof chainUnixTimestamp !== 'bigint' || chainUnixTimestamp < 0n) fail('INVALID_CHAIN_TIME');
  const bytes = accountBytes(account);
  if (account.owner !== LEGACY_TOKEN_PROGRAM && account.owner !== TOKEN_2022_PROGRAM_ADDRESS) fail('UNSUPPORTED_TOKEN_PROGRAM');
  if (account.owner === LEGACY_TOKEN_PROGRAM && bytes.length !== 82) fail('INVALID_LEGACY_MINT');
  let decoded;
  try {
    const [value, end] = getMintDecoder().read(bytes, 0);
    // Exact encoding comparison also rejects permissive boolean/option/padding/length decoding.
    if (end !== bytes.length || !Buffer.from(getMintEncoder().encode(value)).equals(bytes)) fail('INVALID_MINT_ENCODING');
    decoded = value;
  } catch (error) {
    if (error instanceof MintInspectionError) throw error;
    fail('UNSUPPORTED_OR_MALFORMED_MINT');
  }
  if (!decoded.isInitialized) fail('UNINITIALIZED_MINT');
  const extensions = unwrapOption(decoded.extensions) ?? [];
  const seen = new Set();
  for (const extension of extensions) {
    if (!MINT_EXTENSIONS.has(extension.__kind)) fail('UNSUPPORTED_MINT_EXTENSION');
    if (seen.has(extension.__kind)) fail('DUPLICATE_MINT_EXTENSION');
    seen.add(extension.__kind);
    if (extension.__kind === 'TokenMetadata' && extension.mint !== mint) fail('METADATA_MINT_MISMATCH');
  }
  if (seen.has('ScaledUiAmountConfig') && seen.has('InterestBearingConfig')) fail('INCOMPATIBLE_MINT_EXTENSIONS');
  const scaled = extensions.find(item => item.__kind === 'ScaledUiAmountConfig');
  let scaledUi = null;
  if (scaled) {
    if (![scaled.multiplier, scaled.newMultiplier].every(value => Number.isFinite(value) && value > 0)) fail('INVALID_SCALED_MULTIPLIER');
    const nextActive = chainUnixTimestamp >= scaled.newMultiplierEffectiveTimestamp;
    scaledUi = { authority: scaled.authority, storedMultiplier: scaled.multiplier,
      nextMultiplier: scaled.newMultiplier, nextEffectiveUnixTimestamp: scaled.newMultiplierEffectiveTimestamp.toString(),
      observedChainUnixTimestamp: chainUnixTimestamp.toString(), activeField: nextActive ? 'newMultiplier' : 'multiplier',
      effectiveMultiplier: nextActive ? scaled.newMultiplier : scaled.multiplier,
      changesRawSupply: false, numericRepresentation: 'IEEE-754-f64; not an exact decimal conversion' };
  }
  return frozen({ mint, tokenProgram: account.owner, accountBytes: bytes.length,
    rawAccountSha256: createHash('sha256').update(bytes).digest('hex'), decimals: decoded.decimals,
    rawSupply: decoded.supply.toString(), mintAuthority: unwrapOption(decoded.mintAuthority),
    freezeAuthority: unwrapOption(decoded.freezeAuthority), initialized: true,
    extensions: extensions.map(publicValue), scaledUi,
    extensionReviewRequired: extensions.filter(item => !DISPLAY_INSPECTED.has(item.__kind)).map(item => item.__kind),
    eligibility: 'unverified', executionEnabled: false,
    limitations: ['Publisher listing and decoding do not establish user eligibility or issuer backing.',
      'No pool, token-account restrictions, route, transfer, quote, redemption or authority-control proof is tested.',
      'Raw supply is preserved as an integer string; no floating-point supply or holding conversion is produced.'] });
}

/** Fixed endpoints; bounded response/time; only two read RPC methods are expressible. */
export class MintReadClient {
  #fetch; #timeoutMs; #requestId = 0;
  constructor({ fetchImpl = globalThis.fetch, timeoutMs = 10_000 } = {}) {
    if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15_000) fail('INVALID_TIMEOUT');
    this.#fetch = fetchImpl; this.#timeoutMs = timeoutMs;
  }
  async #json(url, init) {
    const controller = new AbortController();
    let reader;
    let timer;
    const deadline = new Promise((_, reject) => {
      timer = setTimeout(() => { controller.abort(); reader?.cancel().catch(() => {}); reject(new MintInspectionError('READ_TIMEOUT')); }, this.#timeoutMs);
    });
    try {
      return await Promise.race([deadline, (async () => {
        const response = await this.#fetch(url, { ...init, redirect: 'error', signal: controller.signal });
        if (controller.signal.aborted) fail('READ_TIMEOUT');
        if (!response.ok) fail(`READ_HTTP_${response.status}`);
        if (response.redirected || !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '')) fail('INVALID_READ_RESPONSE');
        const declared = response.headers.get('content-length');
        if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > MAX_JSON_BYTES)) fail('READ_RESPONSE_TOO_LARGE');
        if (!response.body) fail('INVALID_READ_RESPONSE');
        reader = response.body.getReader();
        const chunks = []; let size = 0;
        while (true) {
          const { done, value } = await reader.read();
          if (controller.signal.aborted) fail('READ_TIMEOUT');
          if (done) break;
          size += value.length;
          if (size > MAX_JSON_BYTES) fail('READ_RESPONSE_TOO_LARGE');
          chunks.push(value);
        }
        reader = undefined;
        return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)));
      })()]);
    } catch (error) {
      controller.abort(); reader?.cancel().catch(() => {});
      if (error instanceof MintInspectionError) throw error;
      fail('READ_FAILED');
    } finally { clearTimeout(timer); }
  }
  issuerAsset() { return this.#json(ISSUER_URL, { method: 'GET' }); }
  async call(method, params = []) {
    if (method !== 'getGenesisHash' && method !== 'getMultipleAccounts') fail('READ_METHOD_NOT_ALLOWED');
    const id = ++this.#requestId;
    const value = await this.#json(MAINNET_RPC_URL, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id, method, params }) });
    if (!object(value) || value.jsonrpc !== '2.0' || value.id !== id || !Object.hasOwn(value, 'result') || Object.hasOwn(value, 'error')) fail('INVALID_RPC_RESPONSE');
    return value.result;
  }
}

export async function runMintInspection({ client = new MintReadClient() } = {}) {
  const report = { schemaVersion: 1, observedAt: new Date().toISOString(), network: 'mainnet-beta',
    rpcUrl: MAINNET_RPC_URL, walletUsed: false, transactionBuilt: false, transactionSigned: false,
    transactionBroadcast: false, eligibility: 'unverified', executionEnabled: false,
    decoder: { token2022: '@solana-program/token-2022@0.6.1', clock: '@solana/sysvars@5.5.1' }, passed: false };
  try {
    report.publisher = parseIssuerAsset(await client.issuerAsset());
    report.genesisHash = await client.call('getGenesisHash');
    if (report.genesisHash !== MAINNET_GENESIS) fail('WRONG_CHAIN');
    const result = await client.call('getMultipleAccounts', [[report.publisher.mint, SYSVAR_CLOCK_ADDRESS], { encoding: 'base64', commitment: 'confirmed' }]);
    if (!object(result) || !object(result.context) || !Number.isSafeInteger(result.context.slot) || result.context.slot < 0
        || !Array.isArray(result.value) || result.value.length !== 2) fail('INVALID_RPC_ACCOUNTS');
    const [mintAccount, clockAccount] = result.value;
    const clockBytes = accountBytes(clockAccount);
    if (clockAccount.owner !== SYSVAR_OWNER || clockBytes.length !== getSysvarClockDecoder().fixedSize) fail('INVALID_CHAIN_CLOCK');
    const clock = getSysvarClockDecoder().decode(clockBytes);
    if (clock.slot !== BigInt(result.context.slot)) fail('CHAIN_CLOCK_CONTEXT_MISMATCH');
    report.contextSlot = result.context.slot;
    report.chainClock = publicValue(clock);
    // Public raw bytes make this observation independently replayable without another network request.
    report.accounts = [mintAccount, clockAccount].map(account => ({ owner: account.owner, executable: account.executable, data: account.data, ...(account.space === undefined ? {} : { space: account.space }) }));
    report.inspection = inspectMintAccount({ mint: report.publisher.mint, account: mintAccount, chainUnixTimestamp: clock.unixTimestamp });
    report.passed = true;
  } catch (error) { report.errorCode = error instanceof MintInspectionError ? error.code : 'INSPECTION_FAILED'; }
  report.finishedAt = new Date().toISOString();
  return frozen(report);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 3 || process.argv[2] !== '--read-only') {
    console.error('Use --read-only to inspect publisher-listed AAPLx on mainnet. No wallet or transaction is used.');
    process.exitCode = 1;
  } else {
    const report = await runMintInspection();
    const output = new URL('../../artifacts/verification/STOCK_MINT_INSPECTION.json', import.meta.url);
    await mkdir(new URL('.', output), { recursive: true });
    await writeFile(output, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({ passed: report.passed, mint: report.publisher?.mint, errorCode: report.errorCode, output: output.pathname }));
    if (!report.passed) process.exitCode = 1;
  }
}
