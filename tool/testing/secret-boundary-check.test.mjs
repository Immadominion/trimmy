import test from 'node:test';
import assert from 'node:assert/strict';
import {chmod, link as createHardLink, mkdir, mkdtemp, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {deflateRawSync, gzipSync, brotliCompressSync} from 'node:zlib';
import {readAuditCredentials, readPrivateXFile, scanSecretBoundary, classifyPath,
  SecretBoundaryError, zipEntries} from './secret-boundary-check.mjs';

// Synthetic test values only. Never read Keychain or the real provider file.
const privateValue = 'synthetic-private-value-for-boundary-test';
const publicValue = 'synthetic-public-app-identifier';
const credentials = [
  {kind: 'privyAppId', public: true, value: publicValue},
  {kind: 'privyAppSecret', public: false, value: privateValue},
];
const storageVerification = Object.freeze({
  privateFileOwnerVerified: true,
  privateAncestorOwnersVerified: true,
  privateFileAndDirectoryPermissionsVerified: true,
  privateFileHardLinkCountVerified: true,
  privateFileOpenedInodeVerified: true,
});
async function workspace(t) {
  const root = await mkdtemp(join(tmpdir(), 'trimmy-boundary-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
}
async function put(root, path, content) {
  const file = join(root, path);
  await mkdir(dirname(file), {recursive: true});
  await writeFile(file, content);
  return file;
}
const crcTable = Array.from({length: 256}, (_, input) => {
  let value = input;
  for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ value >>> 1 : value >>> 1;
  return value >>> 0;
});
function crc32(content) {
  let value = 0xffffffff;
  for (const byte of content) value = crcTable[(value ^ byte) & 0xff] ^ value >>> 8;
  return (value ^ 0xffffffff) >>> 0;
}
function apkSigningBlock(content = Buffer.from('synthetic-signature')) {
  const pairLength = 4 + content.length;
  const declared = 8 + pairLength + 8 + 16;
  const block = Buffer.alloc(8 + declared);
  block.writeBigUInt64LE(BigInt(declared), 0);
  block.writeBigUInt64LE(BigInt(pairLength), 8);
  block.writeUInt32LE(0x7109871a, 16);
  content.copy(block, 20);
  block.writeBigUInt64LE(BigInt(declared), 20 + content.length);
  Buffer.from('APK Sig Block 42').copy(block, 28 + content.length);
  return block;
}
function zip(content, options = {}) {
  content = Buffer.from(content);
  const {method = 8, encrypted = false, descriptor = false,
    name: rawName = 'assets/client.bin', prefix = Buffer.alloc(0),
    signingPadding = Buffer.alloc(0), signingBlock = Buffer.alloc(0),
    crcValue = crc32(content)} = options;
  const payload = method === 0 ? content : deflateRawSync(content);
  const name = Buffer.from(rawName);
  const flags = (encrypted ? 1 : 0) | (descriptor ? 8 : 0);
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50);
  local.writeUInt16LE(flags, 6); local.writeUInt16LE(method, 8);
  if (!descriptor) {
    local.writeUInt32LE(crcValue, 14);
    local.writeUInt32LE(payload.length, 18); local.writeUInt32LE(content.length, 22);
  }
  local.writeUInt16LE(name.length, 26);
  const dataDescriptor = descriptor ? Buffer.alloc(16) : Buffer.alloc(0);
  if (descriptor) {
    dataDescriptor.writeUInt32LE(0x08074b50);
    dataDescriptor.writeUInt32LE(crcValue, 4);
    dataDescriptor.writeUInt32LE(payload.length, 8);
    dataDescriptor.writeUInt32LE(content.length, 12);
  }
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50);
  central.writeUInt16LE(flags, 8); central.writeUInt16LE(method, 10);
  central.writeUInt32LE(crcValue, 16);
  central.writeUInt32LE(payload.length, 20); central.writeUInt32LE(content.length, 24);
  central.writeUInt16LE(name.length, 28);
  central.writeUInt32LE(prefix.length, 42);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length + name.length, 12);
  end.writeUInt32LE(prefix.length + local.length + name.length + payload.length + dataDescriptor.length +
    signingPadding.length + signingBlock.length, 16);
  return Buffer.concat([prefix, local, name, payload, dataDescriptor, signingPadding, signingBlock, central, name, end]);
}
function orphanZip(content) {
  const complete = zip(content);
  const end = complete.length - 22;
  const central = complete.readUInt32LE(end + 16);
  const localOnly = complete.subarray(0, central);
  const emptyEnd = Buffer.alloc(22);
  emptyEnd.writeUInt32LE(0x06054b50);
  emptyEnd.writeUInt32LE(localOnly.length, 16);
  return Buffer.concat([localOnly, emptyEnd]);
}
function overlappingZip(content) {
  const complete = zip(content);
  const oldEnd = complete.length - 22;
  const centralStart = complete.readUInt32LE(oldEnd + 16);
  const central = complete.subarray(centralStart, oldEnd);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(2, 8); end.writeUInt16LE(2, 10);
  end.writeUInt32LE(central.length * 2, 12);
  end.writeUInt32LE(centralStart, 16);
  return Buffer.concat([complete.subarray(0, centralStart), central, central, end]);
}

