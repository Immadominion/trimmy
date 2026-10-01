/**
 * Minimal, dependency-free Solana wire checks around the one signing step.
 *
 * The API reviews, simulates and binds the exact transaction; this module only
 * proves locally that the wallet is asked to sign that transaction, that the
 * user fills their own signer slot and nothing else, and that the message is
 * unchanged. An aggregator order has one signer (the user). A JupiterZ RFQ
 * order has two: the market maker pays the fee from slot 0 and signs later
 * through Jupiter, so its slot must stay empty here. The server verifies again
 * (apps/api/src/live-stock-orders.ts verifyReviewedSignature).
 */
export const MAX_TRANSACTION_BYTES = 1232;
/** The API's limit on the signed transaction it accepts, in base64 characters. */
export const MAX_SIGNED_TRANSACTION_BASE64 = 1644;
const ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

export class TransactionCheckError extends Error {
  constructor(readonly code: 'INVALID_TRANSACTION' | 'WALLET_NOT_SIGNER' | 'SIGNATURE_MISMATCH' | 'ROUTE_MISMATCH') {
    super(code); this.name = 'TransactionCheckError';
  }
}
const invalid = (): never => {throw new TransactionCheckError('INVALID_TRANSACTION');};

export function base58Encode(bytes: Uint8Array): string {
  let zeros = 0;
  while (zeros < bytes.length && bytes[zeros] === 0) zeros++;
  let value = 0n;
  for (const byte of bytes) value = value * 256n + BigInt(byte);
  let out = '';
  while (value > 0n) {out = ALPHABET[Number(value % 58n)]! + out; value /= 58n;}
  return '1'.repeat(zeros) + out;
}

export function base58Decode(text: string, expectedLength?: number): Uint8Array {
  if (text.length === 0 || text.length > 128) invalid();
  let value = 0n, zeros = 0;
  for (let index = 0; index < text.length; index++) {
    const digit = ALPHABET.indexOf(text[index]!);
    if (digit < 0) invalid();
    if (index === zeros && digit === 0) zeros++;
    value = value * 58n + BigInt(digit);
  }
  const body: number[] = [];
  while (value > 0n) {body.unshift(Number(value & 255n)); value >>= 8n;}
  const bytes = new Uint8Array(zeros + body.length);
  bytes.set(body, zeros);
  if (expectedLength !== undefined && bytes.length !== expectedLength) invalid();
  return bytes;
}

export function base64ToBytes(text: string): Uint8Array {
  if (typeof text !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(text) || text.length % 4 !== 0) invalid();
  let binary: string;
  try {binary = atob(text);} catch {return invalid();}
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  if (bytesToBase64(bytes) !== text) invalid();
  return bytes;
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let index = 0; index < bytes.length; index += 0x8000) binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
  return btoa(binary);
}

function compactU16(bytes: Uint8Array, offset: number): [number, number] {
  let value = 0;
  for (let index = 0; index < 3; index++) {
    const byte = bytes[offset + index];
    if (byte === undefined) invalid();
    value |= (byte! & 0x7f) << (7 * index);
    if ((byte! & 0x80) === 0) {
      // Reject non-canonical encodings such as 0x80 0x00.
      if (index > 0 && byte === 0 || value > 65535) invalid();
      return [value, offset + index + 1];
    }
  }
  return invalid();
}

export interface ParsedTransaction {
  readonly signatures: readonly Uint8Array[];
  readonly messageBytes: Uint8Array;
  /** The first N static account keys, in signature slot order. */
  readonly signers: readonly string[];
  readonly version: 'legacy' | 0;
  readonly accounts: readonly string[];
  readonly writable: readonly boolean[];
  readonly instructions: readonly {programIndex: number; accounts: readonly number[]; data: Uint8Array}[];
  readonly lookupCount: number;
}

