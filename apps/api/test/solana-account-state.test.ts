import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {it} from 'node:test';
import {address, getAddressDecoder, getAddressEncoder, getProgramDerivedAddress} from '@solana/kit';
import type {Address} from '@solana/kit';
import {
  AccountState as LegacyAccountState,
  getMintEncoder as getLegacyMintEncoder,
  getTokenEncoder as getLegacyTokenEncoder,
  TOKEN_PROGRAM_ADDRESS as PACKAGE_TOKEN_PROGRAM_ADDRESS,
} from '@solana-program/token';
import type {MintArgs as LegacyMintArgs, TokenArgs as LegacyTokenArgs} from '@solana-program/token';
import {
  AccountState,
  ASSOCIATED_TOKEN_PROGRAM_ADDRESS as PACKAGE_ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
  findAssociatedTokenPda,
  getMintEncoder,
  getTokenEncoder,
  TOKEN_2022_PROGRAM_ADDRESS as PACKAGE_TOKEN_2022_PROGRAM_ADDRESS,
} from '@solana-program/token-2022';
import type {ExtensionArgs, MintArgs, TokenArgs} from '@solana-program/token-2022';
import {
  AccountStateError,
  ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
  decodeAccountState,
  deriveAssociatedTokenAddress,
  NATIVE_MINT_ADDRESS,
  parseObservedAccount,
  summarizeObservedAccount,
  SYSTEM_PROGRAM_ADDRESS,
  TOKEN_2022_PROGRAM_ADDRESS,
  TOKEN_PROGRAM_ADDRESS,
} from '../src/solana-account-state.js';
import type {ObservedAccount} from '../src/solana-account-state.js';

const FIXED_MESSAGE = 'The Solana account observation could not be decoded.';
const LOOKUP_TABLE_PROGRAM = 'AddressLookupTab1e1111111111111111111111111';
const UPGRADEABLE_LOADER = 'BPFLoaderUpgradeab1e11111111111111111111111';
const addr = (fill: number): Address => getAddressDecoder().decode(new Uint8Array(32).fill(fill));
const wallet = address('9fYLFVoVqwH37C3dyPi6cpeobfbQ2jtLpN5HgAYDDdkm');
const usdcMint = address('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v');
const errorIs = (code: string) => (error: unknown) =>
  error instanceof AccountStateError && error.code === code && error.name === 'AccountStateError' &&
  error.message === FIXED_MESSAGE;

function rpcValue(data: Uint8Array, owner: string, changes: Record<string, unknown> = {}): Record<string, unknown> {
  return {data: [Buffer.from(data).toString('base64'), 'base64'], executable: false, lamports: 2_039_280, owner,
    rentEpoch: 0, space: data.byteLength, ...changes};
}

function observe(accountAddress: string, data: Uint8Array, owner: string,
  changes: Record<string, unknown> = {}): ObservedAccount {
  return parseObservedAccount(accountAddress, rpcValue(data, owner, changes));
}

function mint2022(extensions: ExtensionArgs[] | null, changes: Partial<MintArgs> = {}): Uint8Array {
  return new Uint8Array(getMintEncoder().encode({mintAuthority: addr(20), supply: 1_000_000n, decimals: 8,
    isInitialized: true, freezeAuthority: addr(21), extensions, ...changes}));
}

function token2022(extensions: ExtensionArgs[] | null, changes: Partial<TokenArgs> = {}): Uint8Array {
  return new Uint8Array(getTokenEncoder().encode({mint: addr(30), owner: wallet, amount: 7n, delegate: null,
    state: AccountState.Initialized, isNative: null, delegatedAmount: 0n, closeAuthority: null, extensions,
    ...changes}));
}

function legacyMint(changes: Partial<LegacyMintArgs> = {}): Uint8Array {
  return new Uint8Array(getLegacyMintEncoder().encode({mintAuthority: addr(20), supply: 1_000_000n, decimals: 6,
    isInitialized: true, freezeAuthority: addr(21), ...changes}));
}

function legacyToken(changes: Partial<LegacyTokenArgs> = {}): Uint8Array {
  return new Uint8Array(getLegacyTokenEncoder().encode({mint: usdcMint, owner: wallet, amount: 7n, delegate: null,
    state: LegacyAccountState.Initialized, isNative: null, delegatedAmount: 0n, closeAuthority: null, ...changes}));
}

