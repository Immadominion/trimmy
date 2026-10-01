import {address, getAddressEncoder, getProgramDerivedAddress} from '@solana/addresses';
import {planSigning, TransactionCheckError} from './solana-wire.js';
import type {TransferReview} from './wallet-transfer-client.js';
import {USDC_MINT} from './amounts.js';

const SYSTEM = '11111111111111111111111111111111';
const COMPUTE = 'ComputeBudget111111111111111111111111111111';
const ATA = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const TOKEN = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const TOKEN_2022 = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
const reject = (): never => {throw new TransactionCheckError('INVALID_TRANSACTION');};
const raw = (value: string): bigint => {
  if (!/^(?:0|[1-9][0-9]{0,19})$/.test(value) || BigInt(value) > 18446744073709551615n) return reject();
  return BigInt(value);
};
const little = (bytes: Uint8Array, start: number, size: number): bigint => {
  if (start + size > bytes.length) return reject();
  let out = 0n; for (let i = size - 1; i >= 0; i--) out = out * 256n + BigInt(bytes[start + i]!);
  return out;
};
const equal = (actual: readonly string[], expected: readonly string[]) =>
  actual.length === expected.length && actual.every((value, index) => value === expected[index]);
async function associated(owner: string, mint: string, program: string): Promise<string> {
  const encode = getAddressEncoder();
  const [key] = await getProgramDerivedAddress({programAddress: address(ATA),
    seeds: [encode.encode(address(owner)), encode.encode(address(program)), encode.encode(address(mint))]});
  return key;
}

/** Offline intent checks. No server-provided account resolution or instruction labels are trusted.
 * Reject hook account lists, lookup tables, delegates, extra transfers and unknown programs.
 * Token-2022 received amount/rent remain simulation estimates; this does not certify issuer behavior.
 */
export async function checkSendTransaction(input: TransferReview): Promise<void> {
  const review = {...input}; // Capture the approved intent before any async PDA derivation.
  const plan = planSigning(review.unsignedTransaction, review.from, 'aggregator'), tx = plan.parsed;
  if (tx.lookupCount !== 0 || review.from === review.destination) return reject();
  address(review.destination);
  const amount = raw(review.amountRaw), received = raw(review.receivedRaw), fee = raw(review.networkFeeLamports), rent = raw(review.accountRentLamports);
  if (amount === 0n || received === 0n || received > amount || fee > 25000n || rent > 10000000n ||
      !Number.isInteger(review.decimals) || review.decimals < 0 || review.decimals > 18) return reject();
  const isSol = review.assetId === 'SOL', mint = review.assetId === 'USDC' ? USDC_MINT : review.assetId;
  if (isSol && (review.decimals !== 9 || review.createsAccount || rent !== 0n || received !== amount) ||
      review.assetId === 'USDC' && (review.decimals !== 6 || received !== amount) ||
      !review.createsAccount && rent !== 0n || review.createsAccount && rent === 0n) return reject();
  let units: bigint | null = null, price: bigint | null = null, transfers = 0, creations = 0;
  let transferProgram: string | null = null, creationProgram: string | null = null;
  const writable = new Set<string>([review.from]);
  for (const ix of tx.instructions) {
    const program = tx.accounts[ix.programIndex]!, keys = ix.accounts.map(index => tx.accounts[index]!);
    if (tx.writable[ix.programIndex]) return reject();
    if (program === COMPUTE) {
      if (keys.length !== 0) return reject();
      if (ix.data.length === 5 && ix.data[0] === 2 && units === null) units = little(ix.data, 1, 4);
      else if (ix.data.length === 9 && ix.data[0] === 3 && price === null) price = little(ix.data, 1, 8);
      else return reject();
    } else if (program === SYSTEM && isSol) {
      if (++transfers !== 1 || ix.data.length !== 12 || little(ix.data, 0, 4) !== 2n ||
          little(ix.data, 4, 8) !== amount || !equal(keys, [review.from, review.destination])) return reject();
      writable.add(review.destination);
    } else if (!isSol && (program === TOKEN || program === TOKEN_2022)) {
      if (++transfers !== 1 || keys.length !== 4 || ix.data.length !== 10 || ix.data[0] !== 12 ||
          little(ix.data, 1, 8) !== amount || ix.data[9] !== review.decimals) return reject();
      if (review.assetId === 'USDC' && program !== TOKEN) return reject();
      const source = await associated(review.from, mint, program), destination = await associated(review.destination, mint, program);
      if (!equal(keys, [source, mint, destination, review.from])) return reject();
      transferProgram = program; writable.add(source); writable.add(destination);
    } else if (!isSol && program === ATA) {
      if (++creations !== 1 || transfers !== 0 || !review.createsAccount || keys.length !== 6 || ix.data.length !== 1 || ix.data[0] !== 1 ||
          ![TOKEN, TOKEN_2022].includes(keys[5]!)) return reject();
      const tokenProgram = keys[5]!, destination = await associated(review.destination, mint, tokenProgram);
      if (!equal(keys, [review.from, destination, review.destination, mint, SYSTEM, tokenProgram])) return reject();
      creationProgram = tokenProgram; writable.add(destination);
    } else return reject();
  }
  if (transfers !== 1 || creations !== (review.createsAccount ? 1 : 0) || creationProgram !== null && creationProgram !== transferProgram ||
      units === null || units < 1n || units > 200000n || price === null || price > 100000n ||
      5000n + (units * price + 999999n) / 1000000n !== fee) return reject();
  // Extra writable accounts can be used as side effects by programs; none are needed for a plain send.
  if (tx.accounts.some((key, index) => tx.writable[index] !== writable.has(key))) return reject();
}
