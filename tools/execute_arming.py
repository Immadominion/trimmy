#!/usr/bin/env python3
"""Executes a Trimmy arming payment that no public executor has picked up.

## Why this exists

Plimsoll measured that Coston2 runs a public executor and that it is fast — but also that it
"skips what it earns nothing on" (GROUND-TRUTH §10.3). We reproduced that live: a 5 XRP arming
payment carrying `executorFeeUBA = 0` sat unexecuted for 600 seconds and counting.

Separately, nothing in Plimsoll's evidence shows a `0xFE` **Smart Accounts** payment ever being
executed end to end — its measurements used the 48-byte `DIRECT_MINTING_EX` branch. So relying on
somebody else's executor for the branch Trimmy depends on is an unproven assumption, and the
honest move is to be able to execute it ourselves.

This reuses Plimsoll's GATE 3 harness rather than reimplementing the pipeline:

    FDC prepareRequest -> requestAttestation -> wait for proof -> executeDirectMintingWithData

`executeDirectMintingWithData` is the smart-accounts form; `_hasData` is set by *which function was
called*, not by whether the bytes are empty, so the plain form would revert here. The `bytes`
argument is the user-operation pre-image the memo commits to.

## Usage

    source ~/.flare-dart/coston2-test.env
    python3 tools/execute_arming.py \
        --xrpl-tx E41504D3...B6E0 \
        --preimage-file ../arming/out/userop-preimage-v2.hex
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Plimsoll owns this machinery. Trimmy imports it and never edits it.
GATE3 = Path(__file__).resolve().parents[2] / "plimsoll" / "tool" / "gate3"
if not GATE3.is_dir():
    sys.exit(f"Plimsoll GATE 3 harness not found at {GATE3}")
sys.path.insert(0, str(GATE3))

import pipeline  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--xrpl-tx", required=True, help="XRPL transaction id (hex, with or without 0x)")
    ap.add_argument("--preimage-file", required=True, help="file holding the user-op pre-image hex")
    ap.add_argument("--dry-run", action="store_true", help="prepare the request but do not spend")
    ap.add_argument("--voting-round", type=int, default=None,
                    help="resume with an already-paid attestation round instead of buying another")
    args = ap.parse_args()

    key = pipeline.coston2_key()
    proof_owner = pipeline.cast("wallet", "address", "--private-key", key).strip()

    tx = args.xrpl_tx if args.xrpl_tx.startswith("0x") else "0x" + args.xrpl_tx
    tx = tx.lower()

    raw = Path(args.preimage_file).read_text().strip()
    data = bytes.fromhex(raw[2:] if raw.lower().startswith("0x") else raw)

    print(f"executing arming payment")
    print(f"  xrpl tx     : {tx}")
    print(f"  proof owner : {proof_owner}")
    print(f"  data        : {len(data)} bytes (user-operation pre-image)")

    # 1. Ask the verifier for the ABI-encoded attestation request.
    print("\n[1/4] prepareRequest ...")
    encoded = pipeline.prepare_request(tx, proof_owner)
    print(f"      encoded request: {len(encoded)} chars")

    if args.dry_run:
        print("\nDRY RUN — no attestation requested, nothing spent.")
        return 0

    # 2. Submit it to the FdcHub. This costs a fee and is the first irreversible step here.
    if args.voting_round is not None:
        print(f"\n[2/4] reusing already-paid voting round {args.voting_round}")
        voting_round = args.voting_round
    else:
        print("\n[2/4] requestAttestation ...")
        submitted = pipeline.request_attestation(encoded, key)
        # The key is `votingRoundId`. Read the function rather than guessing its shape: an earlier
        # version used `voting_round`, raised KeyError *after* the fee had already been paid, and
        # threw away the round number with it. Hence --voting-round, to resume without paying twice.
        voting_round = submitted["votingRoundId"]
        print(f"      tx           : {submitted['transactionHash']}")
        print(f"      voting round : {voting_round}  (fee {submitted['feeWei']} wei)")

    # 3. Wait for the round to finalise and the DA layer to serve the proof.
    print("\n[3/4] waiting for proof (rounds are usually <2 min; one took 15) ...")
    proof = pipeline.wait_for_proof(encoded, voting_round)
    print("      proof retrieved")

    # 4. Mint. A revert here is informative, not exceptional — report it rather than raise.
    print("\n[4/4] executeDirectMintingWithData ...")
    outcome = pipeline.execute_direct_minting(proof, data, key)
    print(f"      outcome: {outcome}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
