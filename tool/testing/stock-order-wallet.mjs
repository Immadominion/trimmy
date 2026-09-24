/** Dedicated local research key. No transaction-signing interface is exported. */
import { constants } from 'node:fs';
import { lstat, mkdir, open } from 'node:fs/promises';
import { generateKeyPairSync, randomBytes, randomUUID, webcrypto } from 'node:crypto';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { createKeyPairFromBytes, getAddressFromPublicKey } from '@solana/kit';

export const STOCK_WALLET_NAME = 'stock-order-mainnet-v1';
export const STOCK_WALLET_GENESIS = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
const TOOL = 'trimmy-stock-order-inspection-v1';
export class StockWalletError extends Error { constructor(code) { super(code); this.name = 'StockWalletError'; this.code = code; } }
const fail = code => { throw new StockWalletError(code); };
const handles = new WeakSet();

async function syncDirectory(path) {
  const file = await open(path, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try { await file.sync(); } finally { await file.close(); }
}
async function directory(path, {create = false, privateMode = true} = {}) {
  if (create) {
    try { await mkdir(path, {mode: 0o700}); await syncDirectory(dirname(path)); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const stat = await lstat(path);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() ||
      (privateMode ? (stat.mode & 0o777) !== 0o700 : Boolean(stat.mode & 0o022))) fail('STOCK_WALLET_UNSAFE_DIRECTORY');
}
async function exclusiveJson(path, value) {
  const file = await open(path, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try {
    const stat = await file.stat();
    if ((stat.mode & 0o777) !== 0o600 || stat.nlink !== 1 || stat.uid !== process.getuid()) fail('STOCK_WALLET_UNSAFE_FILE');
    await file.writeFile(JSON.stringify(value) + '\n'); await file.sync();
  } finally { await file.close(); }
  await syncDirectory(dirname(path));
}
async function privateJson(path) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o777) !== 0o600 || stat.nlink !== 1 || stat.size > 8192) fail('STOCK_WALLET_UNSAFE_FILE');
    return JSON.parse(await file.readFile('utf8'));
  } finally { await file.close(); }
}
function markerValid(marker) {
  return marker && Object.getPrototypeOf(marker) === Object.prototype && marker.schemaVersion === 1 &&
    marker.createdBy === TOOL && marker.network === 'mainnet-beta' && marker.genesisHash === STOCK_WALLET_GENESIS &&
    marker.applicationAuthenticationVerified === false && marker.purpose === 'read_only_stock_order_inspection' &&
    typeof marker.publicAddress === 'string' && typeof marker.localResearchPrincipalId === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.exec(marker.localResearchPrincipalId)?.[0] === marker.localResearchPrincipalId;
}
async function verifyLocalKey(bytes, expectedAddress) {
  const keyPair = await createKeyPairFromBytes(bytes, false);
  const publicAddress = await getAddressFromPublicKey(keyPair.publicKey);
  if (expectedAddress !== undefined && publicAddress !== expectedAddress) fail('STOCK_WALLET_KEY_MISMATCH');
  const challenge = Buffer.concat([Buffer.from(`Trimmy local stock research key access v1\n${STOCK_WALLET_GENESIS}\n${publicAddress}\n`), randomBytes(32)]);
  let signature;
  try {
    signature = new Uint8Array(await webcrypto.subtle.sign('Ed25519', keyPair.privateKey, challenge));
    if (!await webcrypto.subtle.verify('Ed25519', keyPair.publicKey, signature, challenge)) fail('STOCK_WALLET_PROOF_FAILED');
    return publicAddress;
  } finally { signature?.fill(0); challenge.fill(0); }
}
/** The home override exists only for isolated temporary-directory tests.
 * CLI callers always use the OS home; there is no arbitrary key/path argument.
 */
export async function openStockResearchWallet({mode, homeDirectory = homedir()} = {}) {
  try {
    if (!['create', 'reopen'].includes(mode) || typeof homeDirectory !== 'string' || !isAbsolute(homeDirectory) || resolve(homeDirectory) !== homeDirectory) fail('STOCK_WALLET_INVALID_PATH');
    await directory(homeDirectory, {privateMode: false});
    const config = join(homeDirectory, '.config');
    await directory(config, {create: mode === 'create', privateMode: false});
    const trimmy = join(config, 'trimmy'); const testing = join(trimmy, 'testing'); const path = join(testing, STOCK_WALLET_NAME);
    for (const parent of [trimmy, testing]) await directory(parent, {create: mode === 'create'});
    let marker;
    if (mode === 'create') {
      // Exclusive directory creation is the concurrency guard. Never replace a key.
      try { await mkdir(path, {mode: 0o700}); } catch (error) { if (error.code === 'EEXIST') fail('STOCK_WALLET_ALREADY_EXISTS'); throw error; }
      await directory(path); await syncDirectory(testing);
      const pair = generateKeyPairSync('ed25519');
      const secretDer = pair.privateKey.export({type: 'pkcs8', format: 'der'});
      const publicDer = pair.publicKey.export({type: 'spki', format: 'der'});
      let bytes;
      try {
        if (secretDer.length !== 48 || publicDer.length !== 44) fail('STOCK_WALLET_KEY_ENCODING');
        bytes = Buffer.concat([secretDer.subarray(-32), publicDer.subarray(-32)]);
        const publicAddress = await verifyLocalKey(bytes);
        await exclusiveJson(join(path, 'keypair.json'), Array.from(bytes));
        marker = {schemaVersion: 1, createdBy: TOOL, purpose: 'read_only_stock_order_inspection', network: 'mainnet-beta',
          genesisHash: STOCK_WALLET_GENESIS, publicAddress, localResearchPrincipalId: randomUUID(), applicationAuthenticationVerified: false,
          createdAt: new Date().toISOString()};
        await exclusiveJson(join(path, 'wallet.json'), marker);
      } finally { bytes?.fill(0); secretDer.fill(0); }
    } else {
      await directory(path);
      // Validate provenance/network marker BEFORE touching the private key file.
      marker = await privateJson(join(path, 'wallet.json'));
      if (!markerValid(marker)) fail('STOCK_WALLET_MARKER_INVALID');
      const raw = await privateJson(join(path, 'keypair.json'));
      if (!Array.isArray(raw) || raw.length !== 64 || !raw.every(n => Number.isInteger(n) && n >= 0 && n <= 255)) fail('STOCK_WALLET_KEY_INVALID');
      const bytes = Uint8Array.from(raw);
      try { await verifyLocalKey(bytes, marker.publicAddress); }
      finally { bytes.fill(0); raw.fill(0); }
    }
    const wallet = Object.freeze({publicAddress: marker.publicAddress, localResearchPrincipalId: marker.localResearchPrincipalId,
      network: 'mainnet-beta', genesisHash: STOCK_WALLET_GENESIS, applicationAuthenticationVerified: false, localKeyAccessVerified: true,
      walletName: STOCK_WALLET_NAME});
    handles.add(wallet); return wallet;
  } catch (error) {
    if (error instanceof StockWalletError) throw error;
    // Never forward file contents, crypto details or raw filesystem exceptions.
    fail(error?.code === 'ENOENT' ? 'STOCK_WALLET_NOT_FOUND' : 'STOCK_WALLET_STORAGE_FAILED');
  }
}
export function assertStockResearchWallet(wallet) {
  if (!handles.has(wallet)) fail('STOCK_WALLET_UNRECOGNIZED_HANDLE');
}
