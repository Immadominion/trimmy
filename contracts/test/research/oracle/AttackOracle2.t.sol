// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../../../src/Interfaces.sol";
import {Trimmy} from "../../../src/Trimmy.sol";
import {Quote} from "../../../src/Quote.sol";
import {
    MockERC20,
    MockFtsoV2,
    MockRegistry,
    MockSwapRouter,
    MockQueuedVault
} from "../../mocks/Mocks.sol";

/// @title Oracle-lens attack, second pass — findings O-8 .. O-13
/// @notice `AttackOracle.t.sol` covers the uint64 clamp (O-1..O-3), the unbounded future
///         timestamp (O-4), the fee split (O-5) and the missing floor on vault verbs (O-7).
///         This file covers what that pass did not:
///
///           O-8  the FOUR LIVE RULES have sellTokenId == buyTokenId, which makes the oracle
///                output an algebraic constant while keeping every one of its revert paths live.
///           O-9  the only executor never attaches msg.value, so a nonzero FTSO fee bricks it.
///           O-10 `minOutAbsolute` — the only user-side mitigation for O-1/O-2 — permanently
///                bricks the dust tail of a multi-part rule.
///           O-11 the latch is quantised to `1/relative`; measured 1.72 bips on the live
///                WC2FLR -> FXRP direction, i.e. 3.4% of the whole slippage budget.
///           O-12 the staleness band and the slippage band are additive and unmeasured
///                against each other. Live measurement, this file's header.
///           O-13 `sell.value * scale` overflow: NOT reachable for the allowlisted pairs.
///                Stated with the arithmetic rather than asserted.
///
/// Live reads, Coston2 FtsoV2 0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d, 2026-08-07:
///   XRP/USD  value 1018127  decimals 6   ($1.018127)
///   FLR/USD  value  592985  decimals 8   ($0.00592985)
/// TWO separated windows of 901 contiguous blocks, both feeds pinned per block, 2026-08-07:
///   window A  blocks 33725895..33726795 | window B  blocks 33726438..33727338
///   cross-leg |ts_xrp - ts_flr| : A p99 0 max 0 s      B p99 0 max 0 s   (legs never diverge)
///   feed age (block.ts - ts)    : A p99 31 max 40 s    B p99 30 max 40 s
///                                 (GROUND-TRUTH §5 records a global max of 35 s; 40 s observed)
///   |d(XRP/FLR)| over 120 s     : A p99 30.39 max 31.93 bips
///                                 B p99 34.48 max 38.94 bips
///   |d(XRP/FLR)| over 34 s (the documented p99 age): A max 22.09  B max 25.55 bips
contract AttackOracle2Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    uint256 internal constant XRP_V = 1_018_127;
    int8 internal constant XRP_D = 6;
    uint256 internal constant FLR_V = 592_985;
    int8 internal constant FLR_D = 8;

    uint64 internal constant MAX_FEED_AGE = 120; // deployed value

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockERC20 internal wnat;
    MockFtsoV2 internal ftso;
    MockRegistry internal registry;
    MockSwapRouter internal router;
    MockQueuedVault internal vault;

    address internal account = makeAddr("personalAccount");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("protocolFeeRecipient");

    uint8 internal constant TOK_FXRP = 0;
    uint8 internal constant TOK_WNAT = 1;
    uint8 internal constant VENUE_SWAP = 0;
    uint8 internal constant VENUE_VAULT = 1;

    function setUp() public {
        vm.warp(10 days);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wnat = new MockERC20("Wrapped C2FLR", "WC2FLR", 18);

        ftso = new MockFtsoV2();
        registry = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        router = new MockSwapRouter();
        vault = new MockQueuedVault(IERC20(address(fxrp)));

        uint64 nowTs = uint64(block.timestamp);
        ftso.setFeed(FEED_XRP, XRP_V, XRP_D, nowTs);
        ftso.setFeed(FEED_FLR, FLR_V, FLR_D, nowTs);

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(wnat), feedId: FEED_FLR, decimals: 18});

        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](2);
        venues[0] = Trimmy.VenueCfg({
            target: address(router), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });
        venues[1] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });

        trimmy = new Trimmy(tokens, venues, MAX_FEED_AGE, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1_000_000e6);
        wnat.mint(account, 1_000_000e18);
        vm.startPrank(account);
        fxrp.approve(address(trimmy), type(uint256).max);
        wnat.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();
    }

    function _swapParams() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: TOK_FXRP,
            buyTokenId: TOK_WNAT,
            verb: Trimmy.Verb.SWAP,
            venueId: VENUE_SWAP,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6,
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 50,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    /// Advance past `nextEligibleAt` and re-publish both feeds at the new block time, so the
    /// only thing under test is the floor.
    function _skipToNextSlot() internal {
        vm.warp(block.timestamp + 3601);
        ftso.setFeed(FEED_XRP, XRP_V, XRP_D, uint64(block.timestamp));
        ftso.setFeed(FEED_FLR, FLR_V, FLR_D, uint64(block.timestamp));
    }

    /// The shape `arming/bin/arm.dart:280-296` actually builds, and the shape all four live
    /// rules on 0xf73a2af0… carry: DEPOSIT_VAULT, sellTokenId 0, buyTokenId 0, SCHEDULE 60.
    function _liveRuleParams() internal view returns (Trimmy.RuleParams memory p) {
        p = _swapParams();
        p.verb = Trimmy.Verb.DEPOSIT_VAULT;
        p.venueId = VENUE_VAULT;
        p.sellTokenId = TOK_FXRP;
        p.buyTokenId = TOK_FXRP; // arm.dart passes buyTokenId: 0
        p.trigger = Trimmy.Trigger.SCHEDULE;
        p.triggerValue = 60;
        p.minOutAbsolute = (uint128(100e6) * 90) / 100;
    }

    // =======================================================================================
    // O-8. On the four LIVE rules the oracle output is an algebraic constant, but every one of
    //      its revert paths is still armed. The oracle is pure downside on the deployed config.
    // =======================================================================================

    /// `_validate` (Trimmy.sol:340) rejects `sellTokenId == buyTokenId` only for `Verb.SWAP`.
    /// For the vault verbs it is allowed, and `arm.dart` uses it. With one feed on both legs
    /// `Quote.convert` collapses: exponent = 0 and `mulDiv(10**d, v, v) == 10**d` for EVERY v.
    function test_O8_sameTokenRuleMakesTheOracleOutputAConstant() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_liveRuleParams());

        vm.prank(keeper);
        trimmy.execute(id);
        uint128 latchedAtRealPrice = trimmy.ruleAt(id).latchedPrice;

        // Now move XRP/USD by 10x. The latch would have to move too if it were a price.
        assertEq(uint256(latchedAtRealPrice), 1e6, "latch is 10**6, not a price");

        uint256 relAtTenX = Quote.convert(
            1e6,
            Quote.Feed({value: XRP_V * 10, decimals: XRP_D, timestamp: 0}),
            6,
            Quote.Feed({value: XRP_V * 10, decimals: XRP_D, timestamp: 0}),
            6
        );
        uint256 relAtHundredth = Quote.convert(
            1e6,
            Quote.Feed({value: XRP_V / 100, decimals: XRP_D, timestamp: 0}),
            6,
            Quote.Feed({value: XRP_V / 100, decimals: XRP_D, timestamp: 0}),
            6
        );
        console2.log("relative at 10x XRP  :", relAtTenX);
        console2.log("relative at 0.01x XRP:", relAtHundredth);
        assertEq(relAtTenX, 1e6);
        assertEq(relAtHundredth, 1e6);
        // Matches the live chain read: ruleAt(0..3).latchedPrice == 1000000 == 0x0f4240.
    }

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// The constant is free; the revert path is not. A rule whose price output cannot depend on
    /// the feed is still bricked for the whole staleness outage, and `maxFeedAge` is immutable.
    function test_O8_constantOracleStillBricksTheLiveRuleShape() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_liveRuleParams());

        vm.warp(block.timestamp + 1);
        // ONE feed goes 121 s stale. The rule's price output is 10**6 either way.
        ftso.setFeed(FEED_XRP, XRP_V, XRP_D, uint64(block.timestamp - MAX_FEED_AGE - 1));

        vm.prank(keeper);
        // Should not revert: nothing this rule computes depends on the feed's freshness.
        trimmy.execute(id);
    }

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// Same shape, the other FTSO failure mode: a zero mantissa. `Quote.requireFresh`
    /// (Quote.sol:53) reverts `FeedValueZero` before anything looks at whether the rule uses it.
    function test_O8_zeroFeedValueBricksTheLiveRuleShape() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_liveRuleParams());

        ftso.setFeed(FEED_XRP, 0, XRP_D, uint64(block.timestamp));

        vm.prank(keeper);
        trimmy.execute(id);
    }

    // =======================================================================================
    // O-9. `execute` is payable so a governance-set FTSO fee can be forwarded. The only
    //      executor never attaches value, so the mitigation cannot fire.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// `keeper/bin/keeper.dart` has no `value:` anywhere: `simulate` calls `client.ethCall`
    /// (line 163) and `send` shells out to `cast mktx` (line 194-212) with no `--value`. Both
    /// therefore carry msg.value == 0. This is that call, verbatim, against a nonzero fee.
    function test_O9_zeroValueKeeperCallBricksEveryRuleOnceTheFeeIsSet() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_liveRuleParams());

        ftso.setFeePerRead(1); // governance switches the feed fee on: 1 wei per feed

        vm.prank(keeper);
        // What keeper.dart emits. Reverts InsufficientFeeValue(0, 2).
        trimmy.execute(id);
    }

    /// The contract side is fine — the defect is entirely in the executor. Shown for contrast.
    function test_O9_contractAcceptsTheFeeWhenItIsSupplied() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_liveRuleParams());
        ftso.setFeePerRead(1);

        vm.deal(keeper, 1 ether);
        vm.prank(keeper);
        trimmy.execute{value: 2}(id);
        assertGt(trimmy.ruleAt(id).spent, 0);
    }

    // =======================================================================================
    // O-10. `minOutAbsolute` is the ONLY user-side defence against O-1/O-2. Using it as
    //       documented permanently bricks the last part of a multi-part rule.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// Trimmy.sol:392-394 shrinks the last part to the remainder (A8). Trimmy.sol:469 does NOT
    /// shrink `minOutAbsolute` with it: `if (r.minOutAbsolute > floorOut) floorOut = ...`.
    /// A floor sized for a full part is unmeetable by a tail part, forever, with a live
    /// allowance and months of expiry left.
    function test_O10_minOutAbsoluteBricksTheDustTail() public {
        // Sell WC2FLR -> FXRP: this is the direction where the O-1 clamp does NOT bite, so the
        // failure below is isolated from it. relative == 5824 FXRP units per whole WC2FLR.
        Trimmy.RuleParams memory p = _swapParams();
        p.sellTokenId = TOK_WNAT;
        p.buyTokenId = TOK_FXRP;
        p.totalSellAmount = 250e18;
        p.partSellAmount = 100e18; // parts: 100, 100, 50
        // A user protecting themselves from O-2 pins an absolute floor for a 100-WC2FLR part.
        p.minOutAbsolute = 580_000; // 0.58 FXRP, ~99.6% of the 582,443 a full part is worth

        vm.prank(account);
        uint256 id = trimmy.arm(p);

        uint256 rel = Quote.convert(
            1e18,
            Quote.Feed({value: FLR_V, decimals: FLR_D, timestamp: 0}),
            18,
            Quote.Feed({value: XRP_V, decimals: XRP_D, timestamp: 0}),
            6
        );
        console2.log("relative (FXRP units per 1 WC2FLR):", rel);
        router.setRateWad(rel * 1e12); // honest fill at the oracle price

        vm.prank(keeper);
        trimmy.execute(id); // part 1: 100 WC2FLR
        _skipToNextSlot();
        vm.prank(keeper);
        trimmy.execute(id); // part 2: 100 WC2FLR
        _skipToNextSlot();

        assertEq(trimmy.ruleAt(id).spent, 200e18, "two full parts filled");

        // Part 3 is 50 WC2FLR, worth (50 * rel) == 291,200 FXRP units — HALF the pinned floor,
        // because `minOutAbsolute` was sized for a 100-WC2FLR part and is not pro-rated.
        uint256 tailFairOut = (50e18 * rel) / 1e18;
        console2.log("tail part fair value (FXRP units):", tailFairOut);
        console2.log("floor the contract still demands  :", uint256(580_000));
        assertGe(tailFairOut, 580_000, "O-10: the tail can never clear the un-prorated floor");

        vm.prank(keeper);
        trimmy.execute(id); // unreachable: reverts on amountOutMinimum == 580000, forever
        assertEq(
            trimmy.ruleAt(id).spent, 250e18, "O-10: 50 WC2FLR are stranded for the rule's life"
        );
    }

    // =======================================================================================
    // O-11. The latch's precision is `1/relative`, and the deployed pair is pathological in
    //       BOTH directions of the same uint64 field.
    // =======================================================================================

    function test_O11_theSameUint64FieldIsTooNarrowAndTooCoarse() public pure {
        uint256 fwd = Quote.convert(
            1e6,
            Quote.Feed({value: XRP_V, decimals: XRP_D, timestamp: 0}),
            6,
            Quote.Feed({value: FLR_V, decimals: FLR_D, timestamp: 0}),
            18
        );
        uint256 rev = Quote.convert(
            1e18,
            Quote.Feed({value: FLR_V, decimals: FLR_D, timestamp: 0}),
            18,
            Quote.Feed({value: XRP_V, decimals: XRP_D, timestamp: 0}),
            6
        );
        console2.log("FXRP  -> WC2FLR relative:", fwd); // 1.7169e20
        console2.log("WC2FLR -> FXRP relative :", rev); // 5824
        console2.log("uint64 max              :", uint256(type(uint64).max));

        // Direction 1 overflows the field by 9.3x.
        assertGt(fwd, type(uint64).max);
        // Direction 2 fits, but with only 4 significant digits: the quantum is 1/rev.
        uint256 quantumBips = 10_000 / rev;
        console2.log("reverse-direction quantum (bips):", quantumBips);
        assertEq(quantumBips, 1); // 1.72 bips, floored -> 3.4% of MAX_SLIPPAGE_BIPS=50
        assertLt(rev, 1e5);
    }

    /// The floor derived from a coarse latch has a hard cliff: below `10**sellDec / relative`
    /// base units of input, `oracleOut` truncates to zero and the FTSO floor vanishes entirely.
    function test_O11_smallPartTruncatesTheOracleFloorToZero() public pure {
        uint256 rev = 5824; // measured above
        uint256 cliff = 1e18 / rev; // 1.717e14 wei WC2FLR
        console2.log("input below which oracleOut == 0 (wei):", cliff);
        // Trimmy.sol:466-467 : oracleOut = amountIn * latchedPrice / 10**sellDecimals
        uint256 oracleOut = ((cliff - 1) * rev) / 1e18;
        assertEq(oracleOut, 0, "the FTSO floor is exactly zero below the cliff");
    }

    // =======================================================================================
    // O-12. Staleness budget and slippage budget are additive and neither is sized against the
    //       other. Numbers are MEASURED on Coston2, not recalled.
    // =======================================================================================

    /// Measured 2026-08-07 over two separated 901-block windows (see the file header):
    ///   |d(XRP/FLR)| over 120 s: worst p99 34.48, worst max 38.94 bips.
    /// The floor is `stalePrice * (1 - 50bp)` and nothing checks `stalePrice` against the live
    /// price, so the two bands add. This is a CALM testnet sample; XRP mainnet realised vol is
    /// higher, so 38.94 bips is a lower bound on the staleness term, not an upper one.
    function test_O12_measuredCombinedExtractableBand() public pure {
        uint256 measuredMax120sBips = 38; // floor of 38.94, measured
        uint256 measuredP99120sBips = 34; // floor of 34.48, measured
        uint256 slippage = 50; // MAX_SLIPPAGE_BIPS
        console2.log("p99  combined band, bips:", measuredP99120sBips + slippage);
        console2.log("max  combined band, bips:", measuredMax120sBips + slippage);
        // The product's stated guarantee is "never worse than 50 bips below the FTSO price".
        assertLe(measuredMax120sBips + slippage, 50, "O-12: the real band is 88 bips, not 50");
    }

    // =======================================================================================
    // O-13. `sell.value * scale` at Quote.sol:103. Asked: can it overflow for the ALLOWLISTED
    //       pairs? Answer: no, by three orders of magnitude more than any feed can reach.
    // =======================================================================================

    function test_O13_scaleFoldCannotOverflowForTheAllowlistedPairs() public pure {
        // FXRP(6 dp token, 6 dp feed) -> WC2FLR(18 dp token, 8 dp feed).
        int256 exponent = (int256(18) + int256(8)) - (int256(6) + int256(6));
        assertEq(exponent, 14);
        uint256 scale = 10 ** 14;
        uint256 threshold = type(uint256).max / scale; // 1.1579e63
        console2.log("XRP/USD mantissa needed to overflow:", threshold);
        console2.log("XRP/USD mantissa observed          :", XRP_V);
        assertGt(threshold / XRP_V, 1e50);

        // Reverse direction: exponent -14, the scale lands in the DENOMINATOR.
        // buy.value * scale = 1018127 * 1e14 = 1.018e20. Same headroom.
        assertGt(type(uint256).max / scale / XRP_V, 1e50);

        // And it would be a REVERT, not a wrap: Solidity 0.8 checked arithmetic. The binding
        // constraint is `pow10`'s exponent <= 77 (Quote.sol:115), reached long before any
        // mantissa could.
        assertEq(Quote.pow10(77) / 1e70, 1e7);
    }

    // =======================================================================================
    // O-14. Cross-leg timestamp skew: MEASURED SAFE. Recorded so it is not re-attacked.
    // =======================================================================================

    /// `requireFresh` is applied per leg against `block.timestamp`, so two legs can in principle
    /// be 2*maxFeedAge = 240 s apart from each other with no check on the gap. Measured over
    /// 901 contiguous Coston2 blocks with BOTH feeds pinned to each block:
    ///   |ts_xrp - ts_flr| : p50 0, p90 0, p99 0, max 0 s, over BOTH windows (1802 blocks).
    /// The two feeds are published in the same voting round and never diverge. The unchecked
    /// gap is real in the code and empty in practice. Not a finding — a bounded risk.
    ///
    /// Note the methodology trap: an UNPINNED `eth_call` of each feed at "latest" returned
    /// timestamps 7 s apart (1786079964 vs 1786079971) because the two calls landed on
    /// different blocks. That is the same class of error GROUND-TRUTH §5 records for feed age.
    function test_O14_crossLegSkewIsUnchecked_butMeasuredZero() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_swapParams());

        // Legs 239 s apart, both individually inside maxFeedAge=120. Accepted.
        vm.warp(block.timestamp + 200);
        ftso.setFeed(FEED_XRP, XRP_V, XRP_D, uint64(block.timestamp - 119));
        ftso.setFeed(FEED_FLR, FLR_V, FLR_D, uint64(block.timestamp));

        router.setRateWad(1e30);
        vm.prank(keeper);
        trimmy.execute(id); // succeeds: no cross-leg gap check exists
        assertGt(trimmy.ruleAt(id).spent, 0);
    }
}
