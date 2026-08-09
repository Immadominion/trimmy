// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {IConfidentialTrigger} from "../src/Interfaces.sol";
import {Trimmy} from "../src/Trimmy.sol";
import {
    MockERC20,
    MockFtsoV2,
    MockRegistry,
    MockSwapRouter,
    MockQueuedVault
} from "./mocks/Mocks.sol";

/// @notice Drives Trimmy through bounded random action sequences and records ghost totals.
/// @dev Every action is allowed to revert (`fail_on_revert = false`). A revert is a legitimate
///      outcome here — the point is that no *sequence* of calls, reverting or not, can break an
///      invariant.
contract TrimmyHandler is Test {
    using SafeCast for uint256;

    Trimmy public immutable trimmy;
    MockERC20 public immutable fxrp;
    MockERC20 public immutable usdt;
    MockFtsoV2 public immutable ftso;
    MockSwapRouter public immutable router;

    bytes21 internal immutable feedXrp;
    bytes21 internal immutable feedUsd;

    address public immutable account;
    address public immutable keeper;

    uint256[] public ruleIds;

    // Ghost accounting.
    uint256 public ghostPulled; // sell tokens that left the account
    uint256 public ghostToUser; // proceeds that reached the account
    uint256 public ghostKeeperFees;
    uint256 public ghostProtocolFees;
    uint256 public ghostExecutions;

    constructor(
        Trimmy t,
        MockERC20 f,
        MockERC20 u,
        MockFtsoV2 o,
        MockSwapRouter r,
        bytes21 fx,
        bytes21 fu,
        address acct,
        address kp
    ) {
        trimmy = t;
        fxrp = f;
        usdt = u;
        ftso = o;
        router = r;
        feedXrp = fx;
        feedUsd = fu;
        account = acct;
        keeper = kp;
    }

    function _refreshFeeds(uint256 xrpUsd) internal {
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(feedXrp, xrpUsd, 6, nowTs);
        ftso.setFeed(feedUsd, 1_000_000, 6, nowTs);
    }

    function armRule(uint256 total, uint256 part, uint256 feeFlat, uint8 triggerSeed) external {
        total = bound(total, 1e6, 10_000e6);
        part = bound(part, 1e6, total);
        feeFlat = bound(feeFlat, 0, 1e6);

        uint256 maxExec = (total - 1) / part + 1;

        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 1,
            verb: Trimmy.Verb.SWAP,
            venueId: 0,
            trigger: triggerSeed % 2 == 0 ? Trimmy.Trigger.PRICE_BELOW : Trimmy.Trigger.SCHEDULE,
            totalSellAmount: total.toUint128(),
            partSellAmount: part.toUint128(),
            minOutAbsolute: 0,
            triggerValue: triggerSeed % 2 == 0 ? 1_000_000_000 : 3600,
            expiry: uint64(vm.getBlockTimestamp() + 30 days),
            slippageBips: 50,
            protocolFeeBips: 10,
            keeperFeeFlat: feeFlat.toUint128(),
            keeperFeeBudget: (feeFlat * maxExec).toUint128()
        });

        // No try/catch. `fail_on_revert = false` already lets the fuzzer discard a reverting
        // call, and swallowing the revert here is what made an earlier version of this suite
        // vacuous: 6,586 arm calls, 0 reverts reported, 0 rules actually created.
        vm.prank(account);
        ruleIds.push(trimmy.arm(p));
    }

    function executeRule(uint256 seed) external {
        if (ruleIds.length == 0) return;
        uint256 id = ruleIds[seed % ruleIds.length];

        uint256 sellBefore = fxrp.balanceOf(account);
        uint256 buyBefore = usdt.balanceOf(account);
        uint256 kBefore = usdt.balanceOf(keeper);
        uint256 pBefore = usdt.balanceOf(trimmy.protocolFeeRecipient());

        vm.prank(keeper);
        trimmy.execute(id);

        ghostPulled += sellBefore - fxrp.balanceOf(account);
        ghostToUser += usdt.balanceOf(account) - buyBefore;
        ghostKeeperFees += usdt.balanceOf(keeper) - kBefore;
        ghostProtocolFees += usdt.balanceOf(trimmy.protocolFeeRecipient()) - pBefore;
        ghostExecutions++;
    }

    function cancelRule(uint256 seed) external {
        if (ruleIds.length == 0) return;
        uint256 id = ruleIds[seed % ruleIds.length];
        vm.prank(account);
        trimmy.cancel(id);
    }

    function cancelEverything() external {
        vm.prank(account);
        trimmy.cancelAll(account);
    }

    /// @dev Time and price both move, because a rule engine that only works on a frozen chain is
    ///      not a rule engine.
    function passTime(uint256 secs, uint256 priceSeed) external {
        secs = bound(secs, 1, 3 days);
        vm.warp(vm.getBlockTimestamp() + secs);

        // Keep the venue and oracle consistent, so reverts come from logic rather than from the
        // mock drifting away from the floor.
        uint256 xrpUsd = bound(priceSeed, 500_000, 10_000_000);
        _refreshFeeds(xrpUsd);
        router.setRateWad((xrpUsd * 1e18) / 1_000_000);
    }

    function ruleCount() external view returns (uint256) {
        return ruleIds.length;
    }
}

