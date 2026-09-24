/**
 * Returns the dedicated research wallet's funds to an address the operator
 * names. This is the only module in the repository that signs and submits a
 * Solana transaction on a public cluster, and it can do exactly one thing:
 * move the wallet's own SOL or its own USDC balance out to a destination given
 * on the command line. It builds no swap, quotes no price, touches no product
 * account and reads no Solana CLI configuration or user wallet.
 *
 * Every rule from the isolated recovery harness applies here. A durable plan is
 * written before anything is sent. Successful submission is not confirmation. An
 * uncertain result may only be retried by resending the exact same signed bytes,
 * and a different transaction is permitted only after the original's blockhash
 * has demonstrably expired, the signature is absent, and the balances are
 * unchanged.
 */
import { constants as fsConstants } from 'node:fs';
import { createHash } from 'node:crypto';
import { lstat, open, readdir, unlink } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  address, appendTransactionMessageInstruction, createKeyPairSignerFromBytes, createTransactionMessage,
  getBase64EncodedWireTransaction, getSignatureFromTransaction, isOffCurveAddress,
  setTransactionMessageFeePayerSigner, setTransactionMessageLifetimeUsingBlockhash, signTransactionMessageWithSigners,
} from '@solana/kit';
import { getTransferSolInstruction } from '@solana-program/system';
import { getCloseAccountInstruction, getCreateAssociatedTokenIdempotentInstruction,
  getTransferCheckedInstruction } from '@solana-program/token';
import { findAssociatedTokenPda } from '@solana-program/token-2022';
import { STOCK_WALLET_NAME, STOCK_WALLET_GENESIS } from './stock-order-wallet.mjs';

export const STOCK_RETURN_TOOL_ID = 'trimmy-stock-order-return-v1';
export const MAINNET_URL = 'https://api.mainnet-beta.solana.com';
export const LOCALNET_URL = 'http://127.0.0.1:18999';
export const DEVNET_GENESIS = 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG';
export const USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
export const TOKEN_PROGRAM = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
export const PLAN_FILENAME = 'return-plan.json';
/** A transfer of this shape costs one signature; anything larger is refused. */
export const MAX_FEE_LAMPORTS = 100_000;
const METHODS = new Set(['getGenesisHash', 'getBalance', 'getTokenAccountsByOwner', 'getMultipleAccounts',
  'getLatestBlockhash', 'getFeeForMessage', 'getMinimumBalanceForRentExemption', 'simulateTransaction',
  'sendTransaction', 'getSignatureStatuses', 'getTransaction', 'getBlockHeight', 'isBlockhashValid']);

export class StockReturnError extends Error {
  constructor(code) { super(code); this.name = 'StockReturnError'; this.code = code; }
}
const fail = code => { throw new StockReturnError(code); };
const integer = value => Number.isSafeInteger(value) && value >= 0;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const delay = ms => new Promise(done => setTimeout(done, ms));
const sha256 = value => createHash('sha256').update(value).digest('hex');

function rawAmount(value, code = 'RETURN_AMOUNT_INVALID') {
  if (typeof value !== 'string' || /^(?:0|[1-9][0-9]{0,19})$/.exec(value)?.[0] !== value) fail(code);
  const parsed = BigInt(value);
  if (parsed > 18446744073709551615n) fail(code);
  return parsed;
}

/** A destination must be a real, on-curve, nonzero address that is not the source. */
export function returnDestination(value, source) {
  try {
    if (typeof value !== 'string' || value.length < 32 || value.length > 44) fail('RETURN_DESTINATION_INVALID');
    const parsed = address(value);
    if (parsed !== value || isOffCurveAddress(parsed)) fail('RETURN_DESTINATION_INVALID');
    if (parsed === '11111111111111111111111111111111') fail('RETURN_DESTINATION_INVALID');
    if (source !== undefined && parsed === source) fail('RETURN_DESTINATION_IS_SOURCE');
    return parsed;
  } catch (error) {
    if (error instanceof StockReturnError) throw error;
    return fail('RETURN_DESTINATION_INVALID');
  }
}

