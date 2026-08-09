#!/usr/bin/env python3
"""Independent reference implementation of Quote.convert, and a vector generator.

Why this exists
---------------
`trimmy/AGENTS.md` (verification standard): "A test that exercises our own implementation on both
sides proves self-consistency and nothing else."

`Quote.sol` uses `Math.mulDiv` with a 512-bit intermediate and checked 256-bit arithmetic. This file
uses Python's arbitrary-precision integers and a directly transcribed formula. The two share no
code, no language and no overflow behaviour, so agreement between them is evidence.

The formula is re-derived here from the FTSO definition rather than copied from the Solidity, so a
mistake in the derivation would have to be made twice, identically, to go unnoticed:

    price      = value * 10**(-decimals)          [FTSO convention: value / 10**decimals]
    usd        = amountIn * 10**(-sellTokenDec) * sellPrice
    out        = usd / buyPrice * 10**(buyTokenDec)
               = amountIn * sellValue / buyValue * 10**((bTD + bD) - (sTD + sD))

Usage
-----
    python3 script/quote_reference.py            # regenerate test/fixtures/quote_vectors.json
    python3 script/quote_reference.py --check    # verify the committed fixture matches
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

FIXTURE = Path(__file__).resolve().parent.parent / "test" / "fixtures" / "quote_vectors.json"

UINT256_MAX = 2**256 - 1
# Quote.sol rejects exponents above this; 10**77 < 2**256 < 10**78.
MAX_POW10_EXP = 77


def convert(
    amount_in: int,
    sell_value: int,
    sell_dec: int,
    sell_token_dec: int,
    buy_value: int,
    buy_dec: int,
    buy_token_dec: int,
) -> int:
    """Exact integer conversion, floor-rounded. Mirrors Quote.convert's contract, not its code."""
    if sell_value == 0 or buy_value == 0:
        raise ValueError("FeedValueZero")
    if amount_in == 0:
        return 0

    exponent = (buy_token_dec + buy_dec) - (sell_token_dec + sell_dec)

    if exponent >= 0:
        return (amount_in * sell_value * 10**exponent) // buy_value
    return (amount_in * sell_value) // (buy_value * 10**-exponent)


def representable(
    amount_in: int,
    sell_value: int,
    sell_dec: int,
    sell_token_dec: int,
    buy_value: int,
    buy_dec: int,
    buy_token_dec: int,
) -> bool:
    """True when Quote.sol can evaluate this vector without a legitimate overflow revert.

    Solidity computes `sell.value * scale` (or `buy.value * scale`) at uint256 width *before*
    handing the pair to mulDiv, so that intermediate must fit even though the 512-bit product
    afterwards would not overflow. Python has no such limit, so vectors that would revert on chain
    are excluded here rather than silently disagreeing.
    """
    exponent = (buy_token_dec + buy_dec) - (sell_token_dec + sell_dec)
    if abs(exponent) > MAX_POW10_EXP:
        return False

    scale = 10 ** abs(exponent)
    if exponent >= 0:
        if sell_value * scale > UINT256_MAX:
            return False
    elif buy_value * scale > UINT256_MAX:
        return False

    try:
        out = convert(
            amount_in, sell_value, sell_dec, sell_token_dec, buy_value, buy_dec, buy_token_dec
        )
    except ValueError:
        return False
    return out <= UINT256_MAX


def generate(count: int = 256, seed: int = 20260807) -> dict:
    """Deterministic vectors. The seed is fixed so the fixture is reproducible byte-for-byte."""
    rng = random.Random(seed)

    # Decimals actually observed on Flare feeds, plus negatives to exercise the signed path.
    feed_decimals = [-6, -2, 0, 2, 3, 6, 8, 12, 18]
    token_decimals = [0, 2, 6, 8, 18]

    vectors: list[tuple[int, ...]] = []

    # Hand-chosen edge vectors first, so a regression in the interesting cases is not diluted by
    # hundreds of random ones.
    seeded = [
        # 1 FXRP at XRP/USD 3.00 -> USDT, all 6 dp.
        (10**6, 3_000_000, 6, 6, 1_000_000, 6, 6),
        # Same, into an 18 dp buy token.
        (10**6, 3_000_000, 6, 6, 1_000_000, 6, 18),
        # Negative sell decimals: value 5 dec -2 is a price of 500.
        (10**6, 5, -2, 6, 1, 0, 6),
        # Negative buy decimals.
        (10**6, 1, 0, 6, 5, -2, 6),
        # 1 BTC (8 dp, 2 dp feed) -> FLR (18 dp, 8 dp feed). Real measured scales.
        (10**8, 6_288_717, 2, 8, 626_973, 8, 18),
        # Minimum non-zero amount.
        (1, 3_000_000, 6, 6, 1_000_000, 6, 6),
        # Truncation to zero is a legitimate outcome, not an error.
        (1, 1, 18, 18, 10**18, 0, 0),
        # Identity: same feed, same token decimals, must be exact.
        (12_345_678, 987_654, 6, 6, 987_654, 6, 6),
    ]
    for v in seeded:
        if representable(*v):
            vectors.append(v)

    attempts = 0
    while len(vectors) < count and attempts < count * 200:
        attempts += 1
        v = (
            rng.randrange(0, 10**24),          # amountIn
            rng.randrange(1, 10**24),          # sellValue
            rng.choice(feed_decimals),         # sellDec
            rng.choice(token_decimals),        # sellTokenDec
            rng.randrange(1, 10**24),          # buyValue
            rng.choice(feed_decimals),         # buyDec
            rng.choice(token_decimals),        # buyTokenDec
        )
        if representable(*v):
            vectors.append(v)

    return {
        "_comment": (
            "Generated by script/quote_reference.py. Independent Python reference for "
            "Quote.convert; regenerate with that script, do not hand-edit."
        ),
        "seed": seed,
        "count": len(vectors),
        "amountIn": [str(v[0]) for v in vectors],
        "sellValue": [str(v[1]) for v in vectors],
        "sellDec": [v[2] for v in vectors],
        "sellTokenDec": [v[3] for v in vectors],
        "buyValue": [str(v[4]) for v in vectors],
        "buyDec": [v[5] for v in vectors],
        "buyTokenDec": [v[6] for v in vectors],
        "expected": [str(convert(*v)) for v in vectors],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the committed fixture matches")
    args = parser.parse_args()

    fresh = generate()

    if args.check:
        if not FIXTURE.exists():
            print(f"FAIL: {FIXTURE} does not exist")
            return 1
        committed = json.loads(FIXTURE.read_text())
        if committed != fresh:
            print("FAIL: committed fixture does not match a fresh generation")
            return 1
        print(f"OK: {fresh['count']} vectors match")
        return 0

    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(json.dumps(fresh, indent=2) + "\n")
    print(f"wrote {fresh['count']} vectors to {FIXTURE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
