// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../../../src/Interfaces.sol";
import {Trimmy} from "../../../src/Trimmy.sol";
import {Quote} from "../../../src/Quote.sol";
import {
    MockERC20,
    MockFtsoV2,
    MockRegistry,
    MockSwapRouter,
    MockQueuedVault
} from "../../mocks/Mocks.sol";

/// @title Oracle-lens attack on the DEPLOYED allowlist
/// @notice Every existing test in `test/` uses FXRP(6dp, 6dp feed) -> USDT(6dp, 6dp feed), for
///         which `Quote.convert`'s exponent is 0 and the relative price is ~3e6. The DEPLOYED
///         allowlist on Coston2 is FXRP(6dp, XRP/USD @ 6dp) -> WC2FLR(18dp, FLR/USD @ 8dp), for
///         which the exponent is +14 and the relative price is ~1.72e20. That is 9.3x above
///         `type(uint64).max`. This file is the deployed configuration, with live feed mantissas.
///
///         Live reads, Coston2 block 33726105, 2026-08-07T04:50:46Z:
///           XRP/USD  value 1019644  decimals 6   ($1.019644)
///           FLR/USD  value  593099  decimals 8   ($0.00593099)
/// @notice FtsoV2 stand-in with PER-FEED fees and strict value accounting. `MockFtsoV2` returns
///         one fee for every id and ignores `msg.value`, so the existing suite structurally
///         cannot tell "half the total" from "this feed's own fee". This one can.
contract AsymmetricFeeFtso {
    mapping(bytes21 => uint256) public value_;
    mapping(bytes21 => int8) public dec_;
    mapping(bytes21 => uint64) public ts_;
    mapping(bytes21 => uint256) public fee_;
    mapping(bytes21 => uint256) public paid;

    function setFeed(bytes21 id, uint256 v, int8 d, uint64 t) external {
        value_[id] = v;
        dec_[id] = d;
        ts_[id] = t;
    }

    function setFee(bytes21 id, uint256 f) external {
        fee_[id] = f;
    }

    function calculateFeeById(bytes21 id) external view returns (uint256) {
        return fee_[id];
    }

    function getFeedById(bytes21 id) external payable returns (uint256, int8, uint64) {
        // The real FtsoV2 rejects an underpayment for the feed being read. Model that.
        require(msg.value >= fee_[id], "FTSO: underpaid for this feed");
        paid[id] = msg.value;
        return (value_[id], dec_[id], ts_[id]);
    }
}