export class ReturnRpc {
  #url; #network; #fetch; #timeout; #id = 0;
  constructor({network, fetchImpl = fetch, timeoutMs = 10_000} = {}) {
    if (!['mainnet-beta', 'localnet'].includes(network)) fail('RETURN_NETWORK_INVALID');
    if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 20_000) fail('RETURN_CONFIGURATION_INVALID');
    this.#network = network;
    this.#url = network === 'mainnet-beta' ? MAINNET_URL : LOCALNET_URL;
    this.#fetch = fetchImpl;
    this.#timeout = timeoutMs;
  }
  get network() { return this.#network; }
  get url() { return this.#url; }
  async call(method, params = []) {
    if (!METHODS.has(method)) fail('RETURN_RPC_METHOD_DENIED');
    const id = ++this.#id;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeout);
    let reader; let exhausted = false;
    try {
      const response = await this.#fetch(this.#url, {
        method: 'POST', redirect: 'error', signal: controller.signal,
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({jsonrpc: '2.0', id, method, params}),
      });
      if (!response.ok) fail(`RETURN_RPC_HTTP_${response.status}`);
      if (response.redirected) fail('RETURN_RPC_REDIRECT_REJECTED');
      if (!response.headers.get('content-type')?.toLowerCase().includes('application/json')) fail('RETURN_RPC_INVALID');
      reader = response.body?.getReader();
      if (!reader) fail('RETURN_RPC_INVALID');
      const chunks = []; let size = 0;
      for (;;) {
        const chunk = await reader.read();
        if (chunk.done) { exhausted = true; break; }
        size += chunk.value.byteLength;
        if (size > 262_144) fail('RETURN_RPC_TOO_LARGE');
        chunks.push(chunk.value);
      }
      const decoded = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (decoded?.jsonrpc !== '2.0' || decoded.id !== id) fail('RETURN_RPC_INVALID');
      if (decoded.error) fail(Number.isSafeInteger(decoded.error?.code) ? `RETURN_RPC_ERROR_${decoded.error.code}` : 'RETURN_RPC_ERROR');
      if (!Object.hasOwn(decoded, 'result')) fail('RETURN_RPC_INVALID');
      return decoded.result;
    } catch (error) {
      if (error instanceof StockReturnError) throw error;
      fail(controller.signal.aborted ? 'RETURN_RPC_TIMEOUT' : 'RETURN_RPC_TRANSPORT_FAILURE');
    } finally {
      clearTimeout(timer);
      if (reader && !exhausted) void reader.cancel().catch(() => {});
    }
  }
  /** Mainnet is pinned to its exact genesis; localnet must not be a public cluster. */
  async assertNetwork() {
    const genesis = await this.call('getGenesisHash');
    if (typeof genesis !== 'string') fail('RETURN_RPC_INVALID');
    if (this.#network === 'mainnet-beta') {
      if (genesis !== STOCK_WALLET_GENESIS) fail('RETURN_WRONG_NETWORK');
    } else if (genesis === STOCK_WALLET_GENESIS || genesis === DEVNET_GENESIS) {
      fail('RETURN_WRONG_NETWORK');
    }
    return genesis;
  }
}

async function privateJson(path) {
  const file = await open(path, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o777) !== 0o600 ||
        stat.nlink !== 1 || stat.size > 8192) fail('RETURN_UNSAFE_FILE');
    return JSON.parse(await file.readFile('utf8'));
  } finally { await file.close(); }
}

async function syncDirectory(path) {
  const file = await open(path, fsConstants.O_RDONLY | fsConstants.O_DIRECTORY | fsConstants.O_NOFOLLOW);
  try { await file.sync(); } finally { await file.close(); }
}

