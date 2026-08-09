// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test, console2} from "forge-std/Test.sol";
import {IConfidentialTrigger} from "../src/Interfaces.sol";
import {Trimmy} from "../src/Trimmy.sol";
import {Quote} from "../src/Quote.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockSwapRouter} from "./mocks/Mocks.sol";

/// Independent verification of M-1, using mantissas re-read from Coston2 FtsoV2
/// 0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d at block ts 1786078967 (2026-08-07 05:02:47 UTC),
/// NOT the numbers quoted in the claim:
///   XRP/USD = 1021695 @ 6dp ; FLR/USD = 592698 @ 8dp
/// Allowlist copied from live tokenAt(0)/tokenAt(1)/venueAt(0) of 0xf73a2af0…6554.
contract M1VerifyTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    uint256 internal constant XRP_USD = 1_021_695; // 6 dp, live 2026-08-07
    uint256 internal constant FLR_USD = 592_698; //   8 dp, live 2026-08-07

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockERC20 internal wc2flr;
    MockFtsoV2 internal ftso;
    MockSwapRouter internal router;
    address internal account = makeAddr("pa");
    address internal keeper = makeAddr("keeper");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wc2flr = new MockERC20("Wrapped C2FLR", "WC2FLR", 18);
        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        _feeds(XRP_USD, FLR_USD);
        router = new MockSwapRouter();

        Trimmy.TokenCfg[] memory t = new Trimmy.TokenCfg[](2);
        t[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        t[1] = Trimmy.TokenCfg({token: address(wc2flr), feedId: FEED_FLR, decimals: 18});
        Trimmy.VenueCfg[] memory v = new Trimmy.VenueCfg[](1);
        v[0] = Trimmy.VenueCfg({
            target: address(router), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });
        trimmy = new Trimmy(t, v, 120, makeAddr("sink"), IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1_000_000e6);
        vm.prank(account);
        fxrp.approve(address(trimmy), type(uint256).max);
    }

    function _feeds(uint256 x, uint256 f) internal {
        uint64 ts = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, x, 6, ts);
        ftso.setFeed(FEED_FLR, f, 8, ts);
    }

    function _p() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 1,
            verb: Trimmy.Verb.SWAP,
            venueId: 0,
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

    /// Step 1: _validate() lets the FXRP -> WC2FLR SWAP rule be armed at all.
    function test_reachable_armSwapFxrpToWc2flr() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_p());
        assertTrue(trimmy.ruleAt(id).active);
    }

    /// Step 2: the true relative price overflows uint64 with FRESH live mantissas.
    function test_liveRelativeOverflowsUint64() public view {
        uint256 rel = Quote.convert(
            1e6,
            Quote.Feed({value: XRP_USD, decimals: 6, timestamp: uint64(block.timestamp)}),
            6,
            Quote.Feed({value: FLR_USD, decimals: 8, timestamp: uint64(block.timestamp)}),
            18
        );
        console2.log("relative:", rel);
        console2.log("uint64max:", uint256(type(uint64).max));
        console2.log("overflow factor x100:", (rel * 100) / type(uint64).max);
        assertGt(rel, type(uint64).max);
    }

    /// REGRESSION for M-1. Before the fix this settled at ~11% of oracle fair value while
    /// reporting it had honoured a 50-bip floor. Now the floor is derived from an unsaturated
    /// `uint128` latch, so a venue offering 20 WC2FLR against the oracle's 172.28 cannot fill —
    /// the router rejects it on `amountOutMinimum`, exactly as the real V3 router would.
    function test_floorIsEnforcedAtDeclaredSlippage() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_p());

        uint256 rel = Quote.convert(
            1e6,
            Quote.Feed({value: XRP_USD, decimals: 6, timestamp: uint64(block.timestamp)}),
            6,
            Quote.Feed({value: FLR_USD, decimals: 8, timestamp: uint64(block.timestamp)}),
            18
        );
        uint256 fair = (100e6 * rel) / 1e6;

        // 20 WC2FLR per FXRP vs the oracle's 172.28. MockSwapRouter enforces amountOutMinimum
        // exactly as the real V3 router does, so this only settles because floorOut is low.
        router.setRateWad(20e18);
        vm.prank(keeper);
        vm.expectRevert(bytes("Too little received"));
        trimmy.execute(id);
        assertEq(wc2flr.balanceOf(account), 0, "nothing settled below the floor");

        // And the latch now holds the true relative price rather than a saturated sentinel.
        // For a 6dp sell token and an 18dp buy token, MockSwapRouter's decimal scaling means the
        // rate that reproduces the oracle is numerically the relative price itself.
        router.setRateWad(rel);
        vm.prank(keeper);
        trimmy.execute(id);
        uint128 latched = trimmy.ruleAt(id).latchedPrice;
        assertEq(uint256(latched), rel, "latch stores the exact relative price");
        assertGt(uint256(latched), uint256(type(uint64).max), "and it is past uint64, as measured");
        assertGe(wc2flr.balanceOf(account), (fair * 9950) / 10_000, "settled within 50 bips");
    }

    /// REGRESSION for M-1. Previously `triggerValue` was `uint64`, so the STRICTEST threshold a
    /// user could express was already below the live price — and PRICE_ABOVE fired after a 5x
    /// adverse move. With `uint128` the real price is expressible, so the comparison holds.
    function test_priceAboveDoesNotFireBelowItsThreshold() public {
        uint256 live = _liveRelative();

        Trimmy.RuleParams memory p = _p();
        p.trigger = Trimmy.Trigger.PRICE_ABOVE;
        // safe: `live` is a relative price for an allowlisted pair, ~1.7e20, far inside uint128.
        // forge-lint: disable-next-line(unsafe-typecast)
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        p.triggerValue = uint128(live); // a threshold at today's price: now expressible
        vm.prank(account);
        uint256 id = trimmy.arm(p);

        _feeds(XRP_USD / 5, FLR_USD); // 5x adverse move
        router.setRateWad(34e18);

        vm.prank(keeper);
        vm.expectRevert(); // TriggerNotMet — the price is genuinely below the threshold
        trimmy.execute(id);
        assertEq(wc2flr.balanceOf(account), 0, "PRICE_ABOVE must not fire below its threshold");
    }

    /// REGRESSION for M-1. Previously a PRICE_BELOW rule could not fire even after a 9x crash,
    /// because every price in that band saturated to the same `uint64` sentinel. Now a protective
    /// stop set just under today's price fires on the very next adverse tick, which is the entire
    /// point of the rule.
    function test_priceBelowFiresOnACrash() public {
        uint256 live = _liveRelative();

        Trimmy.RuleParams memory p = _p();
        p.trigger = Trimmy.Trigger.PRICE_BELOW;
        // safe: half of an already-uint128-bounded value.
        // forge-lint: disable-next-line(unsafe-typecast)
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        p.triggerValue = uint128(live / 2); // stop at half of today's price
        vm.prank(account);
        uint256 id = trimmy.arm(p);

        _feeds(XRP_USD / 9, FLR_USD); // a 9x crash, well through the stop
        router.setRateWad(_liveRelative()); // venue tracks the crashed oracle

        vm.prank(keeper);
        trimmy.execute(id);
        assertGt(wc2flr.balanceOf(account), 0, "a protective stop must fire on a crash");
    }

    function _liveRelative() internal view returns (uint256) {
        return Quote.convert(
            1e6,
            Quote.Feed({value: XRP_USD, decimals: 6, timestamp: uint64(block.timestamp)}),
            6,
            Quote.Feed({value: FLR_USD, decimals: 8, timestamp: uint64(block.timestamp)}),
            18
        );
    }

    /// Boundary: the comparison recovers once the true price falls below uint64max. This is what
    /// bounds the defect — the dead band is the whole realistic range, not literally all prices.
    function test_triggerRecoversBelowSaturation() public {
        Trimmy.RuleParams memory p = _p();
        p.trigger = Trimmy.Trigger.PRICE_ABOVE;
        p.triggerValue = type(uint64).max;
        vm.prank(account);
        uint256 id = trimmy.arm(p);

        _feeds(XRP_USD / 100, FLR_USD); // relative 1.72e18, comfortably inside uint64
        router.setRateWad(1.7e18);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                Trimmy.TriggerNotMet.selector, uint256(1_723_643_406_928_992_505), type(uint64).max
            )
        );
        trimmy.execute(id);
    }

    /// Control: DEPOSIT_VAULT / the four LIVE rules are 6dp->6dp, exponent 0, latch == 1e6. Fine.
    function test_liveRuleShapeIsUnaffected() public view {
        uint256 rel = Quote.convert(
            1e6,
            Quote.Feed({value: XRP_USD, decimals: 6, timestamp: uint64(block.timestamp)}),
            6,
            Quote.Feed({value: XRP_USD, decimals: 6, timestamp: uint64(block.timestamp)}),
            6
        );
        assertEq(rel, 1e6);
        assertLt(rel, type(uint64).max);
    }
}
