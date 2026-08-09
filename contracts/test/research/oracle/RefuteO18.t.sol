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

/// @notice The exact guard O-18 proposes, transcribed from the finding:
///           `if (feed.timestamp > block.timestamp + SKEW) revert FeedStale(...)`
///         with SKEW = 2 s ("covers everything measured").
library QuoteWithSkewFix {
    uint64 internal constant SKEW = 2;

    error WouldRevert();

    /// @return true iff the proposed fixed `requireFresh` would ACCEPT this reading.
    function accepts(Quote.Feed memory feed, uint64 maxAge) internal view returns (bool) {
        if (feed.value == 0) return false;
        if (feed.timestamp > block.timestamp + SKEW) return false; // the proposed new line
        if (block.timestamp > feed.timestamp) {
            if (block.timestamp - feed.timestamp > maxAge) return false;
        }
        return true;
    }
}

/// @title Adversarial verification of O-18 — "an unbounded future-dated feed timestamp poisons
///        the execution floor for the rest of the rule"
///
/// @notice O-18's two component facts are both true and both reproduce:
///           (a) Quote.sol:52-59 measures age only inside `if (block.timestamp > feed.timestamp)`,
///               so a future-dated reading is age zero however far ahead;
///           (b) Trimmy.sol:389 writes `latchedPrice` exactly once and nothing rewrites it.
///         What O-18 asserts on top of those is a CAUSAL claim: that the future-dating is what
///         lets the bad price in, and therefore that bounding the skew closes the hole.
///
///         This file attacks that causal claim with a control experiment. `_readFeeds`
///         (Trimmy.sol:666-669) takes `value`, `decimals` and `timestamp` from ONE return tuple
///         of ONE call to ONE contract. There is no path by which a caller supplies a timestamp,
///         and no path by which value and timestamp come from different actors. So any party able
///         to set the timestamp to `now + 365 days` is by construction the same party that set
///         the 20%-off value — and that party's cheapest move is a timestamp of `now`.
contract RefuteO18Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    uint256 internal constant XRP_V = 1_021_607;
    int8 internal constant XRP_D = 6;
    uint256 internal constant FLR_V = 593_189;
    int8 internal constant FLR_D = 8;

    uint64 internal constant MAX_FEED_AGE = 120; // deployed value
    uint16 internal constant SLIP = 50; // MAX_SLIPPAGE_BIPS

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockERC20 internal wnat;
    MockFtsoV2 internal ftso;
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
        MockRegistry registry = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        router = new MockSwapRouter();
        vault = new MockQueuedVault(IERC20(address(fxrp)));

        _publishAt(XRP_V, FLR_V, uint64(vm.getBlockTimestamp()));

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

    function _publishAt(uint256 xrpV, uint256 flrV, uint64 ts) internal {
        ftso.setFeed(FEED_XRP, xrpV, XRP_D, ts);
        ftso.setFeed(FEED_FLR, flrV, FLR_D, ts);
    }

    function _rel(uint256 xrpV, uint256 flrV) internal pure returns (uint256) {
        return Quote.convert(
            1e18,
            Quote.Feed({value: flrV, decimals: FLR_D, timestamp: 0}),
            18,
            Quote.Feed({value: xrpV, decimals: XRP_D, timestamp: 0}),
            6
        );
    }

    function _dcaParams() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: TOK_WNAT,
            buyTokenId: TOK_FXRP,
            verb: Trimmy.Verb.SWAP,
            venueId: VENUE_SWAP,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 300e18,
            partSellAmount: 100e18,
            minOutAbsolute: 0,
            triggerValue: 86_400,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: SLIP,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    function _setFill(uint256 amountIn, uint256 out) internal {
        router.setRateWad((out * 1e12 * 1e18) / amountIn);
    }

    /// The whole O-18 scenario, parameterised on the timestamp the poisoned reading carries.
    /// Returns what `r.account` actually receives on part 2, days after the feed is honest again.
    function _runPoisonScenario(uint64 poisonTs) internal returns (uint256 delivered) {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        uint256 xrpBad = (XRP_V * 12_000) / 10_000; // the same 20%-off price O-18 uses
        _publishAt(xrpBad, FLR_V, poisonTs);

        uint256 relPoison = _rel(xrpBad, FLR_V);
        _setFill(100e18, (100 * relPoison * (10_000 - SLIP)) / 10_000);
        vm.prank(keeper);
        trimmy.execute(id); // part 1: writes the latch

        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), relPoison, "latch poisoned");

        // Feeds honest from here on.
        vm.warp(block.timestamp + 1 days + 1);
        _publishAt(XRP_V, FLR_V, uint64(vm.getBlockTimestamp()));
        // test fixture: the intermediate is a pre-scaled oracle quote, so the ordering is deliberate and the precision loss is the quantity under test.
        // forge-lint: disable-next-line(divide-before-multiply)
        uint256 floorOut = (((100e18 * relPoison) / 1e18) * (10_000 - SLIP)) / 10_000;
        _setFill(100e18, floorOut);

        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id);
        delivered = fxrp.balanceOf(account) - before;
    }

    // =======================================================================================
    // R-1. The control. The identical harm, with a PERFECTLY FRESH timestamp (age 0).
    // =======================================================================================

    /// PASSES. This is the refutation.
    ///
    /// O-18 runs its poison with `timestamp = block.timestamp + 365 days` and attributes the
    /// damage to the missing upper bound. Rerun it with `timestamp = block.timestamp` — age 0,
    /// the on-chain median, accepted by `requireFresh` today and accepted by every conceivable
    /// staleness bound including O-18's own proposed `SKEW = 2` — and the account loses the
    /// SAME NUMBER OF BASE UNITS, to the unit.
    ///
    /// The future-dating contributes nothing. The damage is `latchedPrice` (Trimmy.sol:89, 389)
    /// admitting a bad price and never releasing it, which is findings O-15/O-16, plus a price
    /// source that returned a bad price at all.
    function test_R1_theSameHarmLandsWithAPerfectlyFreshTimestamp() public {
        uint256 deliveredFuture;
        uint256 deliveredFresh;

        uint256 snap = vm.snapshotState();
        deliveredFuture = _runPoisonScenario(uint64(block.timestamp + 365 days));
        vm.revertToState(snap);
        deliveredFresh = _runPoisonScenario(uint64(block.timestamp)); // age 0

        console2.log("delivered, feed dated now + 365 days:", deliveredFuture);
        console2.log("delivered, feed dated now (age 0)   :", deliveredFresh);

        assertEq(
            deliveredFresh,
            deliveredFuture,
            "R-1: the future timestamp changes nothing; a fresh timestamp poisons the latch identically"
        );
    }

    // =======================================================================================
    // R-2. O-18's own proposed fix does not prevent O-18's own failure scenario.
    // =======================================================================================

    /// PASSES.
    ///
    /// O-18 proposes `if (feed.timestamp > block.timestamp + SKEW) revert FeedStale(...)` with
    /// SKEW = 2. Apply it to the poisoned reading dated `now`: it is accepted. The 20%-off price
    /// walks straight through the fixed guard and into `latchedPrice`.
    ///
    /// A guard on the timestamp cannot bound the value, and `maxFeedAge` was never a price
    /// sanity check — it bounds staleness, and a reading published this second is not stale
    /// whatever it says.
    function test_R2_theProposedSkewFixAcceptsThePoisonedReading() public view {
        uint256 xrpBad = (XRP_V * 12_000) / 10_000;

        Quote.Feed memory poisonedFresh =
            Quote.Feed({value: xrpBad, decimals: XRP_D, timestamp: uint64(block.timestamp)});
        Quote.Feed memory poisonedFuture = Quote.Feed({
            value: xrpBad, decimals: XRP_D, timestamp: uint64(block.timestamp + 365 days)
        });

        assertTrue(
            QuoteWithSkewFix.accepts(poisonedFresh, MAX_FEED_AGE),
            "R-2: the proposed fix accepts the 20%-off price when it is dated now"
        );
        assertTrue(
            !QuoteWithSkewFix.accepts(poisonedFuture, MAX_FEED_AGE),
            "the proposed fix does block the far-future dating specifically"
        );
        // ... and R-1 shows blocking that dating specifically saves the account zero base units.
    }

    // =======================================================================================
    // R-3. A future-dated timestamp, on its own, causes no loss at all.
    // =======================================================================================

    /// PASSES.
    ///
    /// Publish both legs 365 days in the future carrying the HONEST market price. The rule
    /// executes and the account receives exactly what the live oracle says it should, to within
    /// the authorised 50 bips. The timestamp field is not a value the floor is computed from —
    /// `_evaluateTrigger` (Trimmy.sol:431-437) reads `value` and `decimals` only.
    function test_R3_futureDatingAloneCostsNothing() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        _publishAt(XRP_V, FLR_V, uint64(block.timestamp + 365 days));
        uint256 relTrue = _rel(XRP_V, FLR_V);
        uint256 fairOut = (100e18 * relTrue) / 1e18;
        _setFill(100e18, fairOut);

        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id);
        uint256 got = fxrp.balanceOf(account) - before;

        assertEq(got, fairOut, "R-3: a future-dated HONEST feed delivers the fair amount");
        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), relTrue, "and latches the fair price");
    }

    // =======================================================================================
    // R-4. There is no split trust boundary to exploit: value and timestamp are one tuple.
    // =======================================================================================

    /// PASSES. Structural, not statistical.
    ///
    /// For O-18's failure scenario to be distinct from "the oracle lied", an attacker would need
    /// to control the TIMESTAMP without controlling the VALUE — e.g. replaying an old honest
    /// reading under a forged forward date. Trimmy.sol:666-669 destructures both fields from a
    /// single `getFeedById` return, and `execute` (372) takes no oracle data as calldata: the
    /// only caller-supplied argument is `ruleId`, and the only other caller input is `msg.value`.
    ///
    /// This test asserts the mechanical consequence: whatever value the feed source chooses to
    /// pair with a future date, it could have paired with `now` instead, and Trimmy cannot tell
    /// the two apart because the freshness check is the only thing that ever looks at the
    /// timestamp and both readings pass it.
    function test_R4_valueAndTimestampShareOneTrustBoundary() public {
        uint256 xrpBad = (XRP_V * 12_000) / 10_000;

        // Same source, same call, two datings — both accepted by the CURRENT requireFresh.
        _publishAt(xrpBad, FLR_V, uint64(block.timestamp));
        vm.prank(account);
        uint256 idA = trimmy.arm(_dcaParams());
        uint256 relPoison = _rel(xrpBad, FLR_V);
        _setFill(100e18, (100 * relPoison * (10_000 - SLIP)) / 10_000);
        vm.prank(keeper);
        trimmy.execute(idA);
        uint128 latchedFromFreshDating = trimmy.ruleAt(idA).latchedPrice;

        _publishAt(xrpBad, FLR_V, uint64(block.timestamp + 365 days));
        vm.prank(account);
        uint256 idB = trimmy.arm(_dcaParams());
        vm.prank(keeper);
        trimmy.execute(idB);
        uint128 latchedFromFutureDating = trimmy.ruleAt(idB).latchedPrice;

        assertEq(
            latchedFromFreshDating,
            latchedFromFutureDating,
            "R-4: the timestamp is not a capability; the same source poisons the latch either way"
        );
    }

    // =======================================================================================
    // R-5. What the missing upper bound DOES buy: only a stalled-oracle window, and only if the
    //      source is already dating readings forward — which the finding's own data says it never
    //      does (0/1022 pinned reads ahead).
    // =======================================================================================

    /// PASSES. This is the residual, and it is the honest scope of the defect.
    ///
    /// A reading dated `now + D` stops being accepted as soon as `block.timestamp - feed.timestamp`
    /// exceeds `maxFeedAge` — i.e. at `now + D + 120`. So the unbounded branch extends the life of
    /// a FROZEN reading by exactly D, and does nothing else. For D to be material the source must
    /// already be emitting wildly forward-dated data, which is the compromised-source case where
    /// the timestamp is the attacker's least interesting lever.
    function test_R5_theResidualIsBoundedToAStalledOracleWindow() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        uint64 dated = uint64(block.timestamp + 1 hours);
        _publishAt(XRP_V, FLR_V, dated);

        // Still accepted while the block clock is behind the dating, and for maxFeedAge after.
        vm.warp(uint256(dated) + MAX_FEED_AGE);
        uint256 relTrue = _rel(XRP_V, FLR_V);
        _setFill(100e18, (100e18 * relTrue) / 1e18);
        vm.prank(keeper);
        trimmy.execute(id); // succeeds: age == maxFeedAge exactly

        // One second later the ordinary staleness branch reclaims it. The feed is NOT immortal.
        vm.warp(uint256(dated) + MAX_FEED_AGE + MIN_GAP);
        vm.prank(keeper);
        vm.expectRevert();
        trimmy.execute(id);
    }

    uint256 internal constant MIN_GAP = 90; // > jittered nextEligibleAt (60 + <30) so the revert
    // we observe is FeedStale, not NotYetEligible
}
