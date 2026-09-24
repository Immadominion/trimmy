/** Isolated, single-transfer devnet smoke. Never loads Solana CLI wallet config. */
import { constants as fsConstants } from 'node:fs';
import { lstat, mkdir, open, writeFile } from 'node:fs/promises';
import { generateKeyPairSync, randomUUID, webcrypto } from 'node:crypto';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  address, appendTransactionMessageInstruction, createKeyPairSignerFromBytes,
  createTransactionMessage, getAddressEncoder, getBase64EncodedWireTransaction, getSignatureFromTransaction,
  getCompiledTransactionMessageDecoder, getTransactionDecoder,
  setTransactionMessageFeePayerSigner, setTransactionMessageLifetimeUsingBlockhash,
  signTransactionMessageWithSigners,
} from '@solana/kit';
import { getTransferSolInstruction } from '@solana-program/system';

export const DEVNET_URL = 'https://api.devnet.solana.com';
export const DEVNET_GENESIS = 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG';
export const TRANSFER_LAMPORTS = 1_000_000;
const AIRDROP_LAMPORTS = 100_000_000;
const TOOL_ID = 'trimmy-isolated-devnet-smoke-v1';
const METHODS = new Set(['getGenesisHash', 'getBalance', 'requestAirdrop',
  'getSignatureStatuses', 'getLatestBlockhash', 'getFeeForMessage',
  'getMinimumBalanceForRentExemption', 'simulateTransaction', 'sendTransaction', 'getTransaction',
  'getBlockHeight', 'isBlockhashValid']);
export class SmokeError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const fail = (code) => { throw new SmokeError(code); };
const integer = (value) => Number.isSafeInteger(value) && value >= 0;
const delay = (ms) => new Promise((done) => setTimeout(done, ms));

export class DevnetRpc {
  #fetch; #id = 0; #timeout;
  constructor({ fetchImpl = fetch, timeoutMs = 10_000 } = {}) {
    this.#fetch = fetchImpl; this.#timeout = timeoutMs;
  }
  async call(method, params = []) {
    if (!METHODS.has(method)) fail('RPC_METHOD_NOT_ALLOWED');
    const id = ++this.#id;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeout);
    let reader;
    let exhausted = false;
    try {
      const response = await this.#fetch(DEVNET_URL, {
        method: 'POST', redirect: 'error', signal: controller.signal,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id, method, params }),
      });
      if (!response.ok) fail(`RPC_HTTP_${response.status}`);
      if (response.redirected || (response.url && response.url !== DEVNET_URL && response.url !== `${DEVNET_URL}/`)) {
        fail('RPC_REDIRECT_REJECTED');
      }
      if (!response.headers.get('content-type')?.toLowerCase().includes('application/json')) fail('RPC_INVALID_RESPONSE');
      reader = response.body?.getReader();
      if (!reader) fail('RPC_INVALID_RESPONSE');
      const chunks = [];
      let size = 0;
      for (;;) {
        const chunk = await reader.read();
        if (chunk.done) { exhausted = true; break; }
        size += chunk.value.byteLength;
        if (size > 262_144) fail('RPC_RESPONSE_TOO_LARGE');
        chunks.push(chunk.value);
      }
      const decoded = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (decoded?.jsonrpc !== '2.0' || decoded.id !== id) fail('RPC_INVALID_RESPONSE');
      if (decoded.error) fail(Number.isSafeInteger(decoded.error.code) ? `RPC_ERROR_${decoded.error.code}` : 'RPC_ERROR');
      if (!Object.hasOwn(decoded, 'result')) fail('RPC_INVALID_RESPONSE');
      return decoded.result;
    } catch (error) {
      if (error instanceof SmokeError) throw error;
      fail(controller.signal.aborted ? 'RPC_TIMEOUT' : 'RPC_TRANSPORT_FAILURE');
    } finally {
      clearTimeout(timer);
      if (reader && !exhausted) void reader.cancel().catch(() => {});
    }
  }
  async assertDevnet() {
    if (await this.call('getGenesisHash') !== DEVNET_GENESIS) fail('WRONG_CHAIN');
  }
}

