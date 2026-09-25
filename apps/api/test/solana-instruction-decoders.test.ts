import assert from 'node:assert/strict';
import { createHash, createPrivateKey, createPublicKey } from 'node:crypto';
import { describe, it } from 'node:test';
import { getAddressDecoder } from '@solana/kit';
import type { Address } from '@solana/kit';
import { getTransferSolInstructionDataEncoder, getCreateAccountInstructionDataEncoder,
  getAdvanceNonceAccountInstructionDataEncoder, getAllocateInstructionDataEncoder } from '@solana-program/system';
import { getSetComputeUnitLimitInstructionDataEncoder, getSetComputeUnitPriceInstructionDataEncoder,
  getRequestHeapFrameInstructionDataEncoder,
  getSetLoadedAccountsDataSizeLimitInstructionDataEncoder } from '@solana-program/compute-budget';
import { getTransferInstructionDataEncoder, getTransferCheckedInstructionDataEncoder,
  getApproveInstructionDataEncoder, getApproveCheckedInstructionDataEncoder, getRevokeInstructionDataEncoder,
  getCloseAccountInstructionDataEncoder, getSyncNativeInstructionDataEncoder,
  getInitializeAccountInstructionDataEncoder, getInitializeAccount2InstructionDataEncoder,
  getInitializeAccount3InstructionDataEncoder, getInitializeImmutableOwnerInstructionDataEncoder,
  getCreateAssociatedTokenInstructionDataEncoder, getCreateAssociatedTokenIdempotentInstructionDataEncoder,
  getMintToInstructionDataEncoder, getBurnInstructionDataEncoder, getFreezeAccountInstructionDataEncoder,
  getRecoverNestedAssociatedTokenInstructionDataEncoder } from '@solana-program/token-2022';
import { decodeInstruction, InstructionDecodeError, KNOWN_PROGRAMS } from '../src/solana-instruction-decoders.js';
import type { DecodableInstruction } from '../src/solana-instruction-decoders.js';

// Deterministic on-curve ed25519 verification keys. The seeds are derived from
// fixed strings so the test vectors never change; no signature is produced.
function key(index: number): string {
  const seed = createHash('sha256').update(`trimmy-decoder-${index}`).digest();
  const pkcs8 = Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]);
  const spki = createPublicKey(createPrivateKey({key: pkcs8, format: 'der', type: 'pkcs8'}))
    .export({format: 'der', type: 'spki'});
  return getAddressDecoder().decode(Uint8Array.from(spki.subarray(spki.length - 32)));
}
const taker = key(1);
const source = key(2);
const destination = key(3);
const mint = key(4);
const outputMint = key(5);
const delegate = key(6);
const eventAuthority = key(7);
const programAuthority = key(8);
const feeAccount = key(9);
const poolAccount = key(10);
const bytes = (value: Uint8Array | ArrayLike<number>) => Uint8Array.from(value as ArrayLike<number>);
const errorIs = (code: string) => (error: unknown) =>
  error instanceof InstructionDecodeError && error.code === code &&
  error.message === 'The Solana instruction cannot be reviewed.';

