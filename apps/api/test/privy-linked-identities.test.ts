import assert from 'node:assert/strict';
import {inspect} from 'node:util';
import {test} from 'node:test';
import {
  parsePrivyLinkedIdentities,
  PrivyLinkedIdentityError,
  PrivyLinkedIdentityResolver,
  readPrivyLinkedIdentityResolver,
} from '../src/privy-linked-identities.js';
import type {
  PrivyLinkedIdentityErrorCode,
  PrivyUserReaderFactory,
} from '../src/privy-linked-identities.js';
import type {PracticeIdentity} from '../src/practice-identity.js';

const appId = 'test_privy_app';
const appSecret = 'test_only_privy_secret_0123456789';
const subject = 'did:privy:cmu1testsubject';
const identity: PracticeIdentity = {provider: 'privy', appId, subject};
const walletAddress = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
const twitter = {
  type: 'twitter_oauth',
  subject: '18446744073709551615',
  username: 'TrimmyHQ',
  name: 'private display value',
  verified_at: 1_757_845_200,
  access_token: 'private-oauth-token',
};
const wallet = {
  type: 'wallet',
  chain_type: 'solana',
  connector_type: 'embedded',
  wallet_client: 'privy',
  wallet_client_type: 'privy',
  address: walletAddress,
  delegated: false,
  imported: false,
  wallet_index: 0,
  verified_at: 1_757_845_201,
  public_key: 'private-unused-provider-field',
};

function errorCode(expected: PrivyLinkedIdentityErrorCode): (error: unknown) => boolean {
  return error => {
    assert.ok(error instanceof PrivyLinkedIdentityError);
    assert.equal(error.code, expected);
    assert.equal('cause' in error, false);
    assert.ok(!inspect(error).includes(appSecret));
    return true;
  };
}

function user(linkedAccounts: unknown[], id = subject): Record<string, unknown> {
  return {
    id,
    created_at: 1,
    has_accepted_terms: true,
    is_guest: false,
    linked_accounts: linkedAccounts,
    mfa_methods: [],
    email: 'never-return@example.invalid',
  };
}

function fakeFactory(result: unknown, inspectCall?: (value: unknown) => void): PrivyUserReaderFactory {
  return configuration => {
    inspectCall?.(configuration);
    return {
      async getById(requestedSubject, request) {
        inspectCall?.({requestedSubject, request});
        return result;
      },
    };
  };
}

test('fetches only the verified subject and projects one X identity and embedded Solana candidate', async () => {
  const calls: unknown[] = [];
  const resolver = new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    timeoutMs: 500,
    clientFactory: fakeFactory(user([
      {type: 'email', address: 'private@example.invalid'},
      twitter,
      wallet,
      {type: 'google_oauth', subject: 'unrelated', access_token: 'also-private'},
    ]), value => calls.push(value)),
  });
  const result = await resolver.resolve(identity);
  assert.deepEqual(result, {
    provider: 'privy',
    subject,
    twitter: {
      status: 'verified',
      subject: twitter.subject,
      usernameSnapshot: 'trimmyhq',
      verifiedAtUnixSeconds: twitter.verified_at,
    },
    embeddedSolanaWallet: {
      status: 'candidate',
      address: walletAddress,
      verifiedAtUnixSeconds: wallet.verified_at,
    },
  });
  assert.equal(Object.isFrozen(result), true);
  assert.equal(Object.isFrozen(result.twitter), true);
  assert.equal(Object.isFrozen(result.embeddedSolanaWallet), true);
  const serialized = `${JSON.stringify(result)} ${inspect(result)}`;
  for (const forbidden of [appSecret, 'private-oauth-token', 'also-private',
    'private@example.invalid', 'never-return@example.invalid', 'private display value']) {
    assert.ok(!serialized.includes(forbidden));
  }
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0], {
    appId,
    appSecret,
    apiUrl: 'https://api.privy.io',
    timeoutMs: 500,
    maxRetries: 0,
  });
  const request = calls[1] as {requestedSubject: string; request: {timeoutMs: number; maxRetries: number; signal: AbortSignal}};
  assert.equal(request.requestedSubject, subject);
  assert.equal(request.request.timeoutMs, 500);
  assert.equal(request.request.maxRetries, 0);
  assert.equal(request.request.signal.aborted, true);
});

