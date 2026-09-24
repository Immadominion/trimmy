/** Explicit, one-use recovery for the prior local smoke. Never contacts a public cluster. */
import { spawn, execFile } from 'node:child_process';
import { createServer } from 'node:net';
import { constants } from 'node:fs';
import { readFile, writeFile, open, lstat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { createKeyPairSignerFromBytes } from '@solana/kit';
import { SmokeError, TRANSFER_LAMPORTS, exclusiveJson, prepareTransfer, recoverSignedTransfer, confirmSignature } from './solana-devnet.mjs';

const endpoint = 'http://127.0.0.1:18999';
const artifacts = resolve(dirname(fileURLToPath(import.meta.url)), '../../artifacts/verification');
const report = { schemaVersion: 1, network: 'local-validator', endpoint, startedAt: new Date().toISOString(),
  scope: 'Explicit same-ledger recovery; one exact-byte retry, or one distinct new intent after proven expiry and absence.', status: 'starting' };
const pause = (ms) => new Promise((done) => setTimeout(done, ms));
const fail = (code) => { throw new SmokeError(code); };
let child;
let exited = false;
let log;
try {
  if (process.argv.length !== 2) fail('NO_RECOVERY_OVERRIDES_ALLOWED');
  const original = JSON.parse(await readFile(join(artifacts, 'SOLANA_LOCAL.json'), 'utf8'));
  if (original.network !== 'local-validator' || !/^local-[a-f0-9-]{36}$/.test(original.walletName) || original.walletName.length !== 42) fail('INVALID_LOCAL_RECORD');
  const base = join(homedir(), '.config', 'trimmy', 'testing');
  const directory = join(base, original.walletName);
  for (const path of [join(homedir(), '.config'), join(homedir(), '.config', 'trimmy'), base, directory, join(directory, 'ledger'), join(directory, 'cli.yml')]) {
    const stat = await lstat(path);
    if (stat.isSymbolicLink() || stat.uid !== process.getuid() || (path !== join(homedir(), '.config') && (stat.mode & 0o077))) fail('UNSAFE_RECOVERY_PATH');
  }
  const privateJson = async (name) => {
    const file = await open(join(directory, name), constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const stat = await file.stat();
      if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o077) || stat.size > 8192) fail('UNSAFE_RECOVERY_FILE');
      return JSON.parse(await file.readFile('utf8'));
    } finally { await file.close(); }
  };
  const marker = await privateJson('wallet.json');
  if (marker.createdBy !== 'trimmy-isolated-local-smoke-v1' || marker.network !== 'local-validator' ||
    marker.signer !== original.signer || marker.recipient !== original.recipient) fail('LOCAL_MARKER_MISMATCH');
  const oldPlan = await privateJson('transfer.json');
  if (oldPlan.network !== 'local-validator' || oldPlan.genesisHash !== original.genesisHash || oldPlan.signature !== original.transferSignature) fail('LOCAL_PLAN_MISMATCH');
  const expected = (await promisify(execFile)('agave-ledger-tool', ['--ledger', join(directory, 'ledger'), 'genesis-hash'], { timeout: 10_000, maxBuffer: 65536 })).stdout.trim();
  if (expected !== original.genesisHash) fail('LOCAL_LEDGER_CHANGED');
  await new Promise((done, reject) => {
    const server = createServer();
    server.once('error', () => reject(new SmokeError('LOCAL_PORT_IN_USE')));
    server.listen(18999, '127.0.0.1', () => server.close(done));
  });
  report.genesisHash = expected;
  report.walletName = original.walletName;
  report.signer = original.signer;
  report.recipient = original.recipient;
  report.originalSignature = original.transferSignature;
  // This one-use marker survives a crash, preventing another automatic recovery attempt.
  await exclusiveJson(join(directory, 'recovery-attempt.json'), { schemaVersion: 1, startedAt: report.startedAt, signature: oldPlan.signature });
  process.umask(0o077);
  log = await open(join(directory, 'recovery-validator.log'), 'wx', 0o600);
  child = spawn('solana-test-validator', ['--config', join(directory, 'cli.yml'), '--url', endpoint,
    '--ledger', join(directory, 'ledger'), '--bind-address', '127.0.0.1', '--rpc-port', '18999',
    '--gossip-port', '18997', '--faucet-port', '18998', '--dynamic-port-range', '19010-19050',
    '--mint', original.signer, '--quiet'], { stdio: ['ignore', log.fd, log.fd] });
  child.once('exit', () => { exited = true; });
  child.once('error', () => { exited = true; });
  let id = 0;
  const allowed = new Set(['getGenesisHash', 'getSignatureStatuses', 'getTransaction', 'getBlockHeight', 'isBlockhashValid',
    'getBalance', 'getLatestBlockhash', 'getFeeForMessage', 'simulateTransaction', 'sendTransaction']);
  const rpc = { call: async (method, params = []) => {
    if (!allowed.has(method)) fail('LOCAL_RECOVERY_METHOD_REJECTED');
    const requestId = ++id;
    const response = await fetch(endpoint, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(5000),
      headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: requestId, method, params }) });
    if (!response.ok) fail('LOCAL_RECOVERY_RPC_HTTP');
    const reader = response.body?.getReader();
    if (!reader) fail('LOCAL_RECOVERY_RPC_BODY');
    const chunks = [];
    let size = 0;
    let exhausted = false;
    try {
      for (;;) {
        const chunk = await reader.read();
        if (chunk.done) { exhausted = true; break; }
        size += chunk.value.byteLength;
        if (size > 262144) fail('LOCAL_RECOVERY_RPC_TOO_LARGE');
        chunks.push(chunk.value);
      }
    } finally { if (!exhausted) void reader.cancel().catch(() => {}); }
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (body.id !== requestId || body.jsonrpc !== '2.0' || body.error) fail('LOCAL_RECOVERY_RPC_INVALID');
    return body.result;
  } };
  let ready = false;
  const startupDeadline = Date.now() + 20000;
  while (Date.now() < startupDeadline && !exited) {
    try { ready = await rpc.call('getGenesisHash') === expected; if (ready) break; } catch { /* bounded startup */ }
    await pause(500);
  }
  if (!ready || exited) fail('LOCAL_RECOVERY_START_FAILED');
  const identityCheck = async () => { if (exited || await rpc.call('getGenesisHash') !== expected) fail('LOCAL_RECOVERY_IDENTITY_CHANGED'); };
  report.originalRecovery = await recoverSignedTransfer(rpc, oldPlan, {
    sender: original.signer, recipient: original.recipient, senderBeforeLamports: original.senderBeforeLamports,
    recipientBeforeLamports: original.recipientBeforeLamports, identityCheck, confirmation: { attempts: 25 },
    beforeResend: async () => {
      await exclusiveJson(join(directory, 'recovery-send.json'), { signature: oldPlan.signature, wire: oldPlan.wire, maxRetries: 3 });
      report.exactOriginalBytesResubmitted = true;
    },
  });
  let currentPlan = oldPlan;
  if (report.originalRecovery.status === 'expired') {
    // Expiry + signature/transaction absence + unchanged balances were all checked above.
    const raw = await privateJson('signer.json');
    if (!Array.isArray(raw) || raw.length !== 64 || !raw.every((n) => Number.isInteger(n) && n >= 0 && n <= 255)) fail('INVALID_LOCAL_KEY');
    const bytes = Uint8Array.from(raw);
    let signer;
    try { signer = await createKeyPairSignerFromBytes(bytes); } finally { bytes.fill(0); raw.fill(0); }
    if (signer.address !== original.signer) fail('LOCAL_KEY_MISMATCH');
    await identityCheck();
    currentPlan = await prepareTransfer(rpc, { signer, recipient: original.recipient });
    if (currentPlan.signature === oldPlan.signature) fail('NEW_INTENT_NOT_DISTINCT');
    const simulation = await rpc.call('simulateTransaction', [currentPlan.wire, { encoding: 'base64', commitment: 'confirmed', sigVerify: true }]);
    if (simulation?.value?.err !== null) fail('LOCAL_NEW_INTENT_SIMULATION_FAILED');
    report.newIntent = { reason: 'Original expired, absent and balances unchanged', signature: currentPlan.signature,
      transferLamports: TRANSFER_LAMPORTS, feeLamports: currentPlan.feeLamports, simulationUnits: simulation.value.unitsConsumed,
      localSignatureVerified: currentPlan.localSignatureVerified, lastValidBlockHeight: currentPlan.lastValidBlockHeight };
    await exclusiveJson(join(directory, 'transfer-after-expiry.json'), { network: 'local-validator', genesisHash: expected,
      supersedesExpiredSignature: oldPlan.signature, ...currentPlan });
    report.newIntent.persistedBeforeSend = true;
    await identityCheck();
    const receipt = await rpc.call('sendTransaction', [currentPlan.wire, { encoding: 'base64', skipPreflight: false, preflightCommitment: 'confirmed', maxRetries: 3 }]);
    if (receipt !== currentPlan.signature) fail('LOCAL_NEW_INTENT_RECEIPT_MISMATCH');
    report.newIntent.submitted = true;
    report.newIntent.confirmation = await confirmSignature(rpc, currentPlan.signature, { attempts: 25 });
  }
  const transaction = await rpc.call('getTransaction', [currentPlan.signature, { encoding: 'json', commitment: 'confirmed', maxSupportedTransactionVersion: 0 }]);
  if (transaction?.meta?.err !== null || transaction.meta.fee !== currentPlan.feeLamports || transaction.transaction?.signatures?.[0] !== currentPlan.signature) fail('LOCAL_RECOVERED_TRANSACTION_MISMATCH');
  report.confirmedSlot = transaction.slot;
  report.confirmedSignature = currentPlan.signature;
  report.senderAfterLamports = (await rpc.call('getBalance', [original.signer, { commitment: 'confirmed' }])).value;
  report.recipientAfterLamports = (await rpc.call('getBalance', [original.recipient, { commitment: 'confirmed' }])).value;
  if (report.senderAfterLamports !== original.senderBeforeLamports - TRANSFER_LAMPORTS - currentPlan.feeLamports ||
    report.recipientAfterLamports !== original.recipientBeforeLamports + TRANSFER_LAMPORTS) fail('LOCAL_RECOVERED_BALANCE_MISMATCH');
  report.balanceDeltasVerified = true;
  report.status = 'confirmed';
} catch (error) {
  report.status = 'incomplete';
  report.errorCode = error instanceof SmokeError ? error.code : (error.code === 'EEXIST' ? 'RECOVERY_ALREADY_ATTEMPTED' : 'LOCAL_RECOVERY_FAILURE');
} finally {
  if (child && !exited) {
    child.kill('SIGINT');
    for (let attempt = 0; attempt < 20 && !exited; attempt++) await pause(250);
    if (!exited) { child.kill('SIGKILL'); await new Promise((done) => child.once('exit', done)); }
  }
  await log?.close();
  report.validatorStopped = !child || exited;
  report.finishedAt = new Date().toISOString();
  try {
    await writeFile(join(artifacts, 'SOLANA_LOCAL_RECOVERY.json'), `${JSON.stringify(report, null, 2)}\n`, { flag: 'wx' });
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    report.previousResultPreserved = true;
  }
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (report.status !== 'confirmed') process.exitCode = 2;
}