function instruction(programAddress: string, accountAddresses: readonly string[], data: Uint8Array): DecodableInstruction {
  return {programAddress, accountAddresses, data};
}
function discriminator(name: string): Uint8Array {
  return Uint8Array.from(createHash('sha256').update(`global:${name}`).digest().subarray(0, 8));
}
function u32(value: number): number[] { return [value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >>> 24) & 0xff]; }
function u64(value: bigint): number[] {
  const out: number[] = [];
  let remaining = value;
  for (let index = 0; index < 8; index += 1) { out.push(Number(remaining & 0xffn)); remaining >>= 8n; }
  return out;
}
/** Jupiter v6 route data: discriminator, optional id, route plan, then the fixed tail. */
function jupiterData(options: {shared: boolean; steps?: number; inAmount?: bigint; quotedOut?: bigint;
  slippageBps?: number; feeBps?: number; planBytes?: number[]; name?: string}): Uint8Array {
  const steps = options.steps ?? 1;
  const plan = options.planBytes ?? new Array<number>(steps * 5).fill(0);
  return bytes([
    ...discriminator(options.name ?? (options.shared ? 'shared_accounts_route' : 'route')),
    ...(options.shared ? [7] : []),
    ...u32(steps), ...plan,
    ...u64(options.inAmount ?? 10_000_000n), ...u64(options.quotedOut ?? 2_972_350n),
    (options.slippageBps ?? 50) & 0xff, ((options.slippageBps ?? 50) >> 8) & 0xff, options.feeBps ?? 0,
  ]);
}
const routeAccounts = (overrides: Partial<Record<number, string>> = {}) => {
  const list = [KNOWN_PROGRAMS.token, taker, source, destination, KNOWN_PROGRAMS.jupiterV6, outputMint,
    KNOWN_PROGRAMS.jupiterV6, eventAuthority, KNOWN_PROGRAMS.jupiterV6, poolAccount];
  for (const [index, value] of Object.entries(overrides)) list[Number(index)] = value!;
  return list;
};
const sharedAccounts = (overrides: Partial<Record<number, string>> = {}) => {
  const list = [KNOWN_PROGRAMS.token, programAuthority, taker, source, key(20), key(21), destination, mint,
    outputMint, KNOWN_PROGRAMS.jupiterV6, KNOWN_PROGRAMS.jupiterV6, eventAuthority, KNOWN_PROGRAMS.jupiterV6, poolAccount];
  for (const [index, value] of Object.entries(overrides)) list[Number(index)] = value!;
  return list;
};

describe('system program', () => {
  it('decodes a SOL transfer and a create account', () => {
    const transfer = decodeInstruction(instruction(KNOWN_PROGRAMS.system, [taker, destination],
      bytes(getTransferSolInstructionDataEncoder().encode({amount: 2_039_280n}))));
    assert.deepEqual(transfer, {program: 'system', kind: 'transfer', from: taker, to: destination, lamports: 2_039_280n});
    assert.ok(Object.isFrozen(transfer));
    const created = decodeInstruction(instruction(KNOWN_PROGRAMS.system, [taker, destination],
      bytes(getCreateAccountInstructionDataEncoder().encode({lamports: 1n, space: 165n, programAddress: KNOWN_PROGRAMS.token as Address}))));
    assert.deepEqual(created, {program: 'system', kind: 'create_account', from: taker, newAccount: destination,
      lamports: 1n, space: 165n, owner: KNOWN_PROGRAMS.token});
  });

  it('rejects nonce, allocate and wrong account counts', () => {
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.system, [taker, destination, mint],
      bytes(getAdvanceNonceAccountInstructionDataEncoder().encode({})))), errorIs('UNSUPPORTED_INSTRUCTION'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.system, [taker],
      bytes(getAllocateInstructionDataEncoder().encode({space: 10n})))), errorIs('UNSUPPORTED_INSTRUCTION'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.system, [taker],
      bytes(getTransferSolInstructionDataEncoder().encode({amount: 1n})))), errorIs('UNSUPPORTED_INSTRUCTION'));
  });

  it('rejects trailing bytes, an unknown discriminator and an off-curve sender', () => {
    const valid = bytes(getTransferSolInstructionDataEncoder().encode({amount: 1n}));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.system, [taker, destination],
      bytes([...valid, 0]))), errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.system, [taker, destination],
      bytes([...u32(99), ...u64(1n)]))), errorIs('UNSUPPORTED_INSTRUCTION'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.system,
      [KNOWN_PROGRAMS.system, destination], valid)), errorIs('INSTRUCTION_INVALID'));
  });
});

