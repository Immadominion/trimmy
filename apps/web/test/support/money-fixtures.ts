/** Test-only builders for own-money contracts: real Solana wire bytes, holdings v2 and live orders. */
import {webcrypto} from 'node:crypto';
import {base58Encode, base58Decode, bytesToBase64} from '../../src/product/money/solana-wire.js';
import {USDC_MINT} from '../../src/product/money/amounts.js';

export const ACCOUNT_ID = '11111111-1111-4111-8111-111111111111';
export const SUBJECT = 'did:privy:accountA';
export const AAPLX = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
export const ONDO_AAPL = '123mYEnRLM2LLYsJW3K6oyYh8uP1fngj732iG638ondo';
export const JUPITER = 'JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4';
const GENESIS = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';

export interface Signer {readonly address: string; readonly publicKey: Uint8Array; sign(message: Uint8Array): Promise<Uint8Array>}
export async function signer(): Promise<Signer> {
  const pair = await webcrypto.subtle.generateKey({name: 'Ed25519'}, true, ['sign', 'verify']) as unknown as CryptoKeyPair;
  const publicKey = new Uint8Array(await webcrypto.subtle.exportKey('raw', pair.publicKey));
  return {address: base58Encode(publicKey), publicKey,
    async sign(message) {return new Uint8Array(await webcrypto.subtle.sign({name: 'Ed25519'}, pair.privateKey, message as BufferSource));}};
}

function compact(value: number): number[] {
  const out: number[] = [];
  for (;;) {const byte = value & 0x7f; value >>= 7; if (value) out.push(byte | 0x80); else {out.push(byte); return out;}}
}

/** One transfer-shaped instruction from a readonly program; enough for decoders to accept the message. */
export function message(signers: readonly string[], options: {version?: 'legacy' | 0; extra?: readonly string[]} = {}): Uint8Array {
  const keys = [...signers, ...(options.extra ?? []), JUPITER].map(key => base58Decode(key, 32));
  const header = [signers.length, 0, 1];
  const instruction = [keys.length - 1, ...compact(1), 0, ...compact(3), 1, 2, 3];
  const bytes = [...(options.version === 0 ? [0x80] : []), ...header, ...compact(keys.length), ...keys.flatMap(key => [...key]),
    ...base58Decode(GENESIS, 32), ...compact(1), ...instruction, ...(options.version === 0 ? compact(0) : [])];
  return new Uint8Array(bytes);
}
export function unsigned(messageBytes: Uint8Array, signatureCount: number): Uint8Array {
  return new Uint8Array([...compact(signatureCount), ...new Uint8Array(64 * signatureCount), ...messageBytes]);
}
/** What an embedded wallet returns: the user's slot filled, every other slot left as it was. */
export async function signSlot(transaction: Uint8Array, slot: number, key: Signer): Promise<Uint8Array> {
  const count = transaction[0]!;
  const messageBytes = transaction.slice(1 + count * 64);
  const out = transaction.slice();
  out.set(await key.sign(messageBytes), 1 + slot * 64);
  return out;
}

export function orderJson(options: {id?: string; status?: string; wallet: string; transaction?: string | null; route?: 'aggregator' | 'rfq';
  side?: 'buy' | 'sell'; mint?: string; amountRaw?: string; expiresAt?: string; signature?: string | null; confirmedSlot?: number;
  reviewFlags?: string[]; terms?: Record<string, unknown>}) {
  const side = options.side ?? 'buy', mint = options.mint ?? AAPLX;
  return {id: options.id ?? '44444444-4444-4444-8444-444444444444', status: options.status ?? 'reviewed', wallet: options.wallet,
    signature: options.signature ?? null, expiresAt: options.expiresAt ?? new Date(Date.now() + 30_000).toISOString(),
    reviewDigest: 'a'.repeat(64), ...(options.confirmedSlot ? {confirmedSlot: options.confirmedSlot} : {}),
    terms: {side, inputMint: side === 'buy' ? USDC_MINT : mint, outputMint: side === 'buy' ? mint : USDC_MINT,
      inputAmountRaw: options.amountRaw ?? '5000000', quotedOutputAmountRaw: side === 'buy' ? '1960000' : '4900000',
      minimumOutputAmountRaw: side === 'buy' ? '1950000' : '4850000', slippageBps: 50, platformFeeBps: 20,
      totalLamportsUpperBound: '2044280', simulatedOutputReceivedRaw: side === 'buy' ? '1960000' : '4900000',
      simulatedTakerLamportsSpent: '5000', stockUiMultiplier: '1.0009180758490996', route: options.route ?? 'aggregator',
      ...options.terms},
    reviewFlags: options.reviewFlags ?? ['output_mint_scaled_ui_amount'],
    ...(options.transaction ? {transaction: options.transaction} : {})};
}