/** Exclusive create is the one-use guard: a second plan cannot overwrite a first. */
export async function writeExclusiveJson(path, value) {
  let file;
  try {
    file = await open(path, fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_NOFOLLOW, 0o600);
  } catch (error) {
    if (error?.code === 'EEXIST') fail('RETURN_PLAN_ALREADY_EXISTS');
    throw error;
  }
  try { await file.writeFile(`${JSON.stringify(value)}\n`); await file.sync(); }
  finally { await file.close(); }
  await syncDirectory(dirname(path));
}

/**
 * Opens the research wallet's key as a signer. The read-only inspection module
 * deliberately exposes no signing interface, so this module validates the same
 * provenance marker itself and never accepts a key path from a caller.
 */
export async function openReturnSigner({homeDirectory = homedir()} = {}) {
  try {
    if (typeof homeDirectory !== 'string' || !isAbsolute(homeDirectory) || resolve(homeDirectory) !== homeDirectory) {
      fail('RETURN_INVALID_PATH');
    }
    const directory = join(homeDirectory, '.config', 'trimmy', 'testing', STOCK_WALLET_NAME);
    const stat = await lstat(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() ||
        (stat.mode & 0o777) !== 0o700) fail('RETURN_UNSAFE_DIRECTORY');
    // Provenance and network are checked before the private key is read.
    const marker = await privateJson(join(directory, 'wallet.json'));
    if (!object(marker) || marker.schemaVersion !== 1 || marker.network !== 'mainnet-beta' ||
        marker.genesisHash !== STOCK_WALLET_GENESIS || typeof marker.publicAddress !== 'string') {
      fail('RETURN_MARKER_INVALID');
    }
    const raw = await privateJson(join(directory, 'keypair.json'));
    if (!Array.isArray(raw) || raw.length !== 64 || !raw.every(n => Number.isInteger(n) && n >= 0 && n <= 255)) {
      fail('RETURN_KEY_INVALID');
    }
    const bytes = Uint8Array.from(raw);
    let signer;
    try { signer = await createKeyPairSignerFromBytes(bytes); }
    finally { bytes.fill(0); raw.fill(0); }
    if (signer.address !== marker.publicAddress) fail('RETURN_KEY_MISMATCH');
    return Object.freeze({signer, publicAddress: marker.publicAddress, directory});
  } catch (error) {
    if (error instanceof StockReturnError) throw error;
    fail(error?.code === 'ENOENT' ? 'RETURN_WALLET_NOT_FOUND' : 'RETURN_STORAGE_FAILED');
  }
}

async function solLamports(rpc, publicAddress, minimumContextSlot) {
  const options = {commitment: 'confirmed'};
  if (minimumContextSlot !== undefined) options.minContextSlot = minimumContextSlot;
  const result = await rpc.call('getBalance', [publicAddress, options]);
  if (!object(result) || !object(result.context) || !integer(result.context.slot) || !integer(result.value)) {
    fail('RETURN_BALANCE_INVALID');
  }
  return {lamports: BigInt(result.value), slot: result.context.slot};
}

/** The owner's canonical USDC account and its exact balance. */
export async function tokenPosition(rpc, owner, {mint = USDC_MINT, decimals = 6} = {}) {
  const [associated] = await findAssociatedTokenPda({
    owner: address(owner), mint: address(mint), tokenProgram: address(TOKEN_PROGRAM),
  });
  const result = await rpc.call('getTokenAccountsByOwner', [owner, {mint},
    {encoding: 'jsonParsed', commitment: 'confirmed'}]);
  if (!object(result) || !Array.isArray(result.value) || result.value.length > 32) fail('RETURN_BALANCE_INVALID');
  let associatedRaw = 0n; let ancillary = 0;
  for (const entry of result.value) {
    const info = entry?.account?.data?.parsed?.info;
    if (!object(entry) || typeof entry.pubkey !== 'string' || !object(info) || info.owner !== owner ||
        info.mint !== mint || info.tokenAmount?.decimals !== decimals) fail('RETURN_BALANCE_INVALID');
    if (entry.pubkey === associated) associatedRaw = rawAmount(info.tokenAmount.amount);
    else ancillary += 1;
  }
  return {associated, associatedRaw, ancillaryAccounts: ancillary, decimals, mint};
}