describe('compute budget program', () => {
  it('decodes all four admitted instructions', () => {
    assert.deepEqual(decodeInstruction(instruction(KNOWN_PROGRAMS.computeBudget, [],
      bytes(getSetComputeUnitLimitInstructionDataEncoder().encode({units: 300_000})))),
    {program: 'compute_budget', kind: 'set_compute_unit_limit', units: 300_000});
    assert.deepEqual(decodeInstruction(instruction(KNOWN_PROGRAMS.computeBudget, [],
      bytes(getSetComputeUnitPriceInstructionDataEncoder().encode({microLamports: 1_500n})))),
    {program: 'compute_budget', kind: 'set_compute_unit_price', microLamports: 1_500n});
    assert.deepEqual(decodeInstruction(instruction(KNOWN_PROGRAMS.computeBudget, [],
      bytes(getRequestHeapFrameInstructionDataEncoder().encode({bytes: 32_768})))),
    {program: 'compute_budget', kind: 'request_heap_frame', bytes: 32_768});
    assert.deepEqual(decodeInstruction(instruction(KNOWN_PROGRAMS.computeBudget, [],
      bytes(getSetLoadedAccountsDataSizeLimitInstructionDataEncoder().encode({accountDataSizeLimit: 64_000})))),
    {program: 'compute_budget', kind: 'set_loaded_accounts_data_size_limit', bytes: 64_000});
  });

  it('rejects the deprecated request, unknown discriminators and any account', () => {
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.computeBudget, [], bytes([0, ...u32(1), ...u32(1)]))),
      errorIs('UNSUPPORTED_INSTRUCTION'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.computeBudget, [], bytes([9, 1]))),
      errorIs('UNSUPPORTED_INSTRUCTION'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.computeBudget, [taker],
      bytes(getSetComputeUnitLimitInstructionDataEncoder().encode({units: 1})))), errorIs('INSTRUCTION_INVALID'));
  });
});

describe('token and token-2022 programs', () => {
  for (const [name, program] of [['token', KNOWN_PROGRAMS.token], ['token_2022', KNOWN_PROGRAMS.token2022]] as const) {
    it(`decodes the admitted ${name} instructions`, () => {
      assert.deepEqual(decodeInstruction(instruction(program, [source, destination, taker],
        bytes(getTransferInstructionDataEncoder().encode({amount: 10n})))),
      {program: name, kind: 'transfer', source, destination, authority: taker, amount: 10n, checked: false,
        mint: null, decimals: null, extraAccounts: []});
      assert.deepEqual(decodeInstruction(instruction(program, [source, mint, destination, taker],
        bytes(getTransferCheckedInstructionDataEncoder().encode({amount: 10n, decimals: 6})))),
      {program: name, kind: 'transfer', source, destination, authority: taker, amount: 10n, checked: true,
        mint, decimals: 6, extraAccounts: []});
      assert.deepEqual(decodeInstruction(instruction(program, [source, delegate, taker],
        bytes(getApproveInstructionDataEncoder().encode({amount: 5n})))),
      {program: name, kind: 'approve', source, delegate, authority: taker, amount: 5n, checked: false, mint: null, decimals: null});
      assert.deepEqual(decodeInstruction(instruction(program, [source, mint, delegate, taker],
        bytes(getApproveCheckedInstructionDataEncoder().encode({amount: 5n, decimals: 8})))),
      {program: name, kind: 'approve', source, delegate, authority: taker, amount: 5n, checked: true, mint, decimals: 8});
      assert.deepEqual(decodeInstruction(instruction(program, [source, taker],
        bytes(getRevokeInstructionDataEncoder().encode({})))), {program: name, kind: 'revoke', source, authority: taker});
      assert.deepEqual(decodeInstruction(instruction(program, [source, destination, taker],
        bytes(getCloseAccountInstructionDataEncoder().encode({})))),
      {program: name, kind: 'close_account', account: source, destination, authority: taker});
      assert.deepEqual(decodeInstruction(instruction(program, [source],
        bytes(getSyncNativeInstructionDataEncoder().encode({})))), {program: name, kind: 'sync_native', account: source});
      assert.deepEqual(decodeInstruction(instruction(program, [source, mint, taker, key(30)],
        bytes(getInitializeAccountInstructionDataEncoder().encode({})))),
      {program: name, kind: 'initialize_account', variant: 1, account: source, mint, owner: taker});
      assert.deepEqual(decodeInstruction(instruction(program, [source, mint, key(30)],
        bytes(getInitializeAccount2InstructionDataEncoder().encode({owner: taker as Address})))),
      {program: name, kind: 'initialize_account', variant: 2, account: source, mint, owner: taker});
      assert.deepEqual(decodeInstruction(instruction(program, [source, mint],
        bytes(getInitializeAccount3InstructionDataEncoder().encode({owner: taker as Address})))),
      {program: name, kind: 'initialize_account', variant: 3, account: source, mint, owner: taker});
      assert.deepEqual(decodeInstruction(instruction(program, [source],
        bytes(getInitializeImmutableOwnerInstructionDataEncoder().encode({})))),
      {program: name, kind: 'initialize_immutable_owner', account: source});
    });

    it(`rejects minting, burning, freezing and multisig on ${name}`, () => {
      assert.throws(() => decodeInstruction(instruction(program, [mint, destination, taker],
        bytes(getMintToInstructionDataEncoder().encode({amount: 1n})))), errorIs('UNSUPPORTED_INSTRUCTION'));
      assert.throws(() => decodeInstruction(instruction(program, [source, mint, taker],
        bytes(getBurnInstructionDataEncoder().encode({amount: 1n})))), errorIs('UNSUPPORTED_INSTRUCTION'));
      assert.throws(() => decodeInstruction(instruction(program, [source, mint, taker],
        bytes(getFreezeAccountInstructionDataEncoder().encode({})))), errorIs('UNSUPPORTED_INSTRUCTION'));
      assert.throws(() => decodeInstruction(instruction(program, [source, destination, taker, key(31), key(32)],
        bytes(getTransferInstructionDataEncoder().encode({amount: 1n})))), errorIs('UNSUPPORTED_INSTRUCTION'));
      assert.throws(() => decodeInstruction(instruction(program, [source, taker, key(31)],
        bytes(getRevokeInstructionDataEncoder().encode({})))), errorIs('UNSUPPORTED_INSTRUCTION'));
      assert.throws(() => decodeInstruction(instruction(program, [source, destination, taker],
        bytes([...getTransferInstructionDataEncoder().encode({amount: 1n}), 7]))), errorIs('INSTRUCTION_INVALID'));
    });
  }

  it('keeps transfer-hook accounts on token-2022 and refuses them on the legacy program', () => {
    const data = bytes(getTransferCheckedInstructionDataEncoder().encode({amount: 1n, decimals: 8}));
    const hookAccounts = [source, mint, destination, taker, key(40), key(41)];
    const decoded = decodeInstruction(instruction(KNOWN_PROGRAMS.token2022, hookAccounts, data));
    assert.equal(decoded.kind, 'transfer');
    assert.deepEqual(decoded.program === 'token_2022' && decoded.kind === 'transfer' ? decoded.extraAccounts : null,
      [key(40), key(41)]);
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.token, hookAccounts, data)),
      errorIs('UNSUPPORTED_INSTRUCTION'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.token2022, [source, mint, destination], data)),
      errorIs('UNSUPPORTED_INSTRUCTION'));
  });
});

