/**
 * Proves the return path against a private local validator before it is ever
 * pointed at mainnet. It creates its own cluster, its own token mint and its own
 * keys, then drives the same `planReturn`, `submitPlan` and `resolvePlan` that a
 * mainnet return uses: a token balance is returned in full, the emptied token
 * account is closed and its rent reclaimed, and the remaining SOL is swept.
 *
 * It takes no arguments, reads no Solana CLI configuration, and touches no
 * public cluster. The ledger and keys live in a private directory that is
 * removed at the end.
 */
import { spawn } from 'node:child_process';
import { generateKeyPairSync, randomUUID } from 'node:crypto';
import { mkdir, open, readFile, rm, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  address, appendTransactionMessageInstruction, createKeyPairSignerFromBytes, createTransactionMessage,
  getBase64EncodedWireTransaction, getSignatureFromTransaction, setTransactionMessageFeePayerSigner,
  setTransactionMessageLifetimeUsingBlockhash, signTransactionMessageWithSigners,
} from '@solana/kit';
import { getCreateAccountInstruction } from '@solana-program/system';
import {
  getCreateAssociatedTokenIdempotentInstruction, getInitializeMint2Instruction, getMintToInstruction,
} from '@solana-program/token';
import { findAssociatedTokenPda } from '@solana-program/token-2022';
import {
  LOCALNET_URL, ReturnRpc, TOKEN_PROGRAM, planReturn, resolvePlan, submitPlan,
} from './stock-order-return.mjs';

const RPC_PORT = 18999;
const MINT_DECIMALS = 6;
const MINT_SUPPLY = 2_500_000n;
const MINT_ACCOUNT_BYTES = 82;
export class LocalReturnError extends Error {
  constructor(code) { super(code); this.name = 'LocalReturnError'; this.code = code; }
}
const fail = code => { throw new LocalReturnError(code); };
const delay = ms => new Promise(done => setTimeout(done, ms));

function secretBytes() {
  const pair = generateKeyPairSync('ed25519');
  const secret = pair.privateKey.export({type: 'pkcs8', format: 'der'});
  const publicKey = pair.publicKey.export({type: 'spki', format: 'der'});
  if (secret.length !== 48 || publicKey.length !== 44) fail('LOCAL_RETURN_KEY_ENCODING');
  const bytes = Buffer.concat([secret.subarray(-32), publicKey.subarray(-32)]);
  secret.fill(0);
  return bytes;
}

async function newSigner(directory, filename) {
  const bytes = secretBytes();
  try {
    await writeFile(join(directory, filename), JSON.stringify(Array.from(bytes)), {mode: 0o600});
    return await createKeyPairSignerFromBytes(Uint8Array.from(bytes));
  } finally { bytes.fill(0); }
}

async function waitForValidator(timeoutMs = 90_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(LOCALNET_URL, {
        method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify({jsonrpc: '2.0', id: 1, method: 'getHealth'}),
        signal: AbortSignal.timeout(2_000),
      });
      if (response.ok && (await response.json())?.result === 'ok') return;
    } catch { /* the validator is still starting */ }
    await delay(1_000);
  }
  fail('LOCAL_RETURN_VALIDATOR_UNAVAILABLE');
}

/**
 * A fresh validator answers getHealth before it will actually confirm anything.
 * A confirmed airdrop is the only readiness signal that proves the whole path
 * works, so it doubles as the funding step. The return transport deliberately
 * has no airdrop method, so this test-only request goes out directly.
 */
async function fundAndWait(rpc, publicAddress, lamportsWanted, timeoutMs = 90_000) {
  const deadline = Date.now() + timeoutMs;
  let signature = null;
  while (Date.now() < deadline) {
    if (signature === null) {
      try {
        const response = await fetch(LOCALNET_URL, {
          method: 'POST', headers: {'content-type': 'application/json'},
          body: JSON.stringify({jsonrpc: '2.0', id: 1, method: 'requestAirdrop',
            params: [publicAddress, Number(lamportsWanted)]}),
          signal: AbortSignal.timeout(5_000),
        });
        const body = await response.json();
        if (typeof body?.result === 'string') signature = body.result;
      } catch { /* the validator is still starting */ }
    }
    if (signature !== null) {
      const statuses = await rpc.call('getSignatureStatuses', [[signature], {searchTransactionHistory: true}]);
      const status = statuses?.value?.[0];
      if (status?.err) fail('LOCAL_RETURN_FUNDING_FAILED');
      if (status && ['confirmed', 'finalized'].includes(status.confirmationStatus)) {
        const balance = await rpc.call('getBalance', [publicAddress, {commitment: 'confirmed'}]);
        if (BigInt(balance.value) < lamportsWanted) fail('LOCAL_RETURN_FUNDING_FAILED');
        return {signature, lamports: BigInt(balance.value)};
      }
    }
    await delay(1_000);
  }
  return fail('LOCAL_RETURN_FUNDING_PENDING');
}

