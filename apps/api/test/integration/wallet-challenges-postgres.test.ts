import assert from 'node:assert/strict';
import { createHash, createPrivateKey, createPublicKey, sign as signBytes } from 'node:crypto';
import { after, describe, test } from 'node:test';
import { Pool } from 'pg';
import { getAddressDecoder, getBase58Decoder } from '@solana/kit';
import { PostgresWalletPossessionChallengeStore } from '../../src/postgres-wallet-challenges.js';
import { InMemoryWalletBindingStore, WalletPossessionError, WalletPossessionService } from '../../src/wallet-possession.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'), 'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');

/** Deterministic ed25519 test keypair. Seeds are local to this test file. */
function keypair(label: string): {address: string; sign: (message: string) => string} {
  const seed = createHash('sha256').update(`trimmy-challenge-${label}`).digest();
  const pkcs8 = Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]);
  const privateKey = createPrivateKey({key: pkcs8, format: 'der', type: 'pkcs8'});
  const spki = createPublicKey(privateKey).export({format: 'der', type: 'spki'});
  const raw = Uint8Array.from(spki.subarray(spki.length - 32));
  return {
    address: getAddressDecoder().decode(raw),
    sign: (message: string) => getBase58Decoder().decode(signBytes(null, Buffer.from(message, 'utf8'), privateKey)),
  };
}

const wallet = keypair('owner');
const HOLDER_ONE = '00000000-0000-4000-8000-000000000031';
const HOLDER_TWO = '00000000-0000-4000-8000-000000000032';
const CLOSED = '00000000-0000-4000-8000-000000000033';

/** Each pool stands for one API instance sharing one database. */
function instance(): Pool {
  const pool = new Pool({
    host: socket, port: 65438, database: 'postgres', user: 'trimmy_wallet_challenge_test_app',
    connectionTimeoutMillis: 3000, max: 4,
  });
  pool.on('error', () => {});
  pools.push(pool);
  return pool;
}
const pools: Pool[] = [];
const owner = new Pool({
  host: socket, port: 65438, database: 'postgres', user: 'trimmy_test_owner',
  connectionTimeoutMillis: 3000, max: 2,
});
pools.push(owner);

after(async () => { for (const pool of pools) await pool.end().catch(() => {}); });

async function clear(userId: string): Promise<void> {
  await owner.query('DELETE FROM trimmy.wallet_possession_challenges WHERE user_id = $1::uuid', [userId]);
}

const first = instance();
const second = instance();
const storeA = new PostgresWalletPossessionChallengeStore(first);
const storeB = new PostgresWalletPossessionChallengeStore(second);

function service(pool: Pool): WalletPossessionService {
  return new WalletPossessionService({
    challenges: new PostgresWalletPossessionChallengeStore(pool),
    bindings: new InMemoryWalletBindingStore(),
  });
}