async function readAccount(rpc, publicAddress) {
  const result = await rpc.call('getMultipleAccounts', [[publicAddress], {encoding: 'base64', commitment: 'confirmed'}]);
  if (!object(result) || !Array.isArray(result.value) || result.value.length !== 1) fail('RETURN_RPC_INVALID');
  const value = result.value[0];
  if (value === null) return null;
  if (!object(value) || !integer(value.lamports)) fail('RETURN_RPC_INVALID');
  return {lamports: BigInt(value.lamports)};
}

async function signedTransfer({rpc, signer, blockhash, lastValidBlockHeight, instructions}) {
  let message = createTransactionMessage({version: 0});
  message = setTransactionMessageFeePayerSigner(signer, message);
  message = setTransactionMessageLifetimeUsingBlockhash({
    blockhash: address(blockhash), lastValidBlockHeight: BigInt(lastValidBlockHeight),
  }, message);
  for (const instruction of instructions) message = appendTransactionMessageInstruction(instruction, message);
  const signed = await signTransactionMessageWithSigners(message);
  const fee = await rpc.call('getFeeForMessage', [Buffer.from(signed.messageBytes).toString('base64'), {commitment: 'confirmed'}]);
  if (!integer(fee?.value) || fee.value > MAX_FEE_LAMPORTS) fail('RETURN_FEE_UNEXPECTED');
  return {
    signature: getSignatureFromTransaction(signed),
    wire: getBase64EncodedWireTransaction(signed),
    messageSha256: sha256(Buffer.from(signed.messageBytes)),
    feeLamports: fee.value,
  };
}

/**
 * Builds and signs exactly one return transfer. For SOL it sweeps the balance
 * minus the measured fee; for USDC it moves the whole canonical balance and
 * creates the destination's account only when that account is missing.
 */
