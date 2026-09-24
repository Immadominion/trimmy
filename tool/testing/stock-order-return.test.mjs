import assert from 'node:assert/strict';
import { generateKeyPairSync, randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { readFile, readdir, writeFile, mkdir, chmod } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, it } from 'node:test';
import {
  address, createKeyPairSignerFromBytes, getAddressDecoder, getProgramDerivedAddress, getTransactionDecoder,
  isOffCurveAddress,
} from '@solana/kit';
import { STOCK_WALLET_GENESIS } from './stock-order-wallet.mjs';
import {
  MAX_FEE_LAMPORTS, PLAN_FILENAME, ReturnRpc, STOCK_RETURN_TOOL_ID, StockReturnError, TOKEN_PROGRAM, USDC_MINT,
  clearStoredPlan, openReturnSigner, planReturn, readStoredPlan, resolvePlan, returnDestination, runStockReturnCli,
  submitPlan, tokenPosition, validatePlan,
} from './stock-order-return.mjs';

const base = mkdtempSync(join(tmpdir(), 'trimmy-return-'));
after(() => rmSync(base, {recursive: true, force: true}));
const errorIs = code => error => error instanceof StockReturnError && error.code === code;
const blockhash = getAddressDecoder().decode(new Uint8Array(32).fill(7));
const LOCAL_GENESIS = getAddressDecoder().decode(new Uint8Array(32).fill(3));

function secretBytes() {
  const pair = generateKeyPairSync('ed25519');
  const secret = pair.privateKey.export({type: 'pkcs8', format: 'der'});
  const publicKey = pair.publicKey.export({type: 'spki', format: 'der'});
  return Buffer.concat([secret.subarray(-32), publicKey.subarray(-32)]);
}
async function newSigner() { return createKeyPairSignerFromBytes(Uint8Array.from(secretBytes())); }

/** Deterministic RPC double. Every method the module may call is answered here. */
class FakeRpc {
  constructor({network = 'mainnet-beta', genesis, lamports = 1_000_000_000n, fee = 5_000,
    tokenAccounts, accounts = {}, rent = 2_039_280, statuses = [], transaction = null,
    height = 1_000, blockhashValid = true, simulationError = null} = {}) {
    this.network = network;
    this.genesis = genesis ?? (network === 'mainnet-beta' ? STOCK_WALLET_GENESIS : LOCAL_GENESIS);
    this.lamports = lamports;
    this.fee = fee;
    this.tokenAccounts = tokenAccounts ?? [];
    this.accounts = accounts;
    this.rent = rent;
    this.statuses = statuses;
    this.transaction = transaction;
    this.height = height;
    this.blockhashValid = blockhashValid;
    this.simulationError = simulationError;
    this.calls = [];
    this.sent = [];
    this.sendHandler = null;
  }
  async assertNetwork() {
    if (this.network === 'mainnet-beta' && this.genesis !== STOCK_WALLET_GENESIS) {
      throw new StockReturnError('RETURN_WRONG_NETWORK');
    }
    return this.genesis;
  }
  async call(method, params = []) {
    this.calls.push(method);
    switch (method) {
      case 'getGenesisHash': return this.genesis;
      case 'getLatestBlockhash': return {context: {slot: 10}, value: {blockhash, lastValidBlockHeight: 1_150}};
      case 'getBalance': return {context: {slot: 10}, value: Number(this.lamports)};
      case 'getFeeForMessage': return {context: {slot: 10}, value: this.fee};
      case 'getTokenAccountsByOwner': return {context: {slot: 10}, value: this.tokenAccounts};
      case 'getMultipleAccounts': return {context: {slot: 10}, value: params[0].map(item => {
        const entry = this.accounts[item];
        return entry === undefined ? null : {lamports: entry.lamports, owner: TOKEN_PROGRAM, executable: false,
          data: ['', 'base64'], rentEpoch: 0, space: 165};
      })};
      case 'getMinimumBalanceForRentExemption': return this.rent;
      case 'simulateTransaction': return {context: {slot: 10},
        value: {err: this.simulationError, logs: [], unitsConsumed: 450, accounts: null}};
      case 'sendTransaction': {
        this.sent.push(params[0]);
        return this.sendHandler ? this.sendHandler(params[0]) : 'wrong-receipt';
      }
      case 'getSignatureStatuses': return {context: {slot: 10}, value: [this.statuses.shift() ?? null]};
      case 'getTransaction': return this.transaction;
      case 'getBlockHeight': return this.height;
      case 'isBlockhashValid': return {context: {slot: 10}, value: this.blockhashValid};
      default: throw new StockReturnError('RETURN_RPC_METHOD_DENIED');
    }
  }
}