test('represents genuinely missing relevant links explicitly', async () => {
  const result = await new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    clientFactory: fakeFactory(user([
      {type: 'email', address: 'private@example.invalid'},
      {type: 'wallet', chain_type: 'solana', wallet_client: 'unknown', address: walletAddress},
    ])),
  }).resolve(identity);
  assert.deepEqual(result.twitter, {status: 'missing'});
  assert.deepEqual(result.embeddedSolanaWallet, {status: 'missing'});
});

test('never guesses when relevant links are duplicated or malformed', () => {
  const invalidTwitter = {...twitter, subject: 'not-numeric'};
  const invalidWallet = {...wallet, address: 'not-a-solana-address'};
  for (const [accounts, twitterStatus, walletStatus] of [
    [[twitter, {...twitter}], 'ambiguous', 'missing'],
    [[invalidTwitter], 'ambiguous', 'missing'],
    [[wallet, {...wallet, wallet_index: 1}], 'missing', 'ambiguous'],
    [[invalidWallet], 'missing', 'ambiguous'],
    [[{...wallet, address: '11111111111111111111111111111111'}], 'missing', 'ambiguous'],
    [[twitter, invalidTwitter, wallet, invalidWallet], 'ambiguous', 'ambiguous'],
  ] as const) {
    const result = parsePrivyLinkedIdentities(user([...accounts]), subject);
    assert.equal(result.twitter.status, twitterStatus);
    assert.equal(result.embeddedSolanaWallet.status, walletStatus);
  }
});

test('rejects a mismatched, malformed or accessor-backed provider user without exposing it', async () => {
  for (const response of [
    user([], 'did:privy:someoneElse'),
    user([], 'did:privy:cmu1testsubject\n'),
    {...user([]), linked_accounts: 'not-an-array'},
    {...user([]), linked_accounts: Array.from({length: 129}, () => ({type: 'email'}))},
    {...user([]), linked_accounts: [null]},
    {...user([]), linked_accounts: [{}]},
    Object.create({id: subject, linked_accounts: []}),
  ]) {
    await assert.rejects(new PrivyLinkedIdentityResolver({
      appId,
      appSecret,
      clientFactory: fakeFactory(response),
    }).resolve(identity), errorCode('PRIVY_USER_RESPONSE_INVALID'));
  }
  const accessor = user([]);
  Object.defineProperty(accessor, 'linked_accounts', {enumerable: true, get: () => [twitter]});
  await assert.rejects(new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    clientFactory: fakeFactory(accessor),
  }).resolve(identity), errorCode('PRIVY_USER_RESPONSE_INVALID'));
});

test('invalid or cross-app verified identities make no provider request', async () => {
  let calls = 0;
  const resolver = new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    clientFactory: () => ({getById: async () => { calls += 1; return user([]); }}),
  });
  for (const invalid of [
    {...identity, appId: 'other_app'},
    {...identity, subject: 'did:privy:bad-subject'},
    {...identity, subject: `${subject}\n`},
    {...identity, extra: true},
  ]) {
    await assert.rejects(resolver.resolve(invalid as PracticeIdentity),
      errorCode('PRIVY_VERIFIED_IDENTITY_INVALID'));
  }
  assert.equal(calls, 0);
});

test('provider failures are sanitized, never retried and never retain the app secret as a cause', async () => {
  let calls = 0;
  const resolver = new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    clientFactory: () => ({
      getById: async () => {
        calls += 1;
        throw new Error(`provider included ${appSecret} and private@example.invalid`);
      },
    }),
  });
  await assert.rejects(resolver.resolve(identity), errorCode('PRIVY_USER_UNAVAILABLE'));
  assert.equal(calls, 1);
});