function zipflingerAlignment(extraLength = 0) {
  const record = Buffer.alloc(30 + extraLength);
  record.writeUInt32LE(0x04034b50);
  record.writeUInt16LE(2081, 10);
  record.writeUInt16LE(545, 12);
  record.writeUInt16LE(extraLength, 28);
  return record;
}

function twoEntryZip(gap) {
  const contents = [Buffer.from('first benign entry'), Buffer.from(privateValue)];
  const names = [Buffer.from('assets/first.bin'), Buffer.from('assets/second.bin')];
  const locals = [];
  const centralRecords = [];
  let offset = 0;
  for (let index = 0; index < contents.length; index++) {
    const content = contents[index];
    const name = names[index];
    const crc = crc32(content);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(content.length, 18);
    local.writeUInt32LE(content.length, 22);
    local.writeUInt16LE(name.length, 26);
    locals.push(local, name, content);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(content.length, 20);
    central.writeUInt32LE(content.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(offset, 42);
    centralRecords.push(central, name);
    offset += local.length + name.length + content.length;
    if (index === 0) {
      locals.push(gap);
      offset += gap.length;
    }
  }
  const central = Buffer.concat(centralRecords);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(2, 8);
  end.writeUInt16LE(2, 10);
  end.writeUInt32LE(central.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, central, end]);
}

test('reads only the three exact services and one exact X path, with no credential argv', async () => {
  const calls = [];
  const values = [publicValue, privateValue, 'synthetic-tokens-key'];
  const result = await readAuditCredentials({home: '/test-owner',
    run: async (command, args, options) => {
      calls.push({command, args, options});
      return {stdout: values[calls.length - 1] + '\n'};
    },
    readX: async (path, options) => {
      assert.equal(path, '/test-owner/.config/trimmy/providers/tip-x.json');
      assert.deepEqual(options, {privateRoot: '/test-owner/.config/trimmy'});
      return {value: {consumerKey: 'synthetic-consumer-key', consumerSecret: 'synthetic-consumer-secret', bearerToken: 'synthetic-bearer-token'},
        verification: storageVerification};
    },
  });
  assert.deepEqual(calls.map(call => [call.command, ...call.args]), [
    ['/usr/bin/security', 'find-generic-password', '-s', 'trimmy-privy-app-id', '-a', 'trimmy', '-w'],
    ['/usr/bin/security', 'find-generic-password', '-s', 'trimmy-privy-app-secret', '-a', 'trimmy', '-w'],
    ['/usr/bin/security', 'find-generic-password', '-s', 'trimmy-tokens-xyz', '-a', 'trimmy', '-w'],
  ]);
  assert.equal(result.credentials.length, 6);
  assert.equal(result.credentials.filter(item => item.public).length, 1);
  assert.deepEqual(result.verification, {...storageVerification,
    keychainReadsUseCurrentUser: true, keychainReadsUseExactAccount: true});
  for (const value of values) assert.equal(JSON.stringify(calls).includes(value), false);
});

