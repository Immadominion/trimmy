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

/// @title Trimmy core behaviour
/// @notice Each test names the finding it defends. A test that does not defend a finding or a
///         stated requirement is not carrying its weight.
contract TrimmyTest is Test {
    // The real Flare registry address, which Trimmy hardcodes. Etched with a mock here.
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_USD =
        bytes21(uint168(0x015553445430000000000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp; // 6 dp, the sell token
    MockERC20 internal usdt; // 6 dp, the buy token
    MockFtsoV2 internal ftso;
    MockRegistry internal registry;
    MockSwapRouter internal router;
    MockQueuedVault internal vault;

    address internal account = makeAddr("personalAccount");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("protocolFeeRecipient");
    address internal attacker = makeAddr("attacker");

    uint8 internal constant TOK_FXRP = 0;
    uint8 internal constant TOK_USDT = 1;
    uint8 internal constant VENUE_SWAP = 0;
    uint8 internal constant VENUE_VAULT = 1;

    uint64 internal constant MAX_FEED_AGE = 60;

    function setUp() public {
        vm.warp(10 days); // day-index arithmetic needs a non-zero clock

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        usdt = new MockERC20("TestUSDT", "USDT", 6);

        ftso = new MockFtsoV2();
        registry = new MockRegistry();
        registry.setFtso(address(ftso));
        // Trimmy hardcodes the registry address, so place the mock there.
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        router = new MockSwapRouter();
        vault = new MockQueuedVault(IERC20(address(fxrp)));

        // XRP/USD = 3.00 at 6 dp; USDT/USD = 1.00 at 6 dp.
        _setFeeds(3_000_000, 1_000_000);

        // The venue must agree with the oracle for the happy path to be a happy path. Leaving the
        // mock at 1:1 while the oracle says 3:1 means every swap is ~67% below the floor and every
        // execution correctly reverts — which is the floor working, not the contract failing.
        // Tests that want a deviation set this explicitly.
        router.setRateWad(3e18);

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

        trimmy = new Trimmy(tokens, venues, MAX_FEED_AGE, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1_000_000e6);
        vm.prank(account);
        fxrp.approve(address(trimmy), type(uint256).max);
    }

    function _setFeeds(uint256 xrpUsd, uint256 usdtUsd) internal {
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, xrpUsd, 6, nowTs);
        ftso.setFeed(FEED_USD, usdtUsd, 6, nowTs);
    }

    function _swapParams() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: TOK_FXRP,
            buyTokenId: TOK_USDT,
            verb: Trimmy.Verb.SWAP,
            venueId: VENUE_SWAP,
            trigger: Trimmy.Trigger.PRICE_BELOW,
            totalSellAmount: 100e6,
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 4_000_000, // fires while XRP <= 4.00 USDT
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 50,
            protocolFeeBips: 10,
            keeperFeeFlat: 1e6,
            keeperFeeBudget: 10e6
        });
    }

    function _arm(Trimmy.RuleParams memory p) internal returns (uint256 id) {
        vm.prank(account);
        id = trimmy.arm(p);
    }

    // =======================================================================================
    // Arming
    // =======================================================================================

    /// The rule is bound to msg.sender. This is the whole reason a leaked keeper key is worthless.
    function test_arm_bindsCallerAsAccount() public {
        uint256 id = _arm(_swapParams());
        assertEq(trimmy.ruleAt(id).account, account);
    }

    function test_arm_rejectsUnknownToken() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.buyTokenId = 99;
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.UnknownToken.selector, uint8(99)));
        trimmy.arm(p);
    }

    function test_arm_rejectsUnknownVenue() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.venueId = 42;
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.UnknownVenue.selector, uint8(42)));
        trimmy.arm(p);
    }

    /// A2: slippage is the attacker's extractable band, so the cap is enforced, not advisory.
    function test_arm_rejectsSlippageAboveCap() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.slippageBips = 51;
        vm.prank(account);
        vm.expectRevert(
            abi.encodeWithSelector(Trimmy.SlippageTooHigh.selector, uint16(51), uint16(50))
        );
        trimmy.arm(p);
    }

    /// L2: a rule whose fee budget cannot fund its own executions stops silently partway through,
    /// with a live allowance and months left. It must be refused at arm time.
    function test_arm_rejectsUnfundableFeeBudget() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.totalSellAmount = 100e6;
        p.partSellAmount = 10e6; // 10 executions
        p.keeperFeeFlat = 1e6; // needs 10e6
        p.keeperFeeBudget = 5e6; // has 5e6
        vm.prank(account);
        vm.expectRevert(
            abi.encodeWithSelector(
                Trimmy.FeeBudgetCannotFundExecutions.selector, uint128(5e6), uint256(10e6)
            )
        );
        trimmy.arm(p);
    }

    function test_arm_rejectsVenueKindMismatch() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.venueId = VENUE_VAULT; // a vault, but verb is SWAP
        vm.prank(account);
        vm.expectRevert(
            abi.encodeWithSelector(Trimmy.VenueKindMismatch.selector, VENUE_VAULT, Trimmy.Verb.SWAP)
        );
        trimmy.arm(p);
    }

    function test_arm_rejectsExpiryInPast() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.expiry = uint64(block.timestamp);
        vm.prank(account);
        vm.expectRevert(Trimmy.BadExpiry.selector);
        trimmy.arm(p);
    }

    // =======================================================================================
    // Execution
    // =======================================================================================

    function test_execute_happyPath() public {
        uint256 id = _arm(_swapParams());

        uint256 userBefore = usdt.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id);

        // 100 FXRP at 3.00 = 300 USDT gross, minus 1 USDT keeper fee, minus 10 bips protocol fee.
        uint256 keeperFee = 1e6;
        uint256 protocolFee = ((300e6 - keeperFee) * 10) / 10_000;

        assertEq(usdt.balanceOf(keeper), keeperFee, "keeper paid");
        assertEq(usdt.balanceOf(feeSink), protocolFee, "protocol paid");
        assertEq(usdt.balanceOf(account) - userBefore, 300e6 - keeperFee - protocolFee, "user paid");
        assertEq(trimmy.ruleAt(id).spent, 100e6);
    }

    /// The keeper fee goes to msg.sender and nothing else does. Anyone can execute.
    function test_execute_isPermissionless() public {
        uint256 id = _arm(_swapParams());
        vm.prank(attacker);
        trimmy.execute(id);
        assertEq(usdt.balanceOf(attacker), 1e6, "any caller earns the fee");
        assertGt(usdt.balanceOf(account), 0, "proceeds still go to the account");
    }

    /// A1: there is no `receiver` field, so proceeds cannot be redirected. The attacker executing
    /// the rule earns only the fee and cannot touch the principal.
    function test_execute_proceedsAlwaysGoToAccount() public {
        uint256 id = _arm(_swapParams());
        vm.prank(attacker);
        trimmy.execute(id);
        uint256 expectedUser = 300e6 - 1e6 - (((300e6 - 1e6) * 10) / 10_000);
        assertEq(usdt.balanceOf(account), expectedUser);
        assertEq(usdt.balanceOf(attacker), 1e6);
    }

    function test_execute_revertsWhenTriggerNotMet() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.trigger = Trimmy.Trigger.PRICE_BELOW;
        p.triggerValue = 2_000_000; // fires only below 2.00; price is 3.00
        uint256 id = _arm(p);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                Trimmy.TriggerNotMet.selector, uint256(3_000_000), uint64(2_000_000)
            )
        );
        trimmy.execute(id);
    }

    /// Rule 6 / rule 7: a stale feed means do not execute. Unknown is never safe.
    function test_execute_revertsOnStaleFeed() public {
        uint256 id = _arm(_swapParams());
        vm.warp(vm.getBlockTimestamp() + MAX_FEED_AGE + 1);

        vm.prank(keeper);
        vm.expectRevert();
        trimmy.execute(id);
    }

    /// A15: the router's claimed return value is not evidence. Trimmy measures its own delta.
    function test_execute_catchesUnderdeliveringRouter() public {
        uint256 id = _arm(_swapParams());
        router.setUnderdeliver(true);

        vm.prank(keeper);
        vm.expectRevert();
        trimmy.execute(id);
    }

    /// A2: the floor is enforced. Move the venue price away from the oracle and execution must fail
    /// rather than fill at the worse price.
    function test_execute_floorBitesWhenVenuePriceIsWorse() public {
        uint256 id = _arm(_swapParams());
        router.setRateWad(2.9e18); // ~3.3% below the 3.00 oracle, far past 50 bips

        vm.prank(keeper);
        vm.expectRevert();
        trimmy.execute(id);
    }

    /// A9: charge the measured delta, not the requested amount. With a transfer fee, `spent` must
    /// reflect what actually arrived.
    function test_execute_chargesMeasuredDeltaUnderTransferFee() public {
        uint256 id = _arm(_swapParams());
        fxrp.setTransferFeeBips(100); // 1%

        vm.prank(keeper);
        trimmy.execute(id);

        assertEq(trimmy.ruleAt(id).spent, 99e6, "spent is what arrived, not what was asked for");
    }

    /// A8: the final part takes the remainder rather than reverting on a dust tail.
    function test_execute_finalPartTakesRemainder() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.totalSellAmount = 25e6;
        p.partSellAmount = 10e6; // 10 + 10 + 5
        p.keeperFeeBudget = 10e6;
        uint256 id = _arm(p);

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(keeper);
            trimmy.execute(id);
            vm.warp(vm.getBlockTimestamp() + 120);
            _setFeeds(3_000_000, 1_000_000);
        }

        vm.prank(keeper);
        trimmy.execute(id); // the 5e6 dust tail must not revert

        Trimmy.Rule memory r = trimmy.ruleAt(id);
        assertEq(r.spent, 25e6);
        assertFalse(r.active, "exhausted rule deactivates");
    }

    function test_execute_revertsWhenExhausted() public {
        uint256 id = _arm(_swapParams());
        vm.prank(keeper);
        trimmy.execute(id);

        vm.warp(vm.getBlockTimestamp() + 120);
        _setFeeds(3_000_000, 1_000_000);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.RuleInactive.selector, id));
        trimmy.execute(id);
    }

    // =======================================================================================
    // The keeper is trusted with nothing
    // =======================================================================================

    /// A keeper who arms a rule binds it to its own address, whose allowance to Trimmy is zero.
    /// So a leaked keeper key buys the attacker nothing at all.
    function test_leakedKeeperKeyCannotArmAgainstAnotherAccount() public {
        Trimmy.RuleParams memory p = _swapParams();
        vm.prank(attacker);
        uint256 id = trimmy.arm(p);

        assertEq(trimmy.ruleAt(id).account, attacker, "bound to the attacker, not the victim");

        vm.prank(attacker);
        vm.expectRevert(); // no balance, no allowance
        trimmy.execute(id);
    }

    // =======================================================================================
    // Cancellation
    // =======================================================================================

    function test_cancel_byAccount() public {
        uint256 id = _arm(_swapParams());
        vm.prank(account);
        trimmy.cancel(id);
        assertFalse(trimmy.ruleAt(id).active);
    }

    function test_cancel_byStrangerReverts() public {
        uint256 id = _arm(_swapParams());
        vm.prank(attacker);
        vm.expectRevert(Trimmy.NotAuthorised.selector);
        trimmy.cancel(id);
    }

    function test_cancel_byGuardian() public {
        uint256 id = _arm(_swapParams());
        address guardian = makeAddr("guardian");
        vm.prank(account);
        trimmy.setGuardian(guardian);

        vm.prank(guardian);
        trimmy.cancel(id);
        assertFalse(trimmy.ruleAt(id).active);
    }

    /// C-auth: the earlier design documented cancelAll as an epoch bump, but the rule struct had no
    /// epoch field and execute() read none — the panic button was a counter nothing consulted.
    function test_cancelAll_actuallyKillsRules() public {
        uint256 a = _arm(_swapParams());
        uint256 b = _arm(_swapParams());

        vm.prank(account);
        trimmy.cancelAll(account);

        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.StaleEpoch.selector, uint32(0), uint32(1)));
        trimmy.execute(a);

        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.StaleEpoch.selector, uint32(0), uint32(1)));
        trimmy.execute(b);
    }

    /// A rule armed after the bump uses the new epoch and still works.
    function test_cancelAll_doesNotKillFutureRules() public {
        vm.prank(account);
        trimmy.cancelAll(account);

        uint256 id = _arm(_swapParams());
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).spent, 100e6);
    }

    // =======================================================================================
    // Vault verbs, including the two-phase exit
    // =======================================================================================

    function test_deposit_intoVault() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.verb = Trimmy.Verb.DEPOSIT_VAULT;
        p.venueId = VENUE_VAULT;
        p.buyTokenId = TOK_FXRP; // vault verbs do not swap; buy leg is the same asset
        p.trigger = Trimmy.Trigger.SCHEDULE;
        p.triggerValue = 3600;
        p.keeperFeeFlat = 0;
        p.keeperFeeBudget = 0;
        p.protocolFeeBips = 0;
        uint256 id = _arm(p);

        vm.prank(keeper);
        trimmy.execute(id);

        assertEq(vault.balanceOf(account), 100e6, "shares land with the account");
    }

    /// L5: a vault exit cannot settle in one transaction, because maxWithdraw is 0 on every FXRP
    /// vault on Coston2. Phase one queues; phase two claims.
    function test_exitVault_isTwoPhase() public {
        // Give the account vault shares to exit with.
        vm.startPrank(account);
        fxrp.approve(address(vault), 200e6);
        vault.deposit(200e6, account);
        vault.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(usdt), feedId: FEED_USD, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        Trimmy exiter =
            new Trimmy(tokens, venues, MAX_FEED_AGE, feeSink, IConfidentialTrigger(address(0)));

        vm.prank(account);
        vault.approve(address(exiter), type(uint256).max);

        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6,
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });

        vm.prank(account);
        uint256 id = exiter.arm(p);

        vm.prank(keeper);
        exiter.execute(id);

        Trimmy.Rule memory r = exiter.ruleAt(id);
        assertEq(r.pendingShares, 100e6, "phase one queued the redemption");
        assertGt(r.claimableAt, block.timestamp, "claim is in the future");

        // Claiming early must fail.
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.NotYetClaimable.selector, r.claimableAt));
        exiter.claim(id);

        // GROUND-TRUTH 4a-bis(1): the real wait is the next UTC midnight, not lagDuration.
        assertGe(r.claimableAt, ((block.timestamp + 300) / 1 days + 1) * 1 days);

        vm.warp(r.claimableAt);
        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        exiter.claim(id);

        assertEq(fxrp.balanceOf(account) - before, 100e6, "phase two paid the account");
        assertEq(exiter.ruleAt(id).pendingShares, 0);
    }
}