function tokenAccount(pubkey, owner, {amount = '1000000', decimals = 6, mint = USDC_MINT} = {}) {
  return {pubkey, account: {owner: TOKEN_PROGRAM, executable: false, lamports: 2_039_280,
    data: {program: 'spl-token', parsed: {type: 'account', info: {owner, mint, state: 'initialized',
      isNative: false, tokenAmount: {amount, decimals}}}}}};
}

/** A private home with a valid research marker, for the command-line path. */
async function fakeHome(publicAddress, secret) {
  const home = join(base, `home-${randomUUID()}`);
  const directory = join(home, '.config', 'trimmy', 'testing', 'stock-order-mainnet-v1');
  await mkdir(directory, {recursive: true, mode: 0o700});
  await chmod(directory, 0o700);
  await writeFile(join(directory, 'wallet.json'), JSON.stringify({schemaVersion: 1,
    createdBy: 'trimmy-stock-order-inspection-v1', purpose: 'read_only_stock_order_inspection',
    network: 'mainnet-beta', genesisHash: STOCK_WALLET_GENESIS, publicAddress,
    localResearchPrincipalId: randomUUID(), applicationAuthenticationVerified: false,
    createdAt: new Date().toISOString()}), {mode: 0o600});
  await writeFile(join(directory, 'keypair.json'), JSON.stringify(Array.from(secret)), {mode: 0o600});
  return {home, directory};
}

it('a destination must be a real on-curve address that is not the source', async () => {
  const signer = await newSigner();
  const [offCurve] = await getProgramDerivedAddress({
    programAddress: address('11111111111111111111111111111111'),
    seeds: [new TextEncoder().encode('trimmy-return-test')],
  });
  assert.equal(isOffCurveAddress(offCurve), true);
  assert.equal(returnDestination(signer.address), signer.address);
  for (const bad of ['', 'nope', '11111111111111111111111111111111', `${signer.address.slice(0, -1)}0`, offCurve]) {
    assert.throws(() => returnDestination(bad), errorIs('RETURN_DESTINATION_INVALID'), bad);
  }
  assert.throws(() => returnDestination(signer.address, signer.address), errorIs('RETURN_DESTINATION_IS_SOURCE'));
});

it('the transport allowlist has no method beyond the return path', async () => {
  const rpc = new ReturnRpc({network: 'mainnet-beta', fetchImpl: async () => { throw new Error('no network'); }});
  assert.equal(rpc.url, 'https://api.mainnet-beta.solana.com');
  for (const method of ['requestAirdrop', 'getProgramAccounts', 'getVoteAccounts', 'signTransaction']) {
    await assert.rejects(rpc.call(method), errorIs('RETURN_RPC_METHOD_DENIED'), method);
  }
  assert.throws(() => new ReturnRpc({network: 'devnet'}), errorIs('RETURN_NETWORK_INVALID'));
  assert.throws(() => new ReturnRpc({network: 'mainnet-beta', timeoutMs: 30_000}), errorIs('RETURN_CONFIGURATION_INVALID'));
});