test('credential read failures discard raw command and JSON errors', async () => {
  await assert.rejects(readAuditCredentials({run: async () => { throw new Error(privateValue); }}),
    error => error instanceof SecretBoundaryError && error.message === 'KEYCHAIN_READ_UNAVAILABLE' && !String(error).includes(privateValue));
  await assert.rejects(readAuditCredentials({run: async () => ({stdout: publicValue}),
    readX: async () => { throw new Error(privateValue); }}),
  error => error.message === 'PRIVATE_X_FILE_UNAVAILABLE');
  await assert.rejects(readAuditCredentials({run: async () => ({stdout: publicValue}),
    readX: async () => ({value: {consumerKey: 'too-short'}, verification: storageVerification})}),
  error => error.code === 'CREDENTIAL_INPUT_INVALID');
  await assert.rejects(readAuditCredentials({run: async () => ({stdout: publicValue}),
    readX: async () => ({value: {}, verification: {...storageVerification, privateFileOpenedInodeVerified: false}})}),
  error => error.code === 'PRIVATE_STORAGE_PERMISSIONS_INVALID');
});

test('private JSON must be current-owner, private, regular and not symlinked', async t => {
  const root = await workspace(t);
  const privateRoot = join(root, 'trimmy');
  const directory = join(privateRoot, 'providers');
  await mkdir(directory, {recursive: true, mode: 0o700});
  await chmod(privateRoot, 0o700);
  const path = join(directory, 'tip-x.json');
  await writeFile(path, '{"consumerKey":"synthetic-test-key"}', {mode: 0o600});
  const read = await readPrivateXFile(path);
  assert.equal(read.value.consumerKey, 'synthetic-test-key');
  assert.deepEqual(read.verification, storageVerification);
  await assert.rejects(readPrivateXFile(path, {uid: process.getuid() + 1}), /PRIVATE_STORAGE_PERMISSIONS_INVALID/);
  await chmod(path, 0o640);
  await assert.rejects(readPrivateXFile(path), /PRIVATE_STORAGE_PERMISSIONS_INVALID/);
  await chmod(path, 0o600);
  await chmod(directory, 0o750);
  await assert.rejects(readPrivateXFile(path), /PRIVATE_STORAGE_PERMISSIONS_INVALID/);
  await chmod(directory, 0o700);
  await chmod(privateRoot, 0o750);
  await assert.rejects(readPrivateXFile(path), /PRIVATE_STORAGE_PERMISSIONS_INVALID/);
  await chmod(privateRoot, 0o700);
  const hardLink = join(directory, 'hard-link.json');
  await createHardLink(path, hardLink);
  await assert.rejects(readPrivateXFile(path), /PRIVATE_STORAGE_PERMISSIONS_INVALID/);
  await rm(hardLink);
  const link = join(directory, 'alias.json');
  await symlink(path, link);
  await assert.rejects(readPrivateXFile(link), /PRIVATE_STORAGE_PERMISSIONS_INVALID/);
  await writeFile(path, '{"invalid":' + privateValue);
  await assert.rejects(readPrivateXFile(path), error => error.message === 'PRIVATE_X_FILE_INVALID');
});

test('public app ID is classified public and does not fail a complete scan', async t => {
  const root = await workspace(t);
  await put(root, 'apps/web/dist/index.js', publicValue);
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.passed, true);
  assert.equal(report.privateCredentialsAbsent.privyAppSecret, true);
  assert.equal(report.counters.publicAppIdMatchingUnits, 1);
  assert.equal(report.filesScannedByPathClass['web-client'], 1);
  assert.deepEqual(privatePaths, []);
  assert.equal(JSON.stringify(report).includes(publicValue), false);
});

