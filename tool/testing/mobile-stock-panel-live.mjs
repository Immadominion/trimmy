#!/usr/bin/env node
/**
 * Real Android emulator discovery-panel check through an explicit HTTPS API.
 *
 * PATH="$HOME/Development/flutter/bin:$PATH" node tool/testing/mobile-stock-panel-live.mjs \
 *   --api-url https://YOUR-API-ORIGIN --device emulator-5582
 *
 * Two UI-triggered reads: Apple search, then Apple's versions. No mocks,
 * credentials, account sign-in, quotes, orders, or production-app navigation.
 * Physical devices are refused before any ADB call. Android must positively
 * identify the selected emulator before build or installation can proceed.
 * Namespace, Kotlin package, application ID, label and callback are isolated.
 * A private SDK proxy rejects device mutations outside stockcheck, verifies
 * every APK before install, and disables Flutter's automatic uninstall.
 * Main-app package identity and a dedicated debug sandbox marker are compared
 * before and after. No login files or normal app preferences are read.
 * The dedicated stockcheck app may remain installed after the test.
 * FLUTTER_BIN and ADB_BIN can override the local executable paths.
 */
import {spawn, spawnSync, execFile as execFileCallback} from 'node:child_process';
import {createHash} from 'node:crypto';
import {appendFileSync, chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, renameSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {homedir, tmpdir} from 'node:os';
import {basename, dirname, join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';

const execFile = promisify(execFileCallback);
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const source = join(root, 'apps/mobile');
const testFile = 'integration_test/stock_discovery_panel_live_test.dart';
const packageId = 'com.trimmy.trimmy.stockcheck';
const protectedPackage = 'com.trimmy.trimmy';
const sandboxMarker = 'files/trimmy_stockcheck_isolation.marker';
const marker = 'TRIMMY_STOCK_DISCOVERY_PANEL_RESULT ';
const flutter = process.env.FLUTTER_BIN || 'flutter';
const adb = process.env.ADB_BIN || join(homedir(), 'Library/Android/sdk/platform-tools/adb');

export function apkIdentity(apk, aapt) {
  const result = spawnSync(aapt, ['dump', 'badging', apk], {encoding: 'utf8', timeout: 15000});
  if (result.status !== 0) throw new Error('Cannot inspect the APK package before installation.');
  const id = result.stdout.match(/^package: name='([^']+)'/mu)?.[1];
  const activity = result.stdout.match(/^launchable-activity: name='([^']+)'/mu)?.[1];
  if (id !== packageId || activity !== `${packageId}.MainActivity`) {
    throw new Error('APK package or launcher is not the isolated stockcheck identity.');
  }
  return {package: id, launchActivity: activity, sha256: createHash('sha256').update(readFileSync(apk)).digest('hex')};
}

function isolatedLaunch(shell) {
  const component = `${packageId}/${packageId}.MainActivity`;
  let targets = 0;
  for (let index = 2; index < shell.length;) {
    const option = shell[index++];
    if (option === component && index === shell.length) { targets++; continue; }
    if (option === '-n' && shell[index++] === component) { targets++; continue; }
    if (option === '-a' && shell[index++] === 'android.intent.action.MAIN') continue;
    if (option === '-c' && shell[index++] === 'android.intent.category.LAUNCHER') continue;
    if (option === '-f' && shell[index++] === '0x20000000') continue;
    if (option === '--ez' && /^[a-z][a-z0-9-]*$/u.test(shell[index++] ?? '') && ['true', 'false'].includes(shell[index++])) continue;
    return false;
  }
  return targets === 1;
}

