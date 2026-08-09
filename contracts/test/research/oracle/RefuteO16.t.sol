// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {console2} from "forge-std/Test.sol";

import {Trimmy} from "../../../src/Trimmy.sol";
import {AttackOracle3Test} from "./AttackOracle3.t.sol";

/// @title Adversarial verification of O-16
/// @notice O-16 claims: "Latching at a local maximum is a PERMANENT one-transaction denial of
///         service on a multi-part rule", executed by an ATTACKER, for the rule's WHOLE LIFE.
///
///         The mechanism is real (the latch is written once, Trimmy.sol:389, and read as the
///         floor at Trimmy.sol:466-468). The three load-bearing words are not:
///
///         R1 — NOT PERMANENT. The block clears the instant the market comes back inside the
///              50-bip band the user themself authorised. The original PoC only produced a
///              28-day outage by *stipulating* the market sits 201 bips below the latch and
///              never moves again. Feed it a mean-reverting path instead and the rule fills
///              every remaining part and completes.
///
///         R2 — NO ATTACKER POWER. The latched value is whatever FTSO printed in that block.
///              An "attacker" and the victim's own keeper calling `execute` in the same block
///              latch bit-identical values. The attacker cannot move the price (the floor
///              never reads a venue) and cannot pick a block the honest keeper could not.
///
///         R3 — THE "ATTACK" PAYS THE VICTIM MORE. Latching high means part 1 was filled at
///              the high. The attacker's only lever — wait for a local maximum — is the lever
///              that maximises what the victim receives for part 1.
///
///         Inherits `AttackOracle3Test` so every number below is produced by the *same*
///         harness, mocks, decimals and measured constants as the finding it is testing.
contract RefuteO16Test is AttackOracle3Test {
    // ===================================================================================
    // R1. The outage is a market-path condition, not a permanent brick.
    // ===================================================================================

    /// PASSES against the current code. Same latch-at-the-local-maximum opening as
    /// `test_O16_latchingAtALocalMaximumBricksTheRuleForItsWholeLife`, then the only change:
    /// the market mean-reverts instead of being pinned 201 bips low forever.
    ///
    /// Result: parts 2 and 3 both fill and the rule reaches `active == false` — inside its
    /// 30-day expiry, with no cancel(), no re-arm and no cooperation from the attacker.
    function test_refuteO16_latchedRuleResumesAndCompletesWhenTheMarketComesBack() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        // --- identical to the O-16 PoC: attacker executes part 1 at a 201-bip local high ---
        uint256 xrpLow = (XRP_V * (10_000 - DRIFT_24H_BIPS)) / 10_000;
        _publish(xrpLow, FLR_V);
        uint256 relHigh = _rel(xrpLow, FLR_V);
        _setFill(100e18, (100 * relHigh * 10_001) / 10_000);
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(uint256(trimmy.ruleAt(id).latchedPrice), relHigh, "latched at the local maximum");

        // --- five days pinned 201 bips below the latch: the outage the finding describes ---
        uint256 relTrue = _rel(XRP_V, FLR_V);
        for (uint256 day = 1; day <= 5; day++) {
            vm.warp(vm.getBlockTimestamp() + 1 days + 1);
            _publish(XRP_V, FLR_V);
            _setFill(100e18, (100e18 * relTrue) / 1e18);
            vm.prank(keeper);
            vm.expectRevert();
            trimmy.execute(id);
        }
        assertEq(trimmy.ruleAt(id).spent, 100e18, "outage is real while the market is below");

        // --- day 6: the market recovers to 40 bips below the latch, i.e. INSIDE the 50-bip
        //     band the user signed for. The measured 24 h |move| p50 is 140 bips and the max
        //     is 201, so a 161-bip recovery is an ordinary day, not a rescue assumption. ---
        uint256 xrpBack = (XRP_V * (10_000 - (DRIFT_24H_BIPS - 40))) / 10_000;
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);
        _publish(xrpBack, FLR_V);
        uint256 relBack = _rel(xrpBack, FLR_V);
        _setFill(100e18, (100e18 * relBack) / 1e18);
        vm.prank(keeper);
        trimmy.execute(id); // part 2 clears the "permanent" floor
        assertEq(trimmy.ruleAt(id).spent, 200e18, "part 2 filled after the frozen latch");

        // --- day 7: part 3, same conditions. The rule finishes. ---
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);
        _publish(xrpBack, FLR_V);
        _setFill(100e18, (100e18 * relBack) / 1e18);
        vm.prank(keeper);
        trimmy.execute(id);

        Trimmy.Rule memory r = trimmy.ruleAt(id);
        console2.log("spent of totalSellAmount :", r.spent);
        console2.log("still latched at         :", r.latchedPrice);
        assertEq(r.spent, 300e18, "R1: the rule filled EVERY part after latching at the maximum");
        assertEq(r.active, false, "R1: the rule completed inside its 30-day life");
    }

    /// The outage boundary, stated exactly: execution resumes at latch*(1 - slippageBips),
    /// and not one unit below. Nothing about it is permanent or attacker-controlled — it is
    /// the user's own `slippageBips` measured from the first fill.
    function test_refuteO16_theBlockIsExactlyTheUsersOwnSlippageBandBelowTheLatch() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        _publish(XRP_V, FLR_V);
        uint256 rel = _rel(XRP_V, FLR_V);
        _setFill(100e18, (100e18 * rel) / 1e18);
        vm.prank(keeper);
        trimmy.execute(id);

        // test fixture: the intermediate is a pre-scaled oracle quote, so the ordering is deliberate and the precision loss is the quantity under test.
        // forge-lint: disable-next-line(divide-before-multiply)
        uint256 floorOut = (((100e18 * rel) / 1e18) * (10_000 - SLIP)) / 10_000;

        // one unit under the floor -> reverts
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);
        _publish(XRP_V, FLR_V);
        _setFill(100e18, floorOut - 1);
        vm.prank(keeper);
        vm.expectRevert();
        trimmy.execute(id);

        // exactly at the floor -> executes
        _setFill(100e18, floorOut);
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).spent, 200e18, "R1b: resumption threshold is latch - 50 bips");
    }

    // ===================================================================================
    // R2 / R3. The "attacker" is not one.
    // ===================================================================================

    /// PASSES. Two identical rules, same block, same feed. One is executed by the declared
    /// attacker, one by an honest keeper. The latched price is bit-identical: the writer of
    /// `latchedPrice` has no influence whatsoever over its value.
    function test_refuteO16_attackerAndHonestKeeperLatchTheIdenticalPrice() public {
        vm.startPrank(account);
        uint256 idAttacked = trimmy.arm(_dcaParams());
        uint256 idHonest = trimmy.arm(_dcaParams());
        vm.stopPrank();

        uint256 xrpLow = (XRP_V * (10_000 - DRIFT_24H_BIPS)) / 10_000;
        _publish(xrpLow, FLR_V);
        uint256 relHigh = _rel(xrpLow, FLR_V);
        _setFill(100e18, (100e18 * relHigh) / 1e18);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        trimmy.execute(idAttacked);
        vm.prank(keeper);
        trimmy.execute(idHonest);

        assertEq(
            trimmy.ruleAt(idAttacked).latchedPrice,
            trimmy.ruleAt(idHonest).latchedPrice,
            "R2: the caller's identity contributes nothing to the latched value"
        );
    }

    /// PASSES. The attacker's only lever is *when* to fire part 1, and firing at a local
    /// maximum hands the victim strictly MORE buy-token for part 1 than firing at the normal
    /// market would have. The "attack" is a gift with a liveness tail.
    function test_refuteO16_latchingHighPaysTheVictimMoreForPartOne() public {
        vm.startPrank(account);
        uint256 idHigh = trimmy.arm(_dcaParams());
        uint256 idNormal = trimmy.arm(_dcaParams());
        vm.stopPrank();

        // control: part 1 at the ordinary market
        _publish(XRP_V, FLR_V);
        uint256 relTrue = _rel(XRP_V, FLR_V);
        _setFill(100e18, (100e18 * relTrue) / 1e18);
        uint256 b0 = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(idNormal);
        uint256 gotNormal = fxrp.balanceOf(account) - b0;

        // the "attack": part 1 at the 201-bip local maximum
        uint256 xrpLow = (XRP_V * (10_000 - DRIFT_24H_BIPS)) / 10_000;
        _publish(xrpLow, FLR_V);
        uint256 relHigh = _rel(xrpLow, FLR_V);
        _setFill(100e18, (100e18 * relHigh) / 1e18);
        uint256 b1 = fxrp.balanceOf(account);
        vm.prank(makeAddr("attacker"));
        trimmy.execute(idHigh);
        uint256 gotAttacked = fxrp.balanceOf(account) - b1;

        console2.log("part 1 fill, honest timing :", gotNormal);
        console2.log("part 1 fill, 'attack'      :", gotAttacked);
        assertGt(gotAttacked, gotNormal, "R3: the attacker's timing improves the victim's fill");
    }

    /// PASSES. While the latch blocks the rule, the standing allowance is NOT exposed: the
    /// reverting `execute` unwinds the `safeTransferFrom` with it, so the account's balance
    /// and `spent` are untouched by 28 failed days.
    function test_refuteO16_blockedRuleDrainsNothingFromTheStandingAllowance() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_dcaParams());

        uint256 xrpLow = (XRP_V * (10_000 - DRIFT_24H_BIPS)) / 10_000;
        _publish(xrpLow, FLR_V);
        _setFill(100e18, (100 * _rel(xrpLow, FLR_V) * 10_001) / 10_000);
        vm.prank(keeper);
        trimmy.execute(id);

        uint256 balAfterPart1 = wnat.balanceOf(account);
        uint256 relTrue = _rel(XRP_V, FLR_V);
        for (uint256 day = 1; day <= 28; day++) {
            vm.warp(vm.getBlockTimestamp() + 1 days + 1);
            _publish(XRP_V, FLR_V);
            _setFill(100e18, (100e18 * relTrue) / 1e18);
            vm.prank(keeper);
            vm.expectRevert();
            trimmy.execute(id);
        }
        assertEq(wnat.balanceOf(account), balAfterPart1, "R4: 28 blocked days move zero tokens");
        assertEq(trimmy.ruleAt(id).spent, 100e18, "R4: no accounting drift either");
    }
}
