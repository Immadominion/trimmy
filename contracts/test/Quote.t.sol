// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {Quote} from "../src/Quote.sol";

/// @dev `vm.expectRevert` cannot observe a revert from an internal library call: `internal`
///      functions are inlined as `JUMP`, so there is no call-depth change for the cheatcode to
///      detect, and the assertion fails with "call didn't revert at a lower depth than cheatcode
///      call depth" even when the code under test reverts correctly. Every revert assertion must
///      therefore go through an external boundary. This harness is that boundary.
contract QuoteHarness {
    function convert(
        uint256 amountIn,
        Quote.Feed memory sell,
        uint8 sellTokenDec,
        Quote.Feed memory buy,
        uint8 buyTokenDec
    ) external pure returns (uint256) {
        return Quote.convert(amountIn, sell, sellTokenDec, buy, buyTokenDec);
    }

    function requireFresh(Quote.Feed memory feed, uint64 maxAge) external view {
        Quote.requireFresh(feed, maxAge);
    }

    function pow10(uint256 exponent) external pure returns (uint256) {
        return Quote.pow10(exponent);
    }
}

/// @title Quote property and fuzz suite
/// @notice A test that exercises our own implementation on both sides proves self-consistency and
///         nothing else. So the concrete vectors here are hand-derived from the FTSO definition
///         (`price = value * 10**(-decimals)`) and cross-checked against an independent Python
///         reference in `script/quote_reference.py` — not against this library's own inverse.
contract QuoteTest is Test {
    // Realistic bounds. Feed mantissas past 1e30 combined with a large positive exponent overflow
    // by design (see Quote.pow10); that path is asserted separately in testRevert_*.
    uint256 internal constant MAX_FEED_VALUE = 1e30;
    uint256 internal constant MAX_AMOUNT = 1e30;

    QuoteHarness internal harness;

    function setUp() public {
        harness = new QuoteHarness();
    }

    function _feed(uint256 value, int8 decimals) internal view returns (Quote.Feed memory) {
        return Quote.Feed({value: value, decimals: decimals, timestamp: uint64(block.timestamp)});
    }

    // ---------------------------------------------------------------------------------------
    // Concrete vectors — derived by hand from the FTSO definition, not from this library.
    // ---------------------------------------------------------------------------------------

    /// 1 FXRP (6 dp) at XRP/USD = 3.00 (value 3_000_000, dec 6) into USDT (6 dp) at $1.00.
    /// exponent = (6 + 6) - (6 + 6) = 0;  out = 1e6 * 3e6 / 1e6 = 3e6 = 3.00 USDT.
    function test_vector_sameDecimals() public view {
        uint256 out = Quote.convert(1e6, _feed(3_000_000, 6), 6, _feed(1_000_000, 6), 6);
        assertEq(out, 3e6, "3 XRP-dollars should be 3.00 USDT");
    }

    /// Same prices, but the buy token has 18 dp.
    /// exponent = (18 + 6) - (6 + 6) = 12;  out = 1e6 * 3e6 * 1e12 / 1e6 = 3e18.
    function test_vector_crossDecimals() public view {
        uint256 out = Quote.convert(1e6, _feed(3_000_000, 6), 6, _feed(1_000_000, 6), 18);
        assertEq(out, 3e18, "decimals must be carried, not assumed");
    }

    /// Negative feed decimals: value 5, decimals -2 means a price of 500, not 0.05.
    /// sell price 500, buy price 1  =>  1 whole sell token buys 500 whole buy tokens.
    /// exponent = (6 + 0) - (6 + (-2)) = 2;  out = 1e6 * 5 * 1e2 / 1 = 5e8 = 500.000000.
    function test_vector_negativeDecimals() public view {
        uint256 out = Quote.convert(1e6, _feed(5, -2), 6, _feed(1, 0), 6);
        assertEq(out, 500e6, "negative decimals scale the price up, not down");
    }

    /// The SDK measured FLR/USD at 8 dp and BTC/USD at 2 dp in the same call. Both legs, one quote:
    /// 1 BTC (8 dp) at $62887.17 into FLR (18 dp) at $0.00626973.
    /// exponent = (18 + 8) - (8 + 2) = 16
    /// out = 1e8 * 6288717 * 1e16 / 626973
    function test_vector_realWorldMixedScales() public view {
        uint256 out = Quote.convert(1e8, _feed(6_288_717, 2), 8, _feed(626_973, 8), 18);
        // Cast before dividing: an un-cast literal expression stays a rational constant and
        // Solidity refuses to truncate it implicitly.
        uint256 expected = (uint256(1e8) * uint256(6_288_717) * uint256(1e16)) / uint256(626_973);
        assertEq(out, expected);
        // ~10.03 million FLR for one BTC. Sanity band, not an exact assertion.
        assertGt(out, 10_000_000e18);
        assertLt(out, 10_100_000e18);
    }

    // ---------------------------------------------------------------------------------------
    // Properties
    // ---------------------------------------------------------------------------------------

    /// Identity: same feed on both legs, same token decimals, must be exact — no drift at all.
    function testFuzz_identityIsExact(uint256 amountIn, uint256 value, int8 dec, uint8 tokenDec)
        public
        view
    {
        amountIn = bound(amountIn, 0, MAX_AMOUNT);
        value = bound(value, 1, MAX_FEED_VALUE);
        tokenDec = uint8(bound(tokenDec, 0, 18));
        dec = int8(bound(int256(dec), -18, 18));

        Quote.Feed memory f = _feed(value, dec);
        assertEq(Quote.convert(amountIn, f, tokenDec, f, tokenDec), amountIn);
    }

    /// Monotonic: more in never yields less out. A violation here is an arbitrage.
    function testFuzz_monotonic(uint256 a, uint256 b, uint256 sv, uint256 bv, int8 sd, int8 bd)
        public
        view
    {
        a = bound(a, 0, 1e24);
        b = bound(b, a, 1e24);
        sv = bound(sv, 1, 1e24);
        bv = bound(bv, 1, 1e24);
        sd = int8(bound(int256(sd), -6, 6));
        bd = int8(bound(int256(bd), -6, 6));

        uint256 outA = Quote.convert(a, _feed(sv, sd), 6, _feed(bv, bd), 6);
        uint256 outB = Quote.convert(b, _feed(sv, sd), 6, _feed(bv, bd), 6);
        assertLe(outA, outB, "more in must not produce less out");
    }

    /// Round trip must never create value. Rounding is floor at each hop, so `back <= amountIn`
    /// is an invariant, not a tolerance — if it can ever be violated the contract mints money.
    function testFuzz_roundTripNeverCreatesValue(
        uint256 amountIn,
        uint256 sv,
        uint256 bv,
        int8 sd,
        int8 bd,
        uint8 sTokenDec,
        uint8 bTokenDec
    ) public view {
        amountIn = bound(amountIn, 0, 1e24);
        sv = bound(sv, 1, 1e18);
        bv = bound(bv, 1, 1e18);
        sd = int8(bound(int256(sd), -8, 8));
        bd = int8(bound(int256(bd), -8, 8));
        sTokenDec = uint8(bound(sTokenDec, 6, 18));
        bTokenDec = uint8(bound(bTokenDec, 6, 18));

        Quote.Feed memory sell = _feed(sv, sd);
        Quote.Feed memory buy = _feed(bv, bd);

        uint256 out = Quote.convert(amountIn, sell, sTokenDec, buy, bTokenDec);
        uint256 back = Quote.convert(out, buy, bTokenDec, sell, sTokenDec);

        assertLe(back, amountIn, "round trip must never create value");
    }

    /// Doubling the sell-leg price doubles the output, up to one unit of floor rounding.
    function testFuzz_priceScalesOutput(uint256 amountIn, uint256 sv, uint256 bv) public view {
        amountIn = bound(amountIn, 1e6, 1e24);
        sv = bound(sv, 1, 1e18);
        bv = bound(bv, 1, 1e18);

        uint256 out1 = Quote.convert(amountIn, _feed(sv, 6), 6, _feed(bv, 6), 6);
        uint256 out2 = Quote.convert(amountIn, _feed(sv * 2, 6), 6, _feed(bv, 6), 6);

        assertApproxEqAbs(out2, out1 * 2, 2, "output must be linear in the sell price");
    }

    // ---------------------------------------------------------------------------------------
    // Failure modes — rule 7: unknown means do not execute.
    // ---------------------------------------------------------------------------------------

    function test_revert_zeroSellValue() public {
        vm.expectRevert(Quote.FeedValueZero.selector);
        harness.convert(1e6, Quote.Feed({value: 0, decimals: 0, timestamp: 0}), 6, _feed(1, 0), 6);
    }

    function test_revert_zeroBuyValue() public {
        vm.expectRevert(Quote.FeedValueZero.selector);
        harness.convert(1e6, _feed(1, 0), 6, Quote.Feed({value: 0, decimals: 0, timestamp: 0}), 6);
    }

    function test_zeroAmountIsZero() public view {
        assertEq(Quote.convert(0, _feed(3e6, 6), 6, _feed(1e6, 6), 6), 0);
    }

    function test_revert_staleFeed() public {
        vm.warp(10_000);
        Quote.Feed memory f = Quote.Feed({value: 1e6, decimals: 6, timestamp: 10_000 - 61});
        vm.expectRevert(
            abi.encodeWithSelector(
                Quote.FeedStale.selector, uint64(10_000 - 61), uint256(10_000), uint64(60)
            )
        );
        harness.requireFresh(f, 60);
    }

    function test_freshFeedPasses() public {
        vm.warp(10_000);
        harness.requireFresh(Quote.Feed({value: 1e6, decimals: 6, timestamp: 10_000 - 59}), 60);
    }

    /// A feed timestamp slightly ahead of the block clock is normal skew, not a reason to refuse.
    function test_futureTimestampIsNotStale() public {
        vm.warp(10_000);
        harness.requireFresh(Quote.Feed({value: 1e6, decimals: 6, timestamp: 10_001}), 60);
    }

    function test_revert_exponentOutOfRange() public {
        vm.expectRevert(abi.encodeWithSelector(Quote.ExponentOutOfRange.selector, uint256(78)));
        harness.pow10(78);
    }
}
