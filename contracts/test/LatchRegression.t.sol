// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../src/Interfaces.sol";
import {Trimmy} from "../src/Trimmy.sol";
import {Quote} from "../src/Quote.sol";
import {
    MockERC20,
    MockFtsoV2,
    MockRegistry,
    MockSwapRouter,
    MockQueuedVault
} from "./mocks/Mocks.sol";

/// @title O-16 and O-18 regressions
/// @notice Both findings came from adversarial review of the deployed code, and both are about the
///         execution-floor latch being permanent and unconditional.
///
///   O-16: a rule that latched at a local maximum could never clear its own floor again. It was
///         bricked for its whole life, with a live allowance and no recovery.
///   O-18: `requireFresh` treated ANY future-dated feed as age zero, so one poisoned read set a
///         floor the rule then carried forever.
contract LatchRegressionTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant F_SELL =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant F_BUY =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal sell;
    MockERC20 internal buy;
    MockFtsoV2 internal ftso;
    MockSwapRouter internal router;

    address internal account = makeAddr("account");
    address internal keeper = makeAddr("keeper");

    uint256 internal constant SELL_USD = 3_000_000; // 3.00 at 6dp
    uint256 internal constant BUY_USD = 1_000_000; // 1.00 at 6dp

    function setUp() public {
        vm.warp(10 days);
        sell = new MockERC20("Sell", "S", 6);
        buy = new MockERC20("Buy", "B", 6);

        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        _feeds(SELL_USD, BUY_USD);

        router = new MockSwapRouter();
        router.setRateWad(3e18);

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(sell), feedId: F_SELL, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(buy), feedId: F_BUY, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(router), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });
        trimmy =
            new Trimmy(tokens, venues, 64, makeAddr("feeSink"), IConfidentialTrigger(address(0)));

        sell.mint(account, 1_000_000e6);
        vm.prank(account);
        sell.approve(address(trimmy), type(uint256).max);
    }

    function _feeds(uint256 s, uint256 b) internal {
        uint64 ts = uint64(vm.getBlockTimestamp());
        ftso.setFeed(F_SELL, s, 6, ts);
        ftso.setFeed(F_BUY, b, 6, ts);
    }

    function _rule() internal returns (uint256 id) {
        vm.prank(account);
        id = trimmy.arm(
            Trimmy.RuleParams({
                sellTokenId: 0,
                buyTokenId: 1,
                verb: Trimmy.Verb.SWAP,
                venueId: 0,
                trigger: Trimmy.Trigger.SCHEDULE,
                totalSellAmount: 100e6,
                partSellAmount: 50e6,
                minOutAbsolute: 0,
                triggerValue: 60,
                expiry: uint64(vm.getBlockTimestamp() + 30 days),
                slippageBips: 50,
                protocolFeeBips: 0,
                keeperFeeFlat: 0,
                keeperFeeBudget: 0
            })
        );
    }

    /// O-16. Latch at the top, then the market falls 30%. Before the fix the rule was permanently
    /// unfillable: the floor stayed pinned to the local maximum forever. Now the latch decays, so
    /// the rule is protected for a while and then executes at fair value.
    function test_O16_latchAtLocalMaximumDoesNotBrickTheRuleForever() public {
        uint256 id = _rule();

        // Part 1 at the top.
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).spent, 50e6, "first part filled");
        uint256 latched = trimmy.ruleAt(id).latchedPrice;

        // The market falls 30%; the venue follows it honestly.
        vm.warp(vm.getBlockTimestamp() + 120);
        _feeds((SELL_USD * 70) / 100, BUY_USD);
        router.setRateWad(2.1e18);

        // Immediately after the fall the latch still protects, so the venue cannot fill.
        vm.prank(keeper);
        vm.expectRevert(bytes("Too little received"));
        trimmy.execute(id);

        // Once the decay window has elapsed the same rule executes at the honest live price.
        vm.warp(vm.getBlockTimestamp() + trimmy.LATCH_DECAY_WINDOW());
        _feeds((SELL_USD * 70) / 100, BUY_USD);
        vm.prank(keeper);
        trimmy.execute(id);

        assertEq(trimmy.ruleAt(id).spent, 100e6, "the rule completed instead of bricking");
        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), latched, "the latch itself is unchanged");
    }

    /// The protection A12 bought is still there: mid-window, the floor is strictly above live.
    function test_A12_latchStillProtectsInsideTheWindow() public {
        uint256 id = _rule();
        vm.prank(keeper);
        trimmy.execute(id);

        vm.warp(vm.getBlockTimestamp() + 120);
        _feeds((SELL_USD * 70) / 100, BUY_USD);
        router.setRateWad(2.1e18); // venue at the new, lower, honest price

        vm.prank(keeper);
        vm.expectRevert(bytes("Too little received"));
        trimmy.execute(id);
    }

    /// A rising market must not be floored at the stale, lower latch — live wins.
    function test_latchNeverUnderProtectsOnARise() public {
        uint256 id = _rule();
        vm.prank(keeper);
        trimmy.execute(id);

        vm.warp(vm.getBlockTimestamp() + 120);
        _feeds(SELL_USD * 2, BUY_USD); // price doubled
        router.setRateWad(3e18); // venue still at the OLD price: a 50% underfill

        vm.prank(keeper);
        vm.expectRevert(bytes("Too little received"));
        trimmy.execute(id);
    }

    /// O-18. An arbitrarily future-dated feed used to pass as "age zero" and poison the latch.
    function test_O18_futureDatedFeedIsRefused() public {
        uint256 id = _rule();
        uint64 future = uint64(vm.getBlockTimestamp() + 3600);
        ftso.setFeed(F_SELL, SELL_USD * 5, 6, future);
        ftso.setFeed(F_BUY, BUY_USD, 6, future);

        vm.prank(keeper);
        vm.expectRevert();
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).latchedPrice, 0, "no latch was poisoned");
    }

    /// Ordinary clock skew of a couple of seconds is still tolerated.
    function test_O18_smallSkewIsStillFine() public {
        uint256 id = _rule();
        uint64 slightlyAhead = uint64(vm.getBlockTimestamp() + 3);
        ftso.setFeed(F_SELL, SELL_USD, 6, slightlyAhead);
        ftso.setFeed(F_BUY, BUY_USD, 6, slightlyAhead);

        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).spent, 50e6);
    }
}
