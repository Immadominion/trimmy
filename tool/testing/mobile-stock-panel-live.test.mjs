import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

import {assertStockPanelEmulator, isolateAndroidIdentity} from './mobile-stock-panel-live.mjs';

const runner = fileURLToPath(new URL('./mobile-stock-panel-live.mjs', import.meta.url));
const app = 'com.trimmy.trimmy.stockcheck';
const device = 'emulator-5582';

// These executable tripwires exercise the process boundary without adb,
// Flutter, Android, credentials, a provider, or an attached device.
function fixture(t, apkPackage = app) {
  const dir = mkdtempSync(join(tmpdir(), 'trimmy-panel-guard-test-'));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  const forwarded = join(dir, 'forwarded.jsonl');
  const adb = join(dir, 'adb-tripwire');
  const aapt = join(dir, 'aapt-fixture');
  const apk = join(dir, 'app-debug.apk');
  const log = join(dir, 'guard.jsonl');
  writeFileSync(adb, `#!/usr/bin/env node\nrequire('node:fs').appendFileSync(${JSON.stringify(forwarded)},JSON.stringify(process.argv.slice(2))+'\\n');\n`, {mode: 0o755});
  writeFileSync(aapt, `#!/usr/bin/env node\nconst data=JSON.parse(require('node:fs').readFileSync(process.argv.at(-1),'utf8'));\nconsole.log("package: name='"+data.package+"' versionCode='1'");\nconsole.log("launchable-activity: name='"+data.activity+"'");\n`, {mode: 0o755});
  writeFileSync(apk, JSON.stringify({package: apkPackage, activity: `${apkPackage}.MainActivity`}));
  const config = join(dir, 'guard-config.json');
  writeFileSync(config, JSON.stringify({adb, aapt, apk, device, log}));
  const run = args => spawnSync(process.execPath, [runner, '--guard-adb', config, ...args], {encoding: 'utf8', timeout: 5000});
  return {dir, forwarded, adb, config, apk, log, run};
}

function emulatorCommands({state = 'device', qemu = '1', failure, stderr = ''} = {}) {
  const calls = [];
  return {
    calls,
    runCommand: async (binary, args) => {
      calls.push({binary, args});
      if (failure) throw new Error('private command diagnostic');
      if (args.join(' ') === 'devices') return {stdout: `List of devices attached\n${device}\t${state}\n`, stderr};
      if (args.slice(2).join(' ') === 'shell getprop ro.kernel.qemu') return {stdout: qemu, stderr};
      throw new Error('Unexpected command');
    },
  };
}

test('stock panel preflight accepts only a ready positively identified emulator', async () => {
  const f = emulatorCommands();
  assert.deepEqual(await assertStockPanelEmulator(device, {runCommand: f.runCommand, adbPath: '/fake/adb'}), {serial: device, emulator: true});
  assert.deepEqual(f.calls.map(call => call.args), [
    ['devices'],
    ['-s', device, 'shell', 'getprop', 'ro.kernel.qemu'],
  ]);
});

test('stock panel preflight rejects physical selectors before any command', async () => {
  for (const serial of ['SEEKER_SERIAL', '192.0.2.1:5555', 'emulator-5582 extra', '', undefined]) {
    const f = emulatorCommands();
    await assert.rejects(assertStockPanelEmulator(serial, f), /Physical devices are refused/u);
    assert.equal(f.calls.length, 0);
  }
});

test('stock panel CLI refuses a physical serial before invoking ADB or Flutter', t => {
  const f = fixture(t);
  const result = spawnSync(process.execPath, [runner, '--api-url', 'https://api.example.test', '--device', 'SEEKER_SERIAL'], {
    encoding: 'utf8', timeout: 5000,
    env: {...process.env, ADB_BIN: f.adb, FLUTTER_BIN: f.adb},
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Physical devices are refused/u);
  assert.equal(existsSync(f.forwarded), false);
});

test('an emulator-shaped serial cannot pass without ro.kernel.qemu=1', async () => {
  for (const qemu of ['', '0', 'true', '1\n0', 'error: permission denied']) {
    const f = emulatorCommands({qemu});
    await assert.rejects(assertStockPanelEmulator(device, f), /positively identify/u);
    assert.equal(f.calls.length, 2);
  }
});

test('stock panel preflight fails closed on unavailable or failed device probes', async () => {
  for (const state of ['offline', 'unauthorized', 'device-extra']) {
    const f = emulatorCommands({state});
    await assert.rejects(assertStockPanelEmulator(device, f), /not attached and ready/u);
    assert.equal(f.calls.length, 1);
  }
  for (const options of [{failure: true}, {stderr: 'Error: incomplete inventory'}]) {
    await assert.rejects(assertStockPanelEmulator(device, emulatorCommands(options)), error => {
      assert.match(error.message, /Cannot verify/u);
      assert.doesNotMatch(error.message, /private/u);
      return true;
    });
  }
});

test('stock panel ADB proxy also refuses a physical target before inventory', t => {
  const f = fixture(t);
  const config = JSON.parse(readFileSync(f.config, 'utf8'));
  writeFileSync(f.config, JSON.stringify({...config, device: 'SEEKER_SERIAL'}));
  assert.equal(f.run(['devices']).status, 1);
  assert.equal(existsSync(f.forwarded), false);
});

for (const [name, command] of [
  ['production uninstall', ['uninstall', 'com.trimmy.trimmy']],
  ['any automatic uninstall', ['uninstall', app]],
  ['production data clear', ['shell', 'pm', 'clear', 'com.trimmy.trimmy']],
  ['production force-stop', ['shell', 'am', 'force-stop', 'com.trimmy.trimmy']],
  ['production launch', ['shell', 'am', 'start', '-n', 'com.trimmy.trimmy/com.trimmy.trimmy.MainActivity']],
  ['second launch target overriding the isolated component', ['shell', 'am', 'start', '-n', `${app}/${app}.MainActivity`, '-n', 'com.trimmy.trimmy/com.trimmy.trimmy.MainActivity']],
  ['launch selector overriding the isolated component', ['shell', 'am', 'start', '-n', `${app}/${app}.MainActivity`, '--selector', '-p', 'com.trimmy.trimmy']],
  ['production sandbox access from Flutter', ['shell', 'run-as', 'com.trimmy.trimmy', 'ls']],
  ['unknown mutation', ['reboot']],
  ['shell injection through getprop', ['shell', 'getprop', 'x;rm -rf y']],
]) {
  test(`stock panel guard blocks ${name} before executing adb`, t => {
    const f = fixture(t);
    const result = f.run(['-s', device, ...command]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /guard refused/u);
    assert.equal(existsSync(f.forwarded), false);
    assert.equal(JSON.parse(readFileSync(f.log, 'utf8')).allowed, false);
  });
}

test('stock panel guard rejects another device before even a read', t => {
  const f = fixture(t);
  assert.equal(f.run(['-s', 'not-the-target', 'shell', 'getprop']).status, 1);
  assert.equal(existsSync(f.forwarded), false);
});

test('stock panel guard inspects APK metadata and rejects production bytes', t => {
  const f = fixture(t, 'com.trimmy.trimmy');
  const result = f.run(['-s', device, 'install', '-t', '-r', f.apk]);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /APK identity verification failed/u);
  assert.equal(existsSync(f.forwarded), false);
});