async function privateDirectory(path) {
  let created = false;
  try { await mkdir(path, { mode: 0o700 }); created = true; } catch (error) { if (error.code !== 'EEXIST') throw error; }
  const stat = await lstat(path);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077)) {
    fail('UNSAFE_WALLET_DIRECTORY');
  }
  if (created) await syncDirectory(dirname(path));
}

export async function syncDirectory(path) {
  const handle = await open(path, fsConstants.O_RDONLY | fsConstants.O_DIRECTORY | fsConstants.O_NOFOLLOW);
  try { await handle.sync(); } finally { await handle.close(); }
}

export async function exclusiveJson(path, value, { syncParent = syncDirectory } = {}) {
  const handle = await open(path, fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_NOFOLLOW, 0o600);
  try { await handle.writeFile(`${JSON.stringify(value)}\n`); await handle.sync(); }
  finally { await handle.close(); }
  await syncParent(dirname(path));
}

async function privateJson(path) {
  const handle = await open(path, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o077) || stat.size > 8192) fail('UNSAFE_WALLET_FILE');
    return JSON.parse(await handle.readFile('utf8'));
  } finally { await handle.close(); }
}

function newSecretBytes() {
  const pair = generateKeyPairSync('ed25519');
  const privateDer = pair.privateKey.export({ type: 'pkcs8', format: 'der' });
  const publicDer = pair.publicKey.export({ type: 'spki', format: 'der' });
  if (privateDer.length !== 48 || publicDer.length !== 44) fail('UNEXPECTED_KEY_ENCODING');
  const bytes = Buffer.concat([privateDer.subarray(-32), publicDer.subarray(-32)]);
  privateDer.fill(0);
  return bytes;
}

export async function openTestWallet(baseDirectory, existingName) {
  await privateDirectory(baseDirectory);
  const name = existingName ?? `devnet-${randomUUID()}`;
  if (!/^devnet-[a-f0-9-]{36}$/.test(name) || name.length !== 43) fail('INVALID_WALLET_NAME');
  const directory = join(baseDirectory, name);
  if (existingName) {
    const stat = await lstat(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077)) fail('UNSAFE_WALLET_DIRECTORY');
    // The marker must validate before any signer bytes are read.
    const marker = await privateJson(join(directory, 'wallet.json'));
    if (marker?.schemaVersion !== 1 || marker.createdBy !== TOOL_ID || marker.network !== 'devnet' || marker.genesisHash !== DEVNET_GENESIS) {
      fail('UNRECOGNIZED_TEST_WALLET');
    }
    const raw = await privateJson(join(directory, 'signer.json'));
    if (!Array.isArray(raw) || raw.length !== 64 || !raw.every((n) => Number.isInteger(n) && n >= 0 && n <= 255)) fail('INVALID_TEST_KEY');
    const bytes = Uint8Array.from(raw);
    let signer;
    try { signer = await createKeyPairSignerFromBytes(bytes); } finally { bytes.fill(0); raw.fill(0); }
    if (signer.address !== marker.signer || address(marker.recipient) === signer.address) fail('INVALID_TEST_WALLET');
    return { name, directory, signer, recipient: address(marker.recipient) };
  }
  await mkdir(directory, { mode: 0o700 });
  await syncDirectory(baseDirectory);
  const keys = [];
  for (const filename of ['signer.json', 'recipient.json']) {
    const bytes = newSecretBytes();
    try {
      const signer = await createKeyPairSignerFromBytes(bytes);
      await exclusiveJson(join(directory, filename), Array.from(bytes));
      keys.push(signer);
    } finally { bytes.fill(0); }
  }
  const [signer, recipient] = keys;
  await exclusiveJson(join(directory, 'wallet.json'), {
    schemaVersion: 1, createdBy: TOOL_ID, network: 'devnet', genesisHash: DEVNET_GENESIS,
    signer: signer.address, recipient: recipient.address, createdAt: new Date().toISOString(),
  });
  return { name, directory, signer, recipient: recipient.address };
}

