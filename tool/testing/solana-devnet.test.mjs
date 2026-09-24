import assert from 'node:assert/strict';
import { chmod, lstat, mkdtemp, readFile, readdir, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  DEVNET_GENESIS, DEVNET_URL, DevnetRpc, SmokeError, TRANSFER_LAMPORTS,
  confirmSignature, exclusiveJson, openTestWallet, prepareTransfer, recoverSignedTransfer, runDevnetSmoke, simulateAndSend,
} from './solana-devnet.mjs';

async function withDirectory(work) {
  const directory = await mkdtemp(join(tmpdir(), 'trimmy-devnet-test-'));
  try { await work(directory); } finally { await rm(directory, { recursive: true, force: true }); }
}
const response = (request, result) => new Response(JSON.stringify({ jsonrpc: '2.0', id: JSON.parse(request.body).id, result }), {
  headers: { 'content-type': 'application/json' },
});

test('fixed devnet identity fails before wallet creation or airdrop on another chain', async () => {
  await withDirectory(async (directory) => {
    const methods = [];
    const rpc = new DevnetRpc({ fetchImpl: async (url, request) => {
      assert.equal(url, DEVNET_URL);
      assert.equal(request.redirect, 'error');
      methods.push(JSON.parse(request.body).method);
      return response(request, '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d');
    } });
    const report = await runDevnetSmoke({ rpc, baseDirectory: join(directory, 'wallets') });
    assert.equal(report.errorCode, 'WRONG_CHAIN');
    assert.deepEqual(methods, ['getGenesisHash']);
    assert.deepEqual(await readdir(directory), []);
  });
});

test('RPC rejects unbounded bodies, mismatched response identity and unexpected methods', async () => {
  const huge = new DevnetRpc({ fetchImpl: async () => new Response(' '.repeat(262_145), { headers: { 'content-type': 'application/json' } }) });
  await assert.rejects(huge.assertDevnet(), { code: 'RPC_RESPONSE_TOO_LARGE' });
  const wrongId = new DevnetRpc({ fetchImpl: async () => new Response(JSON.stringify({ jsonrpc: '2.0', id: 99, result: DEVNET_GENESIS }), {
    headers: { 'content-type': 'application/json' },
  }) });
  await assert.rejects(wrongId.assertDevnet(), { code: 'RPC_INVALID_RESPONSE' });
  await assert.rejects(wrongId.call('sendBundle'), { code: 'RPC_METHOD_NOT_ALLOWED' });
});

test('RPC aborts a stalled request and sanitizes provider errors', async () => {
  const rpc = new DevnetRpc({ timeoutMs: 5, fetchImpl: async (_url, request) => new Promise((_resolve, reject) => {
    request.signal.addEventListener('abort', () => reject(new Error('provider text must not escape')), { once: true });
  }) });
  await assert.rejects(rpc.assertDevnet(), { code: 'RPC_TIMEOUT', message: 'RPC_TIMEOUT' });
  const limited = new DevnetRpc({ fetchImpl: async () => new Response('secret provider diagnostic', { status: 429 }) });
  await assert.rejects(limited.assertDevnet(), { code: 'RPC_HTTP_429', message: 'RPC_HTTP_429' });
});

test('only marked private wallets can reopen; keys are private, exclusive and outside reports', async () => {
  await withDirectory(async (directory) => {
    const wallet = await openTestWallet(directory);
    assert.equal((await lstat(wallet.directory)).mode & 0o777, 0o700);
    for (const name of ['wallet.json', 'signer.json', 'recipient.json']) {
      assert.equal((await lstat(join(wallet.directory, name))).mode & 0o777, 0o600);
    }
    const signerPath = join(wallet.directory, 'signer.json');
    const original = await readFile(signerPath, 'utf8');
    await assert.rejects(exclusiveJson(signerPath, []), { code: 'EEXIST' });
    assert.equal(await readFile(signerPath, 'utf8'), original);
    const reopened = await openTestWallet(directory, wallet.name);
    assert.equal(reopened.signer.address, wallet.signer.address);
    assert.equal(reopened.recipient, wallet.recipient);
    await writeFile(join(wallet.directory, 'wallet.json'), JSON.stringify({ schemaVersion: 1, network: 'mainnet' }));
    await assert.rejects(openTestWallet(directory, wallet.name), { code: 'UNRECOGNIZED_TEST_WALLET' });
  });
});