test('stock panel guard rejects an unexpected launcher in a stockcheck APK', t => {
  const f = fixture(t);
  writeFileSync(f.apk, JSON.stringify({package: app, activity: 'com.trimmy.trimmy.MainActivity'}));
  assert.equal(f.run(['-s', device, 'install', '-t', '-r', f.apk]).status, 1);
  assert.equal(existsSync(f.forwarded), false);
});

test('stock panel guard permits only the verified APK, including canonical path aliases', t => {
  const f = fixture(t);
  const alias = join(f.dir, 'canonical-alias.apk');
  symlinkSync(f.apk, alias);
  assert.equal(f.run(['-s', device, 'install', '-t', '-r', alias]).status, 0);
  assert.equal(JSON.parse(readFileSync(f.forwarded, 'utf8')).at(-1), alias);
  assert.match(readFileSync(f.log, 'utf8'), /APK identity verified immediately before install/u);
});

test('stock panel guard permits Flutter current isolated launcher and quoted log timestamp', t => {
  const f = fixture(t);
  for (const command of [
    ['shell', 'am', 'start', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER', '-f', '0x20000000', '--ez', 'enable-checked-mode', 'true', `${app}/${app}.MainActivity`],
    ['shell', 'am', 'force-stop', app],
    ['shell', '-x', 'logcat', '-v', 'time', '-T', "'09-17 01:29:36.948'"],
  ]) assert.equal(f.run(['-s', device, ...command]).status, 0);
  assert.equal(readFileSync(f.forwarded, 'utf8').trim().split('\n').length, 3);
});

test('prebuild Flutter namespace fallback, built ID, launcher and Kotlin all resolve to stockcheck', t => {
  const dir = mkdtempSync(join(tmpdir(), 'trimmy-panel-package-test-'));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  const put = (path, text) => { const target = join(dir, path); mkdirSync(dirname(target), {recursive: true}); writeFileSync(target, text); };
  put('android/app/build.gradle.kts', 'android {\nnamespace = "com.trimmy.trimmy"\ndefaultConfig { applicationId = "com.trimmy.trimmy" }\n}\n');
  put('android/app/src/main/AndroidManifest.xml', '<manifest><application android:label="Trimmy"><activity android:name=".MainActivity"/><data android:scheme="com.trimmy.trimmy.privy"/></application></manifest>');
  put('android/app/src/main/kotlin/com/trimmy/trimmy/MainActivity.kt', 'package com.trimmy.trimmy\nclass MainActivity\n');
  isolateAndroidIdentity(dir);
  const gradle = readFileSync(join(dir, 'android/app/build.gradle.kts'), 'utf8');
  // Flutter reads namespace before an APK exists. This is the historical
  // cleanup regression: changing applicationId alone was insufficient.
  assert.equal(gradle.match(/namespace = "([^"]+)"/u)?.[1], app);
  assert.equal(gradle.match(/applicationId = "([^"]+)"/u)?.[1], app);
  const manifest = readFileSync(join(dir, 'android/app/src/main/AndroidManifest.xml'), 'utf8');
  assert(manifest.includes(`android:name="${app}.MainActivity"`));
  assert(manifest.includes(`android:scheme="${app}.privy"`));
  assert.equal(existsSync(join(dir, 'android/app/src/main/kotlin/com/trimmy/trimmy/MainActivity.kt')), false);
  assert(readFileSync(join(dir, 'android/app/src/main/kotlin/com/trimmy/trimmy/stockcheck/MainActivity.kt'), 'utf8').startsWith(`package ${app}\n`));
});

test('package isolation refuses unknown source identities instead of continuing', t => {
  const dir = mkdtempSync(join(tmpdir(), 'trimmy-panel-identity-refusal-'));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  mkdirSync(join(dir, 'android/app'), {recursive: true});
  writeFileSync(join(dir, 'android/app/build.gradle.kts'), 'applicationId = "unexpected.app"\n');
  assert.throws(() => isolateAndroidIdentity(dir), /Isolation substitution no longer matches/u);
});