/// @title Trimmy invariants
/// @notice These encode the claims the submission makes. If one of them can be broken, the
///         corresponding sentence must be removed from the submission — not softened.
abstract contract TrimmyFixture is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_USD =
        bytes21(uint168(0x015553445430000000000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockERC20 internal usdt;
    MockFtsoV2 internal ftso;
    MockSwapRouter internal router;
    MockQueuedVault internal vault;
    TrimmyHandler internal handler;

    address internal account = makeAddr("personalAccount");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("protocolFeeRecipient");

    function setUp() public virtual {
        vm.warp(10 days);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        usdt = new MockERC20("TestUSDT", "USDT", 6);
        ftso = new MockFtsoV2();

        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        router = new MockSwapRouter();
        router.setRateWad(3e18);
        vault = new MockQueuedVault(IERC20(address(fxrp)));

        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, 3_000_000, 6, nowTs);
        ftso.setFeed(FEED_USD, 1_000_000, 6, nowTs);

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(usdt), feedId: FEED_USD, decimals: 6});

        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](2);
        venues[0] = Trimmy.VenueCfg({
            target: address(router), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });
        venues[1] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });

        trimmy = new Trimmy(tokens, venues, 3600, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(account, 100_000_000e6);
        vm.prank(account);
        fxrp.approve(address(trimmy), type(uint256).max);

        handler = new TrimmyHandler(
            trimmy, fxrp, usdt, ftso, router, FEED_XRP, FEED_USD, account, keeper
        );
    }
}

/// @title Trimmy invariants
/// @notice These encode the claims the submission makes. If one can be broken, the corresponding
///         sentence must be removed from the submission — not softened.
/// @dev Coverage (that the handler actually reaches `execute`) is proven separately in
///      `TrimmyCoverage.t.sol`. It deliberately does NOT live in `afterInvariant`: a coverage claim
///      is not shrink-stable, so the shrinker collapses every failure to a trivial short sequence
///      and hides the real one.
contract TrimmyInvariantTest is TrimmyFixture {
    function setUp() public override {
        super.setUp();
        targetContract(address(handler));
    }

    /// "Trimmy holds an allowance, never a balance, except within a single atomic transaction."
    /// This is the testable form of that sentence. If it fails, the sentence is false.
    function invariant_neverRetainsSellToken() public view {
        assertEq(fxrp.balanceOf(address(trimmy)), 0, "Trimmy retained sell tokens");
    }

    function invariant_neverRetainsBuyToken() public view {
        assertEq(usdt.balanceOf(address(trimmy)), 0, "Trimmy retained proceeds");
    }

    /// Conservation: every unit of proceeds is accounted for as user + keeper + protocol. If this
    /// drifts, value is being created or destroyed somewhere in _settle.
    function invariant_proceedsFullyAccounted() public view {
        assertEq(
            usdt.totalSupply(),
            handler.ghostToUser() + handler.ghostKeeperFees() + handler.ghostProtocolFees(),
            "proceeds unaccounted for"
        );
    }

    /// No rule may spend more than its lifetime budget, whatever the call sequence.
    function invariant_spentNeverExceedsTotal() public view {
        uint256 n = handler.ruleCount();
        for (uint256 i = 0; i < n; i++) {
            Trimmy.Rule memory r = trimmy.ruleAt(handler.ruleIds(i));
            assertLe(r.spent, r.totalSellAmount, "rule overspent its budget");
        }
    }

    /// The keeper fee is capped for the rule's whole life, not per execution.
    function invariant_keeperFeeWithinBudget() public view {
        uint256 n = handler.ruleCount();
        for (uint256 i = 0; i < n; i++) {
            Trimmy.Rule memory r = trimmy.ruleAt(handler.ruleIds(i));
            assertLe(r.keeperFeePaid, r.keeperFeeBudget, "keeper fee exceeded budget");
        }
    }

    /// An exhausted rule must be deactivated, never left active-but-unexecutable. A rule that is
    /// neither executable nor complete is the "stuck rule with a live allowance" failure.
    function invariant_exhaustedRulesAreInactive() public view {
        uint256 n = handler.ruleCount();
        for (uint256 i = 0; i < n; i++) {
            Trimmy.Rule memory r = trimmy.ruleAt(handler.ruleIds(i));
            if (r.spent >= r.totalSellAmount) {
                assertFalse(r.active, "exhausted rule left active");
            }
        }
    }

    /// The latch is monotone per rule: once set it identifies the price at first fire and is never
    /// silently reset, which is what stops a partial exit chasing the market down (A12).
    function invariant_latchSetOnceExecuted() public view {
        uint256 n = handler.ruleCount();
        for (uint256 i = 0; i < n; i++) {
            Trimmy.Rule memory r = trimmy.ruleAt(handler.ruleIds(i));
            if (r.spent > 0) {
                assertGt(r.latchedPrice, 0, "executed rule has no latched price");
            }
        }
    }
}