test('same-subject reads singleflight, reuse only sanitized cache data, and refresh after expiry', async () => {
  let calls = 0;
  let now = 10_000;
  let release: () => void = () => undefined;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const resolver = new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    now: () => now,
    cacheTtlMs: 100,
    perSubjectLimit: 10,
    globalLimit: 10,
    clientFactory: () => ({
      getById: async requestedSubject => {
        calls += 1;
        if (calls === 1) await gate;
        return user([twitter, wallet], requestedSubject);
      },
    }),
  });
  const first = resolver.resolve(identity);
  const joined = resolver.resolve({...identity});
  assert.equal(calls, 1);
  release();
  const [one, two] = await Promise.all([first, joined]);
  assert.strictEqual(one, two);
  assert.equal(JSON.stringify(one).includes('private-oauth-token'), false);

  now = 10_099;
  assert.strictEqual(await resolver.resolve(identity), one);
  assert.equal(calls, 1);
  now = 10_100;
  const refreshed = await resolver.resolve(identity);
  assert.equal(calls, 2);
  assert.notStrictEqual(refreshed, one);
});

test('fresh identity reads bypass cached links and preserve optional provider wallet identity', async () => {
  let record = user([{...wallet, id: 'provider-wallet-1'}]);
  let calls = 0;
  const resolver = new PrivyLinkedIdentityResolver({appId, appSecret, now: () => 10_000,
    clientFactory: () => ({getById: async () => { calls++; return record; }})});
  const cached = await resolver.resolve(identity);
  assert.deepEqual(cached.embeddedSolanaWallet, {status: 'candidate', address: walletAddress,
    verifiedAtUnixSeconds: wallet.verified_at, walletId: 'provider-wallet-1'});
  record = user([]);
  assert.strictEqual(await resolver.resolve(identity), cached);
  const fresh = await resolver.resolveFresh(identity);
  assert.deepEqual(fresh.embeddedSolanaWallet, {status: 'missing'});
  assert.strictEqual(await resolver.resolve(identity), fresh, 'ordinary reads immediately reuse the fresh link');
  assert.equal(calls, 2);
  for (const id of ['', 123, 'private\nvalue']) {
    assert.deepEqual(parsePrivyLinkedIdentities(user([{...wallet, id}]), subject).embeddedSolanaWallet,
      {status: 'ambiguous'});
  }
});

test('fresh identity reads never join an earlier in-flight snapshot', async () => {
  let release: () => void = () => undefined;
  const gate = new Promise<void>(resolve => { release = resolve; });
  let calls = 0;
  const resolver = new PrivyLinkedIdentityResolver({appId, appSecret,
    clientFactory: () => ({getById: async () => {
      calls++;
      if (calls === 1) { await gate; return user([wallet]); }
      return user([]);
    }})});
  const previous = resolver.resolve(identity);
  try {
    assert.deepEqual((await resolver.resolveFresh(identity)).embeddedSolanaWallet, {status: 'missing'});
    assert.equal(calls, 2);
  } finally { release(); }
  assert.equal((await previous).embeddedSolanaWallet.status, 'candidate');
  assert.deepEqual((await resolver.resolve(identity)).embeddedSolanaWallet, {status: 'missing'},
    'the old request cannot repopulate the cache after the fresh result');
  assert.equal(calls, 2);
});

test('fresh identity reads retain identity validation, provider limits and concurrency cleanup', async () => {
  let release: () => void = () => undefined;
  const gate = new Promise<void>(resolve => { release = resolve; });
  let calls = 0;
  const resolver = new PrivyLinkedIdentityResolver({appId, appSecret, now: () => 10_000,
    perSubjectLimit: 2, maxConcurrentReads: 1,
    clientFactory: () => ({getById: async () => { calls++; await gate; return user([]); }})});
  await assert.rejects(resolver.resolveFresh({...identity, appId: 'another_app'}),
    errorCode('PRIVY_VERIFIED_IDENTITY_INVALID'));
  assert.equal(calls, 0);
  const first = resolver.resolveFresh(identity);
  try {
    await assert.rejects(resolver.resolveFresh(identity), errorCode('PRIVY_USER_RATE_LIMITED'));
  } finally { release(); }
  await first;
  await resolver.resolveFresh(identity);
  await assert.rejects(resolver.resolveFresh(identity), errorCode('PRIVY_USER_RATE_LIMITED'));
  assert.equal(calls, 2);
});

