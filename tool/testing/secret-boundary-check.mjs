/** Local exact-value audit. Credentials remain in memory, never argv, logs,
 * reports or hashes. No network, provider or Keychain enumeration is used. */
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {constants, createReadStream} from 'node:fs';
import {open, lstat, readdir, mkdir, writeFile} from 'node:fs/promises';
import {homedir} from 'node:os';
import {extname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {inflateRawSync, gunzipSync, brotliDecompressSync} from 'node:zlib';

const execute = promisify(execFile);
const excludedNames = new Set(['node_modules', '.git', '.dart_tool', '.gradle', '.pub-cache', 'Pods', '.symlinks', '.cxx']);
const compilerNames = new Set(['javac', 'cxx', 'incremental', 'compile_commands', '.transforms']);
const maxArchiveBytes = 512 * 1024 * 1024;
const maxEntryBytes = 256 * 1024 * 1024;
const maxExpandedBytes = 16 * 1024 ** 3;

export class SecretBoundaryError extends Error {
  constructor(code) { super(code); this.name = 'SecretBoundaryError'; this.code = code; }
}
const fail = code => { throw new SecretBoundaryError(code); };

function privateNode(stat, {uid, directory}) {
  if (stat.uid !== uid || stat.isSymbolicLink() || (stat.mode & 0o077) !== 0 ||
      (directory ? !stat.isDirectory() : !stat.isFile()) || !directory && stat.nlink !== 1) {
    fail('PRIVATE_STORAGE_PERMISSIONS_INVALID');
  }
}

/** Validate the complete private tree rooted at ~/.config/trimmy, then bind the
 * lstat result to the descriptor actually read. Ancestors above privateRoot are
 * intentionally outside this private-storage boundary. */
export async function readPrivateXFile(path, {
  uid = process.getuid(), privateRoot = resolve(path, '../..'),
} = {}) {
  if (typeof path !== 'string' || !isAbsolute(path) || resolve(path) !== path ||
      typeof privateRoot !== 'string' || !isAbsolute(privateRoot) || resolve(privateRoot) !== privateRoot) {
    fail('PRIVATE_STORAGE_PERMISSIONS_INVALID');
  }
  const withinRoot = relative(privateRoot, path);
  if (!withinRoot || withinRoot === '..' || withinRoot.startsWith(`..${sep}`) || isAbsolute(withinRoot)) {
    fail('PRIVATE_STORAGE_PERMISSIONS_INVALID');
  }
  const parts = withinRoot.split(sep);
  if (parts.some(part => !part || part === '.' || part === '..')) fail('PRIVATE_STORAGE_PERMISSIONS_INVALID');
  let directory = privateRoot;
  for (const part of parts.slice(0, -1)) {
    privateNode(await lstat(directory), {uid, directory: true});
    directory = join(directory, part);
  }
  privateNode(await lstat(directory), {uid, directory: true});

  const before = await lstat(path);
  privateNode(before, {uid, directory: false});
  if (before.size > 32_768) fail('PRIVATE_STORAGE_PERMISSIONS_INVALID');
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const opened = await file.stat();
    privateNode(opened, {uid, directory: false});
    if (opened.dev !== before.dev || opened.ino !== before.ino || opened.size !== before.size || opened.size > 32_768) {
      fail('PRIVATE_STORAGE_PERMISSIONS_INVALID');
    }
    const bytes = await file.readFile();
    const after = await file.stat();
    privateNode(after, {uid, directory: false});
    if (after.dev !== opened.dev || after.ino !== opened.ino || after.size !== opened.size || bytes.length !== opened.size) {
      fail('PRIVATE_STORAGE_PERMISSIONS_INVALID');
    }
    let value;
    try { value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)); }
    catch { fail('PRIVATE_X_FILE_INVALID'); }
    return Object.freeze({
      value,
      verification: Object.freeze({
        privateFileOwnerVerified: true,
        privateAncestorOwnersVerified: true,
        privateFileAndDirectoryPermissionsVerified: true,
        privateFileHardLinkCountVerified: true,
        privateFileOpenedInodeVerified: true,
      }),
    });
  } finally { await file.close(); }
}