export async function planReturn({rpc, signer, publicAddress, asset, destination, now = Date.now,
  token = {mint: USDC_MINT, decimals: 6}} = {}) {
  if (!['sol', 'usdc'].includes(asset)) fail('RETURN_ASSET_INVALID');
  // The command line never supplies a token: mainnet returns are USDC only. The
  // parameter exists so a local validator can exercise this path with its own mint.
  if (!object(token) || typeof token.mint !== 'string' || !Number.isInteger(token.decimals) ||
      token.decimals < 0 || token.decimals > 18) fail('RETURN_ASSET_INVALID');
  const source = publicAddress ?? signer?.address;
  if (typeof source !== 'string' || source !== signer?.address) fail('RETURN_SIGNER_INVALID');
  const to = returnDestination(destination, source);
  const genesisHash = await rpc.assertNetwork();
  const latest = await rpc.call('getLatestBlockhash', [{commitment: 'confirmed'}]);
  if (!object(latest?.value) || typeof latest.value.blockhash !== 'string' ||
      !integer(latest.value.lastValidBlockHeight)) fail('RETURN_BLOCKHASH_INVALID');
  const {blockhash, lastValidBlockHeight} = latest.value;
  const balanceBefore = await solLamports(rpc, source);
  const common = {
    schemaVersion: 1, createdBy: STOCK_RETURN_TOOL_ID, network: rpc.network, genesisHash, asset,
    source, destination: to, blockhash, lastValidBlockHeight,
    sourceLamportsBefore: balanceBefore.lamports.toString(), observedSlot: balanceBefore.slot,
    createdAt: new Date(now()).toISOString(),
  };

  if (asset === 'sol') {
    // An emptied token account still holds its rent. Closing it in the same
    // transaction is the difference between recovering the wallet and leaving
    // a few thousand lamports stranded per token for good.
    // Recovering SOL must never depend on a token lookup succeeding: a mint that
    // does not exist on this cluster only costs the close optimization.
    let position = null;
    let tokenAccount = null;
    try {
      position = await tokenPosition(rpc, source, token);
      tokenAccount = await readAccount(rpc, position.associated);
    } catch (error) {
      if (!(error instanceof StockReturnError)) throw error;
      position = null;
      tokenAccount = null;
    }
    const closes = position !== null && tokenAccount !== null && position.associatedRaw === 0n;
    const reclaimed = closes ? tokenAccount.lamports : 0n;
    const prefix = closes
      ? [getCloseAccountInstruction({account: address(position.associated), destination: address(source),
        owner: signer}, {programAddress: address(TOKEN_PROGRAM)})]
      : [];
    // The fee does not depend on the amounts, so a one-lamport draft measures it.
    const draft = await signedTransfer({rpc, signer, blockhash, lastValidBlockHeight,
      instructions: [...prefix, getTransferSolInstruction({source: signer, destination: address(to), amount: 1n})]});
    const amount = balanceBefore.lamports + reclaimed - BigInt(draft.feeLamports);
    if (amount <= 0n) fail('RETURN_BALANCE_INSUFFICIENT');
    const final = await signedTransfer({rpc, signer, blockhash, lastValidBlockHeight,
      instructions: [...prefix, getTransferSolInstruction({source: signer, destination: address(to), amount})]});
    if (final.feeLamports !== draft.feeLamports) fail('RETURN_FEE_UNEXPECTED');
    return Object.freeze({...common, amountRaw: amount.toString(), decimals: 9,
      createsDestinationAccount: false, rentLamports: '0',
      closesSourceTokenAccount: closes, reclaimedRentLamports: reclaimed.toString(),
      // A nonzero token balance must be returned first or it would be unreachable.
      tokenBalanceRemains: position !== null && position.associatedRaw > 0n,
      tokenAccountChecked: position !== null, ...final});
  }

  const position = await tokenPosition(rpc, source, token);
  if (position.associatedRaw <= 0n) fail('RETURN_BALANCE_INSUFFICIENT');
  const [destinationAssociated] = await findAssociatedTokenPda({
    owner: address(to), mint: address(token.mint), tokenProgram: address(TOKEN_PROGRAM),
  });
  const exists = (await readAccount(rpc, destinationAssociated)) !== null;
  let rentLamports = 0n;
  if (!exists) {
    const rent = await rpc.call('getMinimumBalanceForRentExemption', [165]);
    if (!integer(rent)) fail('RETURN_RPC_INVALID');
    rentLamports = BigInt(rent);
  }
  const instructions = [];
  if (!exists) {
    instructions.push(getCreateAssociatedTokenIdempotentInstruction({
      payer: signer, ata: address(destinationAssociated), owner: address(to), mint: address(token.mint),
      tokenProgram: address(TOKEN_PROGRAM),
    }));
  }
  instructions.push(getTransferCheckedInstruction({
    source: address(position.associated), mint: address(token.mint), destination: address(destinationAssociated),
    authority: signer, amount: position.associatedRaw, decimals: position.decimals,
  }, {programAddress: address(TOKEN_PROGRAM)}));
  const final = await signedTransfer({rpc, signer, blockhash, lastValidBlockHeight, instructions});
  if (balanceBefore.lamports < BigInt(final.feeLamports) + rentLamports) fail('RETURN_BALANCE_INSUFFICIENT');
  return Object.freeze({...common, amountRaw: position.associatedRaw.toString(), decimals: position.decimals,
    mint: position.mint, sourceTokenAccount: position.associated, destinationTokenAccount: destinationAssociated,
    ancillaryAccounts: position.ancillaryAccounts, createsDestinationAccount: !exists,
    rentLamports: rentLamports.toString(), ...final});
}

