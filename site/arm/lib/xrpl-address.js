// XRPL address validation, with the checksum actually checked.
//
// This is not cosmetic input validation. `MasterAccountController.getPersonalAccount(string)` is a
// **deterministic derivation, not a registry lookup**, measured on Coston2, it returns a
// plausible-looking account for any string at all:
//
//   rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB  ->  0x07a76b5c…      (the real one)
//   rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsA  ->  0x6085dbe8…      (one character changed)
//   not-an-address                      ->  0xff16dc7a…      (not an address at all)
//
// So a typo does not fail. It silently produces a different Flare account, and an arming payment
// built against it would set an allowance and arm a rule on an account the sender does not
// control, irreversibly, because the XRPL payment cannot be recalled.
//
// A base58check address carries its own 4-byte checksum precisely so this class of typo is
// detectable offline. We check it before anything else happens.

const ALPHABET = 'rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz';
const INDEX = new Map([...ALPHABET].map((c, i) => [c, i]));

const ACCOUNT_PREFIX = 0x00;   // 'r' addresses
const PAYLOAD_LENGTH = 21;     // 1 prefix byte + 20 account id bytes

export class InvalidAddress extends Error {}

/** Decodes XRPL base58 into bytes. Throws on any character outside the alphabet. */
function base58Decode(s) {
  let num = 0n;
  for (const ch of s) {
    const v = INDEX.get(ch);
    if (v === undefined) throw new InvalidAddress(`"${ch}" is not a valid character in an XRPL address`);
    num = num * 58n + BigInt(v);
  }

  const bytes = [];
  while (num > 0n) { bytes.unshift(Number(num & 0xffn)); num >>= 8n; }

  // Each leading '1'... in XRPL's alphabet the zero character is 'r', and leading zeros are
  // significant, so they must be restored as leading zero bytes.
  for (const ch of s) {
    if (ch !== ALPHABET[0]) break;
    bytes.unshift(0);
  }
  return new Uint8Array(bytes);
}

async function sha256(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return new Uint8Array(digest);
}

/**
 * Validates an XRPL classic address and returns it unchanged.
 *
 * @throws {InvalidAddress} with a message meant for a person, not a log.
 */
export async function validateXrplAddress(address) {
  const s = String(address ?? '').trim();
  if (!s) throw new InvalidAddress('Enter your XRPL address.');
  if (!s.startsWith('r')) {
    throw new InvalidAddress('An XRPL address starts with "r".');
  }
  if (s.length < 25 || s.length > 35) {
    throw new InvalidAddress(`That is ${s.length} characters; an XRPL address is 25 to 35.`);
  }

  const decoded = base58Decode(s);
  if (decoded.length !== PAYLOAD_LENGTH + 4) {
    throw new InvalidAddress('That is not a well-formed XRPL address.');
  }

  const payload = decoded.slice(0, PAYLOAD_LENGTH);
  const checksum = decoded.slice(PAYLOAD_LENGTH);
  if (payload[0] !== ACCOUNT_PREFIX) {
    throw new InvalidAddress('That is not an XRPL account address.');
  }

  const expected = (await sha256(await sha256(payload))).slice(0, 4);
  for (let i = 0; i < 4; i++) {
    if (expected[i] !== checksum[i]) {
      // The whole point of the checksum: say plainly that this is a typo, because the contract
      // downstream will happily derive an account from it and never complain.
      throw new InvalidAddress(
        'That address fails its own checksum, so it is mistyped. Copy it from your wallet rather ' +
        'than retyping it.',
      );
    }
  }
  return s;
}