/** Exact service + account lookup only; no Keychain listing. */
export async function readAuditCredentials({run = execute, readX = readPrivateXFile, home = homedir()} = {}) {
  const keychainAccount = 'trimmy';
  async function keychain(service) {
    const args = ['find-generic-password', '-s', service, '-a', keychainAccount, '-w'];
    try {
      const result = await run('/usr/bin/security', args, {encoding: 'utf8', timeout: 5000, maxBuffer: 16_384});
      return result.stdout.replace(/\r?\n$/, '');
    } catch { fail('KEYCHAIN_READ_UNAVAILABLE'); }
  }
  const appId = await keychain('trimmy-privy-app-id');
  const appSecret = await keychain('trimmy-privy-app-secret');
  const tokensKey = await keychain('trimmy-tokens-xyz');
  let xRead;
  try {
    xRead = await readX(join(home, '.config/trimmy/providers/tip-x.json'), {
      privateRoot: join(home, '.config/trimmy'),
    });
  }
  catch (error) {
    if (error instanceof SecretBoundaryError) throw error;
    fail('PRIVATE_X_FILE_UNAVAILABLE');
  }
  if (xRead === null || typeof xRead !== 'object' || Array.isArray(xRead) ||
      xRead.verification === null || typeof xRead.verification !== 'object' ||
      ['privateFileOwnerVerified', 'privateAncestorOwnersVerified',
        'privateFileAndDirectoryPermissionsVerified', 'privateFileHardLinkCountVerified',
        'privateFileOpenedInodeVerified'].some(key => xRead.verification[key] !== true)) {
    fail('PRIVATE_STORAGE_PERMISSIONS_INVALID');
  }
  const x = xRead.value;
  const credentials = [
    {kind: 'privyAppId', public: true, value: appId},
    {kind: 'privyAppSecret', public: false, value: appSecret},
    {kind: 'tokensApiKey', public: false, value: tokensKey},
    {kind: 'xConsumerKey', public: false, value: x?.consumerKey},
    {kind: 'xConsumerSecret', public: false, value: x?.consumerSecret},
    {kind: 'xBearerToken', public: false, value: x?.bearerToken},
  ];
  if (credentials.some(({value}) => typeof value !== 'string' || value.length < 8 || value.length > 4096 ||
    /^[\x21-\x7e]+$/.exec(value)?.[0] !== value)) fail('CREDENTIAL_INPUT_INVALID');
  return Object.freeze({
    credentials: Object.freeze(credentials.map(item => Object.freeze(item))),
    verification: Object.freeze({
      ...xRead.verification,
      keychainReadsUseCurrentUser: true,
      keychainReadsUseExactAccount: true,
    }),
  });
}