export function validatePlan(plan, {network} = {}) {
  if (!object(plan) || plan.schemaVersion !== 1 || plan.createdBy !== STOCK_RETURN_TOOL_ID ||
      !['sol', 'usdc'].includes(plan.asset) || !['mainnet-beta', 'localnet'].includes(plan.network) ||
      (network !== undefined && plan.network !== network) ||
      typeof plan.wire !== 'string' || plan.wire.length < 1 || plan.wire.length > 2_000 ||
      typeof plan.signature !== 'string' || !/^[1-9A-HJ-NP-Za-km-z]{64,88}$/.test(plan.signature) ||
      typeof plan.messageSha256 !== 'string' || !/^[0-9a-f]{64}$/.test(plan.messageSha256) ||
      typeof plan.blockhash !== 'string' || !integer(plan.lastValidBlockHeight) ||
      !integer(plan.feeLamports) || plan.feeLamports > MAX_FEE_LAMPORTS) {
    fail('RETURN_PLAN_INVALID');
  }
  // A malformed stored plan is one condition, whichever field is wrong.
  rawAmount(plan.amountRaw, 'RETURN_PLAN_INVALID');
  rawAmount(plan.sourceLamportsBefore, 'RETURN_PLAN_INVALID');
  rawAmount(plan.rentLamports, 'RETURN_PLAN_INVALID');
  returnDestination(plan.destination, plan.source);
  return plan;
}

/**
 * Polls for confirmation and, every few attempts, rebroadcasts the identical
 * signed bytes. A network can accept a transaction and still drop it, and
 * resending the same signature is idempotent: it either lands once or not at
 * all. This never builds a second transaction, so it cannot double-spend.
 */
async function confirm(rpc, signature, {attempts = 25, pause = delay, timeoutMs = 60_000,
  resend = null, resendEvery = 5} = {}) {
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 120_000) fail('RETURN_CONFIRMATION_LIMIT_INVALID');
  const deadline = Date.now() + timeoutMs;
  let rebroadcasts = 0;
  for (let attempt = 0; attempt < attempts; attempt++) {
    if (Date.now() >= deadline) fail('RETURN_CONFIRMATION_PENDING');
    const result = await rpc.call('getSignatureStatuses', [[signature], {searchTransactionHistory: true}]);
    if (!object(result) || !Array.isArray(result.value) || result.value.length !== 1) fail('RETURN_STATUS_INVALID');
    const status = result.value[0];
    if (status !== null) {
      if (!object(status) || !Object.hasOwn(status, 'err')) fail('RETURN_STATUS_INVALID');
      if (status.err !== null) fail('RETURN_TRANSACTION_FAILED');
      if (['confirmed', 'finalized'].includes(status.confirmationStatus)) {
        return {confirmation: status.confirmationStatus, rebroadcasts};
      }
    }
    if (resend !== null && attempt > 0 && attempt % resendEvery === 0) {
      const valid = await rpc.call('isBlockhashValid', [resend.blockhash, {commitment: 'confirmed'}]);
      if (valid?.value === true) { await resend.send(); rebroadcasts += 1; }
    }
    if (attempt + 1 < attempts) await pause(Math.max(0, Math.min(2_000, deadline - Date.now())));
  }
  return fail('RETURN_CONFIRMATION_PENDING');
}

async function sendExact(rpc, plan) {
  const receipt = await rpc.call('sendTransaction', [plan.wire,
    {encoding: 'base64', skipPreflight: false, preflightCommitment: 'confirmed', maxRetries: 3}]);
  if (receipt !== plan.signature) fail('RETURN_SIGNATURE_RECEIPT_MISMATCH');
  return receipt;
}

/**
 * Simulates with signature verification on, submits once, then confirms. The
 * caller has already durably stored the plan, so an uncertain result is
 * recoverable by resending these exact bytes.
 */