test('ordinary reads join the fresh replacement while superseded reads still count against capacity', async () => {
  let releaseOld: () => void = () => undefined;
  let releaseFresh: () => void = () => undefined;
  const oldGate = new Promise<void>(resolve => { releaseOld = resolve; });
  const freshGate = new Promise<void>(resolve => { releaseFresh = resolve; });
  let calls = 0;
  const resolver = new PrivyLinkedIdentityResolver({appId, appSecret, maxConcurrentReads: 2,
    clientFactory: () => ({getById: async () => {
      const read = ++calls;
      if (read === 1) { await oldGate; return user([]); }
      await freshGate; return user([wallet]);
    }})});
  const old = resolver.resolve(identity);
  const fresh = resolver.resolveFresh(identity);
  const joined = resolver.resolve(identity);
  try {
    await assert.rejects(resolver.resolveFresh(identity), errorCode('PRIVY_USER_RATE_LIMITED'));
    assert.equal(calls, 2);
    releaseOld();
    assert.equal((await old).embeddedSolanaWallet.status, 'missing');
    const joinedAfterOld = resolver.resolve(identity);
    releaseFresh();
    const [current, ordinary, afterOld] = await Promise.all([fresh, joined, joinedAfterOld]);
    assert.equal(current.embeddedSolanaWallet.status, 'candidate');
    assert.strictEqual(current, ordinary);
    assert.strictEqual(current, afterOld);
    assert.strictEqual(await resolver.resolve(identity), current);
    assert.equal(calls, 2);
  } finally { releaseOld(); releaseFresh(); }
});

test('a failed fresh lookup discards the old cache and releases capacity for a new provider read', async () => {
  let calls = 0;
  const resolver = new PrivyLinkedIdentityResolver({appId, appSecret, maxConcurrentReads: 1,
    clientFactory: () => ({getById: async () => {
      calls++;
      if (calls === 1) return user([]);
      if (calls === 2) throw new Error('private provider detail');
      return user([wallet]);
    }})});
  assert.equal((await resolver.resolve(identity)).embeddedSolanaWallet.status, 'missing');
  await assert.rejects(resolver.resolveFresh(identity), errorCode('PRIVY_USER_UNAVAILABLE'));
  assert.equal((await resolver.resolve(identity)).embeddedSolanaWallet.status, 'candidate');
  assert.equal(calls, 3);
});

test('failed Privy attempts consume per-subject budget and the error remains sanitized', async () => {
  let calls = 0;
  const resolver = new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    now: () => 10_000,
    cacheTtlMs: 1,
    rateLimitWindowMs: 1_000,
    perSubjectLimit: 2,
    globalLimit: 10,
    clientFactory: () => ({getById: async () => {
      calls += 1;
      throw new Error(`${appSecret} private provider failure`);
    }}),
  });
  await assert.rejects(resolver.resolve(identity), errorCode('PRIVY_USER_UNAVAILABLE'));
  await assert.rejects(resolver.resolve(identity), errorCode('PRIVY_USER_UNAVAILABLE'));
  await assert.rejects(resolver.resolve(identity), errorCode('PRIVY_USER_RATE_LIMITED'));
  assert.equal(calls, 2);
});

