import assert from 'node:assert/strict';
import { createHash, createPrivateKey, createPublicKey, sign as signBytes } from 'node:crypto';
import { after, describe, test } from 'node:test';
import { Pool } from 'pg';
import { getAddressDecoder, getBase58Decoder } from '@solana/kit';
import { buildApp } from '../../src/app.js';
import { PostgresStockOrderReviews, StockOrderReviewStoreError } from '../../src/postgres-stock-order-reviews.js';
import { PostgresWalletBindingStore } from '../../src/postgres-wallet-bindings.js';
import { InMemoryWalletPossessionChallengeStore, WalletPossessionService } from '../../src/wallet-possession.js';
import { WALLET_CHALLENGE_ROUTE, WALLET_POSSESSION_ROUTE } from '../../src/wallet-possession-route.js';
import type { ReviewedStockOrderIntent } from '../../src/stock-order-review.js';
import type { PracticeIdentity } from '../../src/practice-identity.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'),
  'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const connection = {host: socket, port: 65438, database: 'postgres', connectionTimeoutMillis: 3_000};
const pool = new Pool({...connection, user: 'trimmy_practice_test_app', max: 4});
const reviews = new PostgresStockOrderReviews(pool);
const accountA = '00000000-0000-4000-8000-000000000001';
const accountB = '00000000-0000-4000-8000-000000000002';
const restricted = '00000000-0000-4000-8000-000000000004';
const missingAccount = '00000000-0000-4000-8000-0000000000ff';

function keypair(label: string) {
  const seed = createHash('sha256').update(`trimmy-db-wallet-${label}`).digest();
  const pkcs8 = Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]);
  const privateKey = createPrivateKey({key: pkcs8, format: 'der', type: 'pkcs8'});
  const spki = createPublicKey(privateKey).export({format: 'der', type: 'spki'});
  return {
    address: getAddressDecoder().decode(Uint8Array.from(spki.subarray(spki.length - 32))),
    sign: (message: string) => getBase58Decoder().decode(signBytes(null, Buffer.from(message, 'utf8'), privateKey)),
  };
}
const walletA = keypair('a');
const walletB = keypair('b');

const bindingStore = new PostgresWalletBindingStore(pool);

const now = () => Date.parse('2026-09-15T10:00:00.000Z');
function newPossessionService() {
  return new WalletPossessionService({
    challenges: new InMemoryWalletPossessionChallengeStore({now}), bindings: bindingStore, now,
  });
}
const identity = (subject: string): PracticeIdentity => ({provider: 'privy', appId: 'trimmy_db_app', subject});

/** Privy subjects are alphanumeric after the prefix, so accounts map to labels. */
const subjects: Readonly<Record<string, string>> = Object.freeze({
  [accountA]: 'did:privy:dbwalletA', [accountB]: 'did:privy:dbwalletB',
  [restricted]: 'did:privy:dbwalletRestricted', [missingAccount]: 'did:privy:dbwalletMissing',
});

function appFor(userId: string, walletAddress: string) {
  const subject = subjects[userId]!;
  const resolve = async () => Object.freeze({
    provider: 'privy', subject, twitter: Object.freeze({status: 'missing'}),
    embeddedSolanaWallet: Object.freeze({status: 'candidate', address: walletAddress,
      verifiedAtUnixSeconds: 1_757_845_201}),
  }) as never;
  return buildApp({logger: false, walletPossession: {
    authenticate: async () => ({userId, identity: identity(subject)}),
    linkedIdentities: {resolve, resolveFresh: resolve},
    service: newPossessionService(), network: 'mainnet-beta',
  }});
}