/** One setup transaction: create the mint, the owner's account, and mint to it. */
export async function seedToken(rpc, payer, mintSigner) {
  const latest = await rpc.call('getLatestBlockhash', [{commitment: 'confirmed'}]);
  const rent = await rpc.call('getMinimumBalanceForRentExemption', [MINT_ACCOUNT_BYTES]);
  const [associated] = await findAssociatedTokenPda({
    owner: address(payer.address), mint: address(mintSigner.address), tokenProgram: address(TOKEN_PROGRAM),
  });
  let message = createTransactionMessage({version: 0});
  message = setTransactionMessageFeePayerSigner(payer, message);
  message = setTransactionMessageLifetimeUsingBlockhash({
    blockhash: address(latest.value.blockhash), lastValidBlockHeight: BigInt(latest.value.lastValidBlockHeight),
  }, message);
  for (const instruction of [
    getCreateAccountInstruction({payer, newAccount: mintSigner, lamports: BigInt(rent),
      space: BigInt(MINT_ACCOUNT_BYTES), programAddress: address(TOKEN_PROGRAM)}),
    getInitializeMint2Instruction({mint: address(mintSigner.address), decimals: MINT_DECIMALS,
      mintAuthority: address(payer.address), freezeAuthority: null}, {programAddress: address(TOKEN_PROGRAM)}),
    getCreateAssociatedTokenIdempotentInstruction({payer, ata: address(associated),
      owner: address(payer.address), mint: address(mintSigner.address), tokenProgram: address(TOKEN_PROGRAM)}),
    getMintToInstruction({mint: address(mintSigner.address), token: address(associated), mintAuthority: payer,
      amount: MINT_SUPPLY}, {programAddress: address(TOKEN_PROGRAM)}),
  ]) message = appendTransactionMessageInstruction(instruction, message);
  const signed = await signTransactionMessageWithSigners(message);
  const signature = getSignatureFromTransaction(signed);
  const wire = getBase64EncodedWireTransaction(signed);
  // Simulate first so a program error is reported instead of a confirmation timeout.
  const simulation = await rpc.call('simulateTransaction', [wire,
    {encoding: 'base64', commitment: 'confirmed', sigVerify: true, replaceRecentBlockhash: false}]);
  if (simulation?.value?.err !== null) {
    const detail = JSON.stringify(simulation?.value?.err ?? 'unknown');
    const logs = (simulation?.value?.logs ?? []).slice(-4).join(' | ');
    throw new LocalReturnError(`LOCAL_RETURN_SETUP_SIMULATION_FAILED ${detail} ${logs}`);
  }
  const send = async () => {
    const receipt = await rpc.call('sendTransaction', [wire,
      {encoding: 'base64', skipPreflight: false, preflightCommitment: 'confirmed', maxRetries: 3}]);
    if (receipt !== signature) fail('LOCAL_RETURN_SETUP_FAILED');
  };
  await send();
  const deadline = Date.now() + 60_000;
  const trace = [];
  while (Date.now() < deadline) {
    const statuses = await rpc.call('getSignatureStatuses', [[signature], {searchTransactionHistory: true}]);
    const status = statuses?.value?.[0];
    trace.push(`${new Date().toISOString()} slot=${statuses?.context?.slot} status=${JSON.stringify(status)}`);
    if (status?.err) fail('LOCAL_RETURN_SETUP_FAILED');
    if (status && ['confirmed', 'finalized'].includes(status.confirmationStatus)) return {associated, signature};
    // A warming validator can accept and then drop a transaction; resend the same bytes.
    const valid = await rpc.call('isBlockhashValid', [latest.value.blockhash, {commitment: 'confirmed'}]);
    if (valid?.value === true) await send(); else fail('LOCAL_RETURN_SETUP_EXPIRED');
    await delay(2_000);
  }
  const height = await rpc.call('getBlockHeight', [{commitment: 'confirmed'}]);
  const valid = await rpc.call('isBlockhashValid', [latest.value.blockhash, {commitment: 'confirmed'}]);
  throw new LocalReturnError(`LOCAL_RETURN_SETUP_PENDING signature=${signature} blockhash=${latest.value.blockhash} ` +
    `lastValid=${latest.value.lastValidBlockHeight} height=${height} blockhashValid=${valid?.value} ` +
    `units=${simulation.value.unitsConsumed} trace=${trace.slice(0, 3).join(' ;; ')}`);
}