it('the mainnet transport refuses any cluster but mainnet, and localnet refuses public clusters', async () => {
  const respond = genesis => async () => new Response(JSON.stringify({jsonrpc: '2.0', id: 1, result: genesis}),
    {status: 200, headers: {'content-type': 'application/json'}});
  await assert.rejects(new ReturnRpc({network: 'mainnet-beta', fetchImpl: respond(LOCAL_GENESIS)}).assertNetwork(),
    errorIs('RETURN_WRONG_NETWORK'));
  assert.equal(await new ReturnRpc({network: 'mainnet-beta', fetchImpl: respond(STOCK_WALLET_GENESIS)}).assertNetwork(),
    STOCK_WALLET_GENESIS);
  await assert.rejects(new ReturnRpc({network: 'localnet', fetchImpl: respond(STOCK_WALLET_GENESIS)}).assertNetwork(),
    errorIs('RETURN_WRONG_NETWORK'));
  assert.equal(await new ReturnRpc({network: 'localnet', fetchImpl: respond(LOCAL_GENESIS)}).assertNetwork(), LOCAL_GENESIS);
});

it('a SOL plan sweeps the balance minus the measured fee and signs exactly one transfer', async () => {
  const signer = await newSigner();
  const destination = (await newSigner()).address;
  const rpc = new FakeRpc({lamports: 10_000_000n, fee: 5_000});
  const plan = await planReturn({rpc, signer, publicAddress: signer.address, asset: 'sol', destination});
  assert.equal(plan.createdBy, STOCK_RETURN_TOOL_ID);
  assert.equal(plan.asset, 'sol');
  assert.equal(plan.source, signer.address);
  assert.equal(plan.destination, destination);
  assert.equal(plan.amountRaw, '9995000');
  assert.equal(plan.feeLamports, 5_000);
  assert.equal(plan.sourceLamportsBefore, '10000000');
  assert.equal(plan.createsDestinationAccount, false);
  assert.equal(plan.rentLamports, '0');
  assert.match(plan.messageSha256, /^[0-9a-f]{64}$/);
  // Exactly one instruction, signed by the source alone.
  const decoded = getTransactionDecoder().decode(Buffer.from(plan.wire, 'base64'));
  assert.deepEqual(Object.keys(decoded.signatures), [signer.address]);
  assert.notEqual(decoded.signatures[signer.address], null);
  assert.ok(Object.isFrozen(plan));
});

it('a SOL plan refuses a balance that cannot pay its own fee', async () => {
  const signer = await newSigner();
  const destination = (await newSigner()).address;
  for (const lamports of [0n, 5_000n]) {
    const rpc = new FakeRpc({lamports, fee: 5_000});
    await assert.rejects(planReturn({rpc, signer, publicAddress: signer.address, asset: 'sol', destination}),
      errorIs('RETURN_BALANCE_INSUFFICIENT'), String(lamports));
  }
});

it('an unexpected fee stops the plan before anything is stored', async () => {
  const signer = await newSigner();
  const rpc = new FakeRpc({fee: MAX_FEE_LAMPORTS + 1});
  await assert.rejects(planReturn({rpc, signer, publicAddress: signer.address, asset: 'sol',
    destination: (await newSigner()).address}), errorIs('RETURN_FEE_UNEXPECTED'));
});

it('a token plan moves the whole canonical balance and reports an ancillary account', async () => {
  const signer = await newSigner();
  const destination = (await newSigner()).address;
  const position = await tokenPosition(new FakeRpc({tokenAccounts: []}), signer.address);
  const destinationPosition = await tokenPosition(new FakeRpc({tokenAccounts: []}), destination);
  const rpc = new FakeRpc({tokenAccounts: [
    tokenAccount(position.associated, signer.address, {amount: '2500000'}),
    tokenAccount((await newSigner()).address, signer.address, {amount: '7'}),
  ], accounts: {[destinationPosition.associated]: {lamports: 2_039_280}}});
  const plan = await planReturn({rpc, signer, publicAddress: signer.address, asset: 'usdc', destination});
  assert.equal(plan.asset, 'usdc');
  assert.equal(plan.amountRaw, '2500000');
  assert.equal(plan.decimals, 6);
  assert.equal(plan.mint, USDC_MINT);
  assert.equal(plan.sourceTokenAccount, position.associated);
  assert.equal(plan.ancillaryAccounts, 1);
  assert.equal(plan.createsDestinationAccount, false);
  assert.equal(plan.rentLamports, '0');
});