describe('associated token program', () => {
  it('decodes create and create idempotent', () => {
    const list = [taker, source, taker, mint, KNOWN_PROGRAMS.system, KNOWN_PROGRAMS.token];
    assert.deepEqual(decodeInstruction(instruction(KNOWN_PROGRAMS.associatedToken, list,
      bytes(getCreateAssociatedTokenInstructionDataEncoder().encode({})))),
    {program: 'associated_token', kind: 'create', payer: taker, associatedAccount: source, owner: taker, mint,
      tokenProgram: KNOWN_PROGRAMS.token});
    assert.deepEqual(decodeInstruction(instruction(KNOWN_PROGRAMS.associatedToken,
      [taker, source, taker, mint, KNOWN_PROGRAMS.system, KNOWN_PROGRAMS.token2022],
      bytes(getCreateAssociatedTokenIdempotentInstructionDataEncoder().encode({})))),
    {program: 'associated_token', kind: 'create_idempotent', payer: taker, associatedAccount: source, owner: taker,
      mint, tokenProgram: KNOWN_PROGRAMS.token2022});
  });

  it('rejects recover nested, a wrong system or token program slot and wrong account counts', () => {
    const list = [taker, source, taker, mint, KNOWN_PROGRAMS.system, KNOWN_PROGRAMS.token];
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.associatedToken, list,
      bytes(getRecoverNestedAssociatedTokenInstructionDataEncoder().encode({})))), errorIs('UNSUPPORTED_INSTRUCTION'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.associatedToken,
      [taker, source, taker, mint, KNOWN_PROGRAMS.token, KNOWN_PROGRAMS.token],
      bytes(getCreateAssociatedTokenInstructionDataEncoder().encode({})))), errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.associatedToken,
      [taker, source, taker, mint, KNOWN_PROGRAMS.system, poolAccount],
      bytes(getCreateAssociatedTokenInstructionDataEncoder().encode({})))), errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.associatedToken, list.slice(0, 5),
      bytes(getCreateAssociatedTokenInstructionDataEncoder().encode({})))), errorIs('UNSUPPORTED_INSTRUCTION'));
  });
});

