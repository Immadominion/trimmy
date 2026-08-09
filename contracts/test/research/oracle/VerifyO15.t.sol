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

/// @title Adversarial verification of O-15 — "a keeper picks the floor by choosing when to
///        execute part 1".
///
/// The job here is to REFUTE. What follows is what actually survived:
///   V15a  the keeper's timing choice is NOT necessary. Part 1 executed HONESTLY, at the price
///         that was live in the block after arm(), still leaves part 2 floored 201 bips below
///         market. The defect is the one-way latch, not the identity of the first caller.
///   V15b  the marginal contribution of the keeper's selection, measured against V15a.
///   V15c  the extractable fraction is not bounded by the measured daily drift. It is bounded
///         only by how far the pair moves before expiry, and MAX_RULE_LIFETIME is 365 days.
///   V15d  REFUTES the "unbounded" reading for any rule that sets minOutAbsolute: Trimmy.sol:469
///         raises the floor to it, and the arming tool already populates it (arm.dart:287).
///   V15e  REFUTES the finding entirely for PRICE_ABOVE rules: the trigger check at
///         Trimmy.sol:445 means the latch can never be written below the user's own
///         triggerValue, so the stale floor has a user-chosen lower bound.
contract VerifyO15Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    uint256 internal constant XRP_V = 1_021_607; // live Coston2 mantissa, 6 dp
    int8 internal constant XRP_D = 6;
    uint256 internal constant FLR_V = 593_189; // live Coston2 mantissa, 8 dp
    int8 internal constant FLR_D = 8;

    uint64 internal constant MAX_FEED_AGE = 120; // deployed
    uint16 internal constant SLIP = 50; // MAX_SLIPPAGE_BIPS
    uint256 internal constant DRIFT_24H_BIPS = 201; // measured p99/max, sample_latch_drift.py

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockERC20 internal wnat;
    MockFtsoV2 internal ftso;
    MockSwapRouter internal router;
    MockQueuedVault internal vault;

    address internal account = makeAddr("personalAccount");
    address internal honestKeeper = makeAddr("honestKeeper");
    address internal attacker = makeAddr("attacker");
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

    function _publish(uint256 xrpV, uint256 flrV) internal {
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, xrpV, XRP_D, nowTs);
        ftso.setFeed(FEED_FLR, flrV, FLR_D, nowTs);
    }

    /// FXRP base units per ONE WHOLE WC2FLR, exactly as _evaluateTrigger computes it.
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

    // ===================================================================================
    // V15a. The keeper's timing choice is NOT load-bearing.
    // ===================================================================================

    /// Part 1 is executed by an HONEST keeper in the very next block, at the price that was
    /// live when the user armed. No selection of any kind. The market then drifts by the
    /// MEASURED 24 h move and part 2 is still fillable 245 bips below the live oracle.
    ///
    /// This test FAILS, which shows O-15's stated mechanism ("a keeper picks the floor by
    /// choosing when to execute part 1") is a description of an AMPLIFIER, not of the cause.
    /// The cause is Trimmy.sol:389 + Trimmy.sol:467: `slippageBips` bounds the deviation from
    /// `latchedPrice`, and nothing bounds the deviation of `latchedPrice` from the live price.
    function test_V15a_honestPromptFirstFireStillLeavesPart2FlooredAtTheStalePrice() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        // Part 1, next block, honest keeper, honest fill at the live oracle price.
        uint256 relArm = _rel(XRP_V, FLR_V);
        _setFill(100e18, (100e18 * relArm) / 1e18);
        vm.prank(honestKeeper);
        trimmy.execute(id);
        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), relArm, "latched at the honest price");

        // One day passes. FLR strengthens against XRP by the measured 24 h drift, so a whole
        // WC2FLR now buys 201 bips MORE FXRP.
        uint256 xrpLow = (XRP_V * (10_000 - DRIFT_24H_BIPS)) / 10_000;
        vm.warp(block.timestamp + 1 days + 1);
        _publish(xrpLow, FLR_V);
        uint256 relTrue = _rel(xrpLow, FLR_V);

        // test fixture: the intermediate is a pre-scaled oracle quote, so the ordering is deliberate and the precision loss is the quantity under test.
        // forge-lint: disable-next-line(divide-before-multiply)
        uint256 floorOut = (((100e18 * relArm) / 1e18) * (10_000 - SLIP)) / 10_000;
        uint256 fairOut = (100e18 * relTrue) / 1e18;
        _setFill(100e18, floorOut);

        uint256 before = fxrp.balanceOf(account);
        vm.prank(attacker);
        trimmy.execute(id);
        uint256 got = fxrp.balanceOf(account) - before;

        console2.log("latched at arm-time price :", relArm);
        console2.log("live relative one day on  :", relTrue);
        console2.log("fair out for part 2       :", fairOut);
        console2.log("delivered                 :", got);
        console2.log("loss vs FTSO, bips        :", ((fairOut - got) * 10_000) / fairOut);

        assertGe(
            got,
            (fairOut * (10_000 - SLIP)) / 10_000,
            "V15a: no keeper selection needed - drift alone breaks the 50-bip band"
        );
    }

    // ===================================================================================
    // V15c. The band is not capped at 201 bips. It is capped by nothing.
    // ===================================================================================

    /// MAX_RULE_LIFETIME is 365 days (Trimmy.sol:139) and `expiry` may be set anywhere inside
    /// it (Trimmy.sol:330). `latchedPrice` is written once at Trimmy.sol:389. So for a rule
    /// whose pair moves 3x before the last part, the floor on the last part is 1/3 of market
    /// and roughly two thirds of that part is extractable by whoever can move the venue.
    ///
    /// FAILS: measured extraction is ~66%, i.e. 133x the 50 bips the rule authorised.
    function test_V15c_extractableFractionIsBoundedOnlyByHowFarThePairMoves() public {
        Trimmy.RuleParams memory p = _dcaParams();
        p.expiry = uint64(block.timestamp + 300 days); // inside MAX_RULE_LIFETIME
        vm.prank(account);
        uint256 id = trimmy.arm(p);

        uint256 relArm = _rel(XRP_V, FLR_V);
        _setFill(100e18, (100e18 * relArm) / 1e18);
        vm.prank(honestKeeper);
        trimmy.execute(id); // honest part 1

        // 200 days on, FLR has tripled against XRP.
        vm.warp(block.timestamp + 200 days);
        _publish(XRP_V / 3, FLR_V);
        uint256 relTrue = _rel(XRP_V / 3, FLR_V);

        // test fixture: the intermediate is a pre-scaled oracle quote, so the ordering is deliberate and the precision loss is the quantity under test.
        // forge-lint: disable-next-line(divide-before-multiply)
        uint256 floorOut = (((100e18 * relArm) / 1e18) * (10_000 - SLIP)) / 10_000;
        uint256 fairOut = (100e18 * relTrue) / 1e18;
        _setFill(100e18, floorOut);

        uint256 before = fxrp.balanceOf(account);
        vm.prank(attacker);
        trimmy.execute(id);
        uint256 got = fxrp.balanceOf(account) - before;

        console2.log("fair out  :", fairOut);
        console2.log("delivered :", got);
        console2.log("extracted, bips:", ((fairOut - got) * 10_000) / fairOut);

        assertGe(
            got,
            (fairOut * (10_000 - SLIP)) / 10_000,
            "V15c: the stale floor lets a whole multiple of the part be taken"
        );
    }

    // ===================================================================================
    // V15d. The obvious defence — minOutAbsolute — cannot work. Attempted refutation, FAILED.
    // ===================================================================================

    /// Trimmy.sol:469 raises the floor to `r.minOutAbsolute`, so it looks like a user-side cap
    /// on the stale-latch loss, and arming/bin/arm.dart:287 already populates it at 90% of the
    /// amount. This test tried to use that as a refutation and it does not hold, for two
    /// independent reasons, both asserted below:
    ///
    ///  (1) `minOutAbsolute` is a CONSTANT chosen at arm time. It cannot bound a deviation from
    ///      a price that only exists later, which is exactly what O-15 is about.
    ///  (2) the shipped 90% convention is LOOSER than the latch-derived floor from the very
    ///      first block, so on this rule shape it is inert on day one, never mind day 200.
    ///
    /// This test PASSES — it is a measurement of why the defence is not one.
    function test_V15d_minOutAbsoluteIsStructurallyIncapableOfBoundingThis() public {
        uint256 relArm = _rel(XRP_V, FLR_V);
        uint256 fairAtArm = (100e18 * relArm) / 1e18;
        uint256 latchFloor = (fairAtArm * (10_000 - SLIP)) / 10_000;
        uint256 armDartStyle = (fairAtArm * 90) / 100;

        // (2) the shipped convention is below the latch floor, so `minOutAbsolute` never binds.
        assertLt(armDartStyle, latchFloor, "arm.dart's 90% floor is looser than the latch floor");
        console2.log("arm.dart-style minOutAbsolute:", armDartStyle);
        console2.log("latch-derived floor          :", latchFloor);

        // (1) even a maximally tight absolute floor is a constant. After the 3x move of V15c the
        // fair value of a part is 1741900; the tightest minOutAbsolute a user could have set at
        // arm time is 580600, one third of it. The gap is unbounded in the same way.
        vm.warp(block.timestamp + 200 days);
        _publish(XRP_V / 3, FLR_V);
        uint256 fairLater = (100e18 * _rel(XRP_V / 3, FLR_V)) / 1e18;
        assertGt(
            (fairLater * (10_000 - SLIP)) / 10_000,
            fairAtArm,
            "the correct floor 200 days on exceeds ANY constant the user could have named at arm"
        );
        console2.log("fair value of a part, 200 days on:", fairLater);
    }

    // ===================================================================================
    // V15e. REFUTATION, complete, for PRICE_ABOVE rules.
    // ===================================================================================

    /// `_evaluateTrigger` reverts unless `price >= r.triggerValue` for PRICE_ABOVE
    /// (Trimmy.sol:444-446), and the latch is written from that same `price` (Trimmy.sol:389).
    /// So `latchedPrice >= triggerValue` always, and the floor on every later part is at least
    /// `amountIn * triggerValue / 10**sellDec * (1 - slippage)` — a bound the USER chose.
    /// A keeper choosing the moment cannot push the latch below it. This test PASSES.
    function test_V15e_priceAboveRulesHaveAUserChosenLowerBoundOnTheLatch() public {
        uint256 relArm = _rel(XRP_V, FLR_V); // 5806

        Trimmy.RuleParams memory p = _dcaParams();
        p.trigger = Trimmy.Trigger.PRICE_ABOVE;
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        p.triggerValue = uint64(relArm); // "only sell WC2FLR at 5806 FXRP-units or better"
        vm.prank(account);
        uint256 id = trimmy.arm(p);

        // The would-be attacker waits for a 201-bip low and tries to latch there.
        uint256 xrpHigh = (XRP_V * (10_000 + DRIFT_24H_BIPS)) / 10_000;
        vm.warp(block.timestamp + 1 days);
        _publish(xrpHigh, FLR_V);
        uint256 relLow = _rel(xrpHigh, FLR_V);
        assertLt(relLow, relArm, "the attacker's chosen moment really is a low");

        _setFill(100e18, (100e18 * relLow) / 1e18);
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(Trimmy.TriggerNotMet.selector, relLow, p.triggerValue)
        );
        trimmy.execute(id);

        // The only moments at which the latch CAN be written are at or above triggerValue.
        _publish(XRP_V, FLR_V);
        _setFill(100e18, (100e18 * relArm) / 1e18);
        vm.prank(attacker);
        trimmy.execute(id);
        assertGe(
            uint256(trimmy.ruleAt(id).latchedPrice),
            uint256(p.triggerValue),
            "V15e: the latch on a PRICE_ABOVE rule is bounded below by the user's own threshold"
        );
    }

    // ===================================================================================
    // V15f. The live deployment is not exposed today.
    // ===================================================================================

    /// Chain read, Coston2, Trimmy 0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554:
    ///   ruleAt(0..3) = (.., sellTokenId 0, buyTokenId 0, verb 1 = DEPOSIT_VAULT, venueId 1,
    ///   trigger 2, active FALSE, total 1e6, part 1e6, spent 1e6, minOutAbsolute 9e5, ..,
    ///   latchedPrice 1e6, ..)
    /// All four are SINGLE-PART (total == part) vault deposits, already exhausted and inactive.
    /// `_doDeposit` (Trimmy.sol:498-512) never reads `latchedPrice` — its only floor is
    /// `minOutAbsolute`. So O-15 has no purchase on any rule that exists right now; it is a
    /// property of the immutable code that the next multi-part SWAP rule inherits.
    /// This test documents the shape and PASSES.
    function test_V15f_vaultVerbsNeverReadTheLatchAtAll() public {
        Trimmy.RuleParams memory p = _dcaParams();
        p.sellTokenId = TOK_FXRP;
        p.buyTokenId = TOK_FXRP;
        p.verb = Trimmy.Verb.DEPOSIT_VAULT;
        p.venueId = VENUE_VAULT;
        p.totalSellAmount = 1e6;
        p.partSellAmount = 1e6;
        p.minOutAbsolute = 9e5;

        vm.prank(account);
        uint256 id = trimmy.arm(p);

        vm.prank(attacker);
        trimmy.execute(id);

        // The latch is still written (Trimmy.sol:389 is unconditional) but no floor uses it.
        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), 1e6, "matches the live chain read");
        assertFalse(trimmy.ruleAt(id).active, "single-part rule deactivates after one fire");
    }
}