it('a token plan creates a missing destination account and requires the rent', async () => {
  const signer = await newSigner();
  const destination = (await newSigner()).address;
  const position = await tokenPosition(new FakeRpc({tokenAccounts: []}), signer.address);
  const accounts = [tokenAccount(position.associated, signer.address, {amount: '1000000'})];
  const plan = await planReturn({rpc: new FakeRpc({tokenAccounts: accounts, rent: 2_039_280,
    lamports: 10_000_000n}), signer, publicAddress: signer.address, asset: 'usdc', destination});
  assert.equal(plan.createsDestinationAccount, true);
  assert.equal(plan.rentLamports, '2039280');
  await assert.rejects(planReturn({rpc: new FakeRpc({tokenAccounts: accounts, rent: 2_039_280,
    lamports: 1_000n}), signer, publicAddress: signer.address, asset: 'usdc', destination}),
  errorIs('RETURN_BALANCE_INSUFFICIENT'));
});

it('a token plan refuses an empty balance and a mismatched mint', async () => {
  const signer = await newSigner();
  const destination = (await newSigner()).address;
  await assert.rejects(planReturn({rpc: new FakeRpc({tokenAccounts: []}), signer,
    publicAddress: signer.address, asset: 'usdc', destination}), errorIs('RETURN_BALANCE_INSUFFICIENT'));
  const other = (await newSigner()).address;
  await assert.rejects(tokenPosition(new FakeRpc({tokenAccounts: [
    tokenAccount(other, signer.address, {mint: other}),
  ]}), signer.address), errorIs('RETURN_BALANCE_INVALID'));
});

it('submission verifies the signature receipt and never treats sending as confirmation', async () => {
  const signer = await newSigner();
  const rpc = new FakeRpc({lamports: 10_000_000n});
  const plan = await planReturn({rpc, signer, publicAddress: signer.address, asset: 'sol',
    destination: (await newSigner()).address});
  // A receipt that is not our signature fails closed.
  await assert.rejects(submitPlan({rpc, plan}), errorIs('RETURN_SIGNATURE_RECEIPT_MISMATCH'));
  // A failed simulation never reaches sendTransaction.
  const failing = new FakeRpc({simulationError: {InstructionError: [0, 'Custom']}});
  failing.sendHandler = () => plan.signature;
  await assert.rejects(submitPlan({rpc: failing, plan}), errorIs('RETURN_SIMULATION_FAILED'));
  assert.equal(failing.sent.length, 0);
  // The happy path sends the exact stored bytes once and confirms.
  const good = new FakeRpc({statuses: [null, {err: null, confirmationStatus: 'confirmed'}]});
  good.sendHandler = () => plan.signature;
  const outcome = await submitPlan({rpc: good, plan, confirmation: {pause: async () => {}}});
  assert.equal(outcome.signature, plan.signature);
  assert.equal(outcome.confirmation, 'confirmed');
  assert.deepEqual(good.sent, [plan.wire]);
  // Simulation runs with signature verification on and the bound blockhash kept.
  assert.ok(good.calls.includes('simulateTransaction'));
});

it('a rejected transaction is reported as failed, never as pending', async () => {
  const signer = await newSigner();
  const rpc = new FakeRpc();
  const plan = await planReturn({rpc, signer, publicAddress: signer.address, asset: 'sol',
    destination: (await newSigner()).address});
  const failing = new FakeRpc({statuses: [{err: {InstructionError: [0, 'Custom']}, confirmationStatus: 'confirmed'}]});
  failing.sendHandler = () => plan.signature;
  await assert.rejects(submitPlan({rpc: failing, plan, confirmation: {pause: async () => {}}}),
    errorIs('RETURN_TRANSACTION_FAILED'));
});

