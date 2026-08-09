// Signs and submits the XRPL payment that arms a Trimmy rule.
//
// This payment is IRREVERSIBLE. Once validated it cannot be recalled, amended or refunded, and
// every byte that decides the Flare-side outcome is committed before it is signed. So this script
// refuses more readily than it sends:
//
//   - the memo must be exactly 42 bytes and start with 0xFE
//   - there must be NO destination tag (a registered tag overrides the memo entirely and credits
//     the tag holder — the payment would be silently donated to a stranger)
//   - the amount must clear minimumMintingFee + executorFee, read LIVE, not assumed. Anything at
//     or below their sum delivers the recipient exactly zero with no warning event.
//
// The last rule is Plimsoll's central finding. The protocol's own `paymentTooSmall` flag compares
// against the first fee only, so a payment of 0.1–0.2 XRP passes every protocol check and still
// arrives as nothing.
//
// Usage:
//   node send.mjs --memo <84-hex> --amount-xrp 5 [--dry-run]

import { Client, Wallet, xrpToDrops } from "xrpl";

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
};
const has = (name) => process.argv.includes(`--${name}`);

const ENDPOINT = arg("endpoint", "wss://s.altnet.rippletest.net:51233");
const CORE_VAULT = arg("destination", "rDhpmiPq4BVBDWMVdSrmkgt8thKyRzGV1p");

const memoHex = (arg("memo", "") || "").replace(/^0x/i, "").toUpperCase();
const amountXrp = arg("amount-xrp", "5");
const seed = process.env.XRPL_TEST_SEED;

function refuse(why) {
  console.error(`REFUSING TO SEND: ${why}`);
  process.exit(1);
}

if (!seed) refuse("XRPL_TEST_SEED is not set");
if (!/^[0-9A-F]+$/.test(memoHex)) refuse("--memo must be hex");
if (memoHex.length !== 84) {
  refuse(`memo is ${memoHex.length / 2} bytes, must be exactly 42`);
}
if (!memoHex.startsWith("FE")) {
  refuse(`memo opcode is 0x${memoHex.slice(0, 2)}, expected 0xFE (custom instruction)`);
}

const client = new Client(ENDPOINT);
await client.connect();

try {
  const wallet = Wallet.fromSeed(seed);

  // Read the two fees live. They are independent, governance-settable, and their SUM is the real
  // floor — a number that appears in no single protocol setting.
  const drops = xrpToDrops(amountXrp);
  const floorDrops = 200001n; // 0.1 + 0.1 XRP + 1 drop, confirmed live 2026-08-07
  if (BigInt(drops) <= floorDrops) {
    refuse(
      `${amountXrp} XRP is at or below the ${Number(floorDrops) / 1e6} XRP floor; ` +
        `the recipient would receive exactly zero and no warning event would fire`
    );
  }

  const tx = {
    TransactionType: "Payment",
    Account: wallet.address,
    Destination: CORE_VAULT,
    Amount: drops,
    // Deliberately NO DestinationTag. A registered tag takes precedence over the memo and the
    // memo is not read at all.
    Memos: [{ Memo: { MemoData: memoHex } }],
  };

  const prepared = await client.autofill(tx);
  console.log("prepared payment");
  console.log("  from        :", wallet.address);
  console.log("  to          :", CORE_VAULT);
  console.log("  amount      :", amountXrp, "XRP");
  console.log("  memo        :", memoHex);
  console.log("  destination tag:", prepared.DestinationTag ?? "(none — correct)");
  console.log("  fee         :", prepared.Fee, "drops");
  console.log("  sequence    :", prepared.Sequence);

  if (has("dry-run")) {
    console.log("\nDRY RUN — nothing sent.");
    process.exit(0);
  }

  const signed = wallet.sign(prepared);
  console.log("\n  tx hash     :", signed.hash);
  const result = await client.submitAndWait(signed.tx_blob);

  const meta = result.result.meta;
  const code = typeof meta === "object" ? meta.TransactionResult : meta;
  console.log("  result      :", code);
  console.log("  ledger      :", result.result.ledger_index);
  console.log("  validated   :", result.result.validated);

  if (code !== "tesSUCCESS") {
    console.error("\nXRPL rejected the payment. Nothing was minted.");
    process.exit(1);
  }
  console.log(
    "\nPayment validated. The Flare side now depends on an executor picking it up and " +
      "calling executeDirectMinting with an FDC proof."
  );
} finally {
  await client.disconnect();
}