export function classifyPath(path) {
  const lower = path.toLowerCase().replaceAll('\\', '/');
  if (/apps\/web\/(dist|build)|apps\/mobile\/build\/web|(?:^|\/)\.next\/static/.test(lower)) return 'web-client';
  if (/\.(apk|aab|ipa)$/.test(lower) || /apps\/mobile\/(build|ios\/runner|android\/app)/.test(lower)) return 'mobile-client';
  if (/(?:^|\/)(artifacts|art)\//.test(lower)) return 'artifacts';
  if (/(?:^|\/)docs\//.test(lower) || lower.endsWith('.md')) return 'documentation';
  if (/(?:^|\/)(?:\.env[^/]*|[^/]*(?:config|settings)[^/]*)$/.test(lower)) return 'configuration';
  return 'source-other';
}
export function exclusionReason(path, isDirectory) {
  const parts = path.split(/[\\/]/);
  if (isDirectory && excludedNames.has(parts.at(-1))) return 'dependency-or-tool-cache';
  if (isDirectory && parts.includes('build') && compilerNames.has(parts.at(-1))) return 'compiler-intermediate';
  if (isDirectory && parts.at(-1) === 'cache' && parts.includes('.next')) return 'compiler-intermediate';
  return null;
}

function patterns(credentials) {
  return credentials.map(item => {
    const utf16 = Buffer.from(item.value, 'utf16le');
    return {...item, buffers: [Buffer.from(item.value, 'utf8'), utf16, Buffer.from(utf16).swap16()]};
  });
}
function matchBytes(bytes, needles, matched) {
  for (const needle of needles) {
    if (!matched.has(needle.kind) && needle.buffers.some(buffer => bytes.includes(buffer))) matched.add(needle.kind);
  }
}

const zipExtensions = new Set(['.zip', '.apk', '.aab', '.ipa', '.jar', '.aar', '.xapk', '.apks']);
const apkSigningMagic = Buffer.from('APK Sig Block 42');
const apkSigningAlignment = 4096;
const crcTable = Object.freeze(Array.from({length: 256}, (_, input) => {
  let value = input;
  for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ value >>> 1 : value >>> 1;
  return value >>> 0;
}));

function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) value = crcTable[(value ^ byte) & 0xff] ^ value >>> 8;
  return (value ^ 0xffffffff) >>> 0;
}

function virtualZipName(bytes) {
  let name;
  try { name = new TextDecoder('utf-8', {fatal: true}).decode(bytes); }
  catch { fail('ARCHIVE_UNSUPPORTED'); }
  if (!name || name.length > 4096 || name.startsWith('/') || name.includes('\\') ||
      /[\u0000-\u001f\u007f]/u.test(name) || name.split('/').some(part => part === '.' || part === '..')) {
    fail('ARCHIVE_UNSUPPORTED');
  }
  return name;
}

function validApkSigningBlock(bytes, start, end) {
  if (end - start < 32 || !bytes.subarray(end - 16, end).equals(apkSigningMagic)) return false;
  const declared = bytes.readBigUInt64LE(start);
  if (declared !== bytes.readBigUInt64LE(end - 24) || declared + 8n !== BigInt(end - start)) return false;
  let cursor = start + 8;
  const pairLimit = end - 24;
  let pairs = 0;
  while (cursor < pairLimit) {
    if (cursor + 8 > pairLimit) return false;
    const pairLength = bytes.readBigUInt64LE(cursor);
    if (pairLength < 4n || pairLength > BigInt(pairLimit - cursor - 8)) return false;
    cursor += 8 + Number(pairLength);
    pairs++;
  }
  return pairs > 0 && cursor === pairLimit;
}

function validApkSigningRegion(bytes, start, end) {
  if (validApkSigningBlock(bytes, start, end)) return true;
  if (end - start < 32) return false;
  const declared = bytes.readBigUInt64LE(end - 24);
  const blockLength = declared + 8n;
  if (blockLength > BigInt(end - start)) return false;
  const blockStart = end - Number(blockLength);
  const paddingLength = blockStart - start;
  const expectedPadding = (apkSigningAlignment - start % apkSigningAlignment) % apkSigningAlignment;
  if (paddingLength === 0 || paddingLength !== expectedPadding ||
      bytes.subarray(start, blockStart).some(byte => byte !== 0)) return false;
  return validApkSigningBlock(bytes, blockStart, end);
}