it('an unknown outcome resends the exact same bytes while the blockhash lives', async () => {
  const signer = await newSigner();
  const plan = await planReturn({rpc: new FakeRpc(), signer, publicAddress: signer.address, asset: 'sol',
    destination: (await newSigner()).address});
  const rpc = new FakeRpc({statuses: [null, null, {err: null, confirmationStatus: 'finalized'}],
    transaction: null, height: 1_000, blockhashValid: true, lamports: 1_000_000_000n});
  rpc.sendHandler = () => plan.signature;
  const outcome = await resolvePlan({rpc, plan, confirmation: {pause: async () => {}}});
  assert.equal(outcome.status, 'confirmed');
  assert.equal(outcome.rebroadcast, true);
  assert.deepEqual(rpc.sent, [plan.wire]);
});

it('an already confirmed plan is never resent', async () => {
  const signer = await newSigner();
  const plan = await planReturn({rpc: new FakeRpc(), signer, publicAddress: signer.address, asset: 'sol',
    destination: (await newSigner()).address});
  const rpc = new FakeRpc({statuses: [{err: null, confirmationStatus: 'confirmed'}]});
  const outcome = await resolvePlan({rpc, plan});
  assert.equal(outcome.status, 'confirmed');
  assert.equal(outcome.rebroadcast, false);
  assert.equal(rpc.sent.length, 0);
});

it('expiry is only reported when the signature is absent and the balance is unchanged', async () => {
  const signer = await newSigner();
  const plan = await planReturn({rpc: new FakeRpc({lamports: 1_000_000_000n}), signer,
    publicAddress: signer.address, asset: 'sol', destination: (await newSigner()).address});
  const expired = new FakeRpc({statuses: [null], transaction: null, height: 2_000, blockhashValid: false,
    lamports: 1_000_000_000n});
  const outcome = await resolvePlan({rpc: expired, plan});
  assert.equal(outcome.status, 'expired');
  assert.equal(outcome.transactionAbsent, true);
  assert.equal(outcome.balanceUnchanged, true);
  assert.equal(expired.sent.length, 0);
  // A changed balance means the transfer may have landed: never declare expiry.
  const moved = new FakeRpc({statuses: [null], transaction: null, height: 2_000, blockhashValid: false,
    lamports: 1n});
  await assert.rejects(resolvePlan({rpc: moved, plan}), errorIs('RETURN_BALANCE_CONFLICT'));
  // A present transaction with no status is inconsistent, not expired.
  const present = new FakeRpc({statuses: [null], transaction: {slot: 5}, height: 2_000, blockhashValid: false,
    lamports: 1_000_000_000n});
  await assert.rejects(resolvePlan({rpc: present, plan}), errorIs('RETURN_STATUS_INCONSISTENT'));
});

it('a stored plan is validated and a malformed one is refused', async () => {
  const signer = await newSigner();
  const plan = await planReturn({rpc: new FakeRpc(), signer, publicAddress: signer.address, asset: 'sol',
    destination: (await newSigner()).address});
  assert.equal(validatePlan(plan), plan);
  for (const change of [{createdBy: 'other'}, {asset: 'eth'}, {network: 'devnet'}, {wire: ''},
    {signature: 'short'}, {feeLamports: MAX_FEE_LAMPORTS + 1}, {amountRaw: '-1'}, {messageSha256: 'zz'}]) {
    assert.throws(() => validatePlan({...plan, ...change}), errorIs('RETURN_PLAN_INVALID'), JSON.stringify(change));
  }
  assert.throws(() => validatePlan(plan, {network: 'localnet'}), errorIs('RETURN_PLAN_INVALID'));
});

