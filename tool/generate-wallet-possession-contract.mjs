// Generate the exact serialized API challenge and proof receipt for the native
// parser. All identities, key material and storage are synthetic. This tool
// runs in its own process and never contacts Privy, a wallet or a database.
import assert from 'node:assert/strict';
import crypto, {createHash, createPrivateKey, createPublicKey, sign} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {getAddressDecoder, getBase58Decoder} from '@solana/kit';
import {buildApp} from '../apps/api/src/app.ts';
import {InMemoryWalletPossessionChallengeStore, WalletPossessionService} from '../apps/api/src/wallet-possession.ts';
import {WALLET_CHALLENGE_ROUTE, WALLET_POSSESSION_ROUTE} from '../apps/api/src/wallet-possession-route.ts';

const defaultOutput = fileURLToPath(new URL('../contracts/wallet-possession-v1.json', import.meta.url));
const args = process.argv.slice(2);
let output = defaultOutput;
let check = false;
let outputSpecified = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--check' && !check) check = true;
  else if (args[i] === '--output' && !outputSpecified && args[i + 1] && !args[i + 1].startsWith('--')) {
    output = resolve(args[++i]);
    outputSpecified = true;
  } else throw new Error('Use --check and/or --output FILE once each.');
}

const identity = Object.freeze({provider: 'privy', appId: 'trimmy_contract_app', subject: 'did:privy:contractWallet'});
const userId = '10000000-0000-4000-a000-000000000001';
const challengeId = '20000000-0000-4000-a000-000000000002';
const bindingId = '30000000-0000-4000-a000-000000000003';
const generatedAt = '2026-09-17T10:00:00.000Z';
let now = Date.parse(generatedAt);

// Reproducible test-only seed, never a development or funded wallet key. Only
// its public address reaches the generated artifact, and the signature stays
// within the in-process route request.
const seed = createHash('sha256').update('Trimmy wallet possession contract fixture, synthetic key only, version 1').digest();
const privateKey = createPrivateKey({key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]),
  format: 'der', type: 'pkcs8'});
const publicKey = createPublicKey(privateKey).export({format: 'der', type: 'spki'});
const walletAddress = getAddressDecoder().decode(publicKey.subarray(publicKey.length - 32));
let authenticatedRequests = 0;
let resolverReads = 0;
let bindingWrites = 0;
let storedBinding;
const originalRandomUUID = crypto.randomUUID;
const originalRandomBytes = crypto.randomBytes;
let app;
let serialized;
try {
  // Confined to this generator process. The real service still composes and
  // verifies its own message; supplying deterministic entropy avoids hand-made
  // challenge fixtures or changing production service options just for tests.
  crypto.randomUUID = () => challengeId;
  crypto.randomBytes = size => Buffer.alloc(size, 0x42);
  syncBuiltinESMExports();
  const service = new WalletPossessionService({
    now: () => now,
    challenges: new InMemoryWalletPossessionChallengeStore({now: () => now}),
    bindings: {record: async binding => {
      bindingWrites++;
      assert.equal(binding.userId, userId);
      assert.equal(binding.address, walletAddress);
      assert.equal(binding.network, 'mainnet-beta');
      storedBinding ??= Object.freeze({...binding, id: bindingId});
      return storedBinding;
    }},
  });
  const resolveLinked = async observed => {
      resolverReads++;
      assert.deepEqual(observed, identity);
      return Object.freeze({provider: 'privy', subject: identity.subject, twitter: Object.freeze({status: 'missing'}),
        embeddedSolanaWallet: Object.freeze({status: 'candidate', address: walletAddress,
          verifiedAtUnixSeconds: Math.floor(now / 1000)})});
  };
  app = buildApp({logger: false, walletPossession: {
    authenticate: async () => { authenticatedRequests++; return {userId, identity}; },
    linkedIdentities: {resolve: resolveLinked, resolveFresh: resolveLinked},
    service, network: 'mainnet-beta',
  }});
  const issued = await app.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
  assert.equal(issued.statusCode, 201);
  const challenge = issued.json();
  assert.equal(challenge.challenge.challengeId, challengeId);
  now += 2000;
  const signature = getBase58Decoder().decode(sign(null, Buffer.from(challenge.challenge.message, 'utf8'), privateKey));
  const verified = await app.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
    payload: {challengeId, signature}});
  assert.equal(verified.statusCode, 200);
  const possession = verified.json();
  assert.equal(possession.possessionSignatureVerified, true);
  assert.equal(possession.binding.id, bindingId);
  assert.equal(authenticatedRequests, 2);
  assert.equal(resolverReads, 2);
  assert.equal(bindingWrites, 1);

  // Proving the same wallet later returns the original binding timestamp. The
  // client's parser must distinguish that from this new proof's verifiedAt.
  const repeatChallengeId = '20000000-0000-4000-a000-000000000004';
  crypto.randomUUID = () => repeatChallengeId;
  crypto.randomBytes = size => Buffer.alloc(size, 0x43);
  syncBuiltinESMExports();
  now += 10_000;
  const repeatedIssue = await app.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
  assert.equal(repeatedIssue.statusCode, 201);
  const repeatChallenge = repeatedIssue.json();
  now += 2000;
  const repeatSignature = getBase58Decoder().decode(sign(null,
    Buffer.from(repeatChallenge.challenge.message, 'utf8'), privateKey));
  const repeatedVerification = await app.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
    payload: {challengeId: repeatChallengeId, signature: repeatSignature}});
  assert.equal(repeatedVerification.statusCode, 200);
  const repeatPossession = repeatedVerification.json();
  assert.equal(repeatPossession.binding.id, possession.binding.id);
  assert.equal(repeatPossession.binding.verifiedAt, possession.binding.verifiedAt);
  assert.equal(authenticatedRequests, 4);
  assert.equal(resolverReads, 4);
  assert.equal(bindingWrites, 2);
  serialized = `${JSON.stringify({
    schemaVersion: 1,
    note: 'Generated by tool/generate-wallet-possession-contract.mjs through the real API routes and service. Synthetic account, wallet, entropy and storage only. Do not edit by hand.',
    generatedAt,
    account: {appId: identity.appId, subject: identity.subject, userId, walletAddress, network: 'mainnet-beta'},
    challenge,
    possession,
    repeat: {challenge: repeatChallenge, possession: repeatPossession},
  }, null, 2)}\n`;
} finally {
  if (app) await app.close();
  crypto.randomUUID = originalRandomUUID;
  crypto.randomBytes = originalRandomBytes;
  syncBuiltinESMExports();
}

const digest = createHash('sha256').update(serialized).digest('hex');
if (check) {
  let existing;
  try { existing = readFileSync(output, 'utf8'); } catch { existing = null; }
  if (existing !== serialized) {
    process.stderr.write('Wallet possession contract is stale or missing. Run npm run generate:wallet-possession-contract.\n');
    process.exitCode = 1;
  } else process.stdout.write(`wallet possession contract current (sha256 ${digest})\n`);
} else {
  writeFileSync(output, serialized);
  process.stdout.write(`wrote wallet possession contract (sha256 ${digest})\n`);
}
