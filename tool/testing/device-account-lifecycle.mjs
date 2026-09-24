#!/usr/bin/env node
/**
 * Device account-lifecycle harness.
 *
 * Runs the real Trimmy office on a fresh, dedicated Android emulator
 * against the local secure runtime's TLS-only database, through a second API
 * instance whose verifier trusts a test key generated here. The device build
 * signs in with locally signed tokens for two fake subjects, so everything
 * after the provider callback is exercised for real: HTTPS to the API,
 * account provisioning in PostgreSQL, progress sync, renewal failure and
 * recovery, sign-out, a second account, restore, an offline cold reopen and a
 * process relaunch. The Privy round trip itself is deliberately not part of
 * this harness. Tokens exist in a private temporary file and the test APK;
 * never use that APK as the normal app. Raw child logs are not forwarded.
 * Physical devices and emulators with an installed Trimmy app are refused.
 *
 * Usage: node tool/testing/device-account-lifecycle.mjs --device emulator-5554
 * Requires: runtime initialized and started (npm run runtime:start), Flutter
 * on PATH, adb reachable at ~/Library/Android/sdk/platform-tools/adb.
 */
import { spawn } from 'node:child_process';
import { generateKeyPairSync, randomBytes, sign } from 'node:crypto';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { request as httpsRequest } from 'node:https';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile as execFileCallback } from 'node:child_process';
import { promisify } from 'node:util';
import { escapeVerificationKey, ownerQueryRows, parseApiEnv, runtimePaths } from '../runtime/local-secure-runtime.mjs';

const execFile = promisify(execFileCallback);
const projectDir = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const mobileDir = join(projectDir, 'apps', 'mobile');
const adb = join(homedir(), 'Library', 'Android', 'sdk', 'platform-tools', 'adb');
const flutter = process.env.FLUTTER_BIN ?? join(homedir(), 'Development', 'flutter', 'bin', 'flutter');
const APP_ID = 'trimmy-device-lifecycle';
// Fresh subjects per run: the server's identity mapping is immutable, so a
// reused subject would restore an earlier run's progress instead of starting empty.
const RUN_ID = randomBytes(4).toString('hex');
const SUBJECT_A = `did:privy:dl${RUN_ID}A`;
const SUBJECT_B = `did:privy:dl${RUN_ID}B`;
const API_PORT = 4444;
export const PRODUCTION_PACKAGE = 'com.trimmy.trimmy';

export class LifecycleHarnessError extends Error {}

