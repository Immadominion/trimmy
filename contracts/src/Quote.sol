// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/// @title Quote — FTSO-derived valuation, exact and two-legged
/// @notice The execution floor for every Trimmy rule is computed here. Nothing else in the system
///         is permitted to decide what an amount is worth, and in particular a venue never is:
///         an AMM quote is a number an attacker can move.
///
/// Three findings are encoded in this file. Each was paid for.
///
/// 1. **A price has two legs.** `keeper-security.md` §3.5 computed the floor from a single
///    XRP/USD read. That is only correct if the buy token is worth exactly $1 — an assumption
///    never stated and never validated, against a Coston2 landscape carrying at least five
///    unrelated "USDC" tokens. Both legs are read here, always.
///
/// 2. **Never assume a decimal scale.** One live FTSO call returned 8 dp for FLR/USD, 2 for
///    BTC/USD, 3 for ETH/USD and 6 for XRP/USD; the DA Layer reports 6 dp for the same FLR/USD
///    feed FTSOv2 reports at 8. `value` and `decimals` travel together here, always, and
///    `decimals` is `int8` because it may be negative.
///
/// 3. **Multiply before divide, at 512-bit width.** `Math.mulDiv` carries the full product, so
///    the only rounding in the whole path is the single floor at the end.
library Quote {
    /// @notice A feed reading exactly as FTSOv2 returns it. The three fields are never separated.
    /// @param value      Mantissa. The price is `value * 10**(-decimals)`.
    /// @param decimals   Scale exponent. Signed: a negative value means the price exceeds `value`.
    /// @param timestamp  Publication time, compared against `block.timestamp` — never wall clock.
    struct Feed {
        uint256 value;
        int8 decimals;
        uint64 timestamp;
    }

    /// @dev 10**77 < type(uint256).max < 10**78, so 77 is the largest exponent representable.
    uint256 internal constant MAX_POW10_EXP = 77;

    /// @dev Measured Coston2 inter-block gap is p50 1 s, max 25 s (GROUND-TRUTH §5). A feed a few
    ///      seconds ahead of the block clock is ordinary; minutes ahead is not.
    uint64 internal constant MAX_CLOCK_SKEW = 10;

    error FeedValueZero();
    error ExponentOutOfRange(uint256 exponent);
    error FeedStale(uint64 feedTimestamp, uint256 blockTimestamp, uint64 maxAge);
    error FeedFromTheFuture(uint64 feedTimestamp, uint256 blockTimestamp);

    /// @notice Reverts unless the feed is fresh as measured against `block.timestamp`.
    /// @dev Rule 6: staleness is measured in-contract. A feed age computed from when an off-chain
    ///      script ran is not the age the contract sees — the RPC caching layer sits between them,
    ///      and two earlier measurement passes disagreed for exactly that reason.
    ///
    ///      **O-18.** A small amount of future-dating is benign clock skew and is tolerated. An
    ///      arbitrarily future-dated reading is not: it passed every check as "age zero", and
    ///      because the execution floor latches the first price it sees, one poisoned read set a
    ///      floor that the rule then carried for its whole life. Anything beyond
    ///      `MAX_CLOCK_SKEW` into the future is now refused outright — unknown means do not
    ///      execute, and a clock that disagrees with the chain by more than a block is unknown.
    function requireFresh(Feed memory feed, uint64 maxAge) internal view {
        if (feed.value == 0) revert FeedValueZero();
        if (block.timestamp > feed.timestamp) {
            uint256 age = block.timestamp - feed.timestamp;
            if (age > maxAge) {
                revert FeedStale(feed.timestamp, block.timestamp, maxAge);
            }
        } else {
            uint256 ahead = uint256(feed.timestamp) - block.timestamp;
            if (ahead > MAX_CLOCK_SKEW) {
                revert FeedFromTheFuture(feed.timestamp, block.timestamp);
            }
        }
    }

    /// @notice Value `amountIn` of the sell token in base units of the buy token.
    ///
    /// Derivation, kept here because a reader must be able to check it rather than trust it:
    ///
    ///     sellPrice = sV * 10**(-sD)                     [USD per whole sell token]
    ///     buyPrice  = bV * 10**(-bD)                     [USD per whole buy token]
    ///     usd       = amountIn * 10**(-sTD) * sellPrice
    ///     out       = usd / buyPrice * 10**(bTD)
    ///               = amountIn * sV / bV * 10**((bTD + bD) - (sTD + sD))
    ///
    /// so the whole conversion is one ratio and one power of ten.
    ///
    /// @param amountIn      Amount of sell token, in its own base units.
    /// @param sell          Sell-leg feed reading.
    /// @param sellTokenDec  ERC-20 decimals of the sell token.
    /// @param buy           Buy-leg feed reading.
    /// @param buyTokenDec   ERC-20 decimals of the buy token.
    /// @return out          Amount of buy token, in its own base units, rounded down.
    function convert(
        uint256 amountIn,
        Feed memory sell,
        uint8 sellTokenDec,
        Feed memory buy,
        uint8 buyTokenDec
    ) internal pure returns (uint256 out) {
        if (sell.value == 0 || buy.value == 0) revert FeedValueZero();
        if (amountIn == 0) return 0;

        // Widen before arithmetic: int8 decimals may be negative, and uint8 token decimals must
        // not be subtracted at their own width.
        int256 exponent = (int256(uint256(buyTokenDec)) + int256(buy.decimals))
            - (int256(uint256(sellTokenDec)) + int256(sell.decimals));

        // `exponent` is bounded by construction: it is the difference of two `uint8 + int8` sums,
        // so it lies in roughly [-383, 382] and can never reach `type(int256).min`, where negation
        // would overflow. SafeCast.toUint256 additionally reverts on any negative input, so the
        // sign guarantee is enforced by the code rather than asserted by this comment.
        if (exponent >= 0) {
            uint256 scale = pow10(SafeCast.toUint256(exponent));
            // Fold the scale into the numerator so mulDiv's 512-bit intermediate absorbs it and
            // the only rounding is the final floor.
            out = Math.mulDiv(amountIn, sell.value * scale, buy.value);
        } else {
            uint256 scale = pow10(SafeCast.toUint256(-exponent));
            out = Math.mulDiv(amountIn, sell.value, buy.value * scale);
        }
    }

    /// @notice `10**exponent`, reverting rather than wrapping when it would not fit.
    /// @dev Checked arithmetic throughout. An exponent past 77 means the allowlist was configured
    ///      with a token/feed pairing this library cannot represent, which must fail loudly at
    ///      deploy time rather than silently at execution time.
    function pow10(uint256 exponent) internal pure returns (uint256) {
        if (exponent > MAX_POW10_EXP) revert ExponentOutOfRange(exponent);
        return 10 ** exponent;
    }
}
