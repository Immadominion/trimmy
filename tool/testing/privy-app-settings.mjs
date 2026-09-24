/** Read-only owner-authorized app settings. No user, wallet, token or dashboard
 * mutation methods are called. Uses @privy-io/node 0.34.0 apps().getSettings(). */
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash, createPublicKey} from 'node:crypto';
import {mkdir, writeFile, chmod} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {PrivyClient} from '@privy-io/node';

const execFileAsync = promisify(execFile);
const scheme = 'com.trimmy.trimmy.privy';
const keychainAccount = 'trimmy';
const safeId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.exec(value)?.[0] === value;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export class PrivySettingsError extends Error {
  constructor(code) { super(code); this.name = 'PrivySettingsError'; this.code = code; }
}
const fail = code => { throw new PrivySettingsError(code); };
function boolean(value) { if (typeof value !== 'boolean') fail('PRIVY_SETTINGS_INVALID'); return value; }
function strings(value) {
  if (!Array.isArray(value) || value.length > 1000 || value.some(item => typeof item !== 'string' ||
    item.length > 2048 || /[\u0000-\u001f\u007f]/.test(item))) fail('PRIVY_SETTINGS_INVALID');
  return value;
}

/** Projection only: never serialize the whole SDK response, even if it calls
 * itself public. Unknown fields are discarded and a private key is rejected. */
export function parsePrivyPublicSettings(value, expectedAppId) {
  if (!safeId(expectedAppId) || !object(value) || value.id !== expectedAppId) fail('PRIVY_APP_ID_MISMATCH');
  if (value.data_classification !== 'public' || typeof value.name !== 'string' || value.name.length > 160 ||
    /[\u0000-\u001f\u007f]/.test(value.name)) fail('PRIVY_SETTINGS_INVALID');
  const rawKey = value.verification_key;
  // App settings may return a single-line SPKI PEM. Parse its exact envelope,
  // then export conventional line-wrapped PEM for the API verifier.
  const match = typeof rawKey === 'string'
    ? /^-----BEGIN PUBLIC KEY-----[ \t\r\n]*([A-Za-z0-9+/= \t\r\n]+)-----END PUBLIC KEY-----[ \t\r\n]*$/.exec(rawKey) : null;
  if (typeof rawKey !== 'string' || rawKey.length > 8192 || !match || match[0] !== rawKey) {
    fail('PRIVY_VERIFICATION_KEY_INVALID');
  }
  const body = match[1].replace(/[ \t\r\n]/g, '');
  const der = Buffer.from(body, 'base64');
  if (der.toString('base64') !== body) fail('PRIVY_VERIFICATION_KEY_INVALID');
  let key;
  try { key = createPublicKey({key: der, type: 'spki', format: 'der'}); } catch { fail('PRIVY_VERIFICATION_KEY_INVALID'); }
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1' ||
    !Buffer.from(key.export({type: 'spki', format: 'der'})).equals(der)) fail('PRIVY_VERIFICATION_KEY_INVALID');
  const verificationKey = key.export({type: 'spki', format: 'pem'}).toString();
  const domains = strings(value.allowed_domains);
  const nativeIds = strings(value.allowed_native_app_ids);
  const schemes = strings(value.allowed_native_app_url_schemes);
  return Object.freeze({
    publicSettings: Object.freeze({appId: value.id, name: value.name, dataClassification: 'public',
      twitterOAuthEnabled: boolean(value.twitter_oauth), twitterOAuthOnMobileEnabled: boolean(value.twitter_oauth_on_mobile_enabled),
      emailAuthEnabled: boolean(value.email_auth), googleOAuthEnabled: boolean(value.google_oauth),
      allowlistEnabled: boolean(value.allowlist_enabled),
      nativeScheme: scheme, nativeSchemeAllowed: schemes.includes(scheme),
      allowedNativeAppIdsCount: nativeIds.length, allowedDomainsCount: domains.length,
      nativeAppClientId: null, nativeAppClientIdStatus: 'not_exposed_by_settings',
      xOAuthVersion: 'not_exposed_by_settings', verificationKeyAlgorithm: 'ES256',
      verificationKeySha256: createHash('sha256').update(verificationKey).digest('hex')}),
    verificationKey,
  });
}

/** Read exactly one selected Keychain item, without a shell or inherited output. */
export async function readPrivyKeychain({execute = execFileAsync} = {}) {
  async function item(service) {
    try {
      const result = await execute('/usr/bin/security', ['find-generic-password', '-a', keychainAccount, '-s', service, '-w'],
        {encoding: 'utf8', timeout: 5000, maxBuffer: 16_384});
      // security adds one line ending; do not otherwise normalize a credential.
      return result.stdout.replace(/\r?\n$/, '');
    } catch { fail('PRIVY_KEYCHAIN_UNAVAILABLE'); }
  }
  const appId = await item('trimmy-privy-app-id');
  const appSecret = await item('trimmy-privy-app-secret');
  if (!safeId(appId) || typeof appSecret !== 'string' ||
    /^[\x21-\x7e]{1,4096}$/.exec(appSecret)?.[0] !== appSecret) fail('PRIVY_KEYCHAIN_INVALID');
  return {appId, appSecret};
}