export async function submitPlan({rpc, plan, confirmation = {}}) {
  validatePlan(plan, {network: rpc.network});
  await rpc.assertNetwork();
  const simulation = await rpc.call('simulateTransaction', [plan.wire,
    {encoding: 'base64', commitment: 'confirmed', sigVerify: true, replaceRecentBlockhash: false}]);
  if (!object(simulation?.value)) fail('RETURN_SIMULATION_INVALID');
  if (simulation.value.err !== null) fail('RETURN_SIMULATION_FAILED');
  if (!integer(simulation.value.unitsConsumed)) fail('RETURN_SIMULATION_INVALID');
  await rpc.assertNetwork();
  await sendExact(rpc, plan);
  const settled = await confirm(rpc, plan.signature, {...confirmation,
    resend: {blockhash: plan.blockhash, send: () => sendExact(rpc, plan)}});
  return Object.freeze({signature: plan.signature, unitsConsumed: simulation.value.unitsConsumed,
    confirmation: settled.confirmation, rebroadcasts: settled.rebroadcasts});
}

/**
 * Resolves a stored plan whose outcome is unknown. It confirms, or resends the
 * exact same bytes while the blockhash lives, or reports expiry only once the
 * signature is absent and the balance is unchanged.
 */
export async function resolvePlan({rpc, plan, confirmation = {}}) {
  validatePlan(plan, {network: rpc.network});
  await rpc.assertNetwork();
  const statuses = await rpc.call('getSignatureStatuses', [[plan.signature], {searchTransactionHistory: true}]);
  if (!object(statuses) || !Array.isArray(statuses.value) || statuses.value.length !== 1) fail('RETURN_STATUS_INVALID');
  const status = statuses.value[0];
  if (status !== null) {
    if (!object(status) || !Object.hasOwn(status, 'err')) fail('RETURN_STATUS_INVALID');
    if (status.err !== null) fail('RETURN_TRANSACTION_FAILED');
    if (['confirmed', 'finalized'].includes(status.confirmationStatus)) {
      return Object.freeze({status: 'confirmed', signature: plan.signature, rebroadcast: false,
        confirmation: status.confirmationStatus});
    }
  }
  const transaction = await rpc.call('getTransaction', [plan.signature,
    {encoding: 'json', commitment: 'confirmed', maxSupportedTransactionVersion: 0}]);
  if (transaction !== null) fail('RETURN_STATUS_INCONSISTENT');
  const height = await rpc.call('getBlockHeight', [{commitment: 'confirmed'}]);
  const validity = await rpc.call('isBlockhashValid', [plan.blockhash, {commitment: 'confirmed'}]);
  if (!integer(height) || typeof validity?.value !== 'boolean') fail('RETURN_LIFETIME_INVALID');
  const current = await solLamports(rpc, plan.source);
  if (current.lamports !== rawAmount(plan.sourceLamportsBefore)) fail('RETURN_BALANCE_CONFLICT');
  if (height > plan.lastValidBlockHeight) {
    if (status !== null || validity.value) fail('RETURN_LIFETIME_INCONSISTENT');
    return Object.freeze({status: 'expired', signature: plan.signature, rebroadcast: false, height,
      lastValidBlockHeight: plan.lastValidBlockHeight, transactionAbsent: true, balanceUnchanged: true});
  }
  if (!validity.value) fail('RETURN_BLOCKHASH_UNAVAILABLE');
  await sendExact(rpc, plan);
  const settled = await confirm(rpc, plan.signature, {...confirmation,
    resend: {blockhash: plan.blockhash, send: () => sendExact(rpc, plan)}});
  return Object.freeze({status: 'confirmed', signature: plan.signature, rebroadcast: true,
    confirmation: settled.confirmation, rebroadcasts: settled.rebroadcasts});
}

export async function readStoredPlan(directory) {
  try { return validatePlan(await privateJson(join(directory, PLAN_FILENAME))); }
  catch (error) {
    if (error instanceof StockReturnError) throw error;
    if (error?.code === 'ENOENT') return null;
    return fail('RETURN_STORAGE_FAILED');
  }
}

export async function clearStoredPlan(directory, outcome) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  await writeExclusiveJson(join(directory, `return-outcome-${stamp}.json`), outcome);
  await unlink(join(directory, PLAN_FILENAME));
  await syncDirectory(directory);
}

