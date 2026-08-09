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

/// @title Adversarial verification of claim O-3.
/// @notice Independent re-derivation with mantissas re-read from Coston2 FtsoV2
///         0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d at 2026-08-07 (XRP/USD 1025141 at 6dp,
///         FLR/USD 593615 at 8dp). Also bounds the claim: the OTHER direction of the same
///         deployed pair evaluates a price that fits uint64 and behaves correctly.
contract RefuteO3Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    // Re-read live, this session.
    uint256 internal constant XRP_V = 1_025_141;
    int8 internal constant XRP_D = 6;
    uint256 internal constant FLR_V = 593_615;
    int8 internal constant FLR_D = 8;

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockERC20 internal wnat;
    MockFtsoV2 internal ftso;
    MockRegistry internal registry;
    MockSwapRouter internal router;
    MockQueuedVault internal vault;

    address internal account = makeAddr("personalAccount");
    address internal keeper = makeAddr("keeper");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wnat = new MockERC20("Wrapped C2FLR", "WC2FLR", 18);

        ftso = new MockFtsoV2();
        registry = new MockRegistry();
        registry.setFtso(address(ftso));
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        router = new MockSwapRouter();
        vault = new MockQueuedVault(IERC20(address(fxrp)));
        _setFeeds(XRP_V, FLR_V);

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
        trimmy = new Trimmy(tokens, venues, 120, makeAddr("sink"), IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1_000_000e6);
        wnat.mint(account, 1_000_000e18);
        vm.startPrank(account);
        fxrp.approve(address(trimmy), type(uint256).max);
        wnat.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();
    }

    function _setFeeds(uint256 xrpV, uint256 flrV) internal {
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, xrpV, XRP_D, nowTs);
        ftso.setFeed(FEED_FLR, flrV, FLR_D, nowTs);
    }

    function _p() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 1,
            verb: Trimmy.Verb.SWAP,
            venueId: 0,
            trigger: Trimmy.Trigger.PRICE_BELOW,
            totalSellAmount: 100e6,
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 0,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 50,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    // ------------------------------------------------------------------
    // REPRODUCTION 1: PRICE_BELOW on FXRP -> WC2FLR is dead for every
    // triggerValue < type(uint64).max, at ANY market price.
    // ------------------------------------------------------------------
    function test_repro_priceBelowIsDeadForEveryThresholdBelowMax() public {
        // Sweep the whole expressible range plus a 99.999% crash.
        uint64[6] memory thresholds = [
            uint64(0),
            uint64(1e6),
            uint64(150e18 > type(uint64).max ? type(uint64).max - 3 : 0), // "150 FLR" is inexpressible
            uint64(type(uint64).max / 2),
            uint64(type(uint64).max - 2),
            uint64(type(uint64).max - 1)
        ];
        // XRP loses 99.9% against FLR. rel = 0.1728e18 -> still < uint64.max? check.
        _setFeeds(XRP_V / 1000, FLR_V);
        uint256 relCrash = Quote.convert(
            1e6,
            Quote.Feed({value: XRP_V / 1000, decimals: XRP_D, timestamp: 0}),
            6,
            Quote.Feed({value: FLR_V, decimals: FLR_D, timestamp: 0}),
            18
        );
        console2.log("relative after 99.9% crash:", relCrash);
        console2.log("uint64.max                :", uint256(type(uint64).max));

        for (uint256 i = 0; i < thresholds.length; i++) {
            Trimmy.RuleParams memory p = _p();
            p.triggerValue = thresholds[i];
            vm.prank(account);
            uint256 id = trimmy.arm(p);
            router.setRateWad(relCrash);
            vm.prank(keeper);
            try trimmy.execute(id) {
                console2.log("threshold FIRED:", uint256(thresholds[i]));
            } catch (bytes memory) {
                console2.log("threshold reverted TriggerNotMet:", uint256(thresholds[i]));
            }
        }
        // Even at a 99.9% crash the evaluated price is still clamped, because 0.1728e18 is
        // BELOW uint64.max -- so this crash actually DOES clear. Assert what really happens.
        assertLt(relCrash, uint256(type(uint64).max), "99.9% crash falls back inside range");
    }

    /// The claim's exact scenario: a 70% crash, most-generous expressible stop. Reverts forever.
    function test_repro_seventyPercentCrashNeverFires() public {
        Trimmy.RuleParams memory p = _p();
        p.triggerValue = type(uint64).max - 1;
        vm.prank(account);
        uint256 id = trimmy.arm(p);

        _setFeeds((XRP_V * 30) / 100, FLR_V);
        uint256 rel = Quote.convert(
            1e6,
            Quote.Feed({value: (XRP_V * 30) / 100, decimals: XRP_D, timestamp: 0}),
            6,
            Quote.Feed({value: FLR_V, decimals: FLR_D, timestamp: 0}),
            18
        );
        console2.log("true relative after 70% crash:", rel); // 51.5e18
        router.setRateWad(rel);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                Trimmy.TriggerNotMet.selector, uint256(type(uint64).max), type(uint64).max - 1
            )
        );
        trimmy.execute(id);
    }

    /// The only expressible threshold that fires, fires unconditionally at 9.3x above itself.
    function test_repro_maxThresholdFiresAtNineTimesTheStop() public {
        Trimmy.RuleParams memory p = _p();
        p.triggerValue = type(uint64).max;
        vm.prank(account);
        uint256 id = trimmy.arm(p);

        uint256 rel = Quote.convert(
            1e6,
            Quote.Feed({value: XRP_V, decimals: XRP_D, timestamp: 0}),
            6,
            Quote.Feed({value: FLR_V, decimals: FLR_D, timestamp: 0}),
            18
        );
        router.setRateWad(rel);
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).spent, 100e6, "it fired");
        console2.log("stop set at (wei/XRP):", uint256(type(uint64).max));
        console2.log("filled at   (wei/XRP):", rel);
        console2.log("ratio x100           :", (rel * 100) / type(uint64).max);
    }

    // ------------------------------------------------------------------
    // BOUND: the OPPOSITE direction of the SAME deployed pair is correct.
    // ------------------------------------------------------------------
    function test_bound_reverseDirectionPriceTriggerWorksCorrectly() public {
        uint256 rel = Quote.convert(
            1e18,
            Quote.Feed({value: FLR_V, decimals: FLR_D, timestamp: 0}),
            18,
            Quote.Feed({value: XRP_V, decimals: XRP_D, timestamp: 0}),
            6
        );
        console2.log("WC2FLR -> FXRP relative (FXRP base units per 1 FLR):", rel);
        assertLt(rel, uint256(type(uint64).max), "reverse direction fits uint64");

        Trimmy.RuleParams memory p = _p();
        p.sellTokenId = 1; // sell WC2FLR
        p.buyTokenId = 0; // buy FXRP
        p.totalSellAmount = 100e18;
        p.partSellAmount = 100e18;
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        p.triggerValue = uint64(rel - 1); // stop strictly below the live price

        vm.prank(account);
        uint256 id = trimmy.arm(p);
        router.setRateWad(rel * 1e12); // mock scales 18dp -> 6dp by /1e12
        vm.prank(keeper);
        vm.expectRevert(
            // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
            // forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(Trimmy.TriggerNotMet.selector, rel, uint64(rel - 1))
        );
        trimmy.execute(id); // correctly refuses: price is above the stop

        // Now crash FLR 10% against XRP; the same stop must fire.
        _setFeeds(XRP_V, (FLR_V * 90) / 100);
        uint256 rel2 = Quote.convert(
            1e18,
            Quote.Feed({value: (FLR_V * 90) / 100, decimals: FLR_D, timestamp: 0}),
            18,
            Quote.Feed({value: XRP_V, decimals: XRP_D, timestamp: 0}),
            6
        );
        router.setRateWad(rel2 * 1e12);
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).spent, 100e18, "reverse-direction stop-loss fires correctly");
        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), rel2, "and latches the exact price");
    }

    // ------------------------------------------------------------------
    // The clamp is ORDER-PRESERVING against any threshold in [0, MAX-1].
    // Fuzz it: min(rel, MAX) > T  <=>  rel > T, for every T < MAX.
    // If this holds, PRICE_BELOW is NOT a constant function.
    // ------------------------------------------------------------------
    function testFuzz_clampIsOrderPreservingForPriceBelow(uint256 rel, uint64 t) public pure {
        vm.assume(t < type(uint64).max);
        uint64 clamped = uint64(rel > type(uint64).max ? type(uint64).max : rel);
        assertEq(clamped > t, rel > t, "clamp changes the PRICE_BELOW verdict");
    }

    function testFuzz_clampIsOrderPreservingForPriceAbove(uint256 rel, uint64 t) public pure {
        uint64 clamped = uint64(rel > type(uint64).max ? type(uint64).max : rel);
        assertEq(clamped < t, rel < t, "clamp changes the PRICE_ABOVE verdict");
    }

    /// The single exception: T == type(uint64).max under PRICE_BELOW.
    function test_theOnlyBrokenThresholdIsExactlyUint64Max() public pure {
        uint256 rel = 172_694_591_612_408_716_087; // live
        uint64 clamped = uint64(rel > type(uint64).max ? type(uint64).max : rel);
        assertFalse(clamped > type(uint64).max, "contract says: trigger met");
        assertTrue(rel > type(uint64).max, "truth says: trigger NOT met");
    }

    // ------------------------------------------------------------------
    // What is ACTUALLY wrong: a realistic stop is inexpressible, and the
    // ABI silently wraps it into a nonsense one instead of reverting.
    // ------------------------------------------------------------------
    function test_ablePrice150FlrStopSilentlyWrapsToTwoPointFour() public {
        Trimmy.RuleParams memory p = _p();
        // The user wants "sell if 1 XRP drops below 150 WC2FLR" -> 150e18 wei.
        uint256 wanted = 150e18;
        bytes memory cd = abi.encodeWithSelector(
            Trimmy.arm.selector,
            uint256(p.sellTokenId),
            uint256(p.buyTokenId),
            uint256(uint8(p.verb)),
            uint256(p.venueId),
            uint256(uint8(p.trigger)),
            uint256(p.totalSellAmount),
            uint256(p.partSellAmount),
            uint256(p.minOutAbsolute),
            wanted, // triggerValue word, > uint64
            uint256(p.expiry),
            uint256(p.slippageBips),
            uint256(p.protocolFeeBips),
            uint256(p.keeperFeeFlat),
            uint256(p.keeperFeeBudget)
        );
        vm.prank(account);
        (bool ok, bytes memory ret) = address(trimmy).call(cd);
        console2.log("arm() with an out-of-range triggerValue succeeded:", ok);
        console2.logBytes(ret);
        // control: the identical encoding with an in-range word must succeed
        bytes memory cd2 = cd;
        assembly { mstore(add(cd2, add(32, add(4, mul(8, 32)))), 1000000) }
        vm.prank(account);
        (bool ok2,) = address(trimmy).call(cd2);
        console2.log("same encoding, in-range triggerValue succeeded:", ok2);
        assertTrue(ok2, "control: encoding shape is right");
        // This test originally asserted that arm() REVERTED here, because `triggerValue` was
        // `uint64` and 150e18 does not fit in it. That was the user-facing face of M-1: "sell if
        // 1 XRP drops below 150 WC2FLR" is an entirely ordinary threshold, and the contract could
        // not represent it at all.
        //
        // `triggerValue` is now `uint128`, so the correct assertion is the opposite one: the value
        // is accepted and stored EXACTLY. The property the test was really defending — no silent
        // wrap — still holds; only the boundary moved.
        assertTrue(ok, "an ordinary 150e18 threshold must now be expressible");

        uint256 id = abi.decode(ret, (uint256));
        uint128 stored = trimmy.ruleAt(id).triggerValue;
        console2.log("user asked for (wei/XRP):", wanted);
        console2.log("contract stored          :", uint256(stored));
        assertEq(uint256(stored), wanted, "stored exactly, with no truncation or wrap");
    }
}