const unsigned = Uint8Array.from(Buffer.alloc(180, 3));
function intent(userId: string, taker: string, overrides: Partial<ReviewedStockOrderIntent> = {}): ReviewedStockOrderIntent {
  const messageHash = createHash('sha256').update(`${userId}:${taker}:${overrides.requestId ?? 'order-1'}`).digest('hex');
  return Object.freeze({
    schemaVersion: 1, kind: 'reviewed_stock_order_intent', network: 'solana:mainnet-beta', userId, taker,
    requestId: overrides.requestId ?? 'order-1',
    transactionHash: createHash('sha256').update(`tx:${messageHash}`).digest('hex'),
    transactionMessageHash: messageHash,
    draftBindingHash: createHash('sha256').update(`binding:${messageHash}`).digest('hex'),
    candidateTermsHash: createHash('sha256').update(`terms:${messageHash}`).digest('hex'),
    reviewedAt: '2026-09-15T10:00:00.000Z', expiresAt: '2026-09-15T10:00:10.000Z',
    terms: Object.freeze({side: 'buy', inputMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
      outputMint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', inputAmountRaw: '10000000',
      quotedOutputAmountRaw: '2972350', minimumOutputAmountRaw: '2957488', slippageBps: 50, platformFeeBps: 0,
      totalLamportsUpperBound: '5420', simulatedOutputReceivedRaw: '2972350', simulatedTakerLamportsSpent: '5000'}),
    evidence: Object.freeze({structureSha256: 'a'.repeat(64), lookupResolutionSha256: 'b'.repeat(64),
      lifetimeSha256: 'c'.repeat(64), semanticsSha256: 'd'.repeat(64), reconciliationSha256: 'e'.repeat(64),
      simulationSha256: 'f'.repeat(64), observationSlot: '447100000', simulationSlot: '447100005',
      lastValidBlockHeight: '1150'}),
    reviewFlags: Object.freeze(['output_mint_pausable']),
    reviewDigestSha256: createHash('sha256').update(`digest:${messageHash}`).digest('hex'),
    approval: Object.freeze({status: 'required', method: 'explicit_user_confirmation_bound_to_review_digest',
      walletPossession: 'required_before_signing'}),
    assessment: Object.freeze({status: 'reviewed_pending_approval',
      stagesCompleted: Object.freeze(['structure', 'lookup_tables', 'lifetime', 'semantics', 'reconciliation', 'simulation'] as const),
      revalidationRequired: true, signingEnabled: false, broadcastEnabled: false, financialOperationsEnabled: false}),
    ...overrides,
  }) as ReviewedStockOrderIntent;
}

const errorIs = (code: string) => (error: unknown) =>
  error instanceof StockOrderReviewStoreError && error.code === code;

after(async () => { await pool.end(); });