it('parses a base64 RPC account value into a frozen observation', () => {
  const data = legacyToken();
  const account = parseObservedAccount(wallet, rpcValue(data, TOKEN_PROGRAM_ADDRESS,
    {lamports: 5, rentEpoch: 18_446_744_073_709_552_000}));
  assert.equal(account.address, wallet);
  assert.equal(account.exists, true);
  assert.equal(account.lamports, 5n);
  assert.equal(account.owner, TOKEN_PROGRAM_ADDRESS);
  assert.equal(account.executable, false);
  assert.ok(account.data instanceof Uint8Array && !Buffer.isBuffer(account.data));
  assert.deepEqual([...account.data], [...data]);
  assert.ok(Object.isFrozen(account));
  const minimal = parseObservedAccount(wallet,
    {data: ['', 'base64'], executable: false, lamports: 0, owner: SYSTEM_PROGRAM_ADDRESS});
  assert.equal(minimal.data.byteLength, 0);
  assert.equal(minimal.exists, true);
});

it('treats a null RPC value as a missing account', () => {
  const account = parseObservedAccount(wallet, null);
  assert.deepEqual(account,
    {address: wallet, exists: false, lamports: 0n, owner: null, executable: false, data: new Uint8Array(0)});
  assert.ok(Object.isFrozen(account));
  const state = decodeAccountState(account);
  assert.deepEqual(state, {kind: 'missing', address: wallet});
  assert.ok(Object.isFrozen(state));
});

it('rejects malformed RPC account values and addresses without exposing their contents', () => {
  const data = legacyToken();
  const good = rpcValue(data, TOKEN_PROGRAM_ADDRESS);
  const base64 = Buffer.from(data).toString('base64');
  const {lamports: _omitted, ...withoutLamports} = good;
  const invalid: unknown[] = [
    undefined, 'account', 42, [], [good], Object.create(good), new Map(),
    {...good, data: ['not base64!', 'base64']},
    {...good, data: [base64.slice(0, -1), 'base64']},
    {...good, data: ['AB==', 'base64']},
    {...good, data: [base64, 'base58']},
    {...good, data: [base64]},
    {...good, data: base64},
    {...good, data: {parsed: {}, program: 'spl-token'}},
    {...good, lamports: -1}, {...good, lamports: 1.5}, {...good, lamports: '1'}, {...good, lamports: 2 ** 53},
    {...good, owner: 42}, {...good, owner: null}, {...good, owner: 'not-an-address'},
    {...good, owner: SYSTEM_PROGRAM_ADDRESS.slice(1)},
    {...good, executable: 'false'},
    {...good, rentEpoch: -1}, {...good, rentEpoch: '0'},
    {...good, space: data.byteLength + 1}, {...good, space: '165'},
    {...good, privateProviderField: 'private-upstream'},
    withoutLamports,
  ];
  for (const value of invalid) {
    assert.throws(() => parseObservedAccount(wallet, value), errorIs('ACCOUNT_OBSERVATION_INVALID'));
  }
  for (const bad of ['', 'not-an-address', wallet.toLowerCase(), `${wallet}A`, 'I'.repeat(32)]) {
    assert.throws(() => parseObservedAccount(bad, good), errorIs('ACCOUNT_OBSERVATION_INVALID'));
  }
});