export function token(fields: Record<string, unknown> = {}) {
  return {symbol: 'USDC', mint: USDC_MINT, decimals: 6, amountRaw: '25000000', amountUnits: 'raw_token_units', observedSlot: 400,
    accountCount: 1, accountTopology: 'associated_only', aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false,
    ...fields};
}
export function holdingsJson(wallet: string, options: {usdc?: string; usdcAvailable?: string; lamports?: string; slot?: number;
  tokens?: Record<string, unknown>[]; version?: 1 | 2; userId?: string; observedAt?: string} = {}) {
  const slot = options.slot ?? 400, version = options.version ?? 2;
  const usdc = token({amountRaw: options.usdc ?? '25000000', observedSlot: slot,
    ...(version === 2 ? {availableToTradeRaw: options.usdcAvailable ?? options.usdc ?? '25000000'} : {})});
  const aaplx = token({symbol: 'AAPLx', mint: AAPLX, decimals: 8, amountRaw: '0', accountCount: 0, accountTopology: 'none', observedSlot: slot,
    displayResolution: 'token_2022_scaled_ui_unresolved', displayAmount: null, shareAmount: null, eligibility: 'unverified', executionEnabled: false});
  return {schemaVersion: version, userId: options.userId ?? ACCOUNT_ID,
    wallet: {address: wallet, source: 'privy_embedded_wallet_same_subject', possessionSignatureVerified: false},
    holdings: {network: 'solana:mainnet-beta', genesisHash: GENESIS, commitment: 'confirmed',
      observedAt: options.observedAt ?? new Date().toISOString(), readOnly: true, transactionBuilt: false, transactionSigned: false,
      transactionBroadcast: false,
      balances: {nativeSol: {symbol: 'SOL', decimals: 9, amountRaw: options.lamports ?? '21000000', amountUnits: 'lamports', observedSlot: slot},
        usdc, aaplx, ...(version === 2 ? {tokens: options.tokens ?? []} : {})},
      consistency: {kind: 'independent_confirmed_reads', atomic: false, slots: {nativeSol: slot, usdc: slot, aaplx: slot}}}};
}
export function stockHolding(fields: Record<string, unknown> = {}) {
  return token({assetId: 'spacex', name: 'SpaceX xStock', symbol: 'SPCXx', mint: 'Xs3oZwbHvqis4NYcf4YKWmEia2eC84wSiVrcYcTqpH8', decimals: 8,
    amountRaw: '150000000', availableToTradeRaw: '150000000', displayAmount: '1.5013771', displayResolution: 'rpc_ui_amount',
    displayUnits: 'token_units', ...fields});
}
export function contextJson(wallet: string | null, status: 'candidate' | 'missing' | 'ambiguous' = wallet ? 'candidate' : 'missing') {
  return {schemaVersion: 1, userId: ACCOUNT_ID, xIdentity: {status: 'missing'},
    embeddedSolanaWallet: status === 'candidate' ? {status, address: wallet, verifiedAtUnixSeconds: 1_790_000_000} : {status}};
}
export {bytesToBase64};
