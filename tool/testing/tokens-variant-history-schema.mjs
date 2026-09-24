/**
 * One bounded, read-only Tokens.xyz AAPLx OHLCV schema observation.
 * The API key and raw provider body remain in process memory and are never
 * printed or written. The artifact contains structural metadata and hashes.
 */
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export const TOKENS_ORIGIN = 'https://api.tokens.xyz';
export const ASSET_ID = 'apple';
export const AAPLX_MINT = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
export const INTERVAL = '1H';
const INTERVAL_SECONDS = 3_600;
const WINDOW_SECONDS = 7 * 24 * 60 * 60;
const MAX_BODY_BYTES = 2_097_152;
const MAX_CANDLES = 20_000;
const KEY_SERVICE = 'trimmy-tokens-xyz';
const KEY_ACCOUNT = 'trimmy';
const SAFE_FIELD = /^[A-Za-z][A-Za-z0-9_]{0,63}$/u;
const TIME_FIELDS = new Set(['t', 'time', 'timestamp', 'ts', 'start', 'startTime', 'bucketStart']);

export class TokensHistorySchemaError extends Error {
  constructor(code) { super(code); this.name = 'TokensHistorySchemaError'; this.code = code; }
}
const fail = code => { throw new TokensHistorySchemaError(code); };
const plainObject = value => value !== null && typeof value === 'object' && !Array.isArray(value) &&
  Object.getPrototypeOf(value) === Object.prototype;
const sha256 = value => createHash('sha256').update(value).digest('hex');
const scalarType = value => value === null ? 'null' : Array.isArray(value) ? 'array' : plainObject(value) ? 'object' :
  typeof value === 'number' ? Number.isInteger(value) ? 'integer' : 'number' : typeof value;
function checkedFields(value) {
  if (!plainObject(value)) fail('PAYLOAD_NOT_OBJECT');
  const fields = Object.keys(value).sort();
  if (fields.length > 64 || fields.some(field => !SAFE_FIELD.test(field))) fail('UNSAFE_SCHEMA_FIELD');
  return fields;
}
function publicInteger(value) {
  if (typeof value === 'number') return Number.isSafeInteger(value) && value >= 0 ? value : null;
  if (typeof value === 'string' && /^(?:0|[1-9][0-9]{0,15})$/u.test(value)) {
    const parsed = Number(value);
    return Number.isSafeInteger(parsed) ? parsed : null;
  }
  return null;
}
function ordering(values) {
  if (values.length < 2) return 'not_established';
  let up = true, down = true;
  for (let index = 1; index < values.length; index++) {
    if (values[index] <= values[index - 1]) up = false;
    if (values[index] >= values[index - 1]) down = false;
  }
  return up ? 'strictly_ascending' : down ? 'strictly_descending' : 'unordered_or_duplicate';
}
function timeObservation(name, values, request) {
  const parsed = values.map(publicInteger);
  if (parsed.some(value => value === null)) return Object.freeze({field: name, establishedUnit: null,
    reason: 'not_all_nonnegative_safe_integers'});
  const times = parsed;
  const lower = request.from - INTERVAL_SECONDS * 2;
  const upper = request.to + INTERVAL_SECONDS * 2;
  const seconds = times.every(value => value >= lower && value <= upper);
  const milliseconds = times.every(value => value / 1000 >= lower && value / 1000 <= upper);
  if (seconds === milliseconds) return Object.freeze({field: name, establishedUnit: null,
    reason: seconds ? 'ambiguous_range' : 'outside_requested_time_range'});
  const normalized = milliseconds ? times.map(value => value / 1000) : times;
  return Object.freeze({field: name, establishedUnit: milliseconds ? 'unix_milliseconds' : 'unix_seconds',
    minimum: String(Math.min(...times)), maximum: String(Math.max(...times)), ordering: ordering(normalized),
    unique: new Set(normalized).size === normalized.length});
}