test('global and concurrency limits protect Privy across subjects with bounded tracking', async () => {
  let calls = 0;
  const globalResolver = new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    now: () => 10_000,
    cacheTtlMs: 1,
    perSubjectLimit: 10,
    globalLimit: 2,
    clientFactory: () => ({getById: async requestedSubject => {
      calls += 1;
      return user([], requestedSubject);
    }}),
  });
  for (const value of ['did:privy:globalone', 'did:privy:globaltwo']) {
    await globalResolver.resolve({...identity, subject: value});
  }
  await assert.rejects(globalResolver.resolve({...identity, subject: 'did:privy:globalthree'}),
    errorCode('PRIVY_USER_RATE_LIMITED'));
  assert.equal(calls, 2);

  let release: () => void = () => undefined;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const concurrentResolver = new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    now: () => 20_000,
    maxConcurrentReads: 1,
    maxTrackedSubjects: 1,
    clientFactory: () => ({getById: async requestedSubject => {
      await gate;
      return user([], requestedSubject);
    }}),
  });
  const active = concurrentResolver.resolve({...identity, subject: 'did:privy:active'});
  await assert.rejects(concurrentResolver.resolve({...identity, subject: 'did:privy:other'}),
    errorCode('PRIVY_USER_RATE_LIMITED'));
  release();
  await active;
  await assert.rejects(concurrentResolver.resolve({...identity, subject: 'did:privy:other'}),
    errorCode('PRIVY_USER_RATE_LIMITED'));
});

test('outer deadline settles and aborts an injected client that ignores its signal', async () => {
  let signal: AbortSignal | undefined;
  const resolver = new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    timeoutMs: 10,
    clientFactory: () => ({
      getById: async (_subject, request) => {
        signal = request.signal;
        return await new Promise<unknown>(() => {});
      },
    }),
  });
  await assert.rejects(resolver.resolve(identity), errorCode('PRIVY_USER_TIMEOUT'));
  assert.equal(signal?.aborted, true);
});

test('strict constructor and environment configuration fail closed without echoing values', () => {
  for (const options of [
    {appId: '', appSecret},
    {appId: 'bad app', appSecret},
    {appId, appSecret: ''},
    {appId, appSecret: `secret\n${appSecret}`},
    {appId, appSecret: ` ${appSecret}`},
    {appId, appSecret: appSecret, timeoutMs: 0},
    {appId, appSecret: appSecret, timeoutMs: 10_001},
    {appId, appSecret: appSecret, timeoutMs: 1.2},
    {appId, appSecret: appSecret, cacheTtlMs: 0},
    {appId, appSecret: appSecret, perSubjectLimit: 0},
    {appId, appSecret: appSecret, maxConcurrentReads: 0},
    {appId, appSecret: appSecret, clientFactory: () => null as never},
  ]) {
    assert.throws(() => new PrivyLinkedIdentityResolver(options),
      errorCode('PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED'));
  }
  assert.equal(readPrivyLinkedIdentityResolver({}), undefined);
  assert.equal(readPrivyLinkedIdentityResolver({PRIVY_APP_ID: '', PRIVY_APP_SECRET: ''}), undefined);
  for (const env of [
    {PRIVY_APP_ID: appId},
    {PRIVY_APP_SECRET: appSecret},
    {PRIVY_APP_ID: appId, PRIVY_APP_SECRET: ''},
    {PRIVY_APP_ID: '', PRIVY_APP_SECRET: appSecret},
  ]) {
    assert.throws(() => readPrivyLinkedIdentityResolver(env),
      errorCode('PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED'));
  }
});

test('the pinned official SDK client performs one bounded GET with zero retries through an injected transport', async () => {
  let calls = 0;
  const resolver = new PrivyLinkedIdentityResolver({
    appId,
    appSecret,
    timeoutMs: 777,
    fetch: async (input, init) => {
      calls += 1;
      assert.equal(String(input), `https://api.privy.io/v1/users/${subject}`);
      assert.equal(init?.method, 'GET');
      const headers = new Headers(init?.headers);
      assert.equal(headers.get('privy-app-id'), appId);
      assert.equal(headers.get('x-stainless-retry-count'), '0');
      assert.ok(headers.has('authorization'));
      assert.equal(init?.signal?.aborted, false);
      return new Response(JSON.stringify(user([twitter, wallet])), {
        status: 200,
        headers: {'content-type': 'application/json'},
      });
    },
  });
  const result = await resolver.resolve(identity);
  assert.equal(result.twitter.status, 'verified');
  assert.equal(result.embeddedSolanaWallet.status, 'candidate');
  assert.equal(calls, 1);
});