/** The SDK may only send this specific settings GET. Bound its full body and
 * deadline as well as disabling the SDK's default retries and diagnostics. */
export function settingsFetch(appId, {fetchImpl = globalThis.fetch, timeoutMs = 8000} = {}) {
  if (!safeId(appId) || !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 10_000) fail('PRIVY_SETTINGS_INVALID');
  return async (input, init = {}) => {
    const target = String(input);
    if (target !== `https://api.privy.io/v1/apps/${appId}` || init.method !== 'GET' || init.body != null) fail('PRIVY_READ_NOT_ALLOWED');
    const controller = new AbortController();
    let reader, timer;
    const deadline = new Promise((_, reject) => {
      timer = setTimeout(() => { controller.abort(); reader?.cancel().catch(() => {}); reject(new PrivySettingsError('PRIVY_SETTINGS_TIMEOUT')); }, timeoutMs);
    });
    try {
      return await Promise.race([deadline, (async () => {
        const response = await fetchImpl(target, {...init, redirect: 'error', signal: controller.signal});
        if (controller.signal.aborted) fail('PRIVY_SETTINGS_TIMEOUT');
        if (response.status !== 200) fail(response.status === 401 || response.status === 403 ? 'PRIVY_SETTINGS_AUTH_FAILED' : 'PRIVY_SETTINGS_UNAVAILABLE');
        if (response.redirected || !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body) fail('PRIVY_SETTINGS_INVALID');
        const declared = response.headers.get('content-length');
        if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > 262_144)) fail('PRIVY_SETTINGS_TOO_LARGE');
        reader = response.body.getReader();
        const chunks = []; let length = 0;
        while (true) {
          const part = await reader.read();
          if (controller.signal.aborted) fail('PRIVY_SETTINGS_TIMEOUT');
          if (part.done) break;
          length += part.value.byteLength;
          if (length > 262_144) fail('PRIVY_SETTINGS_TOO_LARGE');
          chunks.push(part.value);
        }
        reader = undefined;
        const body = new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks));
        return new Response(body, {status: 200, headers: {'content-type': 'application/json'}});
      })()]);
    } catch (error) {
      controller.abort(); reader?.cancel().catch(() => {});
      if (error instanceof PrivySettingsError) throw error;
      fail('PRIVY_SETTINGS_UNAVAILABLE');
    } finally { clearTimeout(timer); }
  };
}

export async function inspectPrivyApp({appId, appSecret, fetchImpl, now = () => new Date().toISOString()} = {}) {
  if (!safeId(appId) || typeof appSecret !== 'string' || /^[\x21-\x7e]{1,4096}$/.exec(appSecret)?.[0] !== appSecret) fail('PRIVY_KEYCHAIN_INVALID');
  const quiet = {debug() {}, info() {}, warn() {}, error() {}};
  const client = new PrivyClient({appId, appSecret, apiUrl: 'https://api.privy.io', maxRetries: 0,
    timeout: 8000, logLevel: 'off', logger: quiet, fetch: settingsFetch(appId, {fetchImpl})});
  let value;
  try { value = await client.apps().getSettings(); }
  catch { fail('PRIVY_SETTINGS_READ_FAILED'); }
  const parsed = parsePrivyPublicSettings(value, appId);
  return {publicConfig: Object.freeze({PRIVY_APP_ID: appId, PRIVY_VERIFICATION_KEY: parsed.verificationKey}),
    evidence: Object.freeze({schemaVersion: 1, checkedAt: now(), passed: true,
      source: '@privy-io/node@0.34.0 apps().getSettings()', ...parsed.publicSettings,
      loginVerified: false, usersCreated: false, walletsCreated: false, providerSettingsMutated: false})};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 3 || process.argv[2] !== '--read-only') {
    console.error('Use --read-only to inspect the selected Keychain Privy app.'); process.exitCode = 1;
  } else {
    let evidence;
    try {
      const credentials = await readPrivyKeychain();
      const result = await inspectPrivyApp(credentials);
      const directory = join(homedir(), '.config/trimmy/privy');
      await mkdir(directory, {recursive: true, mode: 0o700}); await chmod(directory, 0o700);
      const configPath = join(directory, 'public-verifier-config.json');
      await writeFile(configPath, JSON.stringify(result.publicConfig, null, 2) + '\n', {mode: 0o600});
      await chmod(configPath, 0o600);
      evidence = {...result.evidence, publicVerifierConfigStoredOutsideRepository: true};
    } catch (error) {
      evidence = {schemaVersion: 1, checkedAt: new Date().toISOString(), passed: false,
        errorCode: error instanceof PrivySettingsError ? error.code : 'PRIVY_SETTINGS_LOCAL_FAILED',
        loginVerified: false, usersCreated: false, walletsCreated: false, providerSettingsMutated: false};
      process.exitCode = 1;
    }
    const output = new URL('../../artifacts/verification/PRIVY_APP_SETTINGS.json', import.meta.url);
    await mkdir(new URL('.', output), {recursive: true});
    await writeFile(output, JSON.stringify(evidence, null, 2) + '\n');
    console.log(JSON.stringify(evidence));
  }
}