if (process.env['TRIMMY_PRACTICE_TEST_RECOVERY'] === '1') {
  test('a new process reads the durable binding and its approved review after a restart', async () => {
    let reviewId = '';
    const client = await pool.connect();
    try {
      await client.query('BEGIN READ ONLY');
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [accountA]);
      const bindings = await client.query<{address: string}>(
        'SELECT address FROM trimmy.wallet_bindings WHERE user_id = $1::uuid', [accountA]);
      assert.equal(bindings.rows.length, 1);
      assert.equal(bindings.rows[0]?.address, walletA.address);
      // The id travels through the private database, not through module state.
      const found = await client.query<{id: string}>(
        "SELECT id FROM trimmy.stock_order_reviews WHERE request_id = 'order-restart'");
      assert.equal(found.rows.length, 1);
      reviewId = found.rows[0]!.id;
      await client.query('COMMIT');
    } finally {
      try { await client.query('ROLLBACK'); } finally { client.release(); }
    }
    const binding = await bindingStore.record({userId: accountA, network: 'mainnet-beta', address: walletA.address,
      providerWalletId: null, verifiedAt: new Date(now()).toISOString()});
    assert.equal(binding.address, walletA.address);
    const stored = await reviews.find(accountA, reviewId);
    assert.ok(stored);
    assert.equal(stored.state, 'approved');
    assert.equal(stored.walletBindingId, binding.id);
    assert.equal(stored.intent.assessment.signingEnabled, false);
    const bytes = await reviews.readApprovedBytes(accountA, stored.id, '2026-09-15T10:00:05.000Z');
    assert.ok(bytes);
    assert.deepEqual([...bytes.bytes], [...unsigned]);
  });
} else {
  describe('wallet possession and reviewed intents in PostgreSQL', () => {
    let reviewId = '';
    let bindingId = '';

    test('a real wallet signature records a durable, account-scoped binding', async () => {
      const app = appFor(accountA, walletA.address);
      try {
        const issued = await app.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
        assert.equal(issued.statusCode, 201, issued.body);
        const challenge = issued.json().challenge as {challengeId: string; message: string};
        const verified = await app.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
          payload: {challengeId: challenge.challengeId, signature: walletA.sign(challenge.message)}});
        assert.equal(verified.statusCode, 200, verified.body);
        bindingId = verified.json().binding.id as string;
        assert.equal(verified.json().walletAddress, walletA.address);
      } finally { await app.close(); }

      // The same wallet proven again returns the original row, not a second one.
      const again = appFor(accountA, walletA.address);
      try {
        const challenge = (await again.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).json().challenge;
        const verified = await again.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
          payload: {challengeId: challenge.challengeId, signature: walletA.sign(challenge.message)}});
        assert.equal(verified.statusCode, 200);
        assert.equal(verified.json().binding.id, bindingId);
      } finally { await again.close(); }
    });

    test('another account cannot see or reuse that wallet', async () => {
      const client = await pool.connect();
      try {
        await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [accountB]);
        const visible = await client.query('SELECT id FROM trimmy.wallet_bindings');
        assert.equal(visible.rows.length, 0);
      } finally { client.release(); }
      const app = appFor(accountB, walletA.address);
      try {
        const challenge = (await app.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).json().challenge;
        const verified = await app.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
          payload: {challengeId: challenge.challengeId, signature: walletA.sign(challenge.message)}});
        // The address is already bound to another account, so the write fails closed.
        assert.equal(verified.statusCode, 503);
      } finally { await app.close(); }
    });

    test('a restricted account cannot record a binding', async () => {
      const app = appFor(restricted, walletB.address);
      try {
        const challenge = (await app.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).json().challenge;
        const verified = await app.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
          payload: {challengeId: challenge.challengeId, signature: walletB.sign(challenge.message)}});
        assert.equal(verified.statusCode, 503);
      } finally { await app.close(); }
    });

    test('concurrent production-store proofs reuse one binding and cannot revive it after revocation', async () => {
      const raceWallet = keypair('concurrent');
      const input = {userId: accountB, network: 'mainnet-beta' as const, address: raceWallet.address,
        providerWalletId: null, verifiedAt: new Date(now()).toISOString()};
      const records = await Promise.all(Array.from({length: 4}, () => bindingStore.record(input)));
      assert.equal(new Set(records.map(record => record.id)).size, 1);
      const owner = new Pool({...connection, user: 'trimmy_test_owner', max: 1});
      try {
        await owner.query('UPDATE trimmy.wallet_bindings SET revoked_at = now() WHERE id = $1::uuid', [records[0]!.id]);
        await assert.rejects(bindingStore.record(input), error => {
          assert.equal((error as {code?: string}).code, 'WALLET_POSSESSION_STORE_UNAVAILABLE');
          return true;
        });
        assert.equal((await owner.query('SELECT count(*)::text AS count FROM trimmy.wallet_bindings WHERE address = $1',
          [raceWallet.address])).rows[0].count, '1');
      } finally { await owner.end(); }
    });

    test('production binding storage rejects owner connections and missing accounts without exposing database errors', async () => {
      const input = {userId: accountA, network: 'mainnet-beta' as const, address: walletA.address,
        providerWalletId: null, verifiedAt: new Date(now()).toISOString()};
      const owner = new Pool({...connection, user: 'trimmy_test_owner', max: 1});
      const unavailable = (error: unknown) => {
        assert.equal((error as {code?: string}).code, 'WALLET_POSSESSION_STORE_UNAVAILABLE');
        assert.equal((error as Error).message, 'Wallet checks are unavailable right now.');
        return true;
      };
      try {
        await assert.rejects(new PostgresWalletBindingStore(owner).record(input), unavailable);
        await assert.rejects(bindingStore.record({...input, userId: missingAccount}), unavailable);
      } finally { await owner.end(); }
    });

    test('a reviewed intent is stored once, read back and approved only with a binding', async () => {
      const saved = await reviews.save({intent: intent(accountA, walletA.address), unsignedTransaction: unsigned,
        walletBindingId: null});
      reviewId = saved.id;
      assert.equal(saved.state, 'reviewed');
      assert.equal(saved.version, 0);
      assert.equal(saved.walletBindingId, null);
      assert.equal(saved.intent.kind, 'reviewed_stock_order_intent');
      const found = await reviews.find(accountA, reviewId);
      assert.deepEqual(found?.intent, saved.intent);
      // The same reviewed message cannot be stored twice for one account.
      await assert.rejects(reviews.save({intent: intent(accountA, walletA.address), unsignedTransaction: unsigned,
        walletBindingId: null}), errorIs('REVIEW_STORE_DUPLICATE'));
      // Approval must cite the verified binding of this taker.
      const approved = await reviews.approve({userId: accountA, reviewId, expectedVersion: 0,
        walletBindingId: bindingId, approvedAt: '2026-09-15T10:00:05.000Z'});
      assert.equal(approved.state, 'approved');
      assert.equal(approved.version, 1);
      assert.equal(approved.walletBindingId, bindingId);
    });

    test('the approved bytes are readable only inside the validity window', async () => {
      const inside = await reviews.readApprovedBytes(accountA, reviewId, '2026-09-15T10:00:06.000Z');
      assert.ok(inside);
      assert.deepEqual([...inside.bytes], [...unsigned]);
      assert.equal(await reviews.readApprovedBytes(accountA, reviewId, '2026-09-15T10:00:11.000Z'), null);
      assert.equal(await reviews.find(accountB, reviewId), null);
      assert.equal(await reviews.readApprovedBytes(accountB, reviewId, '2026-09-15T10:00:06.000Z'), null);
    });

    test('a stale version, a double approval and a terminal state are refused', async () => {
      // The version pins the write, so a repeated approval cannot double-apply.
      await assert.rejects(reviews.approve({userId: accountA, reviewId, expectedVersion: 0,
        walletBindingId: bindingId, approvedAt: '2026-09-15T10:00:06.000Z'}), errorIs('REVIEW_STORE_VERSION_CONFLICT'));
      await assert.rejects(reviews.transition({userId: accountA, reviewId, expectedVersion: 5, state: 'canceled'}),
        errorIs('REVIEW_STORE_VERSION_CONFLICT'));
      await assert.rejects(reviews.transition({userId: accountA, reviewId: '99999999-9999-4999-8999-999999999999',
        expectedVersion: 0, state: 'canceled'}), errorIs('REVIEW_STORE_NOT_FOUND'));
      const consumed = await reviews.transition({userId: accountA, reviewId, expectedVersion: 1, state: 'consumed'});
      assert.equal(consumed.state, 'consumed');
      assert.equal(consumed.version, 2);
      assert.equal(await reviews.readApprovedBytes(accountA, reviewId, '2026-09-15T10:00:06.000Z'), null);
      await assert.rejects(reviews.transition({userId: accountA, reviewId, expectedVersion: 2, state: 'canceled'}),
        errorIs('REVIEW_STORE_TRANSITION_INVALID'));
    });

    test('an unknown account and a malformed intent never write', async () => {
      await assert.rejects(reviews.save({intent: intent(missingAccount, walletA.address),
        unsignedTransaction: unsigned, walletBindingId: null}), errorIs('REVIEW_STORE_ACCOUNT_NOT_FOUND'));
      await assert.rejects(reviews.save({intent: intent(accountB, walletB.address, {requestId: 'order-2'}),
        unsignedTransaction: Uint8Array.from([1, 2, 3])}as never), errorIs('REVIEW_STORE_INPUT_INVALID'));
      const claimsSigning = intent(accountB, walletB.address, {requestId: 'order-3',
        assessment: Object.freeze({status: 'reviewed_pending_approval',
          stagesCompleted: Object.freeze(['structure', 'lookup_tables', 'lifetime', 'semantics', 'reconciliation', 'simulation'] as const),
          revalidationRequired: true, signingEnabled: true as unknown as false, broadcastEnabled: false,
          financialOperationsEnabled: false})});
      await assert.rejects(reviews.save({intent: claimsSigning, unsignedTransaction: unsigned, walletBindingId: null}),
        errorIs('REVIEW_STORE_INPUT_INVALID'));
      assert.equal(await reviews.find(accountB, reviewId), null);
    });

    test('a review left for the restart check is approved and readable', async () => {
      const saved = await reviews.save({intent: intent(accountA, walletA.address, {requestId: 'order-restart'}),
        unsignedTransaction: unsigned, walletBindingId: null});
      const approved = await reviews.approve({userId: accountA, reviewId: saved.id, expectedVersion: 0,
        walletBindingId: bindingId, approvedAt: '2026-09-15T10:00:01.000Z'});
      assert.equal(approved.state, 'approved');
    });
  });
}
