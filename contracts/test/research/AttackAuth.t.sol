// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockQueuedVault} from "../mocks/Mocks.sol";

/// @title Attack: authorization
/// @notice Each test is a proof that an authorization claim made in the docs or in the contract's
///         own NatSpec is not what the deployed bytecode does.
contract AttackAuthTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockFtsoV2 internal ftso;
    MockRegistry internal registry;
    MockQueuedVault internal vault;

    address internal account = makeAddr("personalAccount");
    address internal guardian = makeAddr("guardian");
    address internal keeper = makeAddr("keeper");
    address internal attacker = makeAddr("attacker");
    address internal feeSink = makeAddr("protocolFeeRecipient");

    uint64 internal constant MAX_FEED_AGE = 60;

    function setUp() public {
        vm.warp(10 days);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        ftso = new MockFtsoV2();
        registry = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        vault = new MockQueuedVault(IERC20(address(fxrp)));

        // The sell token for an EXIT_VAULT rule is the vault SHARE token.
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
        vault.deposit(10_000e6, account);
        vault.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();

        _feeds();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
    }

    function _params(uint128 total, uint128 part, uint128 fee, uint128 budget)
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
    // A-1. The guardian cannot press the panic button.
    //
    // 02-ARCHITECTURE-ATTACK.md:377 states `cancelAll` authorises "`account` or
    // `guardians[account]`", and :422-424 instructs "choose one guardian registry — per-account
    // is the right one". The unified registry landed (`guardianOf`) but `cancelAll`
    // (Trimmy.sol:637) never consults it. A guardian calling `cancelAll` bumps its OWN epoch and
    // leaves the protected account's rules fully live.
    // ===================================================================================
    function test_A1_guardianCancelAllBumpsTheWrongEpoch() public {
        vm.prank(account);
        trimmy.setGuardian(guardian);
        assertEq(trimmy.guardianOf(account), guardian);

        uint256 id = _arm(account, _params(100e6, 50e6, 0, 0));

        // The guardian presses the panic button.
        vm.prank(guardian);
        trimmy.cancelAll(account);

        // It bumped the guardian's own epoch. The protected account's is untouched.
        assertEq(trimmy.epochOf(guardian), 1, "guardian bumped its own epoch");
        assertEq(trimmy.epochOf(account), 0, "the account being protected is unaffected");

        // And the rule the guardian tried to kill executes anyway.
        _feeds();
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).spent, 50e6, "rule fired after the guardian's panic button");
    }

    /// The same defect stated as the invariant that SHOULD hold. This test is red against the
    /// current code and is the one to keep after the fix.
    function test_A1_RED_guardianMustBeAbleToStopEveryRule() public {
        vm.prank(account);
        trimmy.setGuardian(guardian);
        uint256 id = _arm(account, _params(100e6, 50e6, 0, 0));

        vm.prank(guardian);
        trimmy.cancelAll(account);

        _feeds();
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.StaleEpoch.selector, uint32(0), uint32(1)));
        trimmy.execute(id);
    }

    /// The per-rule fallback cannot keep up: `cancel` needs a ruleId that exists, and a compromised
    /// account can arm new rules faster than the guardian can enumerate and cancel them.
    function test_A1b_guardianCannotOutpaceReArming() public {
        vm.prank(account);
        trimmy.setGuardian(guardian);

        uint256 id0 = _arm(account, _params(100e6, 50e6, 0, 0));

        // Guardian cancels every rule it can see.
        vm.prank(guardian);
        trimmy.cancel(id0);
        assertFalse(trimmy.ruleAt(id0).active);

        // The compromised account arms a fresh one in the very next transaction. The guardian has
        // no epoch authority, so nothing it did constrains this rule.
        uint256 id1 = _arm(account, _params(100e6, 50e6, 0, 0));
        _feeds();
        vm.prank(attacker); // execute is permissionless
        trimmy.execute(id1);
        assertEq(trimmy.ruleAt(id1).spent, 50e6, "re-armed rule fires despite an active guardian");
    }

    // ===================================================================================
    // A-2. `claim()` bypasses `_load` entirely: no `active`, no `epoch`, no `expiry`.
    //
    // Trimmy.sol:543-566 re-implements its own gate (verb / pendingShares / claimableAt) instead
    // of calling `_load` (:647-654). So neither `cancel` nor `cancelAll` reaches it, and a rule
    // the user believes is dead still runs `_settle`, paying `keeperFeeFlat` to whoever calls and
    // `protocolFeeBips` to the fee sink.
    // ===================================================================================
    function test_A2_claimSurvivesBothCancelPaths() public {
        uint256 id = _arm(account, _params(100e6, 100e6, 1e6, 1e6));

        _feeds();
        vm.prank(keeper);
        trimmy.execute(id); // queues the redemption

        // The user panics, using BOTH cancellation routes.
        vm.prank(account);
        trimmy.cancel(id);
        vm.prank(account);
        trimmy.cancelAll(account);

        // execute() is correctly dead...
        _feeds();
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.RuleInactive.selector, id));
        trimmy.execute(id);

        // ...but claim() is not gated by any of it.
        vm.warp(uint256(trimmy.ruleAt(id).claimableAt));
        uint256 attackerBefore = fxrp.balanceOf(attacker);
        vm.prank(attacker);
        trimmy.claim(id);

        assertEq(
            fxrp.balanceOf(attacker) - attackerBefore,
            1e6,
            "an arbitrary caller collected the keeper fee from a cancelled, stale-epoch rule"
        );
        assertEq(trimmy.ruleAt(id).pendingShares, 0);
    }

    // ===================================================================================
    // A-3. `arm()` is unauthenticated AND unmetered. It requires no tokens, no allowance and no
    // value. Every rule ever armed by anyone is appended to a single global `_rules` array that
    // the non-upgradeable contract can never prune, and the permissionless executor
    // (keeper.dart:232) walks it index 0..ruleCount() on every sweep.
    // ===================================================================================
    function test_A3_armCostsTheAttackerNothingAndIsUnprunable() public {
        assertEq(fxrp.balanceOf(attacker), 0, "attacker holds no tokens");
        assertEq(vault.balanceOf(attacker), 0, "attacker holds no shares");
        assertEq(vault.allowance(attacker, address(trimmy)), 0, "attacker granted no allowance");

        uint256 before = trimmy.ruleCount();
        for (uint256 i = 0; i < 64; i++) {
            _arm(attacker, _params(type(uint128).max, type(uint128).max, 0, 0));
        }
        assertEq(trimmy.ruleCount(), before + 64, "64 junk rules, zero capital required");

        // Every one of them passes the keeper's local filter (keeper.dart:76
        // `active && !exhausted`), so each costs the executor a full simulate round trip.
        for (uint256 i = before; i < before + 64; i++) {
            Trimmy.Rule memory r = trimmy.ruleAt(i);
            assertTrue(r.active, "junk rule is active");
            assertTrue(r.spent < r.totalSellAmount, "junk rule is not exhausted");
        }
    }

    /// The keeper's filter omits the expiry check the contract enforces at Trimmy.sol:651, so the
    /// junk survives its own expiry and is re-simulated on every sweep forever.
    function test_A3b_expiredJunkStillPassesTheKeeperFilter() public {
        uint256 id = _arm(attacker, _params(type(uint128).max, type(uint128).max, 0, 0));

        vm.warp(block.timestamp + 400 days);
        _feeds();

        Trimmy.Rule memory r = trimmy.ruleAt(id);
        assertTrue(block.timestamp > r.expiry, "rule is long expired");
        // keeper.dart:76 -> maybeExecutable == active && !exhausted. Expiry is not consulted.
        assertTrue(r.active && r.spent < r.totalSellAmount, "still passes maybeExecutable");

        // The contract does reject it — but only after the keeper has spent an RPC round trip.
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.RuleExpired.selector, id));
        trimmy.execute(id);
    }

    // ===================================================================================
    // A-4. `setGuardian` is only writable by the account itself, and the production arming batch
    // (arming/bin/arm.dart:165-169) emits exactly two calls — approve + arm. No code path in this
    // repo ever emits a `setGuardian` call, so `guardianOf` is address(0) for every real user.
    // This test pins the on-chain precondition: the guardian slot defaults to address(0) and the
    // ONLY writer is the account.
    // ===================================================================================
    function test_A4_guardianSlotIsWritableOnlyByTheAccountItself() public {
        assertEq(trimmy.guardianOf(account), address(0), "defaults to nobody");

        // Nobody else can install one on the account's behalf — not even the account's guardian.
        vm.prank(attacker);
        trimmy.setGuardian(guardian);
        assertEq(trimmy.guardianOf(attacker), guardian);
        assertEq(trimmy.guardianOf(account), address(0), "attacker cannot write another slot");

        // Which is correct — but it also means the ONLY way to get a guardian is a second XRPL
        // round trip with a hand-built batch that arm.dart cannot produce.
        uint256 id = _arm(account, _params(100e6, 50e6, 0, 0));
        vm.prank(guardian);
        vm.expectRevert(Trimmy.NotAuthorised.selector);
        trimmy.cancel(id);
    }
}