function validZipflingerAlignmentGap(bytes, start, end) {
  let cursor = start;
  let records = 0;
  while (cursor < end) {
    if (cursor + 30 > end || bytes.readUInt32LE(cursor) !== 0x04034b50 ||
        bytes.readUInt16LE(cursor + 4) !== 0 || bytes.readUInt16LE(cursor + 6) !== 0 ||
        bytes.readUInt16LE(cursor + 8) !== 0 || bytes.readUInt16LE(cursor + 10) !== 2081 ||
        bytes.readUInt16LE(cursor + 12) !== 545 || bytes.readUInt32LE(cursor + 14) !== 0 ||
        bytes.readUInt32LE(cursor + 18) !== 0 || bytes.readUInt32LE(cursor + 22) !== 0 ||
        bytes.readUInt16LE(cursor + 26) !== 0) return false;
    const next = cursor + 30 + bytes.readUInt16LE(cursor + 28);
    if (next > end || bytes.subarray(cursor + 30, next).some(byte => byte !== 0)) return false;
    cursor = next;
    records++;
  }
  return records > 0 && cursor === end;
}

function descriptorEnds(bytes, start, entry) {
  const ends = [];
  if (start + 12 <= bytes.length && bytes.readUInt32LE(start) === entry.crc &&
      bytes.readUInt32LE(start + 4) === entry.compressed && bytes.readUInt32LE(start + 8) === entry.expanded) {
    ends.push(start + 12);
  }
  if (start + 16 <= bytes.length && bytes.readUInt32LE(start) === 0x08074b50 &&
      bytes.readUInt32LE(start + 4) === entry.crc && bytes.readUInt32LE(start + 8) === entry.compressed &&
      bytes.readUInt32LE(start + 12) === entry.expanded) {
    ends.push(start + 16);
  }
  return ends;
}

/** Strict single-disk ZIP reader. It validates local/central agreement, CRCs and
 * complete local-record coverage. The only permitted gaps are exact zero-only
 * zipflinger alignment records before a listed local entry, or a validated APK
 * Signing Block before the central directory. APK builders may precede that
 * block with only the zero bytes required to align it to the next 4 KiB page. */
