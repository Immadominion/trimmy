// The two read-only chain calls the arming page needs.
//
// These live here rather than inside a <script> tag so they can be tested against the live chain.
// The bug that made this file necessary was a hand-written ABI offset read from the wrong head
// slot, it produced a plausible-looking number and walked off the end of the buffer. Encoding is
// not the place for code that nothing exercises.

import { keccak256 } from './keccak.js';
import { abiAddressWord, abiWord, concat, fromHex, toHex } from './arming.js';

export const CONTROLLER = '0x434936d47503353f06750Db1A444DBDC5F0AD37c';
export const RPC_COSTON2 = 'https://coston2-api.flare.network/ext/C/rpc';

const selector = (sig) => keccak256(new TextEncoder().encode(sig)).slice(0, 4);

/**
 * `getPersonalAccount(string)`
 *
 * One dynamic argument, so the calldata is: selector, offset-to-string (0x20), length, then the
 * UTF-8 bytes padded up to a whole word.
 */
export function encodeGetPersonalAccount(xrplAddress) {
  const bytes = new TextEncoder().encode(xrplAddress);
  const padded = new Uint8Array(Math.ceil(bytes.length / 32) * 32 || 32);
  padded.set(bytes);
  return concat([
    selector('getPersonalAccount(string)'),
    abiWord(32n),
    abiWord(BigInt(bytes.length)),
    padded,
  ]);
}

/** `getNonce(address)` */
export const encodeGetNonce = (personalAccount) =>
  concat([selector('getNonce(address)'), abiAddressWord(personalAccount)]);

export async function ethCall(to, data, { rpc = RPC_COSTON2, fetchImpl = fetch } = {}) {
  const res = await fetchImpl(rpc, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0', id: 1, method: 'eth_call',
      params: [{ to, data: '0x' + toHex(data) }, 'latest'],
    }),
  });
  const json = await res.json();
  if (json.error) throw new Error(json.error.message);
  return fromHex(json.result);
}

export class UnknownAccount extends Error {}

export const REGISTRY = '0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019';

/// Measured, and the reason this matters: a payment that does not clear the minting fee is not
/// rejected. The protocol emits its SUCCESS event carrying `mintedAmountUBA: 0`, pays every party
/// except the recipient, and the XRP is gone. Plimsoll caught this with a real 0.15 XRP payment
/// whose logs show two Transfers, neither of them to the intended account.
export const MINTING_FEE_UBA = 100000n;

/**
 * Reads the direct-minting executor fee from the live AssetManager.
 *
 * Governance can change it, and if it rises above what a payment carries, the payment is not
 * refused, it is silently under-delivered. So it is read rather than assumed, with the measured
 * value only as a fallback when the read fails.
 */
export async function readExecutorFeeUBA(opts = {}) {
  const sel = (sig) => keccak256(new TextEncoder().encode(sig)).slice(0, 4);
  const strArg = (s) => {
    const b = new TextEncoder().encode(s);
    const padded = new Uint8Array(Math.ceil(b.length / 32) * 32 || 32);
    padded.set(b);
    return concat([abiWord(32n), abiWord(BigInt(b.length)), padded]);
  };

  const controller = '0x' + toHex(
    (await ethCall(REGISTRY, concat([
      sel('getContractAddressByName(string)'), strArg('AssetManagerController'),
    ]), opts)).slice(-20),
  );

  // getAssetManagers() returns address[]: offset word, length word, then the elements.
  const managers = await ethCall(controller, sel('getAssetManagers()'), opts);
  const first = '0x' + toHex(managers.slice(64 + 12, 64 + 32));

  const raw = await ethCall(first, sel('getDirectMintingExecutorFeeUBA()'), opts);
  let fee = 0n;
  for (const b of raw) fee = (fee << 8n) | BigInt(b);
  if (fee <= 0n) throw new Error('executor fee read as zero');
  return { fee, assetManager: first };
}

/**
 * Resolves an XRPL address to the Flare account it controls, and that account's next instruction
 * number.
 *
 * A zero address means Flare has never seen this XRPL account. Returning it as a valid answer
 * would build a payment whose allowance lands on an empty account, permanently, since the payment
 * cannot be recalled.
 */
export async function lookupAccount(xrplAddress, opts = {}) {
  const raw = await ethCall(CONTROLLER, encodeGetPersonalAccount(xrplAddress), opts);
  const personalAccount = '0x' + toHex(raw.slice(-20));
  if (/^0x0+$/.test(personalAccount)) {
    throw new UnknownAccount('Flare has no account for this XRPL address yet');
  }
  const nonceRaw = await ethCall(CONTROLLER, encodeGetNonce(personalAccount), opts);
  let nonce = 0n;
  for (const b of nonceRaw) nonce = (nonce << 8n) | BigInt(b);
  return { xrplAddress, personalAccount, nonce };
}
