import assert from 'node:assert/strict';
import { createHash, createPrivateKey, createPublicKey, sign as signBytes } from 'node:crypto';
import { describe, it } from 'node:test';
import { getAddressDecoder, getBase58Decoder } from '@solana/kit';
import { composeWalletPossessionMessage, encodeWalletSignature, InMemoryWalletBindingStore,
  InMemoryWalletPossessionChallengeStore, verifyWalletMessageSignature, WalletPossessionError,
  WalletPossessionService } from '../src/wallet-possession.js';
import type { WalletPossessionChallenge, WalletPossessionChallengeStore } from '../src/wallet-possession.js';

/** Deterministic ed25519 test keypair. Seeds are local to this test file. */
function keypair(label: string): {address: string; sign: (message: string) => string} {
  const seed = createHash('sha256').update(`trimmy-wallet-${label}`).digest();
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
const otherWallet = keypair('stranger');
const userId = '11111111-2222-4333-8444-555555555555';
const otherUser = '99999999-8888-4777-8666-555555555555';
const errorIs = (code: string) => (error: unknown) => error instanceof WalletPossessionError && error.code === code;

function service(options: {now?: () => number; ttlMs?: number; perUserLimit?: number;
  challenges?: WalletPossessionChallengeStore} = {}) {
  const clock = options.now ?? (() => Date.parse('2026-09-15T08:00:00.000Z'));
  const challenges = options.challenges ?? new InMemoryWalletPossessionChallengeStore({now: clock});
  const bindings = new InMemoryWalletBindingStore();
  return {
    challenges, bindings,
    service: new WalletPossessionService({
      challenges, bindings, now: clock,
      ...(options.ttlMs !== undefined ? {ttlMs: options.ttlMs} : {}),
      ...(options.perUserLimit !== undefined ? {perUserLimit: options.perUserLimit} : {}),
    }),
  };
}
const expectedWallet = {address: wallet.address, network: 'mainnet-beta' as const, providerWalletId: 'w-1'};
const issueInput = {userId, walletAddress: wallet.address, network: 'mainnet-beta' as const, providerWalletId: 'w-1'};

describe('possession message', () => {
  it('is fixed, domain separated and says it authorizes nothing', () => {
    const fields = {challengeId: 'cccccccc-1111-4111-8111-111111111111', userId, walletAddress: wallet.address,
      network: 'mainnet-beta' as const, nonce: 'a'.repeat(64), issuedAt: '2026-09-15T08:00:00.000Z',
      expiresAt: '2026-09-15T08:05:00.000Z'};
    const message = composeWalletPossessionMessage(fields);
    assert.equal(message, [
      'Trimmy wallet possession',
      'This signature proves you control this wallet for your Trimmy account.',
      'It authorizes no transfer, swap or payment.',
      `challenge: ${fields.challengeId}`,
      `account: ${userId}`,
      `wallet: ${wallet.address}`,
      'network: mainnet-beta',
      `nonce: ${'a'.repeat(64)}`,
      'issued: 2026-09-15T08:00:00.000Z',
      'expires: 2026-09-15T08:05:00.000Z',
    ].join('\n'));
    assert.ok(!message.includes('—'));
    // Every field that scopes the proof is inside the signed bytes.
    for (const part of [fields.challengeId, userId, wallet.address, 'mainnet-beta', fields.nonce, fields.issuedAt, fields.expiresAt]) {
      assert.ok(message.includes(part));
    }
  });
});

describe('signature verification', () => {
  it('accepts a signature the wallet itself made over the exact message', () => {
    const message = 'Trimmy wallet possession\nexample';
    assert.equal(verifyWalletMessageSignature({walletAddress: wallet.address, message, signature: wallet.sign(message)}), true);
  });

  it('returns false for a different key, a tampered message and malformed input', () => {
    const message = 'Trimmy wallet possession\nexample';
    const signature = wallet.sign(message);
    assert.equal(verifyWalletMessageSignature({walletAddress: otherWallet.address, message, signature}), false);
    assert.equal(verifyWalletMessageSignature({walletAddress: wallet.address, message: `${message} `, signature}), false);
    assert.equal(verifyWalletMessageSignature({walletAddress: wallet.address, message, signature: wallet.sign('other')}), false);
    for (const bad of ['', 'zzzz', '1'.repeat(64), signature.slice(0, 40), `${signature}1111`, 'l0O I']) {
      assert.equal(verifyWalletMessageSignature({walletAddress: wallet.address, message, signature: bad}), false, bad);
    }
    assert.equal(verifyWalletMessageSignature({walletAddress: 'not-an-address', message, signature}), false);
    assert.equal(verifyWalletMessageSignature({walletAddress: wallet.address, message: '', signature}), false);
    assert.equal(verifyWalletMessageSignature(null as unknown as {walletAddress: string; message: string; signature: string}), false);
  });

  it('encodes a raw signature and refuses the wrong length', () => {
    const raw = Uint8Array.from(Buffer.alloc(64, 7));
    assert.equal(encodeWalletSignature(raw), getBase58Decoder().decode(raw));
    assert.throws(() => encodeWalletSignature(new Uint8Array(63)), errorIs('WALLET_POSSESSION_INPUT_INVALID'));
  });
});

describe('issuing a challenge', () => {
  it('stores a single-use challenge bound to the account and wallet', async () => {
    const context = service();
    const challenge = await context.service.issue(issueInput);
    assert.equal(challenge.kind, 'wallet_possession_challenge');
    assert.equal(challenge.userId, userId);
    assert.equal(challenge.walletAddress, wallet.address);
    assert.equal(challenge.network, 'mainnet-beta');
    assert.match(challenge.nonce, /^[0-9a-f]{64}$/);
    assert.equal(challenge.issuedAt, '2026-09-15T08:00:00.000Z');
    assert.equal(challenge.expiresAt, '2026-09-15T08:05:00.000Z');
    assert.equal(challenge.message, composeWalletPossessionMessage(challenge));
    assert.ok(Object.isFrozen(challenge));
    const stored = await context.challenges.take(userId, challenge.challengeId);
    assert.deepEqual(stored, challenge);
    assert.equal(await context.challenges.take(userId, challenge.challengeId), null);
  });

  it('never repeats a nonce or challenge id', async () => {
    const context = service({perUserLimit: 20});
    const nonces = new Set<string>();
    const ids = new Set<string>();
    for (let index = 0; index < 8; index += 1) {
      const challenge = await context.service.issue(issueInput);
      nonces.add(challenge.nonce);
      ids.add(challenge.challengeId);
    }
    assert.equal(nonces.size, 8);
    assert.equal(ids.size, 8);
  });

  it('rejects an invalid account, wallet, network or provider id', async () => {
    const context = service();
    for (const input of [
      {...issueInput, userId: 'not-a-uuid'},
      {...issueInput, walletAddress: 'nope'},
      {...issueInput, walletAddress: '11111111111111111111111111111111'},
      {...issueInput, network: 'testnet' as unknown as 'devnet'},
      {...issueInput, providerWalletId: 'x'.repeat(201)},
    ]) {
      await assert.rejects(context.service.issue(input), errorIs('WALLET_POSSESSION_INPUT_INVALID'), JSON.stringify(input.userId));
    }
  });

  it('limits how many checks one account can start', async () => {
    const context = service({perUserLimit: 2});
    await context.service.issue(issueInput);
    await context.service.issue(issueInput);
    await assert.rejects(context.service.issue(issueInput), errorIs('WALLET_POSSESSION_RATE_LIMITED'));
    // Another account is unaffected.
    await context.service.issue({...issueInput, userId: otherUser});
  });

  it('rejects configuration outside the allowed validity window', () => {
    assert.throws(() => service({ttlMs: 1_000}), errorIs('WALLET_POSSESSION_CONFIGURATION_INVALID'));
    assert.throws(() => service({ttlMs: 3_600_000}), errorIs('WALLET_POSSESSION_CONFIGURATION_INVALID'));
    assert.throws(() => new WalletPossessionService({} as never), errorIs('WALLET_POSSESSION_CONFIGURATION_INVALID'));
  });

  it('bounds tracked accounts while retaining active limits and reclaiming expired slots', async () => {
    let now = Date.parse('2026-09-15T08:00:00.000Z');
    const context = service({now: () => now, perUserLimit: 1,
      challenges: {put: async () => undefined, take: async () => null}});
    const trackedId = (index: number) => `00000000-0000-4000-a000-${index.toString(16).padStart(12, '0')}`;
    for (let index = 0; index < 10_000; index++) {
      await context.service.issue({...issueInput, userId: trackedId(index)});
    }
    await assert.rejects(context.service.issue({...issueInput, userId: trackedId(10_000)}),
      errorIs('WALLET_POSSESSION_RATE_LIMITED'));
    await assert.rejects(context.service.issue({...issueInput, userId: trackedId(0)}),
      errorIs('WALLET_POSSESSION_RATE_LIMITED'));
    now += 60_000;
    assert.equal((await context.service.issue({...issueInput, userId: trackedId(10_000)})).userId, trackedId(10_000));
  });
});

describe('verifying possession', () => {
  it('requires a valid server-derived expected wallet before consuming a challenge', async () => {
    const context = service();
    const challenge = await context.service.issue(issueInput);
    const proof = {userId, challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)};
    for (const invalid of [undefined, null, {}, {...expectedWallet, address: otherUser},
      {...expectedWallet, network: 'mainnet'}, {...expectedWallet, providerWalletId: ''}]) {
      await assert.rejects(context.service.verify({...proof, expectedWallet: invalid} as never),
        errorIs('WALLET_POSSESSION_INPUT_INVALID'));
    }
    assert.equal(context.bindings.list().length, 0);
    assert.equal((await context.service.verify({...proof, expectedWallet})).possessionSignatureVerified, true);
  });

  it('consumes a challenge on confirmed address, network or provider wallet identity drift', async () => {
    for (const changed of [{...expectedWallet, address: otherWallet.address},
      {...expectedWallet, network: 'devnet' as const}, {...expectedWallet, providerWalletId: 'replacement'},
      {...expectedWallet, providerWalletId: null}]) {
      const context = service();
      const challenge = await context.service.issue(issueInput);
      const proof = {userId, challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)};
      await assert.rejects(context.service.verify({...proof, expectedWallet: changed}),
        errorIs('WALLET_POSSESSION_WALLET_CHANGED'));
      await assert.rejects(context.service.verify({...proof, expectedWallet}),
        errorIs('WALLET_POSSESSION_CHALLENGE_NOT_FOUND'));
      assert.equal(context.bindings.list().length, 0);
    }
  });

  it('allows exactly one binding write when the same valid proof arrives concurrently', async () => {
    const context = service();
    const challenge = await context.service.issue(issueInput);
    const proof = {userId, expectedWallet, challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)};
    const results = await Promise.allSettled([context.service.verify(proof), context.service.verify(proof)]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    const rejected = results.find(result => result.status === 'rejected');
    assert.ok(rejected?.status === 'rejected');
    assert.ok(errorIs('WALLET_POSSESSION_CHALLENGE_NOT_FOUND')(rejected.reason));
    assert.equal(context.bindings.list().length, 1);
  });

  it('records an idempotent binding for a valid signature', async () => {
    const context = service();
    const challenge = await context.service.issue(issueInput);
    const verified = await context.service.verify({expectedWallet,
      userId, challengeId: challenge.challengeId, signature: wallet.sign(challenge.message),
    });
    assert.equal(verified.possessionSignatureVerified, true);
    assert.equal(verified.walletAddress, wallet.address);
    assert.equal(verified.verifiedAt, '2026-09-15T08:00:00.000Z');
    assert.equal(verified.binding.userId, userId);
    assert.equal(verified.binding.address, wallet.address);
    assert.equal(verified.binding.network, 'mainnet-beta');
    assert.equal(verified.binding.providerWalletId, 'w-1');
    assert.ok(Object.isFrozen(verified) && Object.isFrozen(verified.binding));
    assert.equal(context.bindings.list().length, 1);
    // A second proof for the same wallet returns the original binding row.
    const again = await context.service.issue(issueInput);
    const repeat = await context.service.verify({expectedWallet,
      userId, challengeId: again.challengeId, signature: wallet.sign(again.message),
    });
    assert.equal(repeat.binding.id, verified.binding.id);
    assert.equal(context.bindings.list().length, 1);
  });

  it('refuses a reused challenge, an unknown id and another account', async () => {
    const context = service();
    const challenge = await context.service.issue(issueInput);
    const signature = wallet.sign(challenge.message);
    await context.service.verify({expectedWallet, userId, challengeId: challenge.challengeId, signature});
    await assert.rejects(context.service.verify({expectedWallet, userId, challengeId: challenge.challengeId, signature}),
      errorIs('WALLET_POSSESSION_CHALLENGE_NOT_FOUND'));
    const fresh = await context.service.issue(issueInput);
    await assert.rejects(context.service.verify({expectedWallet, userId: otherUser, challengeId: fresh.challengeId,
      signature: wallet.sign(fresh.message)}), errorIs('WALLET_POSSESSION_CHALLENGE_NOT_FOUND'));
  });

  it('refuses an expired challenge and consumes it', async () => {
    let now = Date.parse('2026-09-15T08:00:00.000Z');
    const context = service({now: () => now, ttlMs: 30_000});
    const challenge = await context.service.issue(issueInput);
    now += 30_000;
    await assert.rejects(context.service.verify({expectedWallet, userId, challengeId: challenge.challengeId,
      signature: wallet.sign(challenge.message)}), errorIs('WALLET_POSSESSION_CHALLENGE_EXPIRED'));
    await assert.rejects(context.service.verify({expectedWallet, userId, challengeId: challenge.challengeId,
      signature: wallet.sign(challenge.message)}), errorIs('WALLET_POSSESSION_CHALLENGE_NOT_FOUND'));
    assert.equal(context.bindings.list().length, 0);
  });

  it('refuses a wrong key, a signature over other text and a malformed signature', async () => {
    const context = service({perUserLimit: 10});
    const first = await context.service.issue(issueInput);
    await assert.rejects(context.service.verify({expectedWallet, userId, challengeId: first.challengeId,
      signature: otherWallet.sign(first.message)}), errorIs('WALLET_POSSESSION_SIGNATURE_INVALID'));
    const second = await context.service.issue(issueInput);
    await assert.rejects(context.service.verify({expectedWallet, userId, challengeId: second.challengeId,
      signature: wallet.sign('Trimmy wallet possession\nsomething else')}), errorIs('WALLET_POSSESSION_SIGNATURE_INVALID'));
    const third = await context.service.issue(issueInput);
    for (const signature of ['', 'short', 'O0lI'.repeat(20)]) {
      await assert.rejects(context.service.verify({expectedWallet, userId, challengeId: third.challengeId, signature}),
        errorIs('WALLET_POSSESSION_INPUT_INVALID'));
    }
    assert.equal(context.bindings.list().length, 0);
  });

  it('rejects a store that returns a tampered challenge', async () => {
    const tampered: WalletPossessionChallengeStore = {
      put: async () => undefined,
      take: async (): Promise<WalletPossessionChallenge> => Object.freeze({
        schemaVersion: 1, kind: 'wallet_possession_challenge', challengeId: 'cccccccc-1111-4111-8111-111111111111',
        userId, walletAddress: otherWallet.address, network: 'mainnet-beta', providerWalletId: 'w-1', nonce: 'b'.repeat(64),
        issuedAt: '2026-09-15T08:00:00.000Z', expiresAt: '2026-09-15T08:05:00.000Z',
        message: 'Trimmy wallet possession\nrewritten by the store',
      }),
    };
    const context = service({challenges: tampered});
    await assert.rejects(context.service.verify({expectedWallet, userId, challengeId: 'cccccccc-1111-4111-8111-111111111111',
      signature: wallet.sign('Trimmy wallet possession\nrewritten by the store')}),
    errorIs('WALLET_POSSESSION_STORE_UNAVAILABLE'));
  });

  it('maps a failing store to an unavailable error without leaking its message', async () => {
    const broken: WalletPossessionChallengeStore = {
      put: async () => { throw new Error('private store detail'); },
      take: async () => { throw new Error('private store detail'); },
    };
    const context = service({challenges: broken});
    await assert.rejects(context.service.issue(issueInput), (error: unknown) =>
      error instanceof WalletPossessionError && error.code === 'WALLET_POSSESSION_STORE_UNAVAILABLE' &&
      !error.message.includes('private store detail'));
    await assert.rejects(context.service.verify({expectedWallet, userId, challengeId: 'cccccccc-1111-4111-8111-111111111111',
      signature: '2'.repeat(80)}), (error: unknown) =>
      error instanceof WalletPossessionError && error.code === 'WALLET_POSSESSION_STORE_UNAVAILABLE' &&
      !error.message.includes('private store detail'));
  });
});