async function balance(rpc, publicKey) {
  const result = await rpc.call('getBalance', [publicKey, { commitment: 'confirmed' }]);
  if (!integer(result?.value)) fail('INVALID_BALANCE');
  return result.value;
}

export async function confirmSignature(rpc, signature, { attempts = 12, pause = delay, timeoutMs = 60_000 } = {}) {
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 60_000) fail('INVALID_CONFIRMATION_LIMIT');
  const deadline = Date.now() + timeoutMs;
  for (let attempt = 0; attempt < attempts; attempt++) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) fail('CONFIRMATION_PENDING');
    let timer;
    let result;
    try {
      result = await Promise.race([
        rpc.call('getSignatureStatuses', [[signature], { searchTransactionHistory: true }]),
        new Promise((_, reject) => { timer = setTimeout(() => reject(new SmokeError('CONFIRMATION_PENDING')), remaining); }),
      ]);
    } finally { clearTimeout(timer); }
    const status = result?.value?.[0];
    if (status) {
      if (status.err !== null) fail('TRANSACTION_FAILED');
      if (['confirmed', 'finalized'].includes(status.confirmationStatus)) return status.confirmationStatus;
    }
    if (attempt + 1 < attempts) await pause(Math.max(0, Math.min(2000, deadline - Date.now())));
  }
  fail('CONFIRMATION_PENDING');
}

export async function prepareTransfer(rpc, wallet) {
  const latest = await rpc.call('getLatestBlockhash', [{ commitment: 'confirmed' }]);
  if (!integer(latest?.value?.lastValidBlockHeight)) fail('INVALID_BLOCKHASH');
  let message = createTransactionMessage({ version: 0 });
  message = setTransactionMessageFeePayerSigner(wallet.signer, message);
  message = setTransactionMessageLifetimeUsingBlockhash({
    blockhash: address(latest.value.blockhash), lastValidBlockHeight: BigInt(latest.value.lastValidBlockHeight),
  }, message);
  message = appendTransactionMessageInstruction(getTransferSolInstruction({
    source: wallet.signer, destination: wallet.recipient, amount: BigInt(TRANSFER_LAMPORTS),
  }), message);
  const signed = await signTransactionMessageWithSigners(message);
  const valid = await webcrypto.subtle.verify('Ed25519', wallet.signer.keyPair.publicKey,
    signed.signatures[wallet.signer.address], signed.messageBytes);
  if (!valid) fail('LOCAL_SIGNATURE_INVALID');
  const fee = await rpc.call('getFeeForMessage', [Buffer.from(signed.messageBytes).toString('base64'), { commitment: 'confirmed' }]);
  if (!integer(fee?.value) || fee.value > 100_000) fail('UNEXPECTED_FEE');
  return { signature: getSignatureFromTransaction(signed), wire: getBase64EncodedWireTransaction(signed),
    feeLamports: fee.value, lastValidBlockHeight: latest.value.lastValidBlockHeight, localSignatureVerified: true };
}

export async function simulateAndSend(rpc, plan, beforeSend) {
  await rpc.assertDevnet();
  const simulation = await rpc.call('simulateTransaction', [plan.wire, {
    encoding: 'base64', commitment: 'confirmed', sigVerify: true,
  }]);
  if (simulation?.value?.err !== null) fail('SIMULATION_FAILED');
  if (!integer(simulation.value.unitsConsumed)) fail('INVALID_SIMULATION');
  await beforeSend(simulation.value.unitsConsumed);
  await rpc.assertDevnet();
  const receipt = await rpc.call('sendTransaction', [plan.wire, {
    encoding: 'base64', skipPreflight: false, preflightCommitment: 'confirmed', maxRetries: 3,
  }]);
  if (receipt !== plan.signature) fail('SIGNATURE_RECEIPT_MISMATCH');
  return simulation.value.unitsConsumed;
}