test('wallet path traversal, symlinks and public permissions are rejected', async () => {
  await withDirectory(async (directory) => {
    await assert.rejects(openTestWallet(directory, '../wallet'), { code: 'INVALID_WALLET_NAME' });
    const wallet = await openTestWallet(directory);
    const signerPath = join(wallet.directory, 'signer.json');
    await chmod(signerPath, 0o644);
    await assert.rejects(openTestWallet(directory, wallet.name), { code: 'UNSAFE_WALLET_FILE' });
    await rm(signerPath);
    await symlink(join(wallet.directory, 'recipient.json'), signerPath);
    await assert.rejects(openTestWallet(directory, wallet.name), { code: 'ELOOP' });
    await chmod(directory, 0o755);
    await assert.rejects(openTestWallet(directory), { code: 'UNSAFE_WALLET_DIRECTORY' });
  });
});

test('real Ed25519 signing succeeds; the exact signed bytes are simulated then sent after durable acknowledgment', async () => {
  await withDirectory(async (directory) => {
    const wallet = await openTestWallet(directory);
    const preparationRpc = { call: async (method) => method === 'getLatestBlockhash'
      ? { value: { blockhash: DEVNET_GENESIS, lastValidBlockHeight: 123 } } : { value: 5000 } };
    const plan = await prepareTransfer(preparationRpc, wallet);
    assert.equal(plan.localSignatureVerified, true);
    assert.equal(plan.feeLamports, 5000);
    const order = [];
    const rpc = { assertDevnet: async () => order.push('identity'), call: async (method, params) => {
      order.push(method);
      assert.equal(params[0], plan.wire);
      if (method === 'simulateTransaction') {
        assert.equal(params[1].sigVerify, true);
        assert.equal(params[1].replaceRecentBlockhash, undefined);
        return { value: { err: null, unitsConsumed: 150 } };
      }
      assert.equal(params[1].skipPreflight, false);
      assert.equal(params[1].maxRetries, 3);
      return plan.signature;
    } };
    assert.equal(await simulateAndSend(rpc, plan, async () => order.push('durable-plan')), 150);
    assert.deepEqual(order, ['identity', 'simulateTransaction', 'durable-plan', 'identity', 'sendTransaction']);
  });
});

test('failed simulation or failed durable plan cannot broadcast; a mismatched send receipt cannot succeed', async () => {
  const methods = [];
  let simulationError = 'InsufficientFunds';
  const rpc = { assertDevnet: async () => {}, call: async (method) => {
    methods.push(method);
    return method === 'simulateTransaction' ? { value: { err: simulationError, unitsConsumed: 150 } } : 'different-signature';
  } };
  const plan = { wire: 'signed-wire', signature: 'expected-signature' };
  await assert.rejects(simulateAndSend(rpc, plan, async () => assert.fail('should not persist')), { code: 'SIMULATION_FAILED' });
  simulationError = null;
  await assert.rejects(simulateAndSend(rpc, plan, async () => { throw new SmokeError('DISK_FAILED'); }), { code: 'DISK_FAILED' });
  assert.deepEqual(methods, ['simulateTransaction', 'simulateTransaction']);
  await assert.rejects(simulateAndSend(rpc, plan, async () => {}), { code: 'SIGNATURE_RECEIPT_MISMATCH' });
});

test('directory sync must acknowledge a new plan before broadcast; a failed sync leaves the exclusive guard intact', async () => {
  await withDirectory(async (directory) => {
    let sends = 0;
    let syncAttempts = 0;
    const rpc = { assertDevnet: async () => {}, call: async (method) => {
      if (method === 'simulateTransaction') return { value: { err: null, unitsConsumed: 150 } };
      sends++;
      return 'signature';
    } };
    const path = join(directory, 'transfer.json');
    const plan = { wire: 'public signed bytes', signature: 'signature' };
    await assert.rejects(simulateAndSend(rpc, plan, () => exclusiveJson(path, plan, {
      syncParent: async (parent) => {
        assert.equal(parent, directory);
        assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), plan);
        syncAttempts++;
        throw new SmokeError('DIRECTORY_SYNC_FAILED');
      },
    })), { code: 'DIRECTORY_SYNC_FAILED' });
    assert.equal(syncAttempts, 1);
    assert.equal(sends, 0);
    await assert.rejects(exclusiveJson(path, { wire: 'replacement', signature: 'different' }), { code: 'EEXIST' });
    assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), plan);
  });
});

test('confirmation requires success at confirmed/finalized; processed receipts and null statuses remain pending', async () => {
  let call = 0;
  const rpc = { call: async () => ({ value: [++call === 1 ? null : { err: null, confirmationStatus: 'processed' }] }) };
  await assert.rejects(confirmSignature(rpc, 'signature', { attempts: 2, pause: async () => {} }), { code: 'CONFIRMATION_PENDING' });
  assert.equal(call, 2);
  await assert.rejects(confirmSignature({ call: async () => ({ value: [{ err: { InstructionError: [0, 'failure'] }, confirmationStatus: 'confirmed' }] }) }, 'signature'), { code: 'TRANSACTION_FAILED' });
  assert.equal(await confirmSignature({ call: async () => ({ value: [{ err: null, confirmationStatus: 'finalized' }] }) }, 'signature'), 'finalized');
});

