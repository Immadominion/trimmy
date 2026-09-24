import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {PassThrough} from 'node:stream';
import test from 'node:test';
import {
  assertDedicatedEmulator, lifecycleFlutterArguments, lifecycleFlutterEnvironment,
  lifecycleResult, PRODUCTION_PACKAGE, runFlutter,
} from './device-account-lifecycle.mjs';

function commands({state = 'device', qemu = '1', packages = 'package:android\npackage:com.android.settings\n', failure, packageError = ''} = {}) {
  const calls = [];
  return {
    calls,
    runCommand: async (binary, args) => {
      calls.push({binary, args});
      if (failure) throw new Error('private command diagnostic with a token');
      if (args.join(' ') === 'devices') return {stdout: `List of devices attached\nemulator-5554\t${state}\n`};
      if (args.slice(2).join(' ') === 'shell getprop ro.kernel.qemu') return {stdout: qemu};
      if (args.slice(2).join(' ') === 'shell pm list packages -u') return {stdout: packages, stderr: packageError};
      throw new Error('Unexpected command');
    },
  };
}

test('a ready dedicated emulator with no retained Trimmy package passes only read-only probes', async () => {
  const fixture = commands();
  const result = await assertDedicatedEmulator('emulator-5554', {runCommand: fixture.runCommand, adbPath: '/fake/adb'});
  assert.deepEqual(result, {serial: 'emulator-5554', emulator: true, productionPackageAbsent: true});
  assert.deepEqual(fixture.calls.map(call => call.args), [
    ['devices'],
    ['-s', 'emulator-5554', 'shell', 'getprop', 'ro.kernel.qemu'],
    ['-s', 'emulator-5554', 'shell', 'pm', 'list', 'packages', '-u'],
  ]);
});

test('physical device selectors are refused before any command', async () => {
  for (const serial of ['SEEKER_SERIAL', '192.0.2.1:5555', 'emulator-5554 extra', '', undefined]) {
    const fixture = commands();
    await assert.rejects(assertDedicatedEmulator(serial, fixture), /Physical devices are refused/);
    assert.equal(fixture.calls.length, 0);
  }
});

test('an emulator-shaped name is insufficient without positive Android identification', async () => {
  for (const qemu of ['', '0', 'true', '1\n0', 'error: permission denied']) {
    const fixture = commands({qemu});
    await assert.rejects(assertDedicatedEmulator('emulator-5554', fixture), /positively identify/);
    assert.equal(fixture.calls.length, 2);
  }
});

test('offline, unauthorized and failed inventory queries fail closed', async () => {
  for (const state of ['offline', 'unauthorized', 'device-extra']) {
    const fixture = commands({state});
    await assert.rejects(assertDedicatedEmulator('emulator-5554', fixture), /not attached and ready/);
    assert.equal(fixture.calls.length, 1);
  }
  await assert.rejects(assertDedicatedEmulator('emulator-5554', commands({failure: true})), error => {
    assert.match(error.message, /Could not verify/);
    assert.doesNotMatch(error.message, /private|token/);
    return true;
  });
});

test('production package or retained app data refuses reuse of an emulator', async () => {
  const fixture = commands({packages: `package:com.android.settings\npackage:${PRODUCTION_PACKAGE}\n`});
  await assert.rejects(assertDedicatedEmulator('emulator-5554', fixture), /Trimmy already exists/);
});

test('empty, partial and malformed package inventories are not absence evidence', async () => {
  for (const packages of ['', 'Error: unknown option', 'package:com.android.settings\nWarning: omitted packages', 'package:']) {
    await assert.rejects(assertDedicatedEmulator('emulator-5554', commands({packages})), /package inventory/);
  }
});

test('package-manager errors on stderr reject a partial successful inventory', async () => {
  await assert.rejects(assertDedicatedEmulator('emulator-5554', commands({
    packageError: 'Error: could not list another Android user',
  })), /Could not verify/);
});

test('Flutter cannot launch after a failed final device or package guard', async () => {
  for (const [serial, fixture] of [
    ['SEEKER_SERIAL', commands()],
    ['emulator-5554', commands({qemu: '0'})],
    ['emulator-5554', commands({packages: `package:${PRODUCTION_PACKAGE}`})],
  ]) {
    let spawned = false;
    await assert.rejects(runFlutter(serial, '/private/defines.json', {
      runCommand: fixture.runCommand,
      spawnProcess: () => { spawned = true; throw new Error('must not spawn'); },
    }));
    assert.equal(spawned, false);
  }
});

test('guarded Flutter launch preserves the package and withholds raw child diagnostics', async () => {
  const fixture = commands();
  const result = await runFlutter('emulator-5554', '/private/defines.json', {
    runCommand: fixture.runCommand,
    spawnProcess: (binary, args, options) => {
      assert.equal(fixture.calls.length, 3, 'all device checks precede Flutter');
      assert.deepEqual(args, lifecycleFlutterArguments('emulator-5554', '/private/defines.json'));
      assert.ok(args.includes('--no-uninstall'));
      assert.deepEqual(options.stdio, ['ignore', 'pipe', 'pipe']);
      const child = new EventEmitter();
      child.stdout = new PassThrough();
      child.stderr = new PassThrough();
      queueMicrotask(() => {
        child.stderr.write('a private token must never be forwarded\n');
        child.stdout.write('TRIMMY_LIFECYCLE_RESULT {"accountA":"12345678-1234-1234-1234-123456789abc","token":"private token"}\nAll tests passed!\n');
        child.emit('close', 0);
      });
      return child;
    },
  });
  assert.deepEqual(result, {code: 0, result: {accountA: '12345678-1234-1234-1234-123456789abc'}, passed: true});
  assert.doesNotMatch(JSON.stringify(result), /private token/);
});

test('only build environment keys are inherited and evidence fields remain constrained', () => {
  assert.deepEqual(lifecycleFlutterEnvironment({PATH: '/bin', HOME: '/home/test', JAVA_HOME: '/jdk',
    PRIVY_APP_SECRET: 'secret', TRIMMY_LIFECYCLE_TOKEN_A: 'token', DART_DEFINES: 'encoded-token'}),
  {PATH: '/bin', HOME: '/home/test', JAVA_HOME: '/jdk'});
  assert.deepEqual(lifecycleResult({accountA: 'ey.fake.token', tokenReads: -1,
    serverAfterRecovery: {revision: 2, active: 'ey.fake.token', completions: []},
    offlineReopen: {accountId: 'ey.fake.token', serverVerified: true, syncStatus: 'saved'}}), {});
});

test('invalid result output fails without leaking or throwing raw parser diagnostics', async () => {
  const fixture = commands();
  const result = await runFlutter('emulator-5554', '/private/defines.json', {
    runCommand: fixture.runCommand,
    spawnProcess: () => {
      const child = new EventEmitter();
      child.stdout = new PassThrough();
      child.stderr = new PassThrough();
      queueMicrotask(() => {
        child.stdout.write('TRIMMY_LIFECYCLE_RESULT secret malformed value\n');
        child.emit('close', 1);
      });
      return child;
    },
  });
  assert.deepEqual(result, {code: 1, result: null, passed: false});
});