it('summarizes an observation with a data hash and decimal lamports', () => {
  const data = legacyMint();
  const summary = summarizeObservedAccount(observe(usdcMint, data, TOKEN_PROGRAM_ADDRESS, {lamports: 1_461_600}));
  assert.deepEqual(summary, {address: usdcMint, exists: true, lamports: '1461600', owner: TOKEN_PROGRAM_ADDRESS,
    executable: false, dataLengthBytes: 82, dataSha256: createHash('sha256').update(data).digest('hex')});
  assert.ok(Object.isFrozen(summary));
  const missing = summarizeObservedAccount(parseObservedAccount(wallet, null));
  assert.equal(missing.dataSha256, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  assert.equal(missing.lamports, '0');
  assert.equal(missing.owner, null);
});

it('rejects hand-built observations that break the missing/existing invariants', () => {
  const missing = parseObservedAccount(wallet, null);
  const broken = [
    {...missing, lamports: 1n}, {...missing, owner: TOKEN_PROGRAM_ADDRESS}, {...missing, data: new Uint8Array(1)},
    {...missing, executable: true}, {...missing, exists: true}, {...missing, lamports: 1},
    {...missing, address: 'nope'}, {...missing, data: []}, {...missing, exists: true, owner: 'garbage'},
    {...missing, exists: true, owner: TOKEN_PROGRAM_ADDRESS, lamports: (1n << 64n)},
  ] as unknown as ObservedAccount[];
  for (const account of broken) {
    assert.throws(() => decodeAccountState(account), errorIs('ACCOUNT_OBSERVATION_INVALID'));
    assert.throws(() => summarizeObservedAccount(account), errorIs('ACCOUNT_OBSERVATION_INVALID'));
  }
});

it('classifies system accounts, programs, lookup tables and other owners', () => {
  const system = decodeAccountState(observe(wallet, new Uint8Array(0), SYSTEM_PROGRAM_ADDRESS, {lamports: 12}));
  assert.deepEqual(system, {kind: 'system', address: wallet, lamports: 12n});
  const nonce = decodeAccountState(observe(addr(40), new Uint8Array(80), SYSTEM_PROGRAM_ADDRESS));
  assert.deepEqual(nonce, {kind: 'other', address: addr(40), owner: SYSTEM_PROGRAM_ADDRESS, dataLengthBytes: 80});
  const program = decodeAccountState(observe(TOKEN_2022_PROGRAM_ADDRESS, new Uint8Array(36), UPGRADEABLE_LOADER,
    {executable: true}));
  assert.deepEqual(program,
    {kind: 'program', address: TOKEN_2022_PROGRAM_ADDRESS, owner: UPGRADEABLE_LOADER, executable: true});
  assert.equal(decodeAccountState(observe(addr(41), new Uint8Array(3), TOKEN_PROGRAM_ADDRESS,
    {executable: true})).kind, 'program');
  assert.equal(decodeAccountState(observe(addr(41), new Uint8Array(0), SYSTEM_PROGRAM_ADDRESS,
    {executable: true})).kind, 'program');
  const table = decodeAccountState(observe(addr(42), new Uint8Array(56), LOOKUP_TABLE_PROGRAM));
  assert.deepEqual(table, {kind: 'lookup_table', address: addr(42)});
  const other = decodeAccountState(observe(addr(43), new Uint8Array(10), addr(44)));
  assert.deepEqual(other, {kind: 'other', address: addr(43), owner: addr(44), dataLengthBytes: 10});
  for (const state of [system, nonce, program, table, other]) assert.ok(Object.isFrozen(state));
});

it('decodes a legacy SPL token account with delegate and close authority', () => {
  const data = legacyToken({delegate: addr(50), delegatedAmount: 3n, closeAuthority: addr(51), amount: 12_345n});
  assert.equal(data.byteLength, 165);
  const state = decodeAccountState(observe(addr(52), data, TOKEN_PROGRAM_ADDRESS, {lamports: 2_039_280}));
  assert.deepEqual(state, {kind: 'token_account', address: addr(52), tokenProgram: 'token', mint: usdcMint,
    owner: wallet, amount: 12_345n, delegate: addr(50), delegatedAmount: 3n, state: 'initialized', isNative: false,
    nativeRentExemptReserve: null, closeAuthority: addr(51), extensions: [], immutableOwner: false, cpiGuard: false,
    memoTransferRequired: false, nonTransferable: false, transferHookTransferring: false, lamports: 2_039_280n});
  assert.ok(state.kind === 'token_account' && Object.isFrozen(state) && Object.isFrozen(state.extensions));
});

it('decodes a legacy SPL mint', () => {
  const data = legacyMint({freezeAuthority: null, supply: 99n, decimals: 6});
  assert.equal(data.byteLength, 82);
  const state = decodeAccountState(observe(usdcMint, data, TOKEN_PROGRAM_ADDRESS, {lamports: 1_461_600}));
  assert.deepEqual(state, {kind: 'mint', address: usdcMint, tokenProgram: 'token', decimals: 6, supply: 99n,
    isInitialized: true, mintAuthority: addr(20), freezeAuthority: null, extensions: [], defaultAccountState: null,
    paused: null, transferHookProgram: null, transferHookAuthority: null, permanentDelegate: null, transferFee: null,
    scaledUiAmount: null, nonTransferable: false, confidentialTransfer: false, mintCloseAuthority: null,
    lamports: 1_461_600n});
  assert.ok(state.kind === 'mint' && Object.isFrozen(state) && Object.isFrozen(state.extensions));
});

it('reports frozen, native (wrapped SOL) and uninitialized token accounts', () => {
  const frozen = decodeAccountState(observe(addr(53), legacyToken({state: LegacyAccountState.Frozen}),
    TOKEN_PROGRAM_ADDRESS));
  assert.ok(frozen.kind === 'token_account');
  assert.equal(frozen.state, 'frozen');
  const native = decodeAccountState(observe(addr(54),
    legacyToken({mint: address(NATIVE_MINT_ADDRESS), isNative: 2_039_280n, amount: 5_000n}),
    TOKEN_PROGRAM_ADDRESS, {lamports: 2_044_280}));
  assert.ok(native.kind === 'token_account');
  assert.equal(native.mint, NATIVE_MINT_ADDRESS);
  assert.equal(native.isNative, true);
  assert.equal(native.nativeRentExemptReserve, 2_039_280n);
  assert.equal(native.amount, 5_000n);
  assert.equal(native.lamports, 2_044_280n);
  const uninitialized = decodeAccountState(observe(addr(55), token2022(null, {state: AccountState.Uninitialized}),
    TOKEN_2022_PROGRAM_ADDRESS));
  assert.ok(uninitialized.kind === 'token_account');
  assert.equal(uninitialized.state, 'uninitialized');
  assert.equal(uninitialized.tokenProgram, 'token_2022');
});

it('rejects legacy token-program accounts that are not exactly a token account or a mint', () => {
  const garbage = new Uint8Array(165).fill(0xff);
  const cases = [new Uint8Array(0), new Uint8Array(81), new Uint8Array(100), new Uint8Array(166),
    new Uint8Array(355), garbage, mint2022([{__kind: 'NonTransferable'}]), token2022([{__kind: 'ImmutableOwner'}])];
  for (const data of cases) {
    assert.throws(() => decodeAccountState(observe(addr(56), data, TOKEN_PROGRAM_ADDRESS)),
      errorIs('ACCOUNT_DATA_INVALID'));
  }
});

it('decodes Token-2022 mint extension flags that matter for a swap', () => {
  const extensions: ExtensionArgs[] = [
    {__kind: 'PausableConfig', authority: addr(1), paused: true},
    {__kind: 'DefaultAccountState', state: AccountState.Frozen},
    {__kind: 'TransferHook', authority: addr(2), programId: addr(3)},
    {__kind: 'PermanentDelegate', delegate: addr(4)},
    {__kind: 'ScaledUiAmountConfig', authority: addr(5), multiplier: 1.5,
      newMultiplierEffectiveTimestamp: 1_760_000_000n, newMultiplier: 2.25},
    {__kind: 'TransferFeeConfig', transferFeeConfigAuthority: addr(6), withdrawWithheldAuthority: addr(7),
      withheldAmount: 5n, olderTransferFee: {epoch: 1n, maximumFee: 10n, transferFeeBasisPoints: 50},
      newerTransferFee: {epoch: 2n, maximumFee: 20n, transferFeeBasisPoints: 75}},
    {__kind: 'NonTransferable'},
    {__kind: 'MintCloseAuthority', closeAuthority: addr(8)},
    {__kind: 'ConfidentialTransferMint', authority: addr(9), autoApproveNewAccounts: true,
      auditorElgamalPubkey: null},
    {__kind: 'MetadataPointer', authority: addr(10), metadataAddress: addr(11)},
    {__kind: 'InterestBearingConfig', rateAuthority: addr(12), initializationTimestamp: 1n,
      preUpdateAverageRate: 0, lastUpdateTimestamp: 2n, currentRate: 100},
  ];
  const data = mint2022(extensions);
  assert.equal(data[165], 1);
  const state = decodeAccountState(observe(addr(57), data, TOKEN_2022_PROGRAM_ADDRESS, {lamports: 5_000_000}));
  assert.deepEqual(state, {kind: 'mint', address: addr(57), tokenProgram: 'token_2022', decimals: 8,
    supply: 1_000_000n, isInitialized: true, mintAuthority: addr(20), freezeAuthority: addr(21),
    extensions: ['PausableConfig', 'DefaultAccountState', 'TransferHook', 'PermanentDelegate',
      'ScaledUiAmountConfig', 'TransferFeeConfig', 'NonTransferable', 'MintCloseAuthority',
      'ConfidentialTransferMint', 'MetadataPointer', 'InterestBearingConfig'],
    defaultAccountState: 'frozen', paused: true, transferHookProgram: addr(3), transferHookAuthority: addr(2),
    permanentDelegate: addr(4), transferFee: {basisPoints: 75, maximumFee: 20n},
    scaledUiAmount: {multiplier: 1.5, newMultiplier: 2.25, newMultiplierEffectiveTimestamp: 1_760_000_000n},
    nonTransferable: true, confidentialTransfer: true, mintCloseAuthority: addr(8), lamports: 5_000_000n});
  assert.ok(state.kind === 'mint' && Object.isFrozen(state) && Object.isFrozen(state.extensions) &&
    Object.isFrozen(state.transferFee) && Object.isFrozen(state.scaledUiAmount));
});

it('reports unpaused mints, initialized default state and unset optional keys as null', () => {
  const zero = address(SYSTEM_PROGRAM_ADDRESS);
  const data = mint2022([
    {__kind: 'PausableConfig', authority: null, paused: false},
    {__kind: 'DefaultAccountState', state: AccountState.Initialized},
    {__kind: 'TransferHook', authority: zero, programId: zero},
    {__kind: 'PermanentDelegate', delegate: zero},
    {__kind: 'MintCloseAuthority', closeAuthority: zero},
  ], {mintAuthority: null});
  const state = decodeAccountState(observe(addr(58), data, TOKEN_2022_PROGRAM_ADDRESS));
  assert.ok(state.kind === 'mint');
  assert.equal(state.paused, false);
  assert.equal(state.defaultAccountState, 'initialized');
  assert.equal(state.transferHookProgram, null);
  assert.equal(state.transferHookAuthority, null);
  assert.equal(state.permanentDelegate, null);
  assert.equal(state.mintCloseAuthority, null);
  assert.equal(state.mintAuthority, null);
  assert.equal(state.freezeAuthority, addr(21));
  assert.deepEqual(state.extensions,
    ['PausableConfig', 'DefaultAccountState', 'TransferHook', 'PermanentDelegate', 'MintCloseAuthority']);
});

it('decodes Token-2022 mints without extensions at both the base and the typed size', () => {
  const base = mint2022(null);
  const typed = mint2022([]);
  assert.equal(base.byteLength, 82);
  assert.equal(typed.byteLength, 166);
  assert.equal(typed[165], 1);
  for (const data of [base, typed]) {
    const state = decodeAccountState(observe(addr(59), data, TOKEN_2022_PROGRAM_ADDRESS));
    assert.ok(state.kind === 'mint');
    assert.equal(state.tokenProgram, 'token_2022');
    assert.deepEqual(state.extensions, []);
    assert.equal(state.paused, null);
    assert.equal(state.defaultAccountState, null);
    assert.equal(state.scaledUiAmount, null);
    assert.equal(state.transferFee, null);
  }
});

it('decodes Token-2022 token account extension flags', () => {
  const data = token2022([
    {__kind: 'ImmutableOwner'}, {__kind: 'CpiGuard', lockCpi: true},
    {__kind: 'MemoTransfer', requireIncomingTransferMemos: true}, {__kind: 'NonTransferableAccount'},
    {__kind: 'TransferHookAccount', transferring: true}, {__kind: 'PausableAccount'},
    {__kind: 'TransferFeeAmount', withheldAmount: 3n},
  ], {amount: 250n, state: AccountState.Frozen});
  assert.equal(data[165], 2);
  const state = decodeAccountState(observe(addr(60), data, TOKEN_2022_PROGRAM_ADDRESS, {lamports: 2_157_600}));
  assert.deepEqual(state, {kind: 'token_account', address: addr(60), tokenProgram: 'token_2022', mint: addr(30),
    owner: wallet, amount: 250n, delegate: null, delegatedAmount: 0n, state: 'frozen', isNative: false,
    nativeRentExemptReserve: null, closeAuthority: null,
    extensions: ['ImmutableOwner', 'CpiGuard', 'MemoTransfer', 'NonTransferableAccount', 'TransferHookAccount',
      'PausableAccount', 'TransferFeeAmount'],
    immutableOwner: true, cpiGuard: true, memoTransferRequired: true, nonTransferable: true,
    transferHookTransferring: true, lamports: 2_157_600n});
  assert.ok(state.kind === 'token_account' && Object.isFrozen(state) && Object.isFrozen(state.extensions));
  const relaxed = decodeAccountState(observe(addr(61), token2022([
    {__kind: 'CpiGuard', lockCpi: false}, {__kind: 'MemoTransfer', requireIncomingTransferMemos: false},
    {__kind: 'TransferHookAccount', transferring: false},
  ]), TOKEN_2022_PROGRAM_ADDRESS));
  assert.ok(relaxed.kind === 'token_account');
  assert.equal(relaxed.cpiGuard, false);
  assert.equal(relaxed.memoTransferRequired, false);
  assert.equal(relaxed.transferHookTransferring, false);
  assert.equal(relaxed.immutableOwner, false);
  assert.equal(relaxed.nonTransferable, false);
  const plain = decodeAccountState(observe(addr(62), token2022(null), TOKEN_2022_PROGRAM_ADDRESS));
  assert.ok(plain.kind === 'token_account');
  assert.deepEqual(plain.extensions, []);
  assert.equal(plain.tokenProgram, 'token_2022');
});

it('rejects Token-2022 accounts whose bytes are not a canonical mint or token account', () => {
  const mintWithExtension = mint2022([{__kind: 'NonTransferable'}]);
  const tokenWithExtension = token2022([{__kind: 'ImmutableOwner'}]);
  const unknownType = Uint8Array.from(tokenWithExtension);
  unknownType[165] = 3;
  const dirtyPadding = Uint8Array.from(mintWithExtension);
  dirtyPadding[100] = 1;
  const oddTrailing = new Uint8Array([...tokenWithExtension, 0]);
  const nonCanonicalBoolean = mint2022(null);
  nonCanonicalBoolean[45] = 2;
  const badState = token2022(null);
  badState[108] = 3;
  const duplicate = mint2022([{__kind: 'PausableConfig', authority: null, paused: true},
    {__kind: 'PausableConfig', authority: null, paused: false}]);
  const defaultUninitialized = mint2022([{__kind: 'DefaultAccountState', state: AccountState.Uninitialized}]);
  const truncated = mintWithExtension.slice(0, -1);
  const cases = [new Uint8Array(0), new Uint8Array(81), new Uint8Array(83), new Uint8Array(164),
    new Uint8Array(166), new Uint8Array(355), new Uint8Array(165).fill(0xff), unknownType, dirtyPadding,
    oddTrailing, nonCanonicalBoolean, badState, duplicate, defaultUninitialized, truncated];
  for (const data of cases) {
    assert.throws(() => decodeAccountState(observe(addr(63), data, TOKEN_2022_PROGRAM_ADDRESS)),
      errorIs('ACCOUNT_DATA_INVALID'));
  }
});

it('ignores uninitialized TLV padding and lists unknown extension kinds without failing', () => {
  const data = new Uint8Array([...mint2022([{__kind: 'NonTransferable'}]), 0, 0, 0, 0]);
  const state = decodeAccountState(observe(addr(64), data, TOKEN_2022_PROGRAM_ADDRESS));
  assert.ok(state.kind === 'mint');
  assert.deepEqual(state.extensions, ['NonTransferable']);
  assert.equal(state.nonTransferable, true);
});

it('derives associated token addresses that match both package derivations and fixed vectors', async () => {
  const legacy = await deriveAssociatedTokenAddress(wallet, usdcMint, 'token');
  const token2022Ata = await deriveAssociatedTokenAddress(wallet, usdcMint, 'token_2022');
  assert.equal(legacy, '5DMGH4bkaN4ZYBHrF7DVaNo3bkp5QagP1tfVUjPu7UAY');
  assert.equal(token2022Ata, '6niM1u9GwNKLrcR2ZWiSMfk9KB2La6UkscrvF4bax7LX'); // gitleaks:allow -- public associated token account address
  assert.notEqual(legacy, token2022Ata);
  const [viaPackage] = await findAssociatedTokenPda(
    {owner: wallet, tokenProgram: PACKAGE_TOKEN_PROGRAM_ADDRESS, mint: usdcMint});
  const encoder = getAddressEncoder();
  const viaKit = async (tokenProgram: string) => (await getProgramDerivedAddress({
    programAddress: address(ASSOCIATED_TOKEN_PROGRAM_ADDRESS),
    seeds: [encoder.encode(wallet), encoder.encode(address(tokenProgram)), encoder.encode(usdcMint)],
  }))[0];
  assert.equal(viaPackage, legacy);
  assert.equal(await viaKit(TOKEN_PROGRAM_ADDRESS), legacy);
  assert.equal(await viaKit(TOKEN_2022_PROGRAM_ADDRESS), token2022Ata);
  await assert.rejects(deriveAssociatedTokenAddress('not-an-address', usdcMint, 'token'),
    errorIs('ACCOUNT_OBSERVATION_INVALID'));
  await assert.rejects(deriveAssociatedTokenAddress(wallet, '', 'token_2022'), errorIs('ACCOUNT_OBSERVATION_INVALID'));
  await assert.rejects(deriveAssociatedTokenAddress(wallet, usdcMint, 'spl' as never),
    errorIs('ACCOUNT_OBSERVATION_INVALID'));
});

it('pins the program addresses to the installed packages', () => {
  assert.equal(TOKEN_PROGRAM_ADDRESS, PACKAGE_TOKEN_PROGRAM_ADDRESS);
  assert.equal(TOKEN_2022_PROGRAM_ADDRESS, PACKAGE_TOKEN_2022_PROGRAM_ADDRESS);
  assert.equal(ASSOCIATED_TOKEN_PROGRAM_ADDRESS, PACKAGE_ASSOCIATED_TOKEN_PROGRAM_ADDRESS);
  assert.equal(SYSTEM_PROGRAM_ADDRESS, '11111111111111111111111111111111');
  assert.equal(NATIVE_MINT_ADDRESS, 'So11111111111111111111111111111111111111112');
  for (const value of [TOKEN_PROGRAM_ADDRESS, TOKEN_2022_PROGRAM_ADDRESS, ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
    SYSTEM_PROGRAM_ADDRESS, NATIVE_MINT_ADDRESS]) assert.equal(address(value), value);
});

it('exposes a typed error with a fixed message that never carries account bytes', () => {
  const error = new AccountStateError('ACCOUNT_DATA_INVALID');
  assert.ok(error instanceof Error);
  assert.equal(error.name, 'AccountStateError');
  assert.equal(error.code, 'ACCOUNT_DATA_INVALID');
  assert.equal(error.message, FIXED_MESSAGE);
  const secret = new Uint8Array(165).fill(0xab);
  const base64 = Buffer.from(secret).toString('base64');
  assert.throws(() => decodeAccountState(observe(addr(65), secret, TOKEN_2022_PROGRAM_ADDRESS)), (caught: unknown) => {
    assert.ok(caught instanceof AccountStateError);
    const text = JSON.stringify({...caught, message: caught.message, stack: caught.stack});
    return caught.code === 'ACCOUNT_DATA_INVALID' && !text.includes('abab') && !text.includes(base64.slice(0, 12));
  });
});

it('decodes a mixed getMultipleAccounts value array deterministically', () => {
  const addresses = [addr(70), wallet, usdcMint];
  const values = [null, rpcValue(new Uint8Array(0), SYSTEM_PROGRAM_ADDRESS, {lamports: 10}),
    rpcValue(legacyMint(), TOKEN_PROGRAM_ADDRESS)];
  const decodeAll = () => values.map((value, index) =>
    decodeAccountState(parseObservedAccount(addresses[index] ?? '', value)));
  assert.deepEqual(decodeAll().map(state => state.kind), ['missing', 'system', 'mint']);
  assert.deepEqual(decodeAll(), decodeAll());
});