/** Values are deliberately excluded except for validated request echoes and established timestamps. */
export function inspectHistoryPayload(payload, request, rawBytes) {
  const fields = checkedFields(payload);
  if (!(rawBytes instanceof Uint8Array) || rawBytes.byteLength === 0 || rawBytes.byteLength > MAX_BODY_BYTES) {
    fail('INVALID_RAW_BODY');
  }
  const schema = fields.map(name => Object.freeze({name, type: scalarType(payload[name])}));
  const echoes = {};
  for (const [name, expected] of Object.entries(request)) {
    const value = payload[name];
    const equivalent = typeof expected === 'number' ? publicInteger(value) === expected : value === expected;
    echoes[name] = Object.freeze({present: Object.hasOwn(payload, name), type: scalarType(value), matchesRequest: equivalent});
  }
  if (!Array.isArray(payload.candles) || payload.candles.length > MAX_CANDLES) fail('INVALID_CANDLES_CONTAINER');
  const candles = payload.candles;
  const kinds = [...new Set(candles.map(scalarType))].sort();
  const candleSummary = {count: candles.length, itemKinds: kinds};
  if (kinds.length === 1 && kinds[0] === 'object') {
    const profiles = new Map();
    const keySets = new Set();
    for (const candle of candles) {
      const names = checkedFields(candle);
      keySets.add(names.join(','));
      for (const name of names) {
        const current = profiles.get(name) ?? {name, presentCount: 0, types: new Set(), values: []};
        current.presentCount++;
        current.types.add(scalarType(candle[name]));
        if (TIME_FIELDS.has(name)) current.values.push(candle[name]);
        profiles.set(name, current);
      }
    }
    candleSummary.distinctKeySets = [...keySets].sort();
    candleSummary.fields = [...profiles.values()].sort((a, b) => a.name.localeCompare(b.name)).map(profile =>
      Object.freeze({name: profile.name, presentCount: profile.presentCount, types: [...profile.types].sort()}));
    candleSummary.timeFields = [...profiles.values()].filter(profile => TIME_FIELDS.has(profile.name))
      .sort((a, b) => a.name.localeCompare(b.name)).map(profile => timeObservation(profile.name, profile.values, request));
  } else if (kinds.length === 1 && kinds[0] === 'array') {
    const lengths = [...new Set(candles.map(candle => candle.length))].sort((a, b) => a - b);
    if (lengths.some(length => length > 32)) fail('INVALID_CANDLE_TUPLE');
    const positionTypes = [];
    for (let index = 0; index < (lengths.at(-1) ?? 0); index++) {
      positionTypes.push(Object.freeze({index, types: [...new Set(candles.filter(candle => index < candle.length)
        .map(candle => scalarType(candle[index])))].sort()}));
    }
    candleSummary.tupleLengths = lengths;
    candleSummary.positionTypes = positionTypes;
    candleSummary.timeFields = [];
  } else if (candles.length !== 0) fail('INCONSISTENT_CANDLE_ITEMS');
  else candleSummary.timeFields = [];
  const structuralJson = JSON.stringify({schema, candleSummary});
  return Object.freeze({topLevel: Object.freeze(schema), requestEchoes: Object.freeze(echoes),
    candles: Object.freeze(candleSummary), rawBodyBytes: rawBytes.byteLength, rawBodySha256: sha256(rawBytes),
    structuralSha256: sha256(structuralJson)});
}

function readKeyFromKeychain() {
  let key;
  try {
    key = execFileSync('security', ['find-generic-password', '-a', KEY_ACCOUNT, '-s', KEY_SERVICE, '-w'],
      {encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 4_096}).trim();
  } catch { fail('KEYCHAIN_CREDENTIAL_UNAVAILABLE'); }
  if (typeof key !== 'string' || key.length < 8 || key.length > 512 || !/^[\x21-\x7e]+$/u.test(key)) {
    fail('KEYCHAIN_CREDENTIAL_INVALID');
  }
  return key;
}

async function boundedBody(response, timeout) {
  if (!response.body || !/^application\/json(?:\s*;|$)/iu.test(response.headers.get('content-type') ?? '')) {
    fail('INVALID_CONTENT_TYPE');
  }
  const declared = response.headers.get('content-length');
  if (declared !== null && (!/^\d+$/u.test(declared) || Number(declared) > MAX_BODY_BYTES)) fail('BODY_TOO_LARGE');
  const reader = response.body.getReader();
  const chunks = []; let total = 0;
  try {
    for (;;) {
      const part = await Promise.race([reader.read(), timeout]);
      if (part.done) break;
      total += part.value.byteLength;
      if (total > MAX_BODY_BYTES) fail('BODY_TOO_LARGE');
      chunks.push(part.value);
    }
  } finally { try { void reader.cancel().catch(() => {}); } catch { /* disposal only */ } }
  return Buffer.concat(chunks);
}