contract AttackOracleTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    // The two feed IDs actually written into the deployed Trimmy's token allowlist.
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    // Live mantissas, read from FtsoV2 0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d.
    uint256 internal constant XRP_V = 1_019_644;
    int8 internal constant XRP_D = 6;
    uint256 internal constant FLR_V = 593_099;
    int8 internal constant FLR_D = 8;

    uint64 internal constant MAX_FEED_AGE = 120; // deployed value

    Trimmy internal trimmy;
    MockERC20 internal fxrp; // 6 dp  == 0x0b6A3645...
    MockERC20 internal wnat; // 18 dp == 0xC67DCE33...
    MockFtsoV2 internal ftso;
    MockRegistry internal registry;
    MockSwapRouter internal router;
    MockQueuedVault internal vault;

    address internal account = makeAddr("personalAccount");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("protocolFeeRecipient");

    uint8 internal constant TOK_FXRP = 0;
    uint8 internal constant TOK_WNAT = 1;
    uint8 internal constant VENUE_SWAP = 0;
    uint8 internal constant VENUE_VAULT = 1;

    function setUp() public {
        vm.warp(10 days);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wnat = new MockERC20("Wrapped C2FLR", "WC2FLR", 18);

        ftso = new MockFtsoV2();
        registry = new MockRegistry();
        registry.setFtso(address(ftso));
        vm.etch(REGISTRY_ADDR, address(registry).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        router = new MockSwapRouter();
        vault = new MockQueuedVault(IERC20(address(fxrp)));

        _setFeeds(XRP_V, FLR_V);

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(wnat), feedId: FEED_FLR, decimals: 18});

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

    function _setFeeds(uint256 xrpV, uint256 flrV) internal {
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, xrpV, XRP_D, nowTs);
        ftso.setFeed(FEED_FLR, flrV, FLR_D, nowTs);
    }

    /// The true relative price, in WC2FLR wei per one whole FXRP, at the current feed settings.
    function _trueRelative(uint256 xrpV, uint256 flrV) internal pure returns (uint256) {
        return Quote.convert(
            1e6,
            Quote.Feed({value: xrpV, decimals: XRP_D, timestamp: 0}),
            6,
            Quote.Feed({value: flrV, decimals: FLR_D, timestamp: 0}),
            18
        );
    }

    function _swapParams() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: TOK_FXRP,
            buyTokenId: TOK_WNAT,
            verb: Trimmy.Verb.SWAP,
            venueId: VENUE_SWAP,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6, // 100 FXRP
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 50, // MAX_SLIPPAGE_BIPS
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    // =======================================================================================
    // O-1. The relative price of the deployed pair does not fit in uint64.
    // =======================================================================================

    /// Quote.sol is exact. Trimmy.sol:440 then throws 90% of the answer away.
    function test_O1_deployedPairRelativePriceExceedsUint64() public pure {
        uint256 rel = _trueRelative(XRP_V, FLR_V);
        console2.log("true relative (WC2FLR wei per 1 FXRP):", rel);
        console2.log("type(uint64).max                     :", uint256(type(uint64).max));
        console2.log("overflow factor (x100)               :", (rel * 100) / type(uint64).max);
        assertGt(rel, type(uint64).max, "sanity: the deployed pair overflows uint64");
        // 1 XRP = $1.019644, 1 FLR = $0.00593099  ->  171.918 FLR per XRP.
        assertApproxEqRel(rel, 171.918e18, 1e15);
    }

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// `latchedPrice` (Trimmy.sol:89, uint64) must equal the oracle price it claims to latch.
    function test_O1_latchedPriceMustEqualTheOraclePrice() public {
        uint256 rel = _trueRelative(XRP_V, FLR_V);

        vm.prank(account);
        uint256 id = trimmy.arm(_swapParams());

        // Fill exactly at the true oracle price so the swap itself is honest.
        router.setRateWad((rel * 1e6) / 1e6); // out = amountIn * rateWad / 1e6 (see below)
        router.setRateWad(rel); // rateWad == wei-per-1e6-units == rel for a 6->18 dp pair

        vm.prank(keeper);
        trimmy.execute(id);

        uint128 latched = trimmy.ruleAt(id).latchedPrice;
        console2.log("latched:", uint256(latched));
        console2.log("truth  :", rel);
        assertEq(uint256(latched), rel, "O-1: the latch is clamped, not the price");
    }

    // =======================================================================================
    // O-2. Because the latch is clamped, the FTSO execution floor collapses by ~9.3x.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// A swap that delivers 10.7% of oracle value is accepted by the "50 bip" floor.
    function test_O2_floorAcceptsAnEightyNinePercentHaircut() public {
        uint256 rel = _trueRelative(XRP_V, FLR_V);
        uint256 amountIn = 100e6; // 100 FXRP
        uint256 fairOut = (amountIn * rel) / 1e6; // 17,191.8 WC2FLR

        vm.prank(account);
        uint256 id = trimmy.arm(_swapParams());

        // What the contract will actually demand: amountIn * clampedPrice / 1e6 * 0.995.
        uint256 clampedFloor =
        // test fixture: the intermediate is a pre-scaled oracle quote, so the ordering is deliberate and the precision loss is the quantity under test.
        // forge-lint: disable-next-line(divide-before-multiply)
            (((amountIn * uint256(type(uint64).max)) / 1e6) * (10_000 - 50)) / 10_000;

        // Fill just above that floor. MockSwapRouter: out = amountIn * rateWad / 1e18 * 1e12,
        // whose 1e12-wei granularity needs a 1-bip cushion so truncation cannot dip under.
        // test fixture: the intermediate is a pre-scaled oracle quote, so the ordering is deliberate and the precision loss is the quantity under test.
        // forge-lint: disable-next-line(divide-before-multiply)
        router.setRateWad((((clampedFloor * 1e6) / amountIn) * 10_001) / 10_000);

        uint256 before = wnat.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id);
        uint256 got = wnat.balanceOf(account) - before;

        console2.log("fair value of 100 FXRP (WC2FLR wei):", fairOut);
        console2.log("what the user actually received    :", got);
        console2.log("loss, bips                         :", ((fairOut - got) * 10_000) / fairOut);

        // The stated guarantee: never worse than 50 bips below the FTSO price.
        assertGe(got, (fairOut * (10_000 - 50)) / 10_000, "O-2: floor collapsed");
    }

    // =======================================================================================
    // O-3. The clamp makes every price trigger a constant function.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// A stop-loss at "sell if 1 XRP drops below 150 WC2FLR" cannot be armed at all: 150e18
    /// does not fit in `triggerValue` (uint64). The largest expressible threshold is
    /// type(uint64).max == 18.446 WC2FLR, an 89% crash. Even THAT never fires, because the
    /// evaluated price is pinned at type(uint64).max regardless of the market.
    function test_O3_priceBelowStopLossNeverFires() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.trigger = Trimmy.Trigger.PRICE_BELOW;
        p.triggerValue = type(uint64).max - 1; // the most generous expressible stop-loss

        vm.prank(account);
        uint256 id = trimmy.arm(p);

        // XRP collapses 70% against FLR. Every human reading of this rule says: fire.
        _setFeeds((XRP_V * 30) / 100, FLR_V);
        uint256 rel = _trueRelative((XRP_V * 30) / 100, FLR_V);
        console2.log("relative price after a 70% crash:", rel);
        console2.log("armed threshold                 :", uint256(type(uint64).max - 1));

        router.setRateWad(rel);
        vm.prank(keeper);
        trimmy.execute(id); // reverts TriggerNotMet(uint64max, uint64max-1)
    }

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// The only threshold that DOES fire is type(uint64).max, and it fires unconditionally.
    /// A user who arms "sell if 1 XRP <= 18.446 WC2FLR" is filled at 171.918 — 9.3x above the
    /// stop they set. The trigger has exactly two behaviours: never, and always.
    function test_O3_priceBelowAtMaxThresholdFiresAtNineTimesTheStop() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.trigger = Trimmy.Trigger.PRICE_BELOW;
        p.triggerValue = type(uint64).max; // "1 XRP <= 18.446 WC2FLR"

        vm.prank(account);
        uint256 id = trimmy.arm(p);

        uint256 rel = _trueRelative(XRP_V, FLR_V); // 171.918e18 — far ABOVE the stop
        router.setRateWad(rel);

        vm.prank(keeper);
        trimmy.execute(id);

        // It executed. Assert what should have happened instead.
        assertFalse(
            trimmy.ruleAt(id).spent > 0,
            "O-3: PRICE_BELOW fired while the price was 9.3x above the threshold"
        );
    }

    // =======================================================================================
    // O-4. requireFresh has no upper bound on a future timestamp.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// Quote.sol:54 only measures age when `block.timestamp > feed.timestamp`. A feed dated in
    /// the future is age zero no matter how far ahead, so `maxFeedAge` is unenforced on that
    /// branch. One-second skew tolerance does not require an unbounded window.
    function test_O4_farFutureFeedTimestampBypassesStaleness() public {
        vm.prank(account);
        uint256 id = trimmy.arm(_swapParams());

        // A feed dated one year ahead, carrying a price from a year ago.
        uint64 future = uint64(block.timestamp + 365 days);
        ftso.setFeed(FEED_XRP, XRP_V, XRP_D, future);
        ftso.setFeed(FEED_FLR, FLR_V, FLR_D, future);

        router.setRateWad(_trueRelative(XRP_V, FLR_V));

        vm.expectRevert(); // should be FeedStale; is not
        vm.prank(keeper);
        trimmy.execute(id);
    }

    // =======================================================================================
    // O-5. The FTSO fee split is correct, but only under equal per-feed fees. Prove it isn't
    //      the naive "half" the variable name claims.
    // =======================================================================================

    function test_O5_feeSplitIsPerFeedNotHalf() public {
        // MockFtsoV2 returns one fee for every id, so the existing suite cannot distinguish
        // "half of the total" from "this feed's own fee". Assert the reachable property: an
        // exact-fee payment is accepted and an underpayment is rejected.
        ftso.setFeePerRead(7); // total 14

        vm.prank(account);
        uint256 id = trimmy.arm(_swapParams());
        router.setRateWad(_trueRelative(XRP_V, FLR_V));

        vm.deal(keeper, 1 ether);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.InsufficientFeeValue.selector, 13, 14));
        trimmy.execute{value: 13}(id);

        vm.prank(keeper);
        trimmy.execute{value: 14}(id);
        assertGt(trimmy.ruleAt(id).spent, 0);
    }

    /// The split at Trimmy.sol:662-669 is `sellFee` / `total - sellFee`, despite being named
    /// `half`. Prove that against ASYMMETRIC per-feed fees, which no existing mock can express.
    function test_O5_asymmetricFeesAreSplitCorrectly() public {
        AsymmetricFeeFtso a = new AsymmetricFeeFtso();
        a.setFeed(FEED_XRP, XRP_V, XRP_D, uint64(block.timestamp));
        a.setFeed(FEED_FLR, FLR_V, FLR_D, uint64(block.timestamp));
        a.setFee(FEED_XRP, 9);
        a.setFee(FEED_FLR, 1);
        MockRegistry(REGISTRY_ADDR).setFtso(address(a));

        vm.prank(account);
        uint256 id = trimmy.arm(_swapParams());
        router.setRateWad(_trueRelative(XRP_V, FLR_V));

        vm.deal(keeper, 1 ether);
        vm.prank(keeper);
        trimmy.execute{value: 10}(id);

        // A naive 50/50 split would send 5 to the XRP leg and fail its 9-wei requirement.
        assertEq(a.paid(FEED_XRP), 9, "sell leg must receive its own fee, not half the total");
        assertEq(a.paid(FEED_FLR), 1, "buy leg must receive its own fee");
    }

    // =======================================================================================
    // O-7. Quote.sol:8 claims "The execution floor for every Trimmy rule is computed here."
    //      For 2 of the 3 verbs that is false: the oracle result is read, paid for, staleness-
    //      gated, latched — and then never consulted.
    // =======================================================================================

    /// PROOF OF CONCEPT — FAILS against the current code.
    /// Trimmy.sol:498-512 (`_doDeposit`) floors only against the user-supplied `minOutAbsolute`.
    /// `sellFeed`/`buyFeed`/`latchedPrice` do not appear in it. A vault whose share price has
    /// collapsed to 1% mints 1% of the shares and the "FTSO floor" says nothing.
    function test_O7_vaultDepositHasNoOracleFloor() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.verb = Trimmy.Verb.DEPOSIT_VAULT;
        p.venueId = VENUE_VAULT;
        p.buyTokenId = TOK_FXRP; // vault shares track FXRP, as the 4 live rules are configured
        p.minOutAbsolute = 0;

        vm.prank(account);
        uint256 id = trimmy.arm(p);

        // Share price collapses 100x. deposit() mints assets*1e18/sharePriceWad.
        vault.setSharePriceWad(100e18);

        uint256 before = vault.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id);
        uint256 shares = vault.balanceOf(account) - before;

        console2.log("assets in (FXRP base units):", uint256(100e6));
        console2.log("shares out                 :", shares);
        // A rule that read the oracle should not accept a 99% haircut inside a 50-bip rule.
        assertGe(shares, (uint256(100e6) * 9950) / 10_000, "O-7: no oracle floor on DEPOSIT_VAULT");
    }

    /// EXIT_VAULT is worse: `_doQueueRedeem` (Trimmy.sol:516-537) and `claim` (543-566) have no
    /// floor at all, not even `minOutAbsolute`. Both feeds are still read, paid for and
    /// staleness-gated in `execute`, so a stale or zeroed feed bricks a rule whose settlement
    /// never used a price. This asserts only the coupling, which is the part that is a defect.
    function test_O7_exitVaultIsBrickedByAFeedItNeverUses() public {
        Trimmy.RuleParams memory p = _swapParams();
        p.verb = Trimmy.Verb.EXIT_VAULT;
        p.venueId = VENUE_VAULT;
        p.buyTokenId = TOK_FXRP;
        p.minOutAbsolute = 0;

        vm.prank(account);
        uint256 id = trimmy.arm(p);

        // The BUY-leg feed (FLR/USD) goes stale. EXIT_VAULT never reads a price.
        vm.warp(block.timestamp + 1);
        ftso.setFeed(FEED_FLR, FLR_V, FLR_D, uint64(block.timestamp - MAX_FEED_AGE - 1));
        ftso.setFeed(FEED_XRP, XRP_V, XRP_D, uint64(block.timestamp));

        vm.prank(keeper);
        vm.expectRevert(); // Quote.FeedStale — on a leg the verb does not use
        trimmy.execute(id);
    }

    // =======================================================================================
    // O-6. Staleness budget vs slippage budget, against MEASURED Coston2 data.
    // =======================================================================================

    /// CORRECTED 2026-08-07. This test previously cited "140 disjoint 120 s windows across 30
    /// days ... p99 39.17, max 41.39". No tool in `tools/` produces that number and GROUND-TRUTH
    /// does not record it, so it was unsourced. Replaced with a reproducible measurement:
    ///
    ///     python3 tools/sample_rel_volatility.py 900       # run twice, separated windows
    ///
    /// Two 901-block windows, both feeds pinned per block, 2026-08-07:
    ///   |d(XRP/FLR)| over 120 s : A p99 30.39 max 31.93 | B p99 34.48 max 38.94 bips
    /// See AttackOracle2.t.sol test_O12 for the band arithmetic.
    function test_O6_stalenessAndSlippageBudgetsAreAdditive() public pure {
        uint256 measured120sMaxBips = 38; // measured, worst of two Coston2 windows
        uint256 slippageBips = 50; // MAX_SLIPPAGE_BIPS
        console2.log("combined extractable band, bips:", measured120sMaxBips + slippageBips);
        assertGt(measured120sMaxBips + slippageBips, 50);
    }
}
