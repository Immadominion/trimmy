import assert from 'node:assert/strict';
import { mkdtemp, rm, lstat, chmod, readFile, writeFile, symlink, unlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { it } from 'node:test';
import { openStockResearchWallet, assertStockResearchWallet, STOCK_WALLET_NAME, StockWalletError } from './stock-order-wallet.mjs';
const errorIs = code => error => error instanceof StockWalletError && error.code === code;
async function fixture(fn) {
  const home = await mkdtemp(join(tmpdir(), 'trimmy-stock-wallet-test-'));
  try { await fn(home, join(home, '.config', 'trimmy', 'testing', STOCK_WALLET_NAME)); }
  finally { await rm(home, {recursive: true, force: true}); }
}
it('exclusively creates a private dedicated key/marker and reopens the same proven address', async () => fixture(async (homeDirectory, path) => {
  const wallet = await openStockResearchWallet({mode: 'create', homeDirectory});
  assert.equal((await lstat(path)).mode & 0o777, 0o700);
  for (const name of ['keypair.json', 'wallet.json']) assert.equal((await lstat(join(path, name))).mode & 0o777, 0o600);
  assert.equal(wallet.localKeyAccessVerified, true); assert.equal(wallet.applicationAuthenticationVerified, false);
  assertStockResearchWallet(wallet);
  assert.equal(typeof wallet.publicAddress, 'string'); assert.equal(Object.keys(wallet).some(key => /secret|private|signer|signature|challenge/i.test(key)), false);
  const reopened = await openStockResearchWallet({mode: 'reopen', homeDirectory});
  assert.equal(reopened.publicAddress, wallet.publicAddress); assert.equal(reopened.localResearchPrincipalId, wallet.localResearchPrincipalId);
  await assert.rejects(openStockResearchWallet({mode: 'create', homeDirectory}), errorIs('STOCK_WALLET_ALREADY_EXISTS'));
}));
it('concurrent creation converges on exactly one winner without replacing its key', async () => fixture(async (homeDirectory) => {
  const attempts = await Promise.allSettled([openStockResearchWallet({mode: 'create', homeDirectory}), openStockResearchWallet({mode: 'create', homeDirectory})]);
  const successes = attempts.filter(result => result.status === 'fulfilled'); assert.equal(successes.length, 1);
  const reopened = await openStockResearchWallet({mode: 'reopen', homeDirectory});
  assert.equal(reopened.publicAddress, successes[0].value.publicAddress);
}));
it('reopen never creates a missing wallet and rejects traversal/relative paths', async () => fixture(async (homeDirectory) => {
  await assert.rejects(openStockResearchWallet({mode: 'reopen', homeDirectory}), errorIs('STOCK_WALLET_NOT_FOUND'));
  for (const bad of ['relative', homeDirectory + '/..', homeDirectory + '/']) await assert.rejects(openStockResearchWallet({mode: 'create', homeDirectory: bad}), errorIs('STOCK_WALLET_INVALID_PATH'));
}));
it('rejects symlinked private directory, key and marker paths without following them', async () => fixture(async (homeDirectory, path) => {
  await openStockResearchWallet({mode: 'create', homeDirectory});
  for (const name of ['keypair.json', 'wallet.json']) {
    const file = join(path, name); const bytes = await readFile(file);
    try {
      const target = join(homeDirectory, 'test-link-target'); await writeFile(target, bytes, {mode: 0o600});
      await unlink(file); await symlink(target, file);
      await assert.rejects(openStockResearchWallet({mode: 'reopen', homeDirectory}), errorIs('STOCK_WALLET_STORAGE_FAILED'));
      await unlink(file); await writeFile(file, bytes, {mode: 0o600}); await unlink(target);
    } finally { bytes.fill(0); }
  }
  await rm(path, {recursive: true}); await symlink(homeDirectory, path);
  await assert.rejects(openStockResearchWallet({mode: 'reopen', homeDirectory}), errorIs('STOCK_WALLET_UNSAFE_DIRECTORY'));
}));
it('rejects permissive key, marker and directory modes without silently chmodding them', async () => fixture(async (homeDirectory, path) => {
  await openStockResearchWallet({mode: 'create', homeDirectory});
  for (const name of ['keypair.json', 'wallet.json']) {
    await chmod(join(path, name), 0o644);
    await assert.rejects(openStockResearchWallet({mode: 'reopen', homeDirectory}), errorIs('STOCK_WALLET_UNSAFE_FILE'));
    await chmod(join(path, name), 0o600);
  }
  await chmod(path, 0o750);
  await assert.rejects(openStockResearchWallet({mode: 'reopen', homeDirectory}), errorIs('STOCK_WALLET_UNSAFE_DIRECTORY'));
}));
it('rejects wrong-network/provenance markers before attempting to read a now-missing key', async () => fixture(async (homeDirectory, path) => {
  await openStockResearchWallet({mode: 'create', homeDirectory});
  const marker = JSON.parse(await readFile(join(path, 'wallet.json'), 'utf8')); await unlink(join(path, 'keypair.json'));
  for (const change of [{network: 'devnet'}, {genesisHash: 'devnet'}, {createdBy: 'other'}, {applicationAuthenticationVerified: true}]) {
    await writeFile(join(path, 'wallet.json'), JSON.stringify({...marker, ...change}), {mode: 0o600});
    await assert.rejects(openStockResearchWallet({mode: 'reopen', homeDirectory}), errorIs('STOCK_WALLET_MARKER_INVALID'));
  }
}));
it('rejects invalid key contents and counterfeit public handles', async () => fixture(async (homeDirectory, path) => {
  const wallet = await openStockResearchWallet({mode: 'create', homeDirectory});
  assert.throws(() => assertStockResearchWallet({...wallet}), errorIs('STOCK_WALLET_UNRECOGNIZED_HANDLE'));
  await writeFile(join(path, 'keypair.json'), '[]', {mode: 0o600});
  await assert.rejects(openStockResearchWallet({mode: 'reopen', homeDirectory}), errorIs('STOCK_WALLET_KEY_INVALID'));
}));