/** Exactly one provider request. Dependencies are injectable for offline tests. */
export async function runTokensVariantHistorySchema({
  fetchImpl = globalThis.fetch, readApiKey = readKeyFromKeychain, now = Date.now, timeoutMs = 8_000,
} = {}) {
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 10_000) fail('INVALID_TIMEOUT');
  const nowMs = now();
  if (!Number.isSafeInteger(nowMs) || nowMs < 0 || nowMs > 8_639_999_999_000_000) fail('INVALID_CLOCK');
  const to = Math.floor(nowMs / 1000), from = to - WINDOW_SECONDS;
  const request = Object.freeze({assetId: ASSET_ID, mint: AAPLX_MINT, interval: INTERVAL, from, to});
  const url = new URL(`/v1/assets/${ASSET_ID}/ohlcv`, TOKENS_ORIGIN);
  url.search = new URLSearchParams({mint: AAPLX_MINT, interval: INTERVAL, from: String(from), to: String(to)}).toString();
  const report = {schemaVersion: 1, provider: 'tokens-xyz-v1', endpointMode: 'solana_variant',
    documentedContract: 'GET /v1/assets/:assetId/ohlcv', sourceUrl: url.href, requestedAt: new Date(nowMs).toISOString(),
    request, providerCalls: 0, credentialSource: {store: 'macos-keychain', service: KEY_SERVICE, account: KEY_ACCOUNT,
      valueStored: false}, walletUsed: false, transactionBuilt: false, transactionSigned: false,
    transactionBroadcast: false, financialMutation: false, passed: false};
  const controller = new AbortController();
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => { controller.abort(); reject(new TokensHistorySchemaError('READ_TIMEOUT')); }, timeoutMs);
  });
  try {
    const key = readApiKey();
    report.providerCalls++;
    const pending = fetchImpl(url, {method: 'GET', redirect: 'error', signal: controller.signal,
      headers: {accept: 'application/json', 'x-api-key': key}});
    void pending.then(response => {
      if (controller.signal.aborted) { try { void response.body?.cancel().catch(() => {}); } catch { /* disposal only */ } }
    }, () => {});
    const response = await Promise.race([pending, timeout]);
    report.httpStatus = response.status;
    if (response.redirected || response.url && new URL(response.url).origin !== TOKENS_ORIGIN) fail('REDIRECT_REFUSED');
    const bytes = await boundedBody(response, timeout);
    if (response.status !== 200) fail(response.status === 401 || response.status === 403 ? 'PROVIDER_AUTH_FAILED' :
      response.status === 429 ? 'PROVIDER_RATE_LIMITED' : 'PROVIDER_HTTP_ERROR');
    let payload;
    try { payload = JSON.parse(new TextDecoder('utf8', {fatal: true}).decode(bytes)); }
    catch { fail('INVALID_JSON'); }
    report.observation = inspectHistoryPayload(payload, request, bytes);
    report.providerContract = 'observed_not_execution_qualified';
    report.passed = true;
  } catch (error) {
    report.errorCode = error instanceof TokensHistorySchemaError ? error.code : 'READ_FAILED';
  } finally {
    clearTimeout(timer); controller.abort(); report.finishedAt = new Date().toISOString();
  }
  return Object.freeze(report);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 3 || process.argv[2] !== '--one-read') {
    console.error('Use --one-read for one read-only AAPLx Tokens.xyz schema observation.');
    process.exitCode = 1;
  } else {
    const report = await runTokensVariantHistorySchema();
    const output = new URL('../../artifacts/verification/TOKENS_VARIANT_HISTORY_SCHEMA.json', import.meta.url);
    await mkdir(new URL('.', output), {recursive: true});
    await writeFile(output, JSON.stringify(report, null, 2) + '\n', {mode: 0o644});
    console.log(JSON.stringify({passed: report.passed, httpStatus: report.httpStatus,
      candleCount: report.observation?.candles.count, errorCode: report.errorCode, output: output.pathname}));
    if (!report.passed) process.exitCode = 1;
  }
}
