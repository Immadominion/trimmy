// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockQueuedVault} from "../mocks/Mocks.sol";

/// @title Adversarial verification of L-1 (EXIT_VAULT claimPeriod overwrite).
/// @notice Independent reproduction, a control that isolates the mechanism, and a test of a
///         STRONGER form of the claim than the original finding made.
contract VerifyL1Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockFtsoV2 internal ftso;
    MockRegistry internal registry;
    MockQueuedVault internal vault;

    address internal account = makeAddr("personalAccount");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("feeSink");

    uint64 internal constant MAX_FEED_AGE = 120; // the live value

    function setUp() public {
        vm.warp(10 days);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        ftso = new MockFtsoV2();
        registry = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        vault = new MockQueuedVault(IERC20(address(fxrp)));

        // The only configuration in which EXIT_VAULT is coherent: the sell token IS the share
        // token, because execute() pulls `amount` of sellToken and hands it to redeem() as shares.
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        trimmy = new Trimmy(tokens, venues, MAX_FEED_AGE, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(account, 10_000_000e6);
        vm.startPrank(account);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(1_000_000e6, account);
        vault.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();

        _feeds();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
    }

    function _armExit(uint128 total, uint128 part, uint64 interval) internal returns (uint256) {
        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: total,
            partSellAmount: part,
            minOutAbsolute: 0,
            triggerValue: interval,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(account);
        return trimmy.arm(p);
    }

    // ---------------------------------------------------------------------------------
    // CONTROL. Two parts inside the SAME period lose nothing. This isolates the mechanism:
    // the defect is the period straddle, not slicing per se.
    // ---------------------------------------------------------------------------------
    function test_L1_control_samePeriodTwoPartsLoseNothing() public {
        uint256 B = ((block.timestamp / 1 days) + 2) * 1 days;
        vm.warp(B - 10_000); // far from the boundary: both parts file under the same period

        uint256 id = _armExit(100e6, 50e6, 60);
        _feeds();
        vm.prank(keeper);
        trimmy.execute(id);
        uint64 p1 = trimmy.ruleAt(id).claimPeriod;

        vm.warp(vm.getBlockTimestamp() + 60);
        _feeds();
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).claimPeriod, p1, "same period, no overwrite");

        vm.warp(B + 1);
        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.claim(id);
        assertEq(fxrp.balanceOf(account) - before, 100e6, "control: nothing is lost");
        assertEq(vault.pendingWithdrawAssets(address(trimmy), p1), 0, "bucket drained");
    }

    // ---------------------------------------------------------------------------------
    // REPRODUCTION, independent of the original PoC's exact numbers. Three parts of 100e6,
    // the boundary crossed between part 2 and part 3.
    // ---------------------------------------------------------------------------------
    function test_L1_reproduce_straddleOrphansEveryEarlierBucket() public {
        uint256 B = ((block.timestamp / 1 days) + 2) * 1 days;
        uint256 lag = vault.lagDuration(); // 300, the live value
        // Two parts before the boundary, one after: t0 + 2*60 is the first fire with t + lag >= B.
        vm.warp(B - lag - 120);

        uint256 id = _armExit(300e6, 100e6, 60);

        _feeds();
        vm.prank(keeper);
        trimmy.execute(id);
        uint64 pOld = trimmy.ruleAt(id).claimPeriod;

        vm.warp(vm.getBlockTimestamp() + 60);
        _feeds();
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).claimPeriod, pOld, "still the old period");
        assertEq(vault.pendingWithdrawAssets(address(trimmy), pOld), 200e6, "200e6 filed under P");

        vm.warp(vm.getBlockTimestamp() + 60);
        _feeds();
        vm.prank(keeper);
        trimmy.execute(id);

        Trimmy.Rule memory r = trimmy.ruleAt(id);
        assertEq(uint256(r.claimPeriod), uint256(pOld) + 1, "claimPeriod overwritten");
        assertEq(r.pendingShares, 300e6, "pendingShares still counts all three parts");

        vm.warp(B + 2 days);
        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.claim(id);
        uint256 paid = fxrp.balanceOf(account) - before;

        // 200e6 is stranded in the vault under pOld and no Trimmy code path names pOld again.
        assertEq(vault.pendingWithdrawAssets(address(trimmy), pOld), 200e6, "orphaned");
        assertEq(paid, 100e6, "user got only the LAST bucket");
        assertEq(trimmy.ruleAt(id).pendingShares, 0, "and the rule forgot the rest");

        vm.prank(keeper);
        vm.expectRevert(Trimmy.NothingPending.selector);
        trimmy.claim(id);
    }

    // ---------------------------------------------------------------------------------
    // STRONGER THAN THE ORIGINAL FINDING. The original said "the FIRST bucket" is orphaned.
    // In fact a rule that keeps executing can NEVER be claimed at all while it runs: every
    // execution pushes claimPeriod to the current day index, and claimableAt with it.
    // ---------------------------------------------------------------------------------
    function test_L1_stronger_liveRuleIsNeverClaimableAndStrandsAWholeDay() public {
        uint256 B = ((block.timestamp / 1 days) + 2) * 1 days;
        vm.warp(B - 3600); // start an hour before midnight

        // 1e6 per part, one part per minute, 200 parts: 60 before the boundary, 140 after.
        uint256 id = _armExit(200e6, 1e6, 60);
        uint64 firstPeriod;

        for (uint256 i = 0; i < 200; i++) {
            _feeds();
            vm.prank(keeper);
            trimmy.execute(id);
            if (i == 0) firstPeriod = trimmy.ruleAt(id).claimPeriod;

            // The keeper tries to claim on every pass, exactly as keeper.dart does.
            vm.prank(keeper);
            (bool ok,) = address(trimmy).call(abi.encodeWithSelector(Trimmy.claim.selector, id));
            assertFalse(ok, "claim can never succeed while the rule is still executing");

            vm.warp(vm.getBlockTimestamp() + 60);
        }

        // Everything queued before the boundary is filed under firstPeriod and is now unreachable.
        uint256 stranded = vault.pendingWithdrawAssets(address(trimmy), firstPeriod);
        assertGt(stranded, 0, "a whole day's proceeds sit in a bucket the rule has forgotten");

        Trimmy.Rule memory r = trimmy.ruleAt(id);
        assertEq(r.spent, 200e6, "all shares burned");
        assertEq(r.pendingShares, 200e6, "rule thinks all 200e6 is still pending");

        // The rule is exhausted, so no further execute() moves claimPeriod. Now claim.
        vm.warp(uint256(r.claimPeriod + 1) * 1 days + 1);
        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.claim(id);
        uint256 paid = fxrp.balanceOf(account) - before;

        assertEq(
            vault.pendingWithdrawAssets(address(trimmy), firstPeriod),
            stranded,
            "the earlier bucket is still there after the only claim the rule allows"
        );
        emit log_named_uint("burned shares ", uint256(r.spent));
        emit log_named_uint("assets paid   ", paid);
        emit log_named_uint("assets orphaned", stranded);
        assertEq(paid, 200e6, "STRONGER CLAIM: user must receive assets for every share burned");
    }

    // ---------------------------------------------------------------------------------
    // The proposed fix (per-rule, per-period buckets) is NOT sufficient. The vault keys its
    // queue by (Trimmy address, period) only — so all rules and ALL USERS share one bucket
    // per period, and whichever rule claims first takes the lot.
    // ---------------------------------------------------------------------------------
    function test_L1_fixNote_bucketsAreSharedAcrossRulesAndUsers() public {
        address victim = makeAddr("victim");
        fxrp.mint(victim, 1_000e6);
        vm.startPrank(victim);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(500e6, victim);
        vault.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();

        uint256 B = ((block.timestamp / 1 days) + 2) * 1 days;
        vm.warp(B - 10_000);

        // Victim queues 100e6 through their own rule.
        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6,
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 60,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(victim);
        uint256 vid = trimmy.arm(p);
        // Attacker queues 1e6 in the SAME period.
        uint256 aid = _armExit(1e6, 1e6, 60);

        _feeds();
        vm.prank(keeper);
        trimmy.execute(vid);
        vm.prank(keeper);
        trimmy.execute(aid);

        vm.warp(B + 1);
        uint256 attackerBefore = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.claim(aid); // attacker's rule claims first

        assertEq(
            fxrp.balanceOf(account) - attackerBefore,
            1e6,
            "attacker rule must receive only its own 1e6"
        );
        vm.prank(keeper);
        trimmy.claim(vid);
        assertEq(fxrp.balanceOf(victim), 500e6 + 100e6, "victim must still get their 100e6");
    }
}