// Called only by the generated SDK's adb executable. Unknown operations fail
// closed; the real adb is never invoked for a rejected request.
async function guardAdb(configPath, args) {
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  const audit = (allowed, reason) => appendFileSync(config.log, `${JSON.stringify({at: new Date().toISOString(), allowed, reason, args})}\n`);
  const deny = reason => { audit(false, reason); throw new Error(`Stockcheck adb guard refused: ${reason}`); };
  if (!/^emulator-[0-9]+$/u.test(config.device ?? '')) deny('physical device selectors are forbidden');
  if (args[0] === 'devices' && args.slice(1).every(arg => arg === '-l')) {
    const result = spawnSync(config.adb, args, {encoding: 'utf8', timeout: 10000});
    audit(result.status === 0, 'device inventory filtered to explicit target');
    process.stdout.write(result.stdout.split(/\r?\n/u).filter(line => line.startsWith('List of devices') || line.split(/\s/u)[0] === config.device).join('\n') + '\n');
    process.stderr.write(result.stderr); process.exitCode = result.status ?? 1; return;
  }
  const globalRead = args.length === 1 && ['version', 'start-server'].includes(args[0]);
  if (!globalRead && (args[0] !== '-s' || args[1] !== config.device)) deny('only the explicit device is permitted');
  const command = globalRead ? args : args.slice(2);
  const hashPath = `/data/local/tmp/sky.${packageId}.sha1`;
  let allowed = globalRead || command.join(' ') === 'get-state';
  if (command[0] === 'install') {
    if (command.length !== 4 || command[1] !== '-t' || command[2] !== '-r' || !existsSync(command[3]) || realpathSync(command[3]) !== realpathSync(config.apk)) deny('unexpected install arguments');
    try { apkIdentity(config.apk, config.aapt); } catch { deny('APK identity verification failed'); }
    allowed = true;
  }
  if (command[0] === 'forward') {
    allowed = command.length === 2 && command[1] === '--list'
      || command.length === 3 && command[1] === '--remove' && /^tcp:\d+$/u.test(command[2])
      || command.length === 3 && command.slice(1).every(arg => /^tcp:\d+$/u.test(arg));
  }
  if (command[0] === 'shell') {
    const shell = command.slice(1);
    const plain = shell.join(' ');
    allowed = shell[0] === 'getprop' && shell.length <= 2 && shell.slice(1).every(arg => /^[A-Za-z0-9_.-]+$/u.test(arg))
      || plain === `pm list packages ${packageId}`
      || plain === `am force-stop ${packageId}`
      || plain === `cat ${hashPath}`
      || shell.length === 5 && shell[0] === 'echo' && shell[1] === '-n' && /^[a-f0-9]{40}$/u.test(shell[2]) && shell[3] === '>' && shell[4] === hashPath
      || shell[0] === '-x' && shell[1] === 'logcat' && shell.slice(2).every(arg => /^[A-Za-z0-9_.:*+-]+$/u.test(arg) || /^'\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}'$/u.test(arg));
    if (shell[0] === 'am' && shell[1] === 'start') {
      allowed = isolatedLaunch(shell);
    }
  }
  if (!allowed) deny('operation is outside the isolated package allowlist');
  audit(true, command[0] === 'install' ? 'APK identity verified immediately before install' : 'allowlisted operation');
  await new Promise((resolveChild, reject) => {
    const child = spawn(config.adb, args, {stdio: 'inherit'});
    const stop = () => child.kill('SIGTERM');
    process.once('SIGTERM', stop); process.once('SIGINT', stop);
    child.once('error', reject);
    child.once('close', code => {
      process.removeListener('SIGTERM', stop); process.removeListener('SIGINT', stop);
      process.exitCode = code ?? 1; resolveChild();
    });
  });
}