describe('jupiter v6 swap', () => {
  it('decodes route with its optional accounts absent', () => {
    const decoded = decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, routeAccounts(),
      jupiterData({shared: false, steps: 2})));
    assert.deepEqual(decoded, {
      program: 'jupiter_v6', kind: 'route', tokenProgram: KNOWN_PROGRAMS.token, programAuthority: null,
      userTransferAuthority: taker, userSourceTokenAccount: source, userDestinationTokenAccount: destination,
      programSourceTokenAccount: null, programDestinationTokenAccount: null, sourceMint: null,
      destinationMint: outputMint, platformFeeAccount: null, token2022Program: null, eventAuthority,
      routeAccounts: [poolAccount], inAmount: 10_000_000n, quotedOutAmount: 2_972_350n, slippageBps: 50,
      platformFeeBps: 0, routePlanStepCount: 2,
    });
    assert.ok(Object.isFrozen(decoded) && Object.isFrozen(decoded.program === 'jupiter_v6' ? decoded.routeAccounts : {}));
  });

  it('decodes shared accounts route with a platform fee account present', () => {
    const decoded = decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6,
      sharedAccounts({9: feeAccount, 10: KNOWN_PROGRAMS.token2022}),
      jupiterData({shared: true, steps: 3, inAmount: 250n, quotedOut: 900n, slippageBps: 100, feeBps: 10})));
    assert.deepEqual(decoded, {
      program: 'jupiter_v6', kind: 'shared_accounts_route', tokenProgram: KNOWN_PROGRAMS.token,
      programAuthority, userTransferAuthority: taker, userSourceTokenAccount: source,
      userDestinationTokenAccount: destination, programSourceTokenAccount: key(20),
      programDestinationTokenAccount: key(21), sourceMint: mint, destinationMint: outputMint,
      platformFeeAccount: feeAccount, token2022Program: KNOWN_PROGRAMS.token2022, eventAuthority,
      routeAccounts: [poolAccount], inAmount: 250n, quotedOutAmount: 900n, slippageBps: 100, platformFeeBps: 10,
      routePlanStepCount: 3,
    });
  });

  it('rejects every other jupiter entry point', () => {
    for (const name of ['exact_out_route', 'shared_accounts_exact_out_route', 'route_with_token_ledger',
      'shared_accounts_route_with_token_ledger', 'claim', 'set_token_ledger']) {
      assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, routeAccounts(),
        jupiterData({shared: false, name}))), errorIs('UNSUPPORTED_INSTRUCTION'), name);
    }
  });

  it('rejects malformed route data and account layouts', () => {
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, routeAccounts(), bytes([1, 2, 3]))),
      errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, routeAccounts(),
      bytes([...discriminator('route'), ...u32(1)]))), errorIs('INSTRUCTION_INVALID'));
    for (const options of [{steps: 0, planBytes: []}, {steps: 65}, {inAmount: 0n}, {quotedOut: 0n}, {slippageBps: 10_001}]) {
      assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, routeAccounts(),
        jupiterData({shared: false, ...options}))), errorIs('INSTRUCTION_INVALID'), Object.keys(options).join());
    }
    // The program slot must be the Jupiter program itself.
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, routeAccounts({8: poolAccount}),
      jupiterData({shared: false}))), errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, routeAccounts().slice(0, 8),
      jupiterData({shared: false}))), errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, sharedAccounts().slice(0, 12),
      jupiterData({shared: true}))), errorIs('INSTRUCTION_INVALID'));
    // An off-curve authority cannot hold a wallet signature.
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6,
      routeAccounts({1: KNOWN_PROGRAMS.system}), jupiterData({shared: false}))), errorIs('INSTRUCTION_INVALID'));
  });
});