export async function listOutcomes(directory) {
  const names = await readdir(directory);
  return names.filter(name => name.startsWith('return-outcome-')).sort();
}

function parseArgs(args) {
  if (!Array.isArray(args)) fail('RETURN_ARGUMENTS_INVALID');
  const parsed = {};
  for (let index = 0; index < args.length; index++) {
    const flag = args[index];
    if (flag === '--confirm') { parsed.confirmed = true; continue; }
    if (flag === '--resolve') { parsed.resolve = true; continue; }
    if (!['--network', '--asset', '--to'].includes(flag)) fail('RETURN_ARGUMENTS_INVALID');
    const value = args[++index];
    if (typeof value !== 'string' || value.length === 0 || value.startsWith('--')) fail('RETURN_ARGUMENTS_INVALID');
    parsed[flag.slice(2)] = value;
  }
  if (parsed.resolve) {
    if (parsed.network === undefined || parsed.asset !== undefined || parsed.to !== undefined || parsed.confirmed) {
      fail('RETURN_ARGUMENTS_INVALID');
    }
    return parsed;
  }
  if (parsed.network === undefined || parsed.asset === undefined || parsed.to === undefined || parsed.confirmed !== true) {
    fail('RETURN_ARGUMENTS_INVALID');
  }
  return parsed;
}

/**
 * The command line never accepts a key path, an amount or a swap. It requires
 * the network, the asset, the destination and an explicit confirmation, or
 * `--resolve` to settle a stored plan whose outcome is unknown.
 */
export async function runStockReturnCli(args, {homeDirectory, rpcFactory} = {}) {
  const parsed = parseArgs(args);
  const wallet = await openReturnSigner(homeDirectory === undefined ? {} : {homeDirectory});
  const rpc = rpcFactory ? rpcFactory(parsed.network) : new ReturnRpc({network: parsed.network});
  const stored = await readStoredPlan(wallet.directory);
  if (parsed.resolve) {
    if (stored === null) return Object.freeze({status: 'no_stored_plan'});
    const outcome = await resolvePlan({rpc, plan: stored});
    if (outcome.status === 'confirmed' || outcome.status === 'expired') {
      await clearStoredPlan(wallet.directory, {plan: stored, outcome, resolvedAt: new Date().toISOString()});
    }
    return Object.freeze({...outcome, plan: stored});
  }
  // An unresolved plan blocks a different transaction, by design.
  if (stored !== null) fail('RETURN_PLAN_UNRESOLVED');
  const plan = await planReturn({rpc, signer: wallet.signer, publicAddress: wallet.publicAddress,
    asset: parsed.asset, destination: parsed.to});
  await writeExclusiveJson(join(wallet.directory, PLAN_FILENAME), plan);
  let outcome;
  try { outcome = await submitPlan({rpc, plan}); }
  catch (error) {
    // The plan stays on disk so `--resolve` can settle it. Nothing is retried here.
    return Object.freeze({status: 'unresolved', plan, errorCode: error instanceof StockReturnError ? error.code : 'RETURN_FAILED'});
  }
  await clearStoredPlan(wallet.directory, {plan, outcome, resolvedAt: new Date().toISOString()});
  return Object.freeze({status: 'confirmed', plan, outcome});
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const result = await runStockReturnCli(process.argv.slice(2));
    const plan = result.plan;
    console.log(JSON.stringify({status: result.status, asset: plan?.asset ?? null, amountRaw: plan?.amountRaw ?? null,
      destination: plan?.destination ?? null, signature: result.outcome?.signature ?? result.signature ?? null,
      confirmation: result.outcome?.confirmation ?? result.confirmation ?? null, errorCode: result.errorCode ?? null}));
  } catch (error) {
    console.log(JSON.stringify({status: 'failed', errorCode: error instanceof StockReturnError ? error.code : 'RETURN_FAILED'}));
    process.exitCode = 1;
  }
}