function guardedSdk(temporary, project, device, evidence) {
  if (existsSync(join(homedir(), '.flutter_settings'))) throw new Error('Legacy Flutter settings override private SDK configuration; refusing any device test.');
  const sdk = resolve(dirname(adb), '..');
  const tools = readdirSync(join(sdk, 'build-tools')).sort((a, b) => b.localeCompare(a, undefined, {numeric: true}));
  const aapt = tools.map(version => join(sdk, 'build-tools', version, 'aapt')).find(existsSync);
  if (!aapt) throw new Error('An Android aapt binary is required to verify APK identity.');
  const proxy = join(temporary, 'android-sdk');
  mkdirSync(join(proxy, 'platform-tools'), {recursive: true});
  for (const name of readdirSync(sdk)) if (name !== 'platform-tools') symlinkSync(join(sdk, name), join(proxy, name));
  for (const name of readdirSync(join(sdk, 'platform-tools'))) if (name !== 'adb') symlinkSync(join(sdk, 'platform-tools', name), join(proxy, 'platform-tools', name));
  const apk = join(project, 'build/app/outputs/flutter-apk/app-debug.apk');
  const configFile = join(temporary, 'adb-guard.json');
  const guardLog = join(evidence, 'adb-guard.jsonl');
  writeFileSync(guardLog, '', {mode: 0o600});
  writeFileSync(configFile, JSON.stringify({adb, aapt, apk, device, log: guardLog}), {mode: 0o600});
  const wrapper = join(proxy, 'platform-tools/adb');
  writeFileSync(wrapper, `#!/usr/bin/env node\nconst {spawn}=require('node:child_process');\nconst child=spawn(${JSON.stringify(process.execPath)},[${JSON.stringify(fileURLToPath(import.meta.url))},'--guard-adb',${JSON.stringify(configFile)},...process.argv.slice(2)],{stdio:'inherit'});\nprocess.once('SIGTERM',()=>child.kill('SIGTERM'));process.once('SIGINT',()=>child.kill('SIGTERM'));\nchild.on('error',()=>process.exit(1));child.on('close',code=>process.exit(code??1));\n`, {mode: 0o755});
  chmodSync(wrapper, 0o755);
  const configDir = join(temporary, 'flutter-config');
  mkdirSync(configDir);
  writeFileSync(join(configDir, 'settings'), JSON.stringify({'android-sdk': proxy}));
  const local = join(project, 'android/local.properties');
  const existing = existsSync(local) ? readFileSync(local, 'utf8').split('\n').filter(line => !line.startsWith('sdk.dir=')) : [];
  writeFileSync(local, [...existing, `sdk.dir=${proxy}`, ''].join('\n'));
  // AGP also uses XDG_CONFIG_HOME to locate its default debug keystore. Keep
  // Android's normal developer directory stable while isolating Flutter's SDK
  // setting, otherwise every run silently gets a new signing certificate.
  const androidUserHome = process.env.ANDROID_USER_HOME || join(homedir(), '.android');
  return {aapt, apk, guardLog, environment: {...process.env, TERM: 'dumb', ANDROID_HOME: proxy, ANDROID_SDK_ROOT: proxy, ANDROID_USER_HOME: androidUserHome, XDG_CONFIG_HOME: configDir}};
}

async function protectedIdentity(device) {
  const {stdout} = await execFile(adb, ['-s', device, 'shell', 'dumpsys', 'package', protectedPackage], {timeout: 10000, maxBuffer: 1 << 20});
  const value = name => stdout.match(new RegExp(`^\\s*${name}=([^\\n]+)`, 'mu'))?.[1]?.trim() ?? null;
  const firstInstallTime = value('firstInstallTime');
  const installed = stdout.includes(`Package [${protectedPackage}]`) && firstInstallTime !== null;
  const debuggable = /(?:pkgFlags|flags)=\[[^\]]*DEBUGGABLE/u.test(stdout);
  let markerSha256 = null;
  if (installed && debuggable) {
    try {
      const markerRead = await execFile(adb, ['-s', device, 'shell', 'run-as', protectedPackage, 'cat', sandboxMarker], {timeout: 10000, maxBuffer: 4096, encoding: 'buffer'});
      markerSha256 = createHash('sha256').update(markerRead.stdout).digest('hex');
    } catch { /* No other sandbox file is read or created by this harness. */ }
  }
  return {package: protectedPackage, installed, firstInstallTime, lastUpdateTime: value('lastUpdateTime'), versionCode: value('versionCode'), codePath: value('codePath'), debuggable, markerPath: debuggable ? sandboxMarker : null, markerSha256};
}

export async function assertStockPanelEmulator(device, {runCommand = execFile, adbPath = adb} = {}) {
  if (typeof device !== 'string' || !/^emulator-[0-9]+$/u.test(device)) {
    throw new Error('The stock panel harness is emulator-only. Physical devices are refused before any ADB call.');
  }
  const read = async args => {
    try {
      const result = await runCommand(adbPath, args, {timeout: 10000, maxBuffer: 1 << 20});
      if (typeof result.stdout !== 'string' || (typeof result.stderr === 'string' && result.stderr.trim())) throw new Error();
      return result.stdout.trim();
    } catch {
      throw new Error('Cannot verify the selected emulator. Nothing was built or installed.');
    }
  };
  const devices = await read(['devices']);
  if (!devices.split(/\r?\n/u).some(line => line.trim() === `${device}\tdevice`)) {
    throw new Error('The explicit emulator is not attached and ready. Nothing was built or installed.');
  }
  if (await read(['-s', device, 'shell', 'getprop', 'ro.kernel.qemu']) !== '1') {
    throw new Error('Android did not positively identify this device as an emulator. Nothing was built or installed.');
  }
  return {serial: device, emulator: true};
}