it('the command line requires the network, asset, destination and an explicit confirmation', async () => {
  const secret = secretBytes();
  const signer = await createKeyPairSignerFromBytes(Uint8Array.from(secret));
  const {home} = await fakeHome(signer.address, secret);
  const destination = (await newSigner()).address;
  const rpcFactory = () => new FakeRpc();
  for (const args of [[], ['--network', 'mainnet-beta'], ['--network', 'mainnet-beta', '--asset', 'sol'],
    ['--network', 'mainnet-beta', '--asset', 'sol', '--to', destination],
    ['--network', 'mainnet-beta', '--asset', 'sol', '--to', destination, '--wat'],
    ['--asset', 'sol', '--to', destination, '--confirm'],
    ['--network', 'mainnet-beta', '--asset', 'sol', '--to', '--confirm']]) {
    await assert.rejects(runStockReturnCli(args, {homeDirectory: home, rpcFactory}),
      errorIs('RETURN_ARGUMENTS_INVALID'), JSON.stringify(args));
  }
});

it('the command line stores a plan before sending and clears it after confirmation', async () => {
  const secret = secretBytes();
  const signer = await createKeyPairSignerFromBytes(Uint8Array.from(secret));
  const {home, directory} = await fakeHome(signer.address, secret);
  const destination = (await newSigner()).address;
  let captured = null;
  const rpcFactory = () => {
    const rpc = new FakeRpc({lamports: 10_000_000n, statuses: [{err: null, confirmationStatus: 'confirmed'}]});
    rpc.sendHandler = wire => {
      captured = wire;
      // The plan must already be on disk before any send.
      return JSON.parse(readFileSync(join(directory, PLAN_FILENAME), 'utf8')).signature;
    };
    return rpc;
  };
  const result = await runStockReturnCli(['--network', 'mainnet-beta', '--asset', 'sol', '--to', destination, '--confirm'],
    {homeDirectory: home, rpcFactory});
  assert.equal(result.status, 'confirmed');
  assert.equal(result.plan.destination, destination);
  assert.equal(captured, result.plan.wire);
  assert.equal(await readStoredPlan(directory), null);
  const names = await readdir(directory);
  const outcome = JSON.parse(await readFile(join(directory,
    names.find(name => name.startsWith('return-outcome-'))), 'utf8'));
  assert.equal(outcome.outcome.signature, result.plan.signature);
});

it('an unresolved plan blocks a different transaction until it is resolved', async () => {
  const secret = secretBytes();
  const signer = await createKeyPairSignerFromBytes(Uint8Array.from(secret));
  const {home, directory} = await fakeHome(signer.address, secret);
  const destination = (await newSigner()).address;
  // A send whose receipt never matches leaves the plan on disk.
  const stuck = await runStockReturnCli(['--network', 'mainnet-beta', '--asset', 'sol', '--to', destination, '--confirm'],
    {homeDirectory: home, rpcFactory: () => new FakeRpc({lamports: 10_000_000n})});
  assert.equal(stuck.status, 'unresolved');
  assert.equal(stuck.errorCode, 'RETURN_SIGNATURE_RECEIPT_MISMATCH');
  const stored = await readStoredPlan(directory);
  assert.equal(stored.signature, stuck.plan.signature);
  await assert.rejects(runStockReturnCli(['--network', 'mainnet-beta', '--asset', 'sol', '--to', destination, '--confirm'],
    {homeDirectory: home, rpcFactory: () => new FakeRpc({lamports: 10_000_000n})}), errorIs('RETURN_PLAN_UNRESOLVED'));
  // Resolving it as expired frees the wallet for a fresh plan.
  const resolved = await runStockReturnCli(['--network', 'mainnet-beta', '--resolve'], {homeDirectory: home,
    rpcFactory: () => new FakeRpc({statuses: [null], transaction: null, height: 2_000, blockhashValid: false,
      lamports: 10_000_000n})});
  assert.equal(resolved.status, 'expired');
  assert.equal(await readStoredPlan(directory), null);
});