describe('memo and unknown programs', () => {
  it('reports only the memo length', () => {
    assert.deepEqual(decodeInstruction(instruction(KNOWN_PROGRAMS.memo, [taker],
      bytes(Buffer.from('trimmy review', 'utf8')))), {program: 'memo', kind: 'memo', byteLength: 13});
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.memo, [], new Uint8Array())),
      errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.memo, [], new Uint8Array(567))),
      errorIs('INSTRUCTION_INVALID'));
  });

  it('refuses an unknown program and malformed input', () => {
    assert.throws(() => decodeInstruction(instruction(poolAccount, [], new Uint8Array([1]))),
      errorIs('UNSUPPORTED_PROGRAM'));
    assert.throws(() => decodeInstruction(instruction('not-an-address', [], new Uint8Array([1]))),
      errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.system, ['nope', destination],
      bytes(getTransferSolInstructionDataEncoder().encode({amount: 1n})))), errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction({programAddress: KNOWN_PROGRAMS.system, accountAddresses: [taker, destination],
      data: 'AQID' as unknown as Uint8Array}), errorIs('INSTRUCTION_INVALID'));
    assert.throws(() => decodeInstruction(null as unknown as DecodableInstruction), errorIs('INSTRUCTION_INVALID'));
  });

  it('never puts instruction bytes or addresses in the error message', () => {
    try {
      decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, routeAccounts(), jupiterData({shared: false, name: 'claim'})));
      assert.fail('expected a decode error');
    } catch (error) {
      assert.ok(error instanceof InstructionDecodeError);
      assert.equal(error.message, 'The Solana instruction cannot be reviewed.');
      assert.ok(!error.message.includes(taker) && !/[0-9a-f]{16}/.test(error.message));
    }
  });
});

// Captured unsigned mainnet /order instruction data, with deterministic test accounts.
// No wallet secrets, signatures or executable transaction are part of this vector.
describe('Jupiter route_v2', () => {
  const data = Buffer.from('bb64facc31c4af1440420f0000000000e78404000000000032000a000000020000008d00102700012810270102', 'hex');
  const list = [taker, source, destination, mint, outputMint, KNOWN_PROGRAMS.token,
    KNOWN_PROGRAMS.token2022, KNOWN_PROGRAMS.jupiterV6,
    'D8cy77BBepLMngZx6ZukaTff5hCt1HrWyKk3Hnd9oitf', KNOWN_PROGRAMS.jupiterV6, feeAccount, poolAccount];
  it('reads the V2 header and fee recipient without interpreting the plan as the old trailing amounts', () => {
    const decoded = decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, list, data));
    assert.equal(decoded.program, 'jupiter_v6');
    if (decoded.program !== 'jupiter_v6') return;
    assert.equal(decoded.kind, 'route_v2');
    assert.equal(decoded.inAmount, 1_000_000n);
    assert.equal(decoded.quotedOutAmount, 296167n);
    assert.equal(decoded.slippageBps, 50);
    assert.equal(decoded.platformFeeBps, 10);
    assert.equal(decoded.platformFeeAccount, feeAccount);
    assert.equal(decoded.sourceMint, mint);
    assert.equal(decoded.destinationTokenProgram, KNOWN_PROGRAMS.token2022);
    assert.equal(decoded.routePlanStepCount, 2);
    assert.deepEqual(decoded.routeAccounts, [poolAccount]);
  });
  it('rejects truncated plans, redirected output, positive-slippage fees and malformed program slots', () => {
    for (const truncated of [data.subarray(0, 30), data.subarray(0, 38)]) {
      assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, list, truncated)), errorIs('INSTRUCTION_INVALID'));
    }
    for (const index of [7, 8, 9]) {
      const changed = [...list]; changed[index] = poolAccount;
      assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, changed, data)), errorIs('INSTRUCTION_INVALID'));
    }
    const positiveFee = Buffer.from(data); positiveFee.writeUInt16LE(1, 28);
    assert.throws(() => decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, list, positiveFee)), errorIs('UNSUPPORTED_INSTRUCTION'));
  });
  it('preserves the widened fee value and handles no platform fee without consuming a route account', () => {
    const largeFee = Buffer.from(data); largeFee.writeUInt16LE(300, 26);
    const decoded = decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, list, largeFee));
    assert.equal(decoded.program === 'jupiter_v6' && decoded.platformFeeBps, 300);
    const noFee = Buffer.from(data); noFee.writeUInt16LE(0, 26);
    const result = decodeInstruction(instruction(KNOWN_PROGRAMS.jupiterV6, [...list.slice(0, 10), poolAccount], noFee));
    assert.equal(result.program === 'jupiter_v6' && result.platformFeeAccount, null);
  });
});