export async function validateSavedTransfer(plan, sender, recipient) {
  try {
    if (typeof plan?.wire !== 'string' || plan.wire.length > 2000 || !integer(plan.lastValidBlockHeight) ||
      !integer(plan.feeLamports) || plan.feeLamports > 100_000) fail('INVALID_SAVED_TRANSFER');
    const transaction = getTransactionDecoder().decode(Buffer.from(plan.wire, 'base64'));
    if (getBase64EncodedWireTransaction(transaction) !== plan.wire || getSignatureFromTransaction(transaction) !== plan.signature) fail('INVALID_SAVED_TRANSFER');
    const message = getCompiledTransactionMessageDecoder().decode(transaction.messageBytes);
    const instruction = message.instructions[0];
    const expectedData = Buffer.alloc(12);
    expectedData.writeUInt32LE(2);
    expectedData.writeBigUInt64LE(BigInt(TRANSFER_LAMPORTS), 4);
    if (message.version !== 0 || message.header.numSignerAccounts !== 1 || message.header.numReadonlySignerAccounts !== 0 ||
      message.header.numReadonlyNonSignerAccounts !== 1 || message.staticAccounts.length !== 3 ||
      message.staticAccounts[0] !== sender || message.staticAccounts[1] !== recipient ||
      message.staticAccounts[2] !== '11111111111111111111111111111111' || message.addressTableLookups?.length ||
      message.instructions.length !== 1 || instruction.programAddressIndex !== 2 ||
      instruction.accountIndices.length !== 2 || instruction.accountIndices[0] !== 0 || instruction.accountIndices[1] !== 1 ||
      !Buffer.from(instruction.data).equals(expectedData)) fail('INVALID_SAVED_TRANSFER');
    const publicKey = await webcrypto.subtle.importKey('raw', getAddressEncoder().encode(address(sender)), 'Ed25519', false, ['verify']);
    if (!await webcrypto.subtle.verify('Ed25519', publicKey, transaction.signatures[sender], transaction.messageBytes)) fail('INVALID_SAVED_TRANSFER');
    return message.lifetimeToken;
  } catch { fail('INVALID_SAVED_TRANSFER'); }
}