test('finds UTF-8, both UTF-16 byte orders, and a match spanning stream chunks', async t => {
  const root = await workspace(t);
  await put(root, 'docs/test.md', privateValue);
  await put(root, 'config/settings.json', Buffer.from(privateValue, 'utf16le'));
  await put(root, 'apps/mobile/build/flutter_assets/data.bin', Buffer.from(privateValue, 'utf16le').swap16());
  await put(root, 'source.ts', Buffer.concat([Buffer.alloc(1024 * 1024 - 7, 65), Buffer.from(privateValue)]));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.completed, true);
  assert.equal(report.passed, false);
  assert.equal(report.counters.privateMatchingUnits, 4);
  assert.equal(privatePaths.length, 4);
  assert.equal(report.privateMatchPathClasses['mobile-client'], 1);
  assert.equal(JSON.stringify(report).includes(privateValue), false);
  assert.equal(report.credentialHashesRecorded, false);
});

test('skips dependency/compiler caches but scans web/mobile build outputs', async t => {
  const root = await workspace(t);
  await put(root, 'node_modules/pkg/value.js', privateValue);
  await put(root, 'apps/mobile/.dart_tool/cache/value', privateValue);
  await put(root, 'apps/mobile/build/app/intermediates/javac/value', privateValue);
  await put(root, 'apps/web/dist/index.js', privateValue);
  await put(root, 'apps/mobile/build/web/main.dart.js', privateValue);
  await put(root, 'apps/mobile/build/app/outputs/flutter-apk/app.apk', zip(Buffer.from(privateValue), {descriptor: true}));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.completed, true);
  assert.equal(report.counters.filesScanned, 3);
  assert.equal(report.filesScannedByPathClass['web-client'], 2);
  assert.equal(report.archiveContainersDecodedByPathClass['mobile-client'], 1);
  assert.equal(report.builtClientArchivesDecoded, true);
  assert.equal(report.excludedDirectoriesByReason['dependency-or-tool-cache'], 2);
  assert.equal(report.excludedDirectoriesByReason['compiler-intermediate'], 1);
  assert.equal(privatePaths.length, 3);
  assert.equal(classifyPath('apps/mobile/build/web/main.dart.js'), 'web-client');
});

test('scans deflated/stored nested ZIP, gzip and brotli without writing decoded data', async t => {
  const root = await workspace(t);
  await put(root, 'artifacts/builds/client.ipa', zip(zip(Buffer.from(privateValue), {method: 0})));
  await put(root, 'apps/web/dist/index.js.gz', gzipSync(privateValue));
  await put(root, 'apps/web/dist/index.js.br', brotliCompressSync(Buffer.from(privateValue)));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.completed, true);
  assert.equal(report.counters.archiveEntriesScanned, 4);
  assert.equal(privatePaths.length, 3);
  assert.equal(report.archiveContainersDecodedByPathClass['web-client'], 2);
});

test('finds Brotli data nested in ZIP and preserves its virtual archive path', async t => {
  const root = await workspace(t);
  await put(root, 'artifacts/builds/client.ipa', zip(brotliCompressSync(Buffer.from(privateValue)), {
    name: 'assets/main.js.br',
  }));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.completed, true);
  assert.equal(report.passed, false);
  assert.equal(report.counters.archiveEntriesScanned, 2);
  assert.deepEqual(privatePaths, ['artifacts/builds/client.ipa!/assets/main.js']);
});

test('accepts a structurally valid APK Signing Block while scanning entry content', async t => {
  const root = await workspace(t);
  await put(root, 'apps/mobile/build/app/outputs/flutter-apk/app.apk', zip(Buffer.from(privateValue), {
    signingBlock: apkSigningBlock(),
  }));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.completed, true);
  assert.equal(report.passed, false);
  assert.equal(report.counters.archiveEntriesScanned, 1);
  assert.deepEqual(privatePaths,
    ['apps/mobile/build/app/outputs/flutter-apk/app.apk!/assets/client.bin']);
});

