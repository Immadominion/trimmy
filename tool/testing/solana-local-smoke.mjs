/** Separate fallback: fresh local ledger and keys, fixed loopback ports, no public network. */
import { spawn, execFile } from 'node:child_process';
import { generateKeyPairSync, randomUUID } from 'node:crypto';
import { createServer } from 'node:net';
import { lstat, mkdir, open, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { createKeyPairSignerFromBytes } from '@solana/kit';
import { DEVNET_GENESIS, TRANSFER_LAMPORTS, SmokeError, exclusiveJson, prepareTransfer, confirmSignature, syncDirectory } from './solana-devnet.mjs';

const LOCAL_URL = 'http://127.0.0.1:18999';
const pause = (ms) => new Promise((done) => setTimeout(done, ms));
const fail = (code) => { throw new SmokeError(code); };
const report = { schemaVersion: 1, network: 'local-validator', endpoint: LOCAL_URL,
  startedAt: new Date().toISOString(), scope: 'Isolated localhost test SOL transfer; does not prove devnet or application transactions.', status: 'starting' };
let child;
let childExited = false;
let log;
try {
  if (process.argv.length !== 2) fail('NO_LOCAL_OVERRIDES_ALLOWED');
  process.umask(0o077);
  const base = join(homedir(), '.config', 'trimmy', 'testing');
  for (const path of [join(homedir(), '.config'), join(homedir(), '.config', 'trimmy'), base]) {
    const stat = await lstat(path);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (path !== join(homedir(), '.config') && (stat.mode & 0o077))) fail('UNSAFE_LOCAL_DIRECTORY');
  }
  for (const port of [18997, 18998, 18999, 19000]) {
    await new Promise((done, reject) => {
      const server = createServer();
      server.once('error', () => reject(new SmokeError('LOCAL_PORT_IN_USE')));
      server.listen(port, '127.0.0.1', () => server.close(done));
    });
  }
  const directory = join(base, `local-${randomUUID()}`);
  await mkdir(directory, { mode: 0o700 });
  await syncDirectory(base);
  const signers = [];
  for (const name of ['signer', 'recipient', 'genesis-mint']) {
    const pair = generateKeyPairSync('ed25519');
    const secret = pair.privateKey.export({ type: 'pkcs8', format: 'der' });
    const bytes = Buffer.concat([secret.subarray(-32), pair.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32)]);
    try {
      signers.push(await createKeyPairSignerFromBytes(bytes));
      await exclusiveJson(join(directory, `${name}.json`), Array.from(bytes));
    } finally { bytes.fill(0); secret.fill(0); }
  }
  const [signer, recipient, mint] = signers;
  report.signer = signer.address;
  report.recipient = recipient.address;
  report.walletName = directory.split('/').at(-1);
  await exclusiveJson(join(directory, 'wallet.json'), { schemaVersion: 1, createdBy: 'trimmy-isolated-local-smoke-v1',
    network: 'local-validator', signer: signer.address, recipient: recipient.address, createdAt: report.startedAt });
  const config = join(directory, 'cli.yml');
  const configHandle = await open(config, 'wx', 0o600);
  await configHandle.writeFile(`json_rpc_url: ${LOCAL_URL}\nwebsocket_url: ws://127.0.0.1:19000\nkeypair_path: ${join(directory, 'signer.json')}\naddress_labels: {}\ncommitment: confirmed\n`);
  await configHandle.close();
  log = await open(join(directory, 'validator.log'), 'wx', 0o600);
  child = spawn('solana-test-validator', ['--config', config, '--url', LOCAL_URL,
    '--ledger', join(directory, 'ledger'), '--bind-address', '127.0.0.1', '--rpc-port', '18999',
    '--gossip-port', '18997', '--faucet-port', '18998', '--dynamic-port-range', '19010-19050',
    '--mint', mint.address, '--faucet-sol', '10', '--quiet'], { stdio: ['ignore', log.fd, log.fd] });
  child.once('exit', () => { childExited = true; });
  child.once('error', () => { childExited = true; });
  let id = 0;
  const rpc = { call: async (method, params = []) => {
    const requestId = ++id;
    const result = await fetch(LOCAL_URL, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(5000),
      headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: requestId, method, params }) });
    if (!result.ok) fail('LOCAL_RPC_HTTP_FAILURE');
    const reader = result.body?.getReader();
    if (!reader) fail('LOCAL_RPC_INVALID_RESPONSE');
    const chunks = [];
    let size = 0;
    let exhausted = false;
    try {
      for (;;) {
        const chunk = await reader.read();
        if (chunk.done) { exhausted = true; break; }
        size += chunk.value.byteLength;
        if (size > 262144) fail('LOCAL_RPC_TOO_LARGE');
        chunks.push(chunk.value);
      }
    } finally { if (!exhausted) void reader.cancel().catch(() => {}); }
    const text = Buffer.concat(chunks).toString('utf8');
    const body = JSON.parse(text);
    if (body.jsonrpc !== '2.0' || body.id !== requestId || body.error) fail('LOCAL_RPC_FAILURE');
    return body.result;
  } };
  let actualGenesis;
  for (let attempt = 0; attempt < 20; attempt++) {
    if (childExited) fail('LOCAL_VALIDATOR_EXITED');
    try { actualGenesis = await rpc.call('getGenesisHash'); break; } catch { await pause(500); }
  }
  if (!actualGenesis) fail('LOCAL_VALIDATOR_START_TIMEOUT');
  const expected = (await promisify(execFile)('agave-ledger-tool', ['--ledger', join(directory, 'ledger'), 'genesis-hash'], { timeout: 10_000, maxBuffer: 65536 })).stdout.trim();
  if (actualGenesis !== expected || actualGenesis === DEVNET_GENESIS || actualGenesis === '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d') fail('LOCAL_GENESIS_MISMATCH');
  report.genesisHash = actualGenesis;
  report.genesisVerifiedAgainstFreshLedger = true;
  const assertLocal = async () => { if (childExited || await rpc.call('getGenesisHash') !== expected) fail('LOCAL_IDENTITY_CHANGED'); };
  await assertLocal();
  report.airdropSignature = await rpc.call('requestAirdrop', [signer.address, 100_000_000]);
  report.airdropConfirmation = await confirmSignature(rpc, report.airdropSignature);
  const balance = async (key) => (await rpc.call('getBalance', [key, { commitment: 'confirmed' }])).value;
  report.senderBeforeLamports = await balance(signer.address);
  report.recipientBeforeLamports = await balance(recipient.address);
  const plan = await prepareTransfer(rpc, { signer, recipient: recipient.address });
  report.localSignatureVerified = plan.localSignatureVerified;
  report.transferSignature = plan.signature;
  report.transferLamports = TRANSFER_LAMPORTS;
  report.feeLamports = plan.feeLamports;
  await assertLocal();
  const simulation = await rpc.call('simulateTransaction', [plan.wire, { encoding: 'base64', commitment: 'confirmed', sigVerify: true }]);
  if (simulation?.value?.err !== null) fail('LOCAL_SIMULATION_FAILED');
  report.simulationUnits = simulation.value.unitsConsumed;
  await exclusiveJson(join(directory, 'transfer.json'), { network: 'local-validator', genesisHash: expected, ...plan });
  report.planPersistedBeforeSend = true;
  await assertLocal();
  const signature = await rpc.call('sendTransaction', [plan.wire, { encoding: 'base64', skipPreflight: false, preflightCommitment: 'confirmed', maxRetries: 3 }]);
  if (signature !== plan.signature) fail('LOCAL_RECEIPT_MISMATCH');
  report.transferSubmitted = true;
  report.confirmationAttemptLimit = 12;
  report.transferConfirmation = await confirmSignature(rpc, signature);
  const transaction = await rpc.call('getTransaction', [signature, { encoding: 'json', commitment: 'confirmed', maxSupportedTransactionVersion: 0 }]);
  if (transaction?.meta?.err !== null || transaction.meta.fee !== plan.feeLamports || transaction.transaction?.signatures?.[0] !== signature) fail('LOCAL_TRANSACTION_MISMATCH');
  report.confirmedSlot = transaction.slot;
  report.senderAfterLamports = await balance(signer.address);
  report.recipientAfterLamports = await balance(recipient.address);
  if (report.senderBeforeLamports !== 100_000_000 || report.recipientBeforeLamports !== 0 ||
    report.senderAfterLamports !== 100_000_000 - TRANSFER_LAMPORTS - plan.feeLamports || report.recipientAfterLamports !== TRANSFER_LAMPORTS) fail('LOCAL_BALANCE_MISMATCH');
  report.balanceDeltasVerified = true;
  report.status = 'confirmed';
} catch (error) {
  report.status = 'incomplete';
  report.errorCode = error instanceof SmokeError ? error.code : 'LOCAL_SMOKE_FAILURE';
} finally {
  if (child && !childExited) {
    child.kill('SIGINT');
    for (let attempt = 0; attempt < 20 && !childExited; attempt++) await pause(250);
    if (!childExited) { child.kill('SIGKILL'); await new Promise((done) => child.once('exit', done)); }
  }
  await log?.close();
  report.validatorStopped = !child || childExited;
  report.finishedAt = new Date().toISOString();
  await writeFile(resolve(dirname(fileURLToPath(import.meta.url)), '../../artifacts/verification/SOLANA_LOCAL.json'), `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (report.status !== 'confirmed') process.exitCode = 2;
}
