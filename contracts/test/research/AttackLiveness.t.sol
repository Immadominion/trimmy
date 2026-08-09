// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockQueuedVault} from "../mocks/Mocks.sol";

/// @title Liveness attack — proofs of concept
/// @notice These tests FAIL against the current code. Each one is a liveness or fund-availability
///         hole found by attacking the deployed contract rather than the spec.
contract AttackLivenessTest is Test {
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

    uint64 internal constant MAX_FEED_AGE = 60;

    function setUp() public {
        vm.warp(10 days);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        ftso = new MockFtsoV2();
        registry = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        vault = new MockQueuedVault(IERC20(address(fxrp)));

        // Sell token IS the vault share token: an EXIT_VAULT rule sells shares.
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        trimmy = new Trimmy(tokens, venues, MAX_FEED_AGE, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1_000_000e6);
        vm.startPrank(account);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(1000e6, account);
        vault.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();

        _feeds();
    }

    function _feeds() internal {
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, 3_000_000, 6, nowTs);
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

    // -----------------------------------------------------------------------------------
    // L-1. A sliced EXIT_VAULT rule that straddles a period boundary strands the first
    //      bucket permanently. `_doQueueRedeem` OVERWRITES `r.claimPeriod`, and `claim()`
    //      zeroes `pendingShares` wholesale after claiming only that one period.
    // -----------------------------------------------------------------------------------
    function test_L1_secondQueueOrphansFirstPeriodForever() public {
        // Position the clock so that part 1 files under period P and part 2, 60 s later, files
        // under P+1 — while claim of P is still in the future. That window is exactly
        // [B - lag - interval, B - lag) where B is the next UTC midnight; with the minimum
        // 60 s schedule interval a rule sweeps it every single day.
        uint256 B = ((block.timestamp / 1 days) + 2) * 1 days; // a future UTC midnight
        vm.warp(B - 330); // t1: t1 + 300 < B  ->  period P = B/1days - 1

        uint256 id = _armExit(100e6, 50e6, 60);
        _feeds();

        vm.prank(keeper);
        trimmy.execute(id);

        Trimmy.Rule memory r1 = trimmy.ruleAt(id);
        uint64 firstPeriod = r1.claimPeriod;
        assertEq(r1.pendingShares, 50e6, "part 1 queued");
        assertEq(uint256(r1.claimableAt), B, "part 1 claimable at the next UTC midnight");
        assertEq(vault.pendingWithdrawAssets(address(trimmy), firstPeriod), 50e6);

        // 60 s later. Still BEFORE B, so claim(P) is impossible — but t2 + 300 > B, so the
        // vault files part 2 under P+1.
        vm.warp(B - 270);
        _feeds();
        vm.prank(keeper);
        trimmy.execute(id);

        Trimmy.Rule memory r2 = trimmy.ruleAt(id);
        assertEq(uint256(r2.claimPeriod), uint256(firstPeriod) + 1, "period was overwritten");
        assertEq(r2.pendingShares, 100e6, "but pendingShares counts BOTH parts");

        // Claim, as late as you like.
        vm.warp(B + 3 days);
        _feeds();
        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.claim(id);
        uint256 paid = fxrp.balanceOf(account) - before;

        // The vault still holds the first bucket, and the rule has forgotten it.
        assertEq(
            vault.pendingWithdrawAssets(address(trimmy), firstPeriod),
            50e6,
            "first bucket is still sitting in the vault"
        );
        assertEq(trimmy.ruleAt(id).pendingShares, 0, "rule forgot there was anything pending");
        vm.prank(keeper);
        vm.expectRevert(Trimmy.NothingPending.selector);
        trimmy.claim(id);

        // THE ASSERTION THAT FAILS: the user redeemed 100e6 of shares and got 50e6 of assets.
        assertEq(paid, 100e6, "user must receive the assets for every share they burned");
    }

    // -----------------------------------------------------------------------------------
    // L-2. `_validate`'s L2 guarantee ("a rule whose fee budget cannot fund its own
    //      executions is refused") is void the moment the sell token charges a transfer fee —
    //      the exact scenario A9's balance-delta accounting was written for. `spent` grows by
    //      the measured delta, so the rule needs MORE executions than `_validate` budgeted,
    //      and the keeper is asked to work for nothing well before the rule is finished.
    // -----------------------------------------------------------------------------------
    function test_L2_transferFeeBreaksTheFeeBudgetGuarantee() public {
        // A DEPOSIT_VAULT rule whose sell token is FXRP — the token FAssets can put a
        // governance transfer fee on.
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        Trimmy depositor =
            new Trimmy(tokens, venues, MAX_FEED_AGE, feeSink, IConfidentialTrigger(address(0)));
        vm.prank(account);
        fxrp.approve(address(depositor), type(uint256).max);

        // keeperFeeFlat 1e6, budget 2e6 = exactly the 2 executions _validate says it needs.
        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.DEPOSIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6,
            partSellAmount: 50e6,
            minOutAbsolute: 0,
            triggerValue: 60,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 1e6,
            keeperFeeBudget: 2e6
        });
        vm.prank(account);
        uint256 id = depositor.arm(p);

        // Governance switches on the FAssets transfer fee — the exact scenario A9 exists for.
        fxrp.setTransferFeeBips(100); // 1%

        // Two executions, exactly what the budget funded.
        for (uint256 i = 0; i < 2; i++) {
            vm.warp(vm.getBlockTimestamp() + 120);
            _feeds();
            vm.prank(keeper);
            depositor.execute(id);
        }

        Trimmy.Rule memory r = depositor.ruleAt(id);
        // Budget is spent...
        assertEq(r.keeperFeePaid, 2e6, "budget fully consumed");
        // ...but the rule is not finished, and every remaining execution pays the keeper zero.
        assertTrue(r.active, "rule still live");
        assertLt(r.spent, r.totalSellAmount, "rule still has principal to move");
        assertEq(
            uint256(r.keeperFeeBudget - r.keeperFeePaid), 0, "nothing left to pay a keeper with"
        );

        // THE ASSERTION THAT FAILS: L2 promises a rule never stalls with an unfunded tail.
        assertEq(r.spent, r.totalSellAmount, "L2: a rule must not outlive its own fee budget");
    }

    // -----------------------------------------------------------------------------------
    // L-3. `_advance`'s jitter is advertised as making execution timing unpredictable to an
    //      observer. The result is written to public storage, so an observer reads it exactly.
    // -----------------------------------------------------------------------------------
    function test_L3_jitterIsPubliclyReadable() public {
        // A price-triggered rule so _advance takes the jitter branch.
        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.PRICE_ABOVE,
            totalSellAmount: 100e6,
            partSellAmount: 50e6,
            minOutAbsolute: 0,
            triggerValue: 1, // 1e6 units per whole share > 1, always met
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(account);
        uint256 id = trimmy.arm(p);

        vm.prank(keeper);
        trimmy.execute(id);

        uint64 next = trimmy.ruleAt(id).nextEligibleAt;
        // An "observer positioning around the floor" needs one eth_call, not a hash preimage.
        assertGe(next, block.timestamp + 60);
        assertLt(next, block.timestamp + 90);
        emit log_named_uint("nextEligibleAt, readable by anyone", next);

        // THE ASSERTION THAT FAILS: jitter cannot be a timing defence if it is public state.
        assertEq(uint256(next), 0, "jitter is not secret: nextEligibleAt is returned by ruleAt()");
    }
}