test('accepts only exact zero page-alignment padding before a valid APK Signing Block', async t => {
  const root = await workspace(t);
  const content = Buffer.from(privateValue);
  const unsigned = zip(content);
  const localEnd = unsigned.readUInt32LE(unsigned.length - 6);
  const paddingLength = (4096 - localEnd % 4096) % 4096;
  assert.ok(paddingLength > 0);
  await put(root, 'apps/mobile/build/app/outputs/flutter-apk/aligned.apk', zip(content, {
    signingPadding: Buffer.alloc(paddingLength),
    signingBlock: apkSigningBlock(),
  }));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.completed, true);
  assert.equal(report.passed, false);
  assert.deepEqual(privatePaths,
    ['apps/mobile/build/app/outputs/flutter-apk/aligned.apk!/assets/client.bin']);
});

test('accepts chained zero-only zipflinger alignment records between listed entries', () => {
  const archive = twoEntryZip(Buffer.concat([
    zipflingerAlignment(),
    zipflingerAlignment(17),
    zipflingerAlignment(65_535),
  ]));
  assert.deepEqual([...zipEntries(archive)].map(entry => entry.name),
    ['assets/first.bin', 'assets/second.bin']);
});

test('rejects data, names, payloads, wrong timestamps and truncated zipflinger records', () => {
  const mutations = [];
  const hiddenData = zipflingerAlignment(1);
  hiddenData[30] = 1;
  mutations.push(hiddenData);
  const named = Buffer.concat([zipflingerAlignment(), Buffer.from('x')]);
  named.writeUInt16LE(1, 26);
  mutations.push(named);
  const compressed = Buffer.concat([zipflingerAlignment(), Buffer.from([1])]);
  compressed.writeUInt16LE(8, 8);
  compressed.writeUInt32LE(1, 18);
  compressed.writeUInt32LE(1, 22);
  mutations.push(compressed);
  const wrongTime = zipflingerAlignment();
  wrongTime.writeUInt16LE(2080, 10);
  mutations.push(wrongTime);
  const wrongDate = zipflingerAlignment();
  wrongDate.writeUInt16LE(544, 12);
  mutations.push(wrongDate);
  mutations.push(zipflingerAlignment(4).subarray(0, 33));
  for (const gap of mutations) assert.throws(() => [...zipEntries(twoEntryZip(gap))], /ARCHIVE_INVALID/);
});

test('rejects every other orphan local-header shape and partial record chains', () => {
  const fields = [
    [4, 2, 1],
    [6, 2, 1],
    [8, 2, 1],
    [14, 4, 1],
    [18, 4, 1],
    [22, 4, 1],
    [26, 2, 1],
  ];
  for (const [offset, width, value] of fields) {
    const gap = zipflingerAlignment();
    gap[`writeUInt${width * 8}LE`](value, offset);
    assert.throws(() => [...zipEntries(twoEntryZip(gap))], /ARCHIVE_INVALID/);
  }
  assert.throws(() => [...zipEntries(twoEntryZip(Buffer.concat([
    zipflingerAlignment(3),
    Buffer.from([0]),
  ])))], /ARCHIVE_INVALID/);
  assert.throws(() => [...zipEntries(twoEntryZip(Buffer.alloc(30)))], /ARCHIVE_INVALID/);
});

test('rejects nonzero, unnecessary and whole-page data before an APK Signing Block', async t => {
  const root = await workspace(t);
  const benign = Buffer.from('synthetic archive content without a credential');
  const unsigned = zip(benign);
  const localEnd = unsigned.readUInt32LE(unsigned.length - 6);
  const paddingLength = (4096 - localEnd % 4096) % 4096;
  const nonzeroPadding = Buffer.alloc(paddingLength);
  nonzeroPadding[paddingLength - 1] = 1;
  await put(root, 'artifacts/builds/nonzero-padding.apk', zip(benign, {
    signingPadding: nonzeroPadding,
    signingBlock: apkSigningBlock(),
  }));
  await put(root, 'artifacts/builds/no-signing-block.apk', zip(benign, {
    signingPadding: Buffer.alloc(paddingLength),
  }));
  await put(root, 'artifacts/builds/whole-extra-page.apk', zip(benign, {
    signingPadding: Buffer.alloc(paddingLength + 4096),
    signingBlock: apkSigningBlock(),
  }));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.completed, false);
  assert.equal(report.passed, false);
  assert.equal(report.counters.incompleteUnits, 3);
  assert.equal(report.incompleteReasons.ARCHIVE_INVALID, 3);
  assert.deepEqual(privatePaths, []);
});