/** Read-only guard. Naming an emulator is insufficient: Android must confirm it. */
export async function assertDedicatedEmulator(serial, {runCommand = execFile, adbPath = adb} = {}) {
  if (typeof serial !== 'string' || !/^emulator-[0-9]+$/.test(serial)) {
    throw new LifecycleHarnessError('Lifecycle tests require a fresh dedicated Android emulator. Physical devices are refused.');
  }
  const run = async args => {
    try {
      const result = await runCommand(adbPath, args, {maxBuffer: 1 << 20, timeout: 10000});
      if (typeof result.stdout !== 'string' || (typeof result.stderr === 'string' && result.stderr.trim())) throw new Error();
      return result.stdout.trim();
    } catch {
      throw new LifecycleHarnessError('Could not verify the emulator and its installed packages. Nothing was installed.');
    }
  };
  const devices = (await run(['devices'])).split(/\r?\n/).map(line => line.trim().split(/\s+/));
  if (!devices.some(([id, state]) => id === serial && state === 'device')) {
    throw new LifecycleHarnessError('The requested emulator is not attached and ready. Nothing was installed.');
  }
  if (await run(['-s', serial, 'shell', 'getprop', 'ro.kernel.qemu']) !== '1') {
    throw new LifecycleHarnessError('Android did not positively identify this device as an emulator. Nothing was installed.');
  }
  // Include uninstalled packages retaining data and every Android user. An
  // empty or malformed listing is not proof that the production app is absent.
  const packages = (await run(['-s', serial, 'shell', 'pm', 'list', 'packages', '-u'])).split(/\r?\n/);
  if (!packages.length || packages.some(line => !/^package:[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*$/.test(line))) {
    throw new LifecycleHarnessError('Could not verify the emulator package inventory. Nothing was installed.');
  }
  if (packages.includes(`package:${PRODUCTION_PACKAGE}`)) {
    throw new LifecycleHarnessError('Trimmy already exists on this emulator. Use a fresh dedicated emulator; existing app data will not be overwritten.');
  }
  return Object.freeze({serial, emulator: true, productionPackageAbsent: true});
}

export function lifecycleFlutterArguments(serial, definesFile) {
  return ['test', 'integration_test/account_lifecycle_test.dart', '-d', serial,
    '--no-uninstall', '--dart-define-from-file', definesFile];
}

export function lifecycleFlutterEnvironment(environment = process.env) {
  const allowed = ['PATH', 'HOME', 'USER', 'LOGNAME', 'TMPDIR', 'SHELL', 'JAVA_HOME',
    'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'FLUTTER_ROOT', 'PUB_CACHE', 'LANG', 'LC_ALL', 'TERM'];
  return Object.fromEntries(allowed.filter(key => typeof environment[key] === 'string').map(key => [key, environment[key]]));
}

/** Persist only the documented non-secret evidence shape, never arbitrary logs. */
export function lifecycleResult(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const result = {};
  const uuid = input => typeof input === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(input);
  const activity = input => typeof input === 'string' && /^[a-z0-9-]{1,80}$/.test(input);
  for (const key of ['accountA', 'accountB']) if (uuid(value[key])) result[key] = value[key];
  for (const key of ['renewalFailureShown', 'accountPanelWithoutContextAdapter', 'restoredAfterSwitch',
    'relaunchRestored', 'recoveredOnline']) if (typeof value[key] === 'boolean') result[key] = value[key];
  if (Number.isSafeInteger(value.tokenReads) && value.tokenReads >= 0) result.tokenReads = value.tokenReads;
  for (const key of ['serverAfterCompletion', 'serverAfterRecovery']) {
    const progress = value[key];
    if (progress && Number.isSafeInteger(progress.revision) && progress.revision >= 0 &&
      Array.isArray(progress.completions) && progress.completions.length <= 100 && progress.completions.every(activity) &&
      (progress.active === null || activity(progress.active))) {
      result[key] = {revision: progress.revision, completions: progress.completions, active: progress.active};
    }
  }
  const offline = value.offlineReopen;
  if (offline && uuid(offline.accountId) && typeof offline.serverVerified === 'boolean' &&
    typeof offline.syncStatus === 'string' && /^[a-zA-Z]{1,40}$/.test(offline.syncStatus)) {
    result.offlineReopen = {accountId: offline.accountId, syncStatus: offline.syncStatus, serverVerified: offline.serverVerified};
  }
  return result;
}

function argValue(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function token(privateKey, subject, {expired = false} = {}) {
  const now = Math.floor(Date.now() / 1000);
  const claims = expired
    ? {iss: 'privy.io', aud: APP_ID, sub: subject, iat: now - 7200, exp: now - 3600, sid: 'device-lifecycle-expired'}
    : {iss: 'privy.io', aud: APP_ID, sub: subject, iat: now - 5, exp: now + 3600, sid: 'device-lifecycle-session'};
  const unsigned = [{alg: 'ES256', typ: 'JWT'}, claims]
    .map(value => Buffer.from(JSON.stringify(value)).toString('base64url')).join('.');
  return `${unsigned}.${sign('sha256', Buffer.from(unsigned), {key: privateKey, dsaEncoding: 'ieee-p1363'}).toString('base64url')}`;
}

function health(port, ca, path = '/health') {
  return new Promise(resolvePromise => {
    const req = httpsRequest({host: '127.0.0.1', port, path, ca, servername: 'localhost', agent: false, timeout: 3000}, response => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', chunk => { body += chunk; });
      response.on('end', () => resolvePromise({status: response.statusCode, body}));
    });
    req.on('timeout', () => { req.destroy(); resolvePromise(null); });
    req.on('error', () => resolvePromise(null));
    req.end();
  });
}

async function adbShell(serial, ...args) {
  const result = await execFile(adb, ['-s', serial, 'shell', ...args], {maxBuffer: 1 << 20});
  return result.stdout.trim();
}

export async function runFlutter(serial, definesFile, {spawnProcess = spawn, runCommand = execFile, adbPath = adb} = {}) {
  // Recheck immediately before Flutter can install, after API/token setup.
  await assertDedicatedEmulator(serial, {runCommand, adbPath});
  return new Promise((resolvePromise, reject) => {
    const child = spawnProcess(flutter, lifecycleFlutterArguments(serial, definesFile), {
      cwd: mobileDir, stdio: ['ignore', 'pipe', 'pipe'], env: lifecycleFlutterEnvironment(),
    });
    let output = '';
    const collect = chunk => { output = (output + chunk.toString()).slice(-(1 << 20)); };
    child.stdout.on('data', collect);
    child.stderr.on('data', collect);
    child.on('error', () => reject(new LifecycleHarnessError('Flutter lifecycle test could not start. Child diagnostics were withheld.')));
    child.on('close', code => {
      const line = output.split('\n').find(item => item.includes('TRIMMY_LIFECYCLE_RESULT '));
      let result = null;
      try {
        if (line) result = lifecycleResult(JSON.parse(line.slice(line.indexOf('TRIMMY_LIFECYCLE_RESULT ') + 'TRIMMY_LIFECYCLE_RESULT '.length)));
      } catch { /* Invalid or partial output is a failed run, never a raw diagnostic. */ }
      resolvePromise({code, result, passed: code === 0 && /All tests passed!/.test(output)});
    });
  });
}

async function main() {
  const serial = argValue('--device') ?? 'emulator-5554';
  await assertDedicatedEmulator(serial);
  const paths = runtimePaths(process.env.TRIMMY_RUNTIME_DIR ?? join(homedir(), '.config', 'trimmy', 'runtime'));
  if (!existsSync(paths.apiEnv)) throw new Error('Runtime is not initialized. Run npm run runtime:init first.');
  const runtimeEnv = parseApiEnv(readFileSync(paths.apiEnv, 'utf8'));
  const ca = readFileSync(paths.caCert);
  const model = await adbShell(serial, 'getprop', 'ro.product.model');
  const sdk = await adbShell(serial, 'getprop', 'ro.build.version.sdk');

  const {privateKey, publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
  const verificationKey = publicKey.export({type: 'spki', format: 'pem'}).toString();
  const api = spawn(process.execPath, [join(projectDir, 'apps', 'api', 'dist', 'index.js')], {
    cwd: projectDir,
    env: {
      PATH: process.env.PATH, HOME: process.env.HOME, HOST: '127.0.0.1', PORT: String(API_PORT), LOG_LEVEL: 'warn',
      PRIVY_APP_ID: APP_ID, PRIVY_VERIFICATION_KEY: escapeVerificationKey(verificationKey),
      PRACTICE_DATABASE_URL: runtimeEnv.PRACTICE_DATABASE_URL, PRACTICE_DATABASE_CA_FILE: runtimeEnv.PRACTICE_DATABASE_CA_FILE,
      TRIMMY_GUEST_SOURCE_MODE: runtimeEnv.TRIMMY_GUEST_SOURCE_MODE,
      TRIMMY_GUEST_SOURCE_HMAC_KEY: runtimeEnv.TRIMMY_GUEST_SOURCE_HMAC_KEY,
      ...(runtimeEnv.TRIMMY_GUEST_TRUSTED_PROXY_CIDRS
        ? {TRIMMY_GUEST_TRUSTED_PROXY_CIDRS: runtimeEnv.TRIMMY_GUEST_TRUSTED_PROXY_CIDRS} : {}),
      TRIMMY_TLS_CERT_FILE: runtimeEnv.TRIMMY_TLS_CERT_FILE, TRIMMY_TLS_KEY_FILE: runtimeEnv.TRIMMY_TLS_KEY_FILE,
    },
    stdio: ['ignore', 'ignore', 'ignore'],
  });
  const tempDir = mkdtempSync(join(tmpdir(), 'trimmy-device-lifecycle-'));
  chmodSync(tempDir, 0o700);
  const definesFile = join(tempDir, 'defines.json');
  const record = {
    schemaVersion: 1, recordedAt: new Date().toISOString(),
    scope: 'Real office UI on a fresh dedicated emulator against the local secure runtime database through a test-key API. Locally signed tokens stand in for the Privy session; the Privy callback is not exercised here.',
    device: {serial, model, androidApiLevel: Number(sdk), emulator: true, existingProductionPackageRefused: true},
    api: {origin: `https://10.0.2.2:${API_PORT}`, verifier: 'ephemeral P-256 test key generated by this harness', appId: APP_ID, accountContextEnabled: false},
    runId: RUN_ID, subjects: [SUBJECT_A, SUBJECT_B], run: null, database: null, passed: false,
  };
  try {
    let ready = null;
    for (let attempt = 0; attempt < 40 && !ready; attempt++) {
      ready = await health(API_PORT, ca);
      if (!ready) await new Promise(r => setTimeout(r, 500));
    }
    if (!ready || ready.status !== 200) throw new Error('Test-key API did not become healthy.');
    const config = JSON.parse((await health(API_PORT, ca, '/v1/config')).body);
    if (!config.practiceAccountsEnabled) throw new Error('Practice accounts are not enabled on the test-key API.');

    const defines = {
      TRIMMY_LIFECYCLE_API_URL: `https://10.0.2.2:${API_PORT}`,
      TRIMMY_LIFECYCLE_CA_BASE64: ca.toString('base64'),
      TRIMMY_LIFECYCLE_APP_ID: APP_ID,
      TRIMMY_LIFECYCLE_SUBJECT_A: SUBJECT_A, TRIMMY_LIFECYCLE_SUBJECT_B: SUBJECT_B,
      TRIMMY_LIFECYCLE_TOKEN_A: token(privateKey, SUBJECT_A), TRIMMY_LIFECYCLE_TOKEN_B: token(privateKey, SUBJECT_B),
      TRIMMY_LIFECYCLE_EXPIRED_A: token(privateKey, SUBJECT_A, {expired: true}),
    };
    writeFileSync(definesFile, JSON.stringify(defines), {mode: 0o600});

    // The whole lifecycle runs in one app process so the real SharedPreferences
    // plugin persists across the simulated relaunches inside the test.
    const run = await runFlutter(serial, definesFile);
    record.run = {passed: run.passed, result: run.result};
    if (!run.passed || !run.result?.accountA) throw new Error('Device lifecycle run failed.');

    const rows = await ownerQueryRows(paths, [
      `SELECT 'lifecycle_identities' AS item, count(*)::text AS value FROM trimmy.practice_auth_identities WHERE app_id = '${APP_ID}' AND subject LIKE 'did:privy:dl${RUN_ID}%'`,
      `UNION ALL SELECT 'lifecycle_progress_rows', count(*)::text FROM trimmy.practice_progress p JOIN trimmy.practice_auth_identities i ON i.user_id = p.user_id WHERE i.app_id = '${APP_ID}' AND i.subject LIKE 'did:privy:dl${RUN_ID}%'`,
      `UNION ALL SELECT 'lifecycle_receipts', count(*)::text FROM trimmy.practice_mutation_receipts r JOIN trimmy.practice_auth_identities i ON i.user_id = r.user_id WHERE i.app_id = '${APP_ID}' AND i.subject LIKE 'did:privy:dl${RUN_ID}%'`,
      `UNION ALL SELECT 'lifecycle_max_revision', coalesce(max(p.revision), 0)::text FROM trimmy.practice_progress p JOIN trimmy.practice_auth_identities i ON i.user_id = p.user_id WHERE i.app_id = '${APP_ID}' AND i.subject LIKE 'did:privy:dl${RUN_ID}%'`,
    ].join(' '));
    record.database = Object.fromEntries(rows.map(([item, value]) => [item, value]));
    record.passed = true;
  } finally {
    api.kill('SIGTERM');
    rmSync(tempDir, {recursive: true, force: true});
    const out = join(projectDir, 'artifacts', 'verification', 'DEVICE_ACCOUNT_LIFECYCLE.json');
    writeFileSync(out, `${JSON.stringify(record, null, 2)}\n`);
    console.log(`\nRecorded ${out} (passed=${record.passed}).`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(error instanceof LifecycleHarnessError ? error.message : 'Lifecycle verification failed. Private child diagnostics were withheld.');
    process.exitCode = 1;
  });
}