function argumentsForRun(args) {
  if (args.length === 1 && args[0] === '--help') return null;
  const values = new Map();
  for (let index = 0; index < args.length; index += 2) {
    const name = args[index], value = args[index + 1];
    if (!['--api-url', '--device'].includes(name) || !value || values.has(name)) {
      throw new Error('Supply --api-url HTTPS_ORIGIN and --device EXACT_ANDROID_SERIAL once each.');
    }
    values.set(name, value);
  }
  if (values.size !== 2) throw new Error('Both --api-url and --device are required; neither is selected automatically.');
  const raw = values.get('--api-url');
  let api;
  try { api = new URL(raw); } catch { throw new Error('--api-url must be an HTTPS origin.'); }
  if (raw.length > 2048 || /\s/u.test(raw) || api.protocol !== 'https:' || !api.hostname || api.username || api.password || api.search || api.hash || api.pathname !== '/' || /[?#]/u.test(raw)) {
    throw new Error('--api-url must be an HTTPS origin with no credentials, path, query or fragment.');
  }
  const device = values.get('--device');
  if (!/^[A-Za-z0-9._:-]{1,160}$/u.test(device)) throw new Error('--device must be an exact Android serial.');
  return {apiOrigin: api.origin, device};
}

function replaceOnce(path, before, after) {
  const text = readFileSync(path, 'utf8');
  if (text.split(before).length !== 2) throw new Error(`Isolation substitution no longer matches ${basename(path)}; nothing was installed.`);
  writeFileSync(path, text.replace(before, after));
}

export function isolateAndroidIdentity(project) {
  const gradle = join(project, 'android/app/build.gradle.kts');
  replaceOnce(gradle, 'applicationId = "com.trimmy.trimmy"', `applicationId = "${packageId}"`);
  replaceOnce(gradle, 'namespace = "com.trimmy.trimmy"', `namespace = "${packageId}"`);
  const manifest = join(project, 'android/app/src/main/AndroidManifest.xml');
  replaceOnce(manifest, 'android:label="Trimmy"', 'android:label="Trimmy Stock Check"');
  replaceOnce(manifest, 'android:name=".MainActivity"', `android:name="${packageId}.MainActivity"`);
  replaceOnce(manifest, 'android:scheme="com.trimmy.trimmy.privy"', `android:scheme="${packageId}.privy"`);
  const mainActivity = join(project, 'android/app/src/main/kotlin/com/trimmy/trimmy/MainActivity.kt');
  replaceOnce(mainActivity, 'package com.trimmy.trimmy\n', `package ${packageId}\n`);
  const isolatedKotlin = join(dirname(mainActivity), 'stockcheck');
  mkdirSync(isolatedKotlin);
  renameSync(mainActivity, join(isolatedKotlin, 'MainActivity.kt'));
}

function dartFiles(path) {
  return readdirSync(path, {withFileTypes: true}).flatMap(entry => {
    const child = join(path, entry.name);
    return entry.isDirectory() ? dartFiles(child) : entry.isFile() && entry.name.endsWith('.dart') ? [child] : [];
  });
}

function snapshot(project) {
  const paths = [...dartFiles(join(project, 'lib')), join(project, testFile), ...[
    'pubspec.yaml', 'pubspec.lock', 'android/app/build.gradle.kts',
    'android/app/src/main/AndroidManifest.xml',
    'android/app/src/main/kotlin/com/trimmy/trimmy/stockcheck/MainActivity.kt',
  ].map(path => join(project, path))].sort();
  const hashes = Object.fromEntries(paths.map(path => [relative(project, path), createHash('sha256').update(readFileSync(path)).digest('hex')]));
  return {sha256: createHash('sha256').update(JSON.stringify(hashes)).digest('hex'), files: hashes};
}

function runFlutter(args, project, log, signal, timeout, environment) {
  return new Promise((resolveRun, reject) => {
    const child = spawn(flutter, args, {
      cwd: project, stdio: ['ignore', 'pipe', 'pipe'], signal, timeout,
      env: environment,
    });
    let tail = '';
    const collect = chunk => {
      const text = chunk.toString();
      appendFileSync(log, text);
      process.stdout.write(text);
      tail = (tail + text).slice(-262144);
    };
    child.stdout.on('data', collect);
    child.stderr.on('data', collect);
    child.once('error', reject);
    child.once('close', (code, terminatedBy) => resolveRun({code, terminatedBy, tail}));
  });
}

async function main() {
  const input = argumentsForRun(process.argv.slice(2));
  if (!input) {
    console.log('Usage: node tool/testing/mobile-stock-panel-live.mjs --api-url HTTPS_ORIGIN --device emulator-PORT\nEmulator-only. Runs the real discovery panel in separate com.trimmy.trimmy.stockcheck. No account auth or trading is tested; physical devices are refused.');
    return;
  }
  const {apiOrigin, device} = input;
  // Reject physical selectors before even inventorying ADB, then require a
  // positive Android emulator property before any build or installation.
  const emulatorIdentity = await assertStockPanelEmulator(device);
  const [model, apiLevel] = await Promise.all([
    execFile(adb, ['-s', device, 'shell', 'getprop', 'ro.product.model'], {timeout: 10000}),
    execFile(adb, ['-s', device, 'shell', 'getprop', 'ro.build.version.sdk'], {timeout: 10000}),
  ]);
  const protectedBefore = await protectedIdentity(device);
  if (!protectedBefore.installed) throw new Error('The protected main package is missing before the test; refusing installation.');
  if (protectedBefore.debuggable && !protectedBefore.markerSha256) throw new Error(`A debug main app requires a pre-existing harmless ${sandboxMarker} to prove sandbox preservation. The runner will not create it or read other app data.`);
  const temporary = mkdtempSync(join(tmpdir(), 'trimmy-stock-panel-'));
  const project = join(temporary, 'mobile');
  const at = new Date().toISOString();
  const evidence = join(root, 'artifacts/verification/mobile-stock-panel-live', at.replace(/[:.]/gu, '-'));
  mkdirSync(evidence, {recursive: true});
  const log = join(evidence, 'flutter.log');
  writeFileSync(log, '', {mode: 0o600});
  const record = {
    schemaVersion: 1, startedAt: at, finishedAt: null, passed: false,
    scope: 'Live Android StockResearchHost and StockResearchPanel discovery harness. Not normal app navigation, account authentication, trading or a full app walkthrough.',
    apiOrigin, device: {...emulatorIdentity, model: model.stdout.trim(), androidApiLevel: Number(apiLevel.stdout.trim())},
    isolationObservedPassed: false,
    isolation: {package: packageId, namespace: packageId, label: 'Trimmy Stock Check', callbackScheme: `${packageId}.privy`, automaticUninstall: false, protectedBefore, protectedAfter: null, packageIdentityPreserved: false, debugSandboxMarkerPreserved: null, adbGuard: null},
    explicitReadBudget: ['search:Apple', 'variants:apple'], credentialsProvided: false,
    source: null, runnerSha256: createHash('sha256').update(readFileSync(fileURLToPath(import.meta.url))).digest('hex'), apkIdentity: null, result: null, error: null,
  };
  const abort = new AbortController();
  const interrupt = () => abort.abort();
  process.once('SIGINT', interrupt);
  process.once('SIGTERM', interrupt);
  try {
    const excluded = new Set(['build', '.gradle', '.cxx', '.DS_Store', '.dart_tool', 'key.properties']);
    for (const folder of ['lib', 'assets', 'android']) {
      cpSync(join(source, folder), join(project, folder), {
        recursive: true,
        filter: path => !excluded.has(basename(path)) && !/^\.env(?:\.|$)|\.(?:jks|keystore)$/u.test(basename(path)),
      });
    }
    for (const name of ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']) cpSync(join(source, name), join(project, name));
    mkdirSync(join(project, 'integration_test'));
    cpSync(join(source, testFile), join(project, testFile));
    isolateAndroidIdentity(project);
    const guard = guardedSdk(temporary, project, device, evidence);
    record.isolation.adbGuard = {log: 'adb-guard.jsonl', mode: 'private SDK proxy with explicit-device and package allowlist'};
    record.source = snapshot(project);
    console.log(`Running the isolated stock discovery panel on ${device}. Evidence: ${relative(root, evidence)}`);
    const dependencies = await runFlutter(['pub', 'get', '--offline', '--enforce-lockfile'], project, log, abort.signal, 120000, guard.environment);
    if (dependencies.code !== 0) throw new Error('Pinned offline Flutter dependency setup failed; no device test was started.');
    const defines = [`--dart-define=TRIMMY_STOCK_API_URL=${apiOrigin}`, `--dart-define=TRIMMY_STOCK_PANEL_ISOLATED=${packageId}`];
    // Flutter's test device caches package metadata before it builds. Supply a
    // verified APK beforehand, in addition to isolating every source identity.
    const build = await runFlutter(['build', 'apk', '--debug', '--no-pub', `--target=${testFile}`, '--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false', ...defines], project, log, abort.signal, 600000, guard.environment);
    if (build.code !== 0) throw new Error('Isolated APK prebuild failed; no device test was started.');
    record.apkIdentity = apkIdentity(guard.apk, guard.aapt);
    const run = await runFlutter([
      'test', testFile, '-d', device, '--no-pub', '--no-uninstall', '--reporter', 'expanded', ...defines,
    ], project, log, abort.signal, 600000, guard.environment);
    record.apkIdentity = apkIdentity(guard.apk, guard.aapt);
    const lines = run.tail.split(/\r?\n/u).filter(line => line.includes(marker));
    if (lines.length === 1) {
      try { record.result = JSON.parse(lines[0].slice(lines[0].indexOf(marker) + marker.length).trim()); } catch { /* Remain a failed run. */ }
    }
    const result = record.result;
    if (run.code !== 0 || !/All tests passed!/u.test(run.tail) || result?.passed !== true || result.package !== packageId || result.apiOrigin !== apiOrigin || JSON.stringify(result.explicitReads) !== JSON.stringify(record.explicitReadBudget) || result.executionEnabled !== false || result.ordersAttempted !== false) {
      throw new Error('The live panel check did not produce a matching success marker and successful Flutter exit. See the dated Flutter log.');
    }
    record.panelAssertionsPassed = true;
  } catch (error) {
    record.error = abort.signal.aborted ? 'Interrupted; no successful run is claimed.' : error instanceof Error ? error.message : 'Panel harness failed.';
    throw error;
  } finally {
    process.removeListener('SIGINT', interrupt);
    process.removeListener('SIGTERM', interrupt);
    try {
      record.isolation.protectedAfter = await protectedIdentity(device);
      const after = record.isolation.protectedAfter;
      record.isolation.packageIdentityPreserved = after.installed
        && ['firstInstallTime', 'lastUpdateTime', 'versionCode', 'codePath'].every(key => protectedBefore[key] === after[key]);
      record.isolation.debugSandboxMarkerPreserved = protectedBefore.debuggable
        ? protectedBefore.markerSha256 !== null && after.markerSha256 === protectedBefore.markerSha256 : null;
      record.isolationObservedPassed = record.isolation.packageIdentityPreserved
        && (!protectedBefore.debuggable || record.isolation.debugSandboxMarkerPreserved);
      record.passed = record.panelAssertionsPassed === true && record.isolationObservedPassed;
      if (!record.isolationObservedPassed) {
        record.error = 'Protected main package identity or dedicated sandbox marker changed during the harness.';
        process.exitCode = 1;
      }
    } catch {
      record.error ??= 'Cannot verify protected package identity after the harness.';
      record.passed = false; process.exitCode = 1;
    }
    record.finishedAt = new Date().toISOString();
    writeFileSync(join(evidence, 'result.json'), `${JSON.stringify(record, null, 2)}\n`, {mode: 0o600});
    rmSync(temporary, {recursive: true, force: true});
    console.log(`Panel-only evidence: ${relative(root, join(evidence, 'result.json'))} (passed=${record.passed})`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  (process.argv[2] === '--guard-adb' ? guardAdb(process.argv[3], process.argv.slice(4)) : main()).catch(error => {
    console.error(error instanceof Error ? error.message : 'The panel harness failed.');
    process.exitCode = 1;
  });
}