test('confirmation has a wall-clock deadline even when a status request never returns', async () => {
  const rpc = { call: async () => new Promise(() => {}) };
  await assert.rejects(confirmSignature(rpc, 'signature', { attempts: 25, timeoutMs: 5 }), { code: 'CONFIRMATION_PENDING' });
  await assert.rejects(confirmSignature(rpc, 'signature', { timeoutMs: 60_001 }), { code: 'INVALID_CONFIRMATION_LIMIT' });
});

test('confirmed smoke verifies exact balances and prevents a second logical transfer after restart', async () => {
  await withDirectory(async (directory) => {
    let sent = false;
    let signature;
    let source;
    const rpc = { assertDevnet: async () => {}, call: async (method, params) => {
      if (method === 'getBalance') {
        source ??= params[0];
        return { value: params[0] === source ? 100_000_000 - (sent ? TRANSFER_LAMPORTS + 5000 : 0) : (sent ? TRANSFER_LAMPORTS : 0) };
      }
      if (method === 'getMinimumBalanceForRentExemption') return 890880;
      if (method === 'getLatestBlockhash') return { value: { blockhash: DEVNET_GENESIS, lastValidBlockHeight: 123 } };
      if (method === 'getFeeForMessage') return { value: 5000 };
      if (method === 'simulateTransaction') return { value: { err: null, unitsConsumed: 150 } };
      if (method === 'sendTransaction') { sent = true; return signature; }
      if (method === 'getSignatureStatuses') return { value: [{ err: null, confirmationStatus: 'confirmed' }] };
      if (method === 'getTransaction') return { slot: 456, meta: { err: null, fee: 5000 }, transaction: { signatures: [signature] } };
      assert.fail(`Unexpected ${method}`);
    } };
    const report = await runDevnetSmoke({ rpc, baseDirectory: directory, notify: (event) => { if (event.signature) signature = event.signature; } });
    assert.equal(report.status, 'confirmed');
    assert.equal(report.balanceDeltasVerified, true);
    assert.equal(report.planPersistedBeforeSend, true);
    assert.equal(JSON.stringify(report).includes('wire'), false);
    const secretText = (await readFile(join(directory, report.walletName, 'signer.json'), 'utf8')).trim();
    assert.equal(JSON.stringify(report).includes(secretText), false, 'Reports must not contain key file contents');
    assert.equal(JSON.stringify(report).includes(Buffer.from(JSON.parse(secretText)).toString('base64')), false,
      'Reports must not contain base64 private keys');
    const restarted = await runDevnetSmoke({ rpc, baseDirectory: directory, existingName: report.walletName });
    assert.equal(restarted.errorCode, 'TRANSFER_ALREADY_PLANNED');
  });
});

test('an uncertain broadcast preserves the plan and reopening cannot silently send a second transfer', async () => {
  await withDirectory(async (directory) => {
    let source;
    let sendCount = 0;
    const events = [];
    const rpc = { assertDevnet: async () => {}, call: async (method, params) => {
      if (method === 'getBalance') { source ??= params[0]; return { value: params[0] === source ? 100_000_000 : 0 }; }
      if (method === 'getMinimumBalanceForRentExemption') return 890880;
      if (method === 'getLatestBlockhash') return { value: { blockhash: DEVNET_GENESIS, lastValidBlockHeight: 123 } };
      if (method === 'getFeeForMessage') return { value: 5000 };
      if (method === 'simulateTransaction') return { value: { err: null, unitsConsumed: 150 } };
      if (method === 'sendTransaction') { sendCount++; throw new SmokeError('RPC_TIMEOUT'); }
      assert.fail(`Unexpected ${method}`);
    } };
    const report = await runDevnetSmoke({ rpc, baseDirectory: directory, notify: (event) => events.push(event) });
    assert.equal(report.errorCode, 'RPC_TIMEOUT');
    assert.equal(report.planPersistedBeforeSend, true);
    const plan = JSON.parse(await readFile(join(directory, report.walletName, 'transfer.json'), 'utf8'));
    assert.equal(plan.signature, report.transferSignature);
    const restarted = await runDevnetSmoke({ rpc, baseDirectory: directory, existingName: report.walletName });
    assert.equal(restarted.errorCode, 'TRANSFER_ALREADY_PLANNED');
    assert.equal(sendCount, 1);
    const keyBytes = JSON.parse(await readFile(join(directory, report.walletName, 'signer.json'), 'utf8'));
    const output = JSON.stringify({ events, report, restarted });
    assert.equal(output.includes(JSON.stringify(keyBytes)), false, 'Public output must not contain private bytes');
    assert.equal(output.includes(Buffer.from(keyBytes).toString('base64')), false, 'Public output must not contain encoded private bytes');
  });
});