export function* zipEntries(input) {
  const bytes = Buffer.isBuffer(input) ? input : Buffer.from(input);
  let end = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65_557); i--) {
    if (bytes.readUInt32LE(i) === 0x06054b50 && i + 22 + bytes.readUInt16LE(i + 20) === bytes.length) {
      end = i;
      break;
    }
  }
  if (end < 0) fail('ARCHIVE_UNSUPPORTED');
  const count = bytes.readUInt16LE(end + 10);
  const centralSize = bytes.readUInt32LE(end + 12);
  const centralStart = bytes.readUInt32LE(end + 16);
  if (bytes.readUInt16LE(end + 4) !== 0 || bytes.readUInt16LE(end + 6) !== 0 ||
      bytes.readUInt16LE(end + 8) !== count || count === 65_535 ||
      centralStart + centralSize !== end) fail('ARCHIVE_UNSUPPORTED');

  const entries = [];
  let cursor = centralStart;
  for (let index = 0; index < count; index++) {
    if (cursor + 46 > end || bytes.readUInt32LE(cursor) !== 0x02014b50) fail('ARCHIVE_INVALID');
    const flags = bytes.readUInt16LE(cursor + 8);
    const method = bytes.readUInt16LE(cursor + 10);
    const crc = bytes.readUInt32LE(cursor + 16);
    const compressed = bytes.readUInt32LE(cursor + 20);
    const expanded = bytes.readUInt32LE(cursor + 24);
    const nameLength = bytes.readUInt16LE(cursor + 28);
    const extraLength = bytes.readUInt16LE(cursor + 30);
    const commentLength = bytes.readUInt16LE(cursor + 32);
    const localDisk = bytes.readUInt16LE(cursor + 34);
    const local = bytes.readUInt32LE(cursor + 42);
    const next = cursor + 46 + nameLength + extraLength + commentLength;
    if (next > end || localDisk !== 0 || compressed === 0xffffffff || expanded === 0xffffffff ||
        local === 0xffffffff || (flags & ~0x080e) !== 0 || method !== 0 && method !== 8 ||
        method === 0 && (flags & 0x0006) !== 0 ||
        expanded > maxEntryBytes) fail('ARCHIVE_UNSUPPORTED');
    const nameBytes = bytes.subarray(cursor + 46, cursor + 46 + nameLength);
    entries.push({flags, method, crc, compressed, expanded, local, nameBytes,
      name: virtualZipName(nameBytes), data: undefined});
    cursor = next;
  }
  if (cursor !== end || count === 0 && centralStart !== 0) fail('ARCHIVE_INVALID');

  const localOrder = [...entries].sort((left, right) => left.local - right.local);
  if (localOrder.length && localOrder[0].local !== 0) fail('ARCHIVE_UNSUPPORTED');
  for (let index = 0; index < localOrder.length; index++) {
    const entry = localOrder[index];
    const nextLocal = localOrder[index + 1]?.local ?? centralStart;
    if (index > 0 && entry.local <= localOrder[index - 1].local || entry.local + 30 > centralStart ||
        bytes.readUInt32LE(entry.local) !== 0x04034b50) fail('ARCHIVE_INVALID');
    const localFlags = bytes.readUInt16LE(entry.local + 6);
    const localMethod = bytes.readUInt16LE(entry.local + 8);
    const localCrc = bytes.readUInt32LE(entry.local + 14);
    const localCompressed = bytes.readUInt32LE(entry.local + 18);
    const localExpanded = bytes.readUInt32LE(entry.local + 22);
    const localNameLength = bytes.readUInt16LE(entry.local + 26);
    const localExtraLength = bytes.readUInt16LE(entry.local + 28);
    const dataStart = entry.local + 30 + localNameLength + localExtraLength;
    const dataEnd = dataStart + entry.compressed;
    if (localFlags !== entry.flags || localMethod !== entry.method || dataStart > centralStart || dataEnd > centralStart ||
        !bytes.subarray(entry.local + 30, entry.local + 30 + localNameLength).equals(entry.nameBytes)) {
      fail('ARCHIVE_INVALID');
    }
    const descriptor = (entry.flags & 0x0008) !== 0;
    if (descriptor ?
      ![0, entry.crc].includes(localCrc) || ![0, entry.compressed].includes(localCompressed) || ![0, entry.expanded].includes(localExpanded) :
      localCrc !== entry.crc || localCompressed !== entry.compressed || localExpanded !== entry.expanded) {
      fail('ARCHIVE_INVALID');
    }
    const candidateEnds = descriptor ? descriptorEnds(bytes, dataEnd, entry) : [dataEnd];
    const validEnds = candidateEnds.filter(candidate => {
      if (candidate === nextLocal) return true;
      if (candidate >= nextLocal) return false;
      return index + 1 < localOrder.length ? validZipflingerAlignmentGap(bytes, candidate, nextLocal) :
        validApkSigningRegion(bytes, candidate, centralStart);
    });
    if (validEnds.length !== 1) fail('ARCHIVE_INVALID');
    const compressedBytes = bytes.subarray(dataStart, dataEnd);
    const data = entry.method === 0 ? compressedBytes :
      inflateRawSync(compressedBytes, {maxOutputLength: maxEntryBytes});
    if (data.length !== entry.expanded || crc32(data) !== entry.crc) fail('ARCHIVE_INVALID');
    entry.data = data;
  }
  for (const entry of entries) yield Object.freeze({name: entry.name, bytes: entry.data});
}