it('the command line refuses a home without a valid research marker', async () => {
  const home = join(base, `empty-${randomUUID()}`);
  await mkdir(home, {recursive: true, mode: 0o700});
  await assert.rejects(openReturnSigner({homeDirectory: home}), errorIs('RETURN_WALLET_NOT_FOUND'));
  await assert.rejects(openReturnSigner({homeDirectory: 'relative/path'}), errorIs('RETURN_INVALID_PATH'));
  const secret = secretBytes();
  const signer = await createKeyPairSignerFromBytes(Uint8Array.from(secret));
  const {home: valid, directory} = await fakeHome(signer.address, secret);
  const opened = await openReturnSigner({homeDirectory: valid});
  assert.equal(opened.publicAddress, signer.address);
  assert.equal(opened.directory, directory);
  // A marker naming a different key cannot unlock this one.
  await writeFile(join(directory, 'wallet.json'), JSON.stringify({schemaVersion: 1, network: 'mainnet-beta',
    genesisHash: STOCK_WALLET_GENESIS, publicAddress: (await newSigner()).address}), {mode: 0o600});
  await assert.rejects(openReturnSigner({homeDirectory: valid}), errorIs('RETURN_KEY_MISMATCH'));
  // A marker for another network is refused before the key is read.
  await writeFile(join(directory, 'wallet.json'), JSON.stringify({schemaVersion: 1, network: 'devnet',
    genesisHash: STOCK_WALLET_GENESIS, publicAddress: signer.address}), {mode: 0o600});
  await assert.rejects(openReturnSigner({homeDirectory: valid}), errorIs('RETURN_MARKER_INVALID'));
});

it('clearing a plan records the outcome and cannot overwrite an earlier record', async () => {
  const secret = secretBytes();
  const signer = await createKeyPairSignerFromBytes(Uint8Array.from(secret));
  const {directory} = await fakeHome(signer.address, secret);
  const plan = await planReturn({rpc: new FakeRpc(), signer, publicAddress: signer.address, asset: 'sol',
    destination: (await newSigner()).address});
  await writeFile(join(directory, PLAN_FILENAME), `${JSON.stringify(plan)}\n`, {mode: 0o600});
  await clearStoredPlan(directory, {plan, outcome: {status: 'confirmed'}, resolvedAt: new Date().toISOString()});
  assert.equal(await readStoredPlan(directory), null);
});

it('the SOL sweep closes an emptied token account and adds its rent to the transfer', async () => {
  const signer = await newSigner();
  const destination = (await newSigner()).address;
  const position = await tokenPosition(new FakeRpc({tokenAccounts: []}), signer.address);
  const rpc = new FakeRpc({lamports: 10_000_000n, fee: 5_000,
    tokenAccounts: [tokenAccount(position.associated, signer.address, {amount: '0'})],
    accounts: {[position.associated]: {lamports: 2_039_280}}});
  const plan = await planReturn({rpc, signer, publicAddress: signer.address, asset: 'sol', destination});
  assert.equal(plan.closesSourceTokenAccount, true);
  assert.equal(plan.reclaimedRentLamports, '2039280');
  assert.equal(plan.tokenBalanceRemains, false);
  assert.equal(plan.amountRaw, (10_000_000n + 2_039_280n - 5_000n).toString());
});

it('the SOL sweep leaves a funded token account alone and says so', async () => {
  const signer = await newSigner();
  const destination = (await newSigner()).address;
  const position = await tokenPosition(new FakeRpc({tokenAccounts: []}), signer.address);
  const rpc = new FakeRpc({lamports: 10_000_000n, fee: 5_000,
    tokenAccounts: [tokenAccount(position.associated, signer.address, {amount: '250000'})],
    accounts: {[position.associated]: {lamports: 2_039_280}}});
  const plan = await planReturn({rpc, signer, publicAddress: signer.address, asset: 'sol', destination});
  assert.equal(plan.closesSourceTokenAccount, false);
  assert.equal(plan.reclaimedRentLamports, '0');
  assert.equal(plan.tokenBalanceRemains, true);
  assert.equal(plan.amountRaw, '9995000');
});