/** At most one acknowledged retry of the exact saved wire bytes. Never obtains a new blockhash. */
export async function recoverSignedTransfer(rpc, plan, {
  sender, recipient, senderBeforeLamports, recipientBeforeLamports,
  identityCheck = () => rpc.assertDevnet(), beforeResend, confirmation = {},
}) {
  await identityCheck();
  const blockhash = await validateSavedTransfer(plan, sender, recipient);
  const statuses = await rpc.call('getSignatureStatuses', [[plan.signature], { searchTransactionHistory: true }]);
  if (!Array.isArray(statuses?.value) || statuses.value.length !== 1) fail('INVALID_RECOVERY_STATUS');
  const status = statuses.value[0];
  if (status !== null && (!status || typeof status !== 'object' || Array.isArray(status) ||
    !Object.hasOwn(status, 'err') || !['processed', 'confirmed', 'finalized'].includes(status.confirmationStatus))) fail('INVALID_RECOVERY_STATUS');
  if (status && status.err !== null) fail('RECOVERY_TRANSACTION_FAILED');
  if (status && ['confirmed', 'finalized'].includes(status.confirmationStatus)) {
    return { status: 'confirmed', signature: plan.signature, rebroadcast: false, confirmation: status.confirmationStatus };
  }
  const transaction = await rpc.call('getTransaction', [plan.signature, { encoding: 'json', commitment: 'confirmed', maxSupportedTransactionVersion: 0 }]);
  if (transaction !== null) fail('RECOVERY_STATUS_INCONSISTENT');
  const height = await rpc.call('getBlockHeight', [{ commitment: 'confirmed' }]);
  const validity = await rpc.call('isBlockhashValid', [blockhash, { commitment: 'confirmed' }]);
  if (!integer(height) || typeof validity?.value !== 'boolean') fail('INVALID_RECOVERY_LIFETIME');
  const senderBalance = await balance(rpc, sender);
  const recipientBalance = await balance(rpc, recipient);
  if (!integer(senderBeforeLamports) || !integer(recipientBeforeLamports) ||
    senderBalance !== senderBeforeLamports || recipientBalance !== recipientBeforeLamports) fail('RECOVERY_BALANCE_CONFLICT');
  if (height > plan.lastValidBlockHeight) {
    if (status || validity.value) fail('RECOVERY_LIFETIME_INCONSISTENT');
    return { status: 'expired', signature: plan.signature, rebroadcast: false, height,
      lastValidBlockHeight: plan.lastValidBlockHeight, oldTransactionAbsent: true,
      balancesUnchanged: true, senderBalanceLamports: senderBalance, recipientBalanceLamports: recipientBalance };
  }
  if (!validity.value) fail('RECOVERY_BLOCKHASH_UNAVAILABLE');
  if (typeof beforeResend !== 'function') fail('RECOVERY_ACK_REQUIRED');
  await identityCheck();
  await beforeResend();
  const receipt = await rpc.call('sendTransaction', [plan.wire, {
    encoding: 'base64', skipPreflight: false, preflightCommitment: 'confirmed', maxRetries: 3,
  }]);
  if (receipt !== plan.signature) fail('SIGNATURE_RECEIPT_MISMATCH');
  return { status: 'confirmed', signature: plan.signature, rebroadcast: true,
    confirmation: await confirmSignature(rpc, plan.signature, confirmation) };
}