export async function scanSecretBoundary({root, credentials, maxBytes = 16 * 1024 ** 3}) {
  const needles = patterns(credentials);
  const longest = Math.max(...needles.flatMap(item => item.buffers.map(buffer => buffer.length)));
  const privateKinds = new Set(credentials.filter(item => !item.public).map(item => item.kind));
  const privatePaths = new Set();
  const counters = {filesScanned: 0, bytesScanned: 0, archiveEntriesScanned: 0, expandedBytesScanned: 0,
    publicAppIdMatchingUnits: 0, privateMatchingUnits: 0, symlinksNotFollowed: 0, incompleteUnits: 0};
  const classes = {};
  const scannedClasses = {};
  const archiveClasses = {};
  const incompleteReasons = {};
  const exclusions = {};
  const privateKindsFound = new Set();
  let totalExpanded = 0;
  const count = (bag, key) => { bag[key] = (bag[key] ?? 0) + 1; };
  const incomplete = reason => { counters.incompleteUnits++; count(incompleteReasons, reason); };
  function found(path, matches) {
    if (matches.has('privyAppId')) counters.publicAppIdMatchingUnits++;
    const privateMatches = [...matches].filter(kind => privateKinds.has(kind));
    if (privateMatches.length) {
      counters.privateMatchingUnits++;
      privatePaths.add(path);
      count(classes, classifyPath(path));
      for (const kind of privateMatches) privateKindsFound.add(kind);
    }
  }
  function compressionKind(path, input) {
    const bytes = Buffer.isBuffer(input) ? input : Buffer.from(input);
    const extension = extname(path).toLowerCase();
    if (zipExtensions.has(extension) || bytes.length >= 4 &&
        [0x04034b50, 0x06054b50].includes(bytes.readUInt32LE(0))) return 'zip';
    if (bytes[0] === 0x1f && bytes[1] === 0x8b) return 'gzip';
    if (extension === '.br') return 'brotli';
    return null;
  }
  function inspectCompressed(path, bytes, depth = 0) {
    if (depth > 3) fail('ARCHIVE_NESTING_LIMIT');
    bytes = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
    const kind = compressionKind(path, bytes);
    if (kind === null) return;
    let entries;
    if (kind === 'zip') entries = zipEntries(bytes);
    else {
      const expanded = kind === 'gzip' ? gunzipSync(bytes, {maxOutputLength: maxEntryBytes}) :
        brotliDecompressSync(bytes, {maxOutputLength: maxEntryBytes});
      entries = [{name: null, bytes: expanded}];
    }
    for (const entry of entries) {
      const entryPath = entry.name === null ?
        ((kind === 'gzip' && path.toLowerCase().endsWith('.gz')) || kind === 'brotli' ? path.slice(0, -3) : path) :
        `${path}!/${entry.name}`;
      totalExpanded += entry.bytes.length;
      if (totalExpanded > maxExpandedBytes) fail('ARCHIVE_EXPANSION_LIMIT');
      counters.archiveEntriesScanned++; counters.expandedBytesScanned += entry.bytes.length;
      const matched = new Set(); matchBytes(entry.bytes, needles, matched); found(entryPath, matched);
      inspectCompressed(entryPath, entry.bytes, depth + 1);
    }
    if (depth === 0) count(archiveClasses, classifyPath(path));
  }
  async function visit(directory) {
    let entries;
    try { entries = await readdir(directory, {withFileTypes: true}); }
    catch { incomplete('DIRECTORY_UNREADABLE'); return; }
    entries.sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      const absolute = join(directory, entry.name);
      const path = relative(root, absolute).split(sep).join('/');
      const reason = exclusionReason(path, entry.isDirectory());
      if (reason) { count(exclusions, reason); continue; }
      if (entry.isSymbolicLink()) { counters.symlinksNotFollowed++; continue; }
      if (entry.isDirectory()) { await visit(absolute); continue; }
      if (!entry.isFile()) { incomplete('SPECIAL_FILE_NOT_READ'); continue; }
      try {
        const stat = await lstat(absolute);
        if (!stat.isFile() || stat.isSymbolicLink() || counters.bytesScanned + stat.size > maxBytes) fail('SCAN_BYTE_LIMIT');
        let carry = Buffer.alloc(0), first = true,
          archive = zipExtensions.has(extname(path).toLowerCase()) || extname(path).toLowerCase() === '.br', fileBytes = 0;
        const chunks = []; const matched = new Set();
        for await (const part of createReadStream(absolute, {highWaterMark: 1024 * 1024, flags: constants.O_RDONLY | constants.O_NOFOLLOW})) {
          if (first) {
            archive ||= part.length >= 4 && [0x04034b50, 0x06054b50].includes(part.readUInt32LE(0)) ||
              part[0] === 0x1f && part[1] === 0x8b;
            first = false;
          }
          if (counters.bytesScanned + part.length > maxBytes) fail('SCAN_BYTE_LIMIT');
          fileBytes += part.length;
          if (archive && fileBytes > maxArchiveBytes) fail('ARCHIVE_BYTE_LIMIT');
          const bytes = Buffer.concat([carry, part]); matchBytes(bytes, needles, matched);
          carry = bytes.subarray(Math.max(0, bytes.length - longest + 1));
          counters.bytesScanned += part.length;
          if (archive && stat.size <= maxArchiveBytes) chunks.push(part);
        }
        counters.filesScanned++; count(scannedClasses, classifyPath(path)); found(path, matched);
        if (archive) {
          if (stat.size > maxArchiveBytes) fail('ARCHIVE_BYTE_LIMIT');
          inspectCompressed(path, Buffer.concat(chunks));
        }
      } catch (error) { incomplete(error instanceof SecretBoundaryError ? error.code : 'FILE_OR_ARCHIVE_READ_FAILED'); }
    }
  }
  await visit(root);
  const privateAbsent = Object.fromEntries([...privateKinds].sort().map(kind => [kind, counters.incompleteUnits === 0 && !privateKindsFound.has(kind)]));
  return {
    report: {schemaVersion: 1, completed: counters.incompleteUnits === 0,
      passed: counters.incompleteUnits === 0 && privatePaths.size === 0,
      exactValueScanOnly: true, networkUsed: false, credentialValuesRecorded: false, credentialHashesRecorded: false,
      privateCredentialsAbsent: privateAbsent, publicAppIdIsNotSecret: true,
      counters, filesScannedByPathClass: scannedClasses, archiveContainersDecodedByPathClass: archiveClasses,
      privateMatchPathClasses: classes, excludedDirectoriesByReason: exclusions, incompleteReasons,
      builtClientArchivesDecoded: (archiveClasses['mobile-client'] ?? 0) + (archiveClasses['web-client'] ?? 0) > 0,
      transformedCredentialSearchPerformed: false,
      symlinkTargetsInspected: false, keychainItemAclsInspected: false},
    // Caller may report these paths privately to the owner; never persist them
    // with credentials or print a path that itself embeds a credential value.
    privatePaths: [...privatePaths].sort().map(path => {
      for (const needle of credentials) if (!needle.public) path = path.replaceAll(needle.value, '[redacted]');
      return path;
    }),
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let report;
  try {
    if (process.argv.length !== 2) fail('NO_ARGUMENTS_ACCEPTED');
    const audit = await readAuditCredentials();
    const result = await scanSecretBoundary({root: fileURLToPath(new URL('../../../', import.meta.url)),
      credentials: audit.credentials});
    report = {...result.report, checkedAt: new Date().toISOString(),
      ...audit.verification};
    if (result.privatePaths.length) console.error(JSON.stringify({privateMatchFiles: result.privatePaths}));
  } catch (error) {
    report = {schemaVersion: 1, checkedAt: new Date().toISOString(), passed: false, completed: false,
      errorCode: error instanceof SecretBoundaryError ? error.code : 'SECRET_BOUNDARY_CHECK_FAILED',
      networkUsed: false, credentialValuesRecorded: false, credentialHashesRecorded: false};
  }
  const output = new URL('../../artifacts/verification/SECRET_BOUNDARY_CHECK.json', import.meta.url);
  await mkdir(new URL('.', output), {recursive: true});
  await writeFile(output, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report));
  if (!report.passed) process.exitCode = 1;
}
