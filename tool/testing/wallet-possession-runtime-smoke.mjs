#!/usr/bin/env node
/** Probe only configuration and unauthenticated refusals in a separate local
 * compiled API process. Never asks a real account for a challenge/signature. */
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {request} from 'node:https';
import {createServer} from 'node:net';
import {homedir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseApiEnv} from '../runtime/local-secure-runtime.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const port = 4445;
let child;
let childEnded;
let passed = false;
const checks = {};
const startedAt = new Date().toISOString();
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function read(ca, path, method = 'GET') {
  return new Promise((resolve, reject) => {
    const body = method === 'GET' ? undefined : '{}';
    const req = request({hostname: '127.0.0.1', servername: 'localhost', port, path, method,
      ca, rejectUnauthorized: true,
      ...(body ? {headers: {'content-type': 'application/json', 'content-length': '2'}} : {}),
    }, res => {
      const parts = [];
      let size = 0;
      res.on('data', chunk => {
        size += chunk.length;
        if (size > 32_768) req.destroy(new Error('Probe response exceeded its bound.'));
        else parts.push(chunk);
      });
      res.on('end', () => {
        try { resolve({status: res.statusCode, body: JSON.parse(Buffer.concat(parts).toString('utf8'))}); }
        catch { reject(new Error('Probe response was invalid.')); }
      });
      res.on('error', reject);
    });
    req.setTimeout(2000, () => req.destroy(new Error('Probe timeout.')));
    req.on('error', reject);
    req.end(body);
  });
}

try {
  if (process.argv.length !== 3 || process.argv[2] !== '--local-unauthenticated') throw new Error('Explicit probe flag required.');
  // Refuse an occupied port; never probe or terminate an unrelated process.
  const reservation = createServer();
  await new Promise((resolve, reject) => { reservation.once('error', reject); reservation.listen(port, '127.0.0.1', resolve); });
  await new Promise((resolve, reject) => reservation.close(error => error ? reject(error) : resolve()));
  const privateRoot = join(homedir(), '.config/trimmy/runtime');
  const runtimeEnv = parseApiEnv(readFileSync(join(privateRoot, 'api.env'), 'utf8'));
  const secret = execFileSync('/usr/bin/security', ['find-generic-password', '-a', 'trimmy',
    '-s', 'trimmy-privy-app-secret', '-w'], {encoding: 'utf8', timeout: 5000,
    maxBuffer: 16_384, stdio: ['ignore', 'pipe', 'ignore']}).replace(/\r?\n$/, '');
  if (!/^[\x21-\x7e]{1,4096}$/.test(secret)) throw new Error('Private configuration unavailable.');
  const ca = readFileSync(join(privateRoot, 'tls/ca.crt'));
  child = spawn(process.execPath, [join(root, 'apps/api/dist/index.js')], {cwd: root,
    env: {PATH: process.env.PATH, HOME: process.env.HOME, ...runtimeEnv,
      HOST: '127.0.0.1', PORT: String(port), LOG_LEVEL: 'silent', PRIVY_APP_SECRET: secret,
      TRIMMY_WALLET_POSSESSION: 'single_process', TRIMMY_WALLET_NETWORK: 'mainnet-beta'},
    stdio: 'ignore',
  });
  childEnded = new Promise(resolve => {
    child.once('exit', (code, signal) => resolve({code, signal}));
    child.once('error', () => resolve({code: -1, signal: null}));
  });
  let config;
  for (let attempt = 0; attempt < 30; attempt++) {
    if (child.exitCode !== null) throw new Error('Compiled API exited.');
    try { config = await read(ca, '/v1/config'); break; } catch { await sleep(100); }
  }
  assert.equal(config?.status, 200);
  assert.equal(config.body.walletPossessionEnabled, true);
  assert.equal(config.body.practiceAccountsEnabled, true);
  assert.equal(config.body.accountContextEnabled, true);
  assert.equal(config.body.moneyMode, 'practice_only');
  for (const capability of ['financialOperationsEnabled', 'liveWalletsEnabled', 'fundedGiftsEnabled', 'swapsEnabled']) {
    assert.equal(config.body.capabilities[capability], false);
  }
  checks.configured = true;
  checks.moneyCapabilitiesDisabled = true;
  for (const path of ['/v1/account/wallet/challenge', '/v1/account/wallet/possession']) {
    const response = await read(ca, path, 'POST');
    assert.equal(response.status, 401);
    assert.equal(response.body.error.code, 'ACCOUNT_WALLET_UNAUTHENTICATED');
  }
  checks.unauthenticatedWalletRoutes = 401;
  const wrongMethod = await read(ca, '/v1/account/wallet/challenge', 'PUT');
  assert.equal(wrongMethod.status, 503);
  assert.equal(wrongMethod.body.error.code, 'FINANCIAL_OPERATIONS_DISABLED');
  const order = await read(ca, '/v1/orders', 'POST');
  assert.equal(order.status, 503);
  assert.equal(order.body.error.code, 'FINANCIAL_OPERATIONS_DISABLED');
  checks.wrongMethodAndOrder = 503;
  passed = true;
} catch {
  // Never print child output, provider errors, configuration or credentials.
  process.exitCode = 1;
} finally {
  if (child && childEnded) {
    child.kill('SIGTERM');
    const deadline = setTimeout(() => child.kill('SIGKILL'), 2000);
    const result = await childEnded;
    clearTimeout(deadline);
    checks.processStopped = true;
    checks.childExitCode = result.code;
    if (result.code !== 0 && result.signal !== 'SIGTERM') { passed = false; process.exitCode = 1; }
  }
  const sources = ['apps/api/src/index.ts', 'apps/api/src/practice-runtime.ts',
    'apps/api/src/wallet-possession-runtime.ts', 'apps/api/src/postgres-wallet-bindings.ts',
    'tool/testing/wallet-possession-runtime-smoke.mjs'];
  const evidence = {schemaVersion: 1, kind: 'compiled_wallet_possession_runtime', startedAt,
    finishedAt: new Date().toISOString(), passed, scope: 'local_tls_separate_process_unauthenticated_only',
    checks, authenticatedRequests: 0, challengeIssued: false, walletSignatureRequested: false,
    rejectedOrderProbe: true, financialOperationExecuted: false,
    sourceSha256: Object.fromEntries(sources.map(path => [path,
      createHash('sha256').update(readFileSync(join(root, path))).digest('hex')])),
  };
  writeFileSync(join(root, 'artifacts/verification/WALLET_POSSESSION_RUNTIME.json'), `${JSON.stringify(evidence, null, 2)}\n`);
  console.log(JSON.stringify({passed, checks, authenticatedRequests: 0, challengeIssued: false}));
}