export function parseTransaction(bytes: Uint8Array): ParsedTransaction {
  if (bytes.length < 1 + 64 + 3 || bytes.length > MAX_TRANSACTION_BYTES) invalid();
  const [count, start] = compactU16(bytes, 0);
  if (count < 1 || count > 12) invalid();
  const messageStart = start + count * 64;
  if (messageStart >= bytes.length) invalid();
  const signatures = Array.from({length: count}, (_, index) => bytes.slice(start + index * 64, start + (index + 1) * 64));
  const messageBytes = bytes.slice(messageStart);
  let cursor = 0;
  let version: 'legacy' | 0 = 'legacy';
  if (messageBytes[0]! & 0x80) {
    if ((messageBytes[0]! & 0x7f) !== 0) invalid();
    version = 0; cursor = 1;
  }
  const required = messageBytes[cursor], readonlySigned = messageBytes[cursor + 1], readonlyUnsigned = messageBytes[cursor + 2];
  if (required === undefined || readonlySigned === undefined || readonlyUnsigned === undefined || readonlySigned >= required) return invalid();
  cursor += 3;
  const [keyCount, keysStart] = compactU16(messageBytes, cursor);
  if (keyCount < required || keyCount > 256 || readonlyUnsigned > keyCount - required || keysStart + keyCount * 32 + 32 > messageBytes.length) invalid();
  if (required !== count) invalid();
  const accounts = Array.from({length: keyCount}, (_, index) =>
    base58Encode(messageBytes.slice(keysStart + index * 32, keysStart + (index + 1) * 32)));
  if (new Set(accounts).size !== accounts.length) invalid();
  const writable = accounts.map((_, index) => index < required ? index < required - readonlySigned : index < keyCount - readonlyUnsigned);
  const signers = accounts.slice(0, required);
  cursor = keysStart + keyCount * 32 + 32;
  let instructionCount; [instructionCount, cursor] = compactU16(messageBytes, cursor);
  if (instructionCount < 1 || instructionCount > 64) invalid();
  const instructions: {programIndex: number; accounts: number[]; data: Uint8Array}[] = [];
  for (let i = 0; i < instructionCount; i++) {
    const programIndex = messageBytes[cursor++];
    if (programIndex === undefined) return invalid();
    let n; [n, cursor] = compactU16(messageBytes, cursor);
    if (n > 256 || cursor + n > messageBytes.length) invalid();
    const indexes = [...messageBytes.slice(cursor, cursor + n)]; cursor += n;
    [n, cursor] = compactU16(messageBytes, cursor);
    if (cursor + n > messageBytes.length) invalid();
    const data = messageBytes.slice(cursor, cursor + n); cursor += n;
    instructions.push({programIndex, accounts: indexes, data});
  }
  let lookupCount = 0, loaded = 0;
  if (version === 0) {
    [lookupCount, cursor] = compactU16(messageBytes, cursor);
    if (lookupCount > 32) invalid();
    for (let i = 0; i < lookupCount; i++) {
      cursor += 32;
      for (let kind = 0; kind < 2; kind++) {
        let n; [n, cursor] = compactU16(messageBytes, cursor);
        if (n > 256 || cursor + n > messageBytes.length) invalid();
        cursor += n; loaded += n;
      }
    }
  }
  if (cursor !== messageBytes.length || keyCount + loaded > 256 || instructions.some(ix =>
    ix.programIndex >= keyCount || ix.accounts.some(index => index >= keyCount + loaded))) invalid();
  return Object.freeze({signatures: Object.freeze(signatures), messageBytes, signers: Object.freeze(signers), version,
    accounts: Object.freeze(accounts), writable: Object.freeze(writable), instructions: Object.freeze(instructions), lookupCount});
}

const empty = (signature: Uint8Array) => signature.every(byte => byte === 0);
const sameBytes = (left: Uint8Array, right: Uint8Array) => left.length === right.length && left.every((byte, index) => byte === right[index]);

export interface SigningPlan {
  readonly bytes: Uint8Array; readonly parsed: ParsedTransaction; readonly slot: number;
  readonly route: 'aggregator' | 'rfq';
}

/**
 * The exact reviewed transaction, checked before the wallet sees it: one signer
 * (aggregator) with the user as fee payer, or two (RFQ) with the market maker in
 * slot 0 and the user in slot 1. No slot may already carry a signature.
 */
export function planSigning(transaction: string, wallet: string, route: 'aggregator' | 'rfq' | null): SigningPlan {
  const bytes = base64ToBytes(transaction);
  const parsed = parseTransaction(bytes);
  if (parsed.signatures.length > 2 || parsed.signatures.some(signature => !empty(signature))) invalid();
  const slot = parsed.signers.indexOf(wallet);
  if (slot < 0 || parsed.signers.lastIndexOf(wallet) !== slot) throw new TransactionCheckError('WALLET_NOT_SIGNER');
  const actual = parsed.signatures.length === 2 ? 'rfq' : 'aggregator';
  if (route !== null && route !== actual || actual === 'rfq' && slot !== 1 || actual === 'aggregator' && slot !== 0) {
    throw new TransactionCheckError('ROUTE_MISMATCH');
  }
  return Object.freeze({bytes, parsed, slot, route: actual});
}

/** Proves the wallet filled only the user's slot of the unchanged message. */
export async function checkSignedTransaction(plan: SigningPlan, signed: Uint8Array, wallet: string,
  verify: (key: Uint8Array, signature: Uint8Array, message: Uint8Array) => Promise<boolean | null> = verifyEd25519): Promise<string> {
  if (!(signed instanceof Uint8Array) || signed.length > MAX_TRANSACTION_BYTES) throw new TransactionCheckError('SIGNATURE_MISMATCH');
  let after: ParsedTransaction;
  try {after = parseTransaction(signed);} catch {throw new TransactionCheckError('SIGNATURE_MISMATCH');}
  if (!sameBytes(after.messageBytes, plan.parsed.messageBytes) || after.signatures.length !== plan.parsed.signatures.length ||
      after.signers.some((key, index) => key !== plan.parsed.signers[index])) throw new TransactionCheckError('SIGNATURE_MISMATCH');
  for (let index = 0; index < after.signatures.length; index++) {
    const filled = !empty(after.signatures[index]!);
    if (index === plan.slot ? !filled : filled) throw new TransactionCheckError('SIGNATURE_MISMATCH');
  }
  const verified = await verify(base58Decode(wallet, 32), after.signatures[plan.slot]!, after.messageBytes);
  if (verified === false) throw new TransactionCheckError('SIGNATURE_MISMATCH');
  const encoded = bytesToBase64(signed);
  if (encoded.length > MAX_SIGNED_TRANSACTION_BASE64) throw new TransactionCheckError('SIGNATURE_MISMATCH');
  return encoded;
}

/** Ed25519 check where the browser supports it; null means unsupported (the server still verifies). */
export async function verifyEd25519(key: Uint8Array, signature: Uint8Array, message: Uint8Array): Promise<boolean | null> {
  const subtle = globalThis.crypto?.subtle;
  if (!subtle) return null;
  let imported: CryptoKey;
  try {imported = await subtle.importKey('raw', key as BufferSource, {name: 'Ed25519'}, false, ['verify']);}
  catch {return null;}
  try {return await subtle.verify({name: 'Ed25519'}, imported, signature as BufferSource, message as BufferSource);}
  catch {return false;}
}