describe('durable wallet challenges across instances', () => {
  test('a proof issued by one instance is verified by another', async () => {
    await clear(HOLDER_ONE);
    const issuing = service(first);
    const verifying = service(second);
    const challenge = await issuing.issue({
      userId: HOLDER_ONE, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: 'w-31',
    });
    // This is the failure the in-memory store produced: the second instance
    // never saw the challenge, so a correct signature could not be verified.
    const verified = await verifying.verify({
      userId: HOLDER_ONE, challengeId: challenge.challengeId, signature: wallet.sign(challenge.message),
      expectedWallet: {address: wallet.address, network: 'mainnet-beta', providerWalletId: 'w-31'},
    });
    assert.equal(verified.binding.address, wallet.address);
    assert.equal(verified.binding.userId, HOLDER_ONE);
  });

  test('a challenge is consumed once, whichever instance takes it', async () => {
    await clear(HOLDER_ONE);
    const challenge = await service(first).issue({
      userId: HOLDER_ONE, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null,
    });
    const taken = await storeB.take(HOLDER_ONE, challenge.challengeId);
    assert.equal(taken?.message, challenge.message);
    assert.equal(await storeA.take(HOLDER_ONE, challenge.challengeId), null, 'a replay must find nothing');
  });

  test('two instances racing for one challenge produce exactly one winner', async () => {
    await clear(HOLDER_ONE);
    const challenge = await service(first).issue({
      userId: HOLDER_ONE, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null,
    });
    const results = await Promise.all([
      storeA.take(HOLDER_ONE, challenge.challengeId),
      storeB.take(HOLDER_ONE, challenge.challengeId),
      storeA.take(HOLDER_ONE, challenge.challengeId),
    ]);
    assert.equal(results.filter(result => result !== null).length, 1, 'the delete must be the single-use gate');
  });

  test('another account cannot take a challenge it was not issued', async () => {
    await clear(HOLDER_ONE);
    await clear(HOLDER_TWO);
    const challenge = await service(first).issue({
      userId: HOLDER_ONE, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null,
    });
    assert.equal(await storeB.take(HOLDER_TWO, challenge.challengeId), null, 'row security must hide it');
    // It is still there for its owner, so the failed attempt consumed nothing.
    assert.ok(await storeA.take(HOLDER_ONE, challenge.challengeId));
  });

  test('a closed account is issued nothing at all', async () => {
    await assert.rejects(storeA.put(Object.freeze({
      schemaVersion: 1, kind: 'wallet_possession_challenge',
      challengeId: '44444444-4444-4444-8444-444444444444', userId: CLOSED,
      walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null,
      nonce: 'a'.repeat(64), issuedAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 300_000).toISOString(), message: 'unused',
    })), WalletPossessionError);
  });

  test('outstanding challenges are capped, and the cap is shared', async () => {
    await clear(HOLDER_TWO);
    const alternating = [service(first), service(second)];
    for (let issued = 0; issued < 5; issued += 1) {
      await alternating[issued % 2]!.issue({
        userId: HOLDER_TWO, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null,
      });
    }
    // The sixth is refused by either instance, because the count is in the
    // database rather than in one process.
    await assert.rejects(
      alternating[1]!.issue({userId: HOLDER_TWO, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null}),
      (error: unknown) => error instanceof WalletPossessionError && error.code === 'WALLET_POSSESSION_RATE_LIMITED');
    const {rows} = await owner.query<{total: string}>(
      'SELECT count(*)::text AS total FROM trimmy.wallet_possession_challenges WHERE user_id = $1::uuid', [HOLDER_TWO]);
    assert.equal(rows[0]?.total, '5');
  });

  test('an outstanding challenge cannot be rewritten by the serving role', async () => {
    await clear(HOLDER_ONE);
    const challenge = await service(first).issue({
      userId: HOLDER_ONE, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null,
    });
    // Changing the wallet or window would change what the person agreed to sign.
    await assert.rejects(first.query(
      'UPDATE trimmy.wallet_possession_challenges SET wallet_address = $1 WHERE id = $2::uuid',
      [keypair('stranger').address, challenge.challengeId]), /permission denied|reject|not allowed/i);
  });

  test('the serving role cannot delete a challenge it used', async () => {
    await clear(HOLDER_ONE);
    const challenge = await service(first).issue({
      userId: HOLDER_ONE, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null,
    });
    await storeA.take(HOLDER_ONE, challenge.challengeId);
    // Consumption marks the row. A serving process that could then remove it
    // could erase the record of the challenge it just used.
    await assert.rejects(first.query(
      'DELETE FROM trimmy.wallet_possession_challenges WHERE id = $1::uuid', [challenge.challengeId]),
    /permission denied/i);
    const {rows} = await owner.query<{consumed_at: Date | null}>(
      'SELECT consumed_at FROM trimmy.wallet_possession_challenges WHERE id = $1::uuid', [challenge.challengeId]);
    assert.ok(rows[0]?.consumed_at instanceof Date, 'the used challenge is still on record');
  });

  test('a used challenge cannot be returned to unused, even by the owner', async () => {
    await clear(HOLDER_ONE);
    const challenge = await service(first).issue({
      userId: HOLDER_ONE, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null,
    });
    await storeA.take(HOLDER_ONE, challenge.challengeId);
    // The trigger is the backstop that holds for any writer, not only the
    // column-restricted serving role.
    await assert.rejects(owner.query(
      'UPDATE trimmy.wallet_possession_challenges SET consumed_at = NULL WHERE id = $1::uuid',
      [challenge.challengeId]), /single use/i);
  });

  test('the serving role cannot read another account rows in bulk', async () => {
    await clear(HOLDER_ONE);
    await service(first).issue({
      userId: HOLDER_ONE, walletAddress: wallet.address, network: 'mainnet-beta', providerWalletId: null,
    });
    // Outside a scoped transaction the policy admits nothing.
    const {rows} = await first.query('SELECT id FROM trimmy.wallet_possession_challenges');
    assert.equal(rows.length, 0, 'an unscoped read must see no challenge at all');
  });
});