export async function runDevnetSmoke({ rpc = new DevnetRpc(), baseDirectory, existingName, notify = () => {} } = {}) {
  const report = { schemaVersion: 1, network: 'devnet', endpoint: DEVNET_URL,
    expectedGenesisHash: DEVNET_GENESIS, startedAt: new Date().toISOString(),
    scope: 'Isolated test-wallet SOL transport; no app, wallet-adapter, trading, custody or mainnet verification.',
    transferLamports: TRANSFER_LAMPORTS, status: 'starting' };
  try {
    await rpc.assertDevnet();
    report.genesisVerified = true;
    const wallet = await openTestWallet(baseDirectory, existingName);
    report.walletName = wallet.name;
    report.signer = wallet.signer.address;
    report.recipient = wallet.recipient;
    notify({ network: report.network, walletName: report.walletName, signer: report.signer, recipient: report.recipient });
    // Never create a second transfer from a wallet whose first submission might have committed.
    try { await lstat(join(wallet.directory, 'transfer.json')); fail('TRANSFER_ALREADY_PLANNED'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    report.initialBalanceLamports = await balance(rpc, wallet.signer.address);
    const minimum = await rpc.call('getMinimumBalanceForRentExemption', [0, { commitment: 'confirmed' }]);
    if (!integer(minimum) || TRANSFER_LAMPORTS < minimum) fail('RECIPIENT_RENT_BOUNDARY');
    if (report.initialBalanceLamports < TRANSFER_LAMPORTS + 100_000) {
      await rpc.assertDevnet();
      report.airdropRequestedLamports = AIRDROP_LAMPORTS;
      report.airdropSignature = await rpc.call('requestAirdrop', [wallet.signer.address, AIRDROP_LAMPORTS, { commitment: 'confirmed' }]);
      if (typeof report.airdropSignature !== 'string' || !/^[1-9A-HJ-NP-Za-km-z]{64,90}$/.test(report.airdropSignature)) fail('INVALID_AIRDROP_RECEIPT');
      report.airdropConfirmation = await confirmSignature(rpc, report.airdropSignature);
    }
    report.senderBeforeLamports = await balance(rpc, wallet.signer.address);
    report.recipientBeforeLamports = await balance(rpc, wallet.recipient);
    const plan = await prepareTransfer(rpc, wallet);
    report.localSignatureVerified = plan.localSignatureVerified;
    report.transferSignature = plan.signature;
    report.feeLamports = plan.feeLamports;
    if (report.senderBeforeLamports < TRANSFER_LAMPORTS + plan.feeLamports) fail('INSUFFICIENT_DEVNET_FUNDS');
    report.simulationUnits = await simulateAndSend(rpc, plan, async (units) => {
      report.simulationUnits = units;
      // A public signed plan is durably saved before broadcasting. No secret key is included.
      await exclusiveJson(join(wallet.directory, 'transfer.json'), {
        schemaVersion: 1, network: 'devnet', genesisHash: DEVNET_GENESIS, ...plan,
        sender: report.signer, recipient: report.recipient, amountLamports: TRANSFER_LAMPORTS,
        senderBeforeLamports: report.senderBeforeLamports, recipientBeforeLamports: report.recipientBeforeLamports,
      });
      report.planPersistedBeforeSend = true;
      notify({ phase: 'signed-and-simulated', signature: plan.signature });
    });
    report.transferConfirmation = await confirmSignature(rpc, plan.signature);
    const transaction = await rpc.call('getTransaction', [plan.signature, {
      encoding: 'json', commitment: 'confirmed', maxSupportedTransactionVersion: 0,
    }]);
    if (!transaction || transaction.meta?.err !== null || transaction.meta.fee !== plan.feeLamports ||
      transaction.transaction?.signatures?.[0] !== plan.signature) fail('CONFIRMED_TRANSACTION_MISMATCH');
    report.confirmedSlot = transaction.slot;
    report.senderAfterLamports = await balance(rpc, wallet.signer.address);
    report.recipientAfterLamports = await balance(rpc, wallet.recipient);
    if (report.senderAfterLamports !== report.senderBeforeLamports - TRANSFER_LAMPORTS - plan.feeLamports ||
      report.recipientAfterLamports !== report.recipientBeforeLamports + TRANSFER_LAMPORTS) fail('BALANCE_DELTA_MISMATCH');
    report.balanceDeltasVerified = true;
    report.status = 'confirmed';
  } catch (error) {
    report.status = 'incomplete';
    report.errorCode = error instanceof SmokeError ? error.code : 'LOCAL_TEST_SETUP_FAILURE';
  }
  report.finishedAt = new Date().toISOString();
  return report;
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length && !(args.length === 2 && args[0] === '--wallet')) fail('USAGE_ONLY_OPTION_IS_WALLET_NAME');
  const config = join(homedir(), '.config');
  let configCreated = false;
  try { await mkdir(config, { mode: 0o700 }); configCreated = true; } catch (error) { if (error.code !== 'EEXIST') throw error; }
  const configStat = await lstat(config);
  if (!configStat.isDirectory() || configStat.isSymbolicLink() || configStat.uid !== process.getuid()) fail('UNSAFE_CONFIG_DIRECTORY');
  if (configCreated) await syncDirectory(homedir());
  await privateDirectory(join(config, 'trimmy'));
  const report = await runDevnetSmoke({ baseDirectory: join(config, 'trimmy', 'testing'), existingName: args[1],
    notify: (value) => process.stdout.write(`${JSON.stringify(value)}\n`) });
  const artifact = resolve(dirname(fileURLToPath(import.meta.url)), '../../artifacts/verification/SOLANA_DEVNET.json');
  await writeFile(artifact, `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (report.status !== 'confirmed') process.exitCode = 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof SmokeError ? error.code : 'LOCAL_TEST_SETUP_FAILURE'}\n`);
    process.exitCode = 2;
  });
}