describe('challenge store bounds', () => {
  it('evicts expired entries and refuses to grow past its limit', async () => {
    let now = Date.parse('2026-09-15T08:00:00.000Z');
    const store = new InMemoryWalletPossessionChallengeStore({maxEntries: 2, now: () => now});
    const base = {schemaVersion: 1, kind: 'wallet_possession_challenge', userId, walletAddress: wallet.address,
      network: 'mainnet-beta', providerWalletId: 'w-1', nonce: 'c'.repeat(64), issuedAt: '2026-09-15T08:00:00.000Z',
      expiresAt: '2026-09-15T08:05:00.000Z'} as const;
    const make = (id: string): WalletPossessionChallenge => Object.freeze({
      ...base, challengeId: id, message: composeWalletPossessionMessage({...base, challengeId: id}),
    });
    await store.put(make('aaaaaaaa-1111-4111-8111-111111111111'));
    await store.put(make('bbbbbbbb-1111-4111-8111-111111111111'));
    assert.equal(store.size, 2);
    await assert.rejects(store.put(make('cccccccc-1111-4111-8111-111111111111')),
      errorIs('WALLET_POSSESSION_STORE_UNAVAILABLE'));
    now += 300_000;
    await store.put(make('cccccccc-1111-4111-8111-111111111111'));
    assert.equal(store.size, 1);
    assert.throws(() => new InMemoryWalletPossessionChallengeStore({maxEntries: 0}),
      errorIs('WALLET_POSSESSION_CONFIGURATION_INVALID'));
  });
});
