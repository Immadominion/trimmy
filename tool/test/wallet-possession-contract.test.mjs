import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));
const generator = fileURLToPath(new URL('../generate-wallet-possession-contract.mjs', import.meta.url));
const fixture = fileURLToPath(new URL('../../contracts/wallet-possession-v1.json', import.meta.url));
const run = (...args) => spawnSync(process.execPath, ['--import', 'tsx', generator, ...args],
  {cwd: root, encoding: 'utf8', timeout: 15_000, maxBuffer: 32_768});

test('actual route and signature verification produce a stable shared contract without private key material', () => {
  const directory = mkdtempSync(join(tmpdir(), 'trimmy-wallet-contract-'));
  try {
    const output = join(directory, 'contract.json');
    const generated = run('--output', output);
    assert.equal(generated.status, 0, generated.stderr);
    const first = readFileSync(output, 'utf8');
    assert.equal(first, readFileSync(fixture, 'utf8'));
    assert.equal(run('--output', output).status, 0);
    assert.equal(readFileSync(output, 'utf8'), first);
    const contract = JSON.parse(first);
    const challenge = contract.challenge.challenge;
    assert.equal(challenge.walletAddress, contract.account.walletAddress);
    assert.equal(challenge.network, contract.account.network);
    assert.equal(challenge.issuedAt, contract.generatedAt);
    assert.equal(challenge.expiresAt, '2026-09-17T10:05:00.000Z');
    assert.ok(challenge.message.includes(`account: ${contract.account.userId}\n`));
    assert.ok(challenge.message.includes(`wallet: ${contract.account.walletAddress}\n`));
    assert.ok(challenge.message.includes('It authorizes no transfer, swap or payment.'));
    assert.equal(contract.possession.possessionSignatureVerified, true);
    assert.equal(contract.possession.verifiedAt, '2026-09-17T10:00:02.000Z');
    assert.equal(contract.possession.binding.verifiedAt, contract.possession.verifiedAt);
    assert.equal(contract.repeat.possession.binding.id, contract.possession.binding.id);
    assert.equal(contract.repeat.possession.binding.verifiedAt, contract.possession.binding.verifiedAt);
    assert.ok(Date.parse(contract.repeat.possession.binding.verifiedAt) < Date.parse(contract.repeat.challenge.challenge.issuedAt));
    assert.equal(contract.repeat.possession.verifiedAt, '2026-09-17T10:00:14.000Z');
    assert.equal(/privateKey|PRIVATE KEY|"signature"|"seed"/.test(first), false);
  } finally { rmSync(directory, {recursive: true, force: true}); }
});

test('--check accepts the exact contract without changing it', () => {
  const directory = mkdtempSync(join(tmpdir(), 'trimmy-wallet-contract-check-'));
  try {
    const output = join(directory, 'contract.json');
    writeFileSync(output, readFileSync(fixture));
    const before = statSync(output);
    const checked = run('--check', '--output', output);
    assert.equal(checked.status, 0, checked.stderr);
    assert.equal(statSync(output).mtimeMs, before.mtimeMs);
  } finally { rmSync(directory, {recursive: true, force: true}); }
});

test('--check exits nonzero on message/receipt drift or a missing file without rewriting any fixture', () => {
  const directory = mkdtempSync(join(tmpdir(), 'trimmy-wallet-contract-drift-'));
  const original = readFileSync(fixture, 'utf8');
  try {
    const output = join(directory, 'contract.json');
    for (const mutate of [
      value => { value.challenge.challenge.message += '\nextra authorization'; },
      value => { value.possession.binding.verified_at = value.possession.binding.verifiedAt; delete value.possession.binding.verifiedAt; },
    ]) {
      const changed = JSON.parse(original);
      mutate(changed);
      const drift = `${JSON.stringify(changed, null, 2)}\n`;
      writeFileSync(output, drift);
      const checked = run('--check', '--output', output);
      assert.equal(checked.status, 1, checked.stderr);
      assert.match(checked.stderr, /stale or missing/);
      assert.equal(readFileSync(output, 'utf8'), drift);
    }
    rmSync(output);
    assert.equal(run('--check', '--output', output).status, 1);
    assert.equal(readFileSync(fixture, 'utf8'), original);
  } finally { rmSync(directory, {recursive: true, force: true}); }
});