test('orphan, overlapping and prefixed ZIP records make the audit incomplete', async t => {
  const root = await workspace(t);
  const benign = Buffer.from('synthetic archive content without a credential');
  await put(root, 'artifacts/builds/orphan.apk', orphanZip(benign));
  await put(root, 'artifacts/builds/overlapping.apk', overlappingZip(benign));
  await put(root, 'artifacts/builds/prefixed.apk', zip(benign, {prefix: Buffer.from('synthetic-sfx-stub')}));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.completed, false);
  assert.equal(report.passed, false);
  assert.equal(report.counters.incompleteUnits, 3);
  assert.equal(report.incompleteReasons.ARCHIVE_INVALID, 2);
  assert.equal(report.incompleteReasons.ARCHIVE_UNSUPPORTED, 1);
  assert.deepEqual(privatePaths, []);
});

test('a ZIP entry with a mismatched CRC makes the audit incomplete', async t => {
  const root = await workspace(t);
  const benign = Buffer.from('synthetic archive content without a credential');
  await put(root, 'artifacts/builds/bad-crc.apk', zip(benign, {
    crcValue: (crc32(benign) + 1) >>> 0,
  }));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials});
  assert.equal(report.completed, false);
  assert.equal(report.passed, false);
  assert.equal(report.counters.incompleteUnits, 1);
  assert.equal(report.incompleteReasons.ARCHIVE_INVALID, 1);
  assert.deepEqual(privatePaths, []);
});

test('unsupported or truncated included archives fail incomplete rather than claiming clean', async t => {
  const root = await workspace(t);
  await put(root, 'artifacts/builds/encrypted.apk', zip(Buffer.from('no secret here'), {encrypted: true}));
  await put(root, 'artifacts/builds/broken.apk', zip(Buffer.from('no secret here')).subarray(0, 40));
  const {report} = await scanSecretBoundary({root, credentials});
  assert.equal(report.passed, false);
  assert.equal(report.completed, false);
  assert.equal(report.counters.incompleteUnits, 2);
  assert.equal(report.privateCredentialsAbsent.privyAppSecret, false);
});

test('byte limit is incomplete and outside symlinks are never followed', async t => {
  const root = await workspace(t);
  await put(root, 'source.ts', Buffer.alloc(128));
  const outside = await workspace(t);
  const path = await put(outside, 'outside-secret', privateValue);
  await symlink(path, join(root, 'outside-link'));
  const {report, privatePaths} = await scanSecretBoundary({root, credentials, maxBytes: 64});
  assert.equal(report.passed, false);
  assert.equal(report.incompleteReasons.SCAN_BYTE_LIMIT, 1);
  assert.equal(report.counters.symlinksNotFollowed, 1);
  assert.equal(report.symlinkTargetsInspected, false);
  assert.deepEqual(privatePaths, []);
});

test('a value classified both public and private is still private; result paths redact values', async t => {
  const root = await workspace(t);
  await put(root, privateValue + '.txt', privateValue);
  const {report, privatePaths} = await scanSecretBoundary({root, credentials: [
    ...credentials, {kind: 'duplicatePublic', public: true, value: privateValue},
  ]});
  assert.equal(report.passed, false);
  assert.deepEqual(privatePaths, ['[redacted].txt']);
  assert.equal(JSON.stringify({report, privatePaths}).includes(privateValue), false);
});