test('recovery validates and retries identical signed bytes once; failed retry acknowledgment cannot send', async () => {
  await withDirectory(async (directory) => {
    const wallet = await openTestWallet(directory);
    const plan = await prepareTransfer({ call: async (method) => method === 'getLatestBlockhash'
      ? { value: { blockhash: DEVNET_GENESIS, lastValidBlockHeight: 123 } } : { value: 5000 } }, wallet);
    let sends = 0;
    let identityChecks = 0;
    const rpc = { call: async (method, params) => {
      if (method === 'getSignatureStatuses') return { value: [sends ? { err: null, confirmationStatus: 'confirmed' } : null] };
      if (method === 'getTransaction') return null;
      if (method === 'getBlockHeight') return 100;
      if (method === 'isBlockhashValid') { assert.equal(params[0], DEVNET_GENESIS); return { value: true }; }
      if (method === 'getBalance') return { value: params[0] === wallet.signer.address ? 100_000_000 : 0 };
      if (method === 'sendTransaction') {
        sends++;
        assert.equal(params[0], plan.wire);
        assert.equal(params[1].maxRetries, 3);
        return plan.signature;
      }
      assert.fail(`Recovery must not create a new transaction: ${method}`);
    } };
    const args = { sender: wallet.signer.address, recipient: wallet.recipient, senderBeforeLamports: 100_000_000,
      recipientBeforeLamports: 0, identityCheck: async () => { identityChecks++; } };
    await assert.rejects(recoverSignedTransfer(rpc, plan, { ...args, beforeResend: async () => { throw new SmokeError('DISK_FAILED'); } }), { code: 'DISK_FAILED' });
    assert.equal(sends, 0);
    const recoveryFile = join(directory, 'recovery.json');
    const recovered = await recoverSignedTransfer(rpc, plan, { ...args, beforeResend: () => exclusiveJson(recoveryFile, { signature: plan.signature }) });
    assert.equal(recovered.signature, plan.signature);
    assert.equal(recovered.rebroadcast, true);
    assert.equal(sends, 1);
    assert.equal(identityChecks, 4);
    const observed = await recoverSignedTransfer(rpc, plan, { ...args, beforeResend: () => assert.fail('Already confirmed') });
    assert.equal(observed.rebroadcast, false);
    assert.equal(sends, 1);
    await assert.rejects(recoverSignedTransfer(rpc, { ...plan, signature: 'tampered' }, args), { code: 'INVALID_SAVED_TRANSFER' });
    await assert.rejects(recoverSignedTransfer(rpc, plan, { ...args, recipient: '11111111111111111111111111111111' }), { code: 'INVALID_SAVED_TRANSFER' });
  });
});

test('an expired plan only permits a distinct future intent after absence and unchanged balances are established', async () => {
  await withDirectory(async (directory) => {
    const wallet = await openTestWallet(directory);
    const plan = await prepareTransfer({ call: async (method) => method === 'getLatestBlockhash'
      ? { value: { blockhash: DEVNET_GENESIS, lastValidBlockHeight: 123 } } : { value: 5000 } }, wallet);
    let changed = false;
    const rpc = { call: async (method, params) => {
      if (method === 'getSignatureStatuses') return { value: [null] };
      if (method === 'getTransaction') return null;
      if (method === 'getBlockHeight') return 124;
      if (method === 'isBlockhashValid') return { value: false };
      if (method === 'getBalance') return { value: params[0] === wallet.signer.address ? (changed ? 99_000_000 : 100_000_000) : 0 };
      assert.fail(`Expired recovery must not sign or send: ${method}`);
    } };
    const args = { sender: wallet.signer.address, recipient: wallet.recipient, senderBeforeLamports: 100_000_000,
      recipientBeforeLamports: 0, identityCheck: async () => {} };
    const expired = await recoverSignedTransfer(rpc, plan, args);
    assert.equal(expired.status, 'expired');
    assert.equal(expired.oldTransactionAbsent, true);
    assert.equal(expired.balancesUnchanged, true);
    changed = true;
    await assert.rejects(recoverSignedTransfer(rpc, plan, args), { code: 'RECOVERY_BALANCE_CONFLICT' });
  });
});