async function tokenBalance(rpc, owner, mint) {
  const result = await rpc.call('getTokenAccountsByOwner', [owner, {mint},
    {encoding: 'jsonParsed', commitment: 'confirmed'}]);
  let total = 0n;
  for (const entry of result?.value ?? []) total += BigInt(entry.account.data.parsed.info.tokenAmount.amount);
  return total;
}
async function lamports(rpc, publicAddress) {
  const result = await rpc.call('getBalance', [publicAddress, {commitment: 'confirmed'}]);
  return BigInt(result.value);
}

export async function runLocalReturnVerification({baseDirectory = join(homedir(), '.config', 'trimmy', 'testing')} = {}) {
  const directory = join(baseDirectory, `return-local-${randomUUID()}`);
  await mkdir(directory, {recursive: true, mode: 0o700});
  let child = null;
  let log = null;
  try {
    const source = await newSigner(directory, 'source.json');
    const mintSigner = await newSigner(directory, 'mint.json');
    const destination = await newSigner(directory, 'destination.json');
    log = await open(join(directory, 'validator.log'), 'a', 0o600);
    child = spawn('solana-test-validator', ['--ledger', join(directory, 'ledger'),
      '--bind-address', '127.0.0.1', '--rpc-port', String(RPC_PORT), '--gossip-port', '18997',
      '--faucet-port', '18998', '--dynamic-port-range', '19010-19050'],
    {stdio: ['ignore', log.fd, log.fd]});
    let exited = false;
    child.once('exit', () => { exited = true; });
    child.once('error', () => { exited = true; });
    await waitForValidator();
    if (exited) fail('LOCAL_RETURN_VALIDATOR_UNAVAILABLE');

    const rpc = new ReturnRpc({network: 'localnet'});
    const genesisHash = await rpc.assertNetwork();
    const funding = await fundAndWait(rpc, source.address, 1_000_000_000n);
    const token = {mint: mintSigner.address, decimals: MINT_DECIMALS};
    const seeded = await seedToken(rpc, source, mintSigner);
    const sourceTokensBefore = await tokenBalance(rpc, source.address, token.mint);
    if (sourceTokensBefore !== MINT_SUPPLY) fail('LOCAL_RETURN_SETUP_FAILED');

    // 1. Return the whole token balance. The destination has no account yet.
    const tokenPlan = await planReturn({rpc, signer: source, publicAddress: source.address, asset: 'usdc',
      destination: destination.address, token});
    if (tokenPlan.amountRaw !== MINT_SUPPLY.toString() || tokenPlan.createsDestinationAccount !== true) {
      fail('LOCAL_RETURN_TOKEN_PLAN_UNEXPECTED');
    }
    const tokenOutcome = await submitPlan({rpc, plan: tokenPlan});
    // A resolve after confirmation must confirm without resending.
    const tokenResolved = await resolvePlan({rpc, plan: tokenPlan});
    if (tokenResolved.status !== 'confirmed' || tokenResolved.rebroadcast !== false) fail('LOCAL_RETURN_RESOLVE_UNEXPECTED');
    const destinationTokens = await tokenBalance(rpc, destination.address, token.mint);
    const sourceTokensAfter = await tokenBalance(rpc, source.address, token.mint);
    if (destinationTokens !== MINT_SUPPLY || sourceTokensAfter !== 0n) fail('LOCAL_RETURN_TOKEN_BALANCE_UNEXPECTED');

    // 2. Sweep the SOL, closing the emptied token account to reclaim its rent.
    const destinationLamportsBefore = await lamports(rpc, destination.address);
    const solPlan = await planReturn({rpc, signer: source, publicAddress: source.address, asset: 'sol',
      destination: destination.address, token});
    if (solPlan.closesSourceTokenAccount !== true || solPlan.tokenBalanceRemains !== false ||
        BigInt(solPlan.reclaimedRentLamports) <= 0n) fail('LOCAL_RETURN_SOL_PLAN_UNEXPECTED');
    const solOutcome = await submitPlan({rpc, plan: solPlan});
    const sourceAfter = await lamports(rpc, source.address);
    const destinationAfter = await lamports(rpc, destination.address);
    if (sourceAfter !== 0n) fail('LOCAL_RETURN_SOURCE_NOT_EMPTY');
    if (destinationAfter - destinationLamportsBefore !== BigInt(solPlan.amountRaw)) {
      fail('LOCAL_RETURN_SOL_BALANCE_UNEXPECTED');
    }
    const strandedTokenAccount = await rpc.call('getMultipleAccounts',
      [[tokenPlan.sourceTokenAccount], {encoding: 'base64', commitment: 'confirmed'}]);
    if (strandedTokenAccount.value[0] !== null) fail('LOCAL_RETURN_TOKEN_ACCOUNT_NOT_CLOSED');

    return Object.freeze({
      schemaVersion: 1,
      recordedAt: new Date().toISOString(),
      scope: 'Private local validator. The same planning, submission, confirmation and resolve functions a mainnet return uses, exercised on a token balance and a SOL sweep with a locally created mint. No public cluster was contacted.',
      cluster: {url: LOCALNET_URL, genesisHash, validator: 'solana-test-validator',
        fundingSignature: funding.signature, sourceLamportsFunded: funding.lamports.toString()},
      token: {mint: token.mint, decimals: MINT_DECIMALS, supplyRaw: MINT_SUPPLY.toString(), setupSignature: seeded.signature},
      tokenReturn: {
        amountRaw: tokenPlan.amountRaw, createdDestinationAccount: tokenPlan.createsDestinationAccount,
        rentLamports: tokenPlan.rentLamports, signature: tokenOutcome.signature,
        confirmation: tokenOutcome.confirmation, unitsConsumed: tokenOutcome.unitsConsumed,
        destinationBalanceRaw: destinationTokens.toString(), sourceBalanceRaw: sourceTokensAfter.toString(),
        resolveAfterConfirmation: {status: tokenResolved.status, rebroadcast: tokenResolved.rebroadcast},
      },
      solReturn: {
        amountRaw: solPlan.amountRaw, feeLamports: solPlan.feeLamports,
        closedSourceTokenAccount: solPlan.closesSourceTokenAccount,
        reclaimedRentLamports: solPlan.reclaimedRentLamports, signature: solOutcome.signature,
        confirmation: solOutcome.confirmation, sourceLamportsAfter: sourceAfter.toString(),
        destinationGainLamports: (destinationAfter - destinationLamportsBefore).toString(),
      },
      invariants: {
        sourceFullyEmptied: sourceAfter === 0n && sourceTokensAfter === 0n,
        emptiedTokenAccountClosed: true,
        confirmedPlanNeverResent: tokenResolved.rebroadcast === false,
        exactBytesOnly: true,
      },
      passed: true,
    });
  } catch (error) {
    // Keep the validator's own log for diagnosis before the directory is removed.
    try {
      const tail = (await readFile(join(directory, 'validator.log'), 'utf8')).split('\n').slice(-40).join('\n');
      await writeFile(join(baseDirectory, 'return-local-failure.log'),
        `${new Date().toISOString()} ${error?.code ?? error?.message ?? 'unknown'}\n${tail}\n`, {mode: 0o600});
    } catch { /* diagnosis is best effort */ }
    throw error;
  } finally {
    if (child && child.exitCode === null && child.signalCode === null) {
      child.kill('SIGTERM');
      for (let attempt = 0; attempt < 40 && child.exitCode === null && child.signalCode === null; attempt++) {
        await delay(250);
      }
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    }
    await log?.close();
    await rm(directory, {recursive: true, force: true});
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 2) {
    console.log(JSON.stringify({passed: false, errorCode: 'LOCAL_RETURN_ARGUMENTS_INVALID'}));
    process.exitCode = 1;
  } else {
    try {
      const report = await runLocalReturnVerification();
      await writeFile(new URL('../../artifacts/verification/STOCK_ORDER_RETURN_LOCAL.json', import.meta.url),
        `${JSON.stringify(report, null, 2)}\n`);
      console.log(JSON.stringify({passed: report.passed, tokenSignature: report.tokenReturn.signature,
        solSignature: report.solReturn.signature, sourceLamportsAfter: report.solReturn.sourceLamportsAfter,
        reclaimedRentLamports: report.solReturn.reclaimedRentLamports}));
    } catch (error) {
      console.log(JSON.stringify({passed: false,
        errorCode: error instanceof LocalReturnError ? error.code : error?.code ?? 'LOCAL_RETURN_FAILED'}));
      process.exitCode = 1;
    }
  }
}
