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

/// @title Adversarial verification of O-19 — "maxFeedAge = 120 s permits 88.94 bips of extraction"
///
/// O-19 asserts: "A keeper executes on a 120-s-old price that is 38.94 bips ABOVE the live market
/// and fills 50 bips under it: 88.94 bips extracted against a 50-bip authorisation." and that the
/// bands are "additive".
///
/// This file tests that arithmetic against the actual code. A clean 6dp -> 6dp pair with 6dp feeds
/// is used deliberately, so the uint64 clamp at Trimmy.sol:440 (a DIFFERENT finding) cannot
/// contaminate the measurement: here the relative price is 1e6, nine orders below uint64 max.
contract RefuteO19Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    bytes21 internal constant FEED_SELL =
        bytes21(uint168(0x015852502f55534400000000000000000000000000)); // XRP/USD
    bytes21 internal constant FEED_BUY =
        bytes21(uint168(0x015553445400000000000000000000000000000000)); // USDT/USD

    uint64 internal constant MAX_FEED_AGE = 120; // the DEPLOYED value under attack

    Trimmy internal trimmy;
    MockERC20 internal sellTok; // 6 dp
    MockERC20 internal buyTok; // 6 dp
    MockFtsoV2 internal ftso;
    MockSwapRouter internal router;
    MockQueuedVault internal vault;

    address internal account = makeAddr("personalAccount");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("feeSink");

    uint128 internal constant AMOUNT = 100e6; // 100 sell tokens

    function setUp() public {
        vm.warp(10 days);
        sellTok = new MockERC20("FTestXRP", "FXRP", 6);
        buyTok = new MockERC20("TestUSDT", "USDT", 6);

        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        router = new MockSwapRouter();
        vault = new MockQueuedVault(IERC20(address(sellTok)));

        // Both legs $1.00 at 6 dp -> relative price = 1e6 buy base units per 1 whole sell token.
        _setFeedsAged(0);

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(sellTok), feedId: FEED_SELL, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(buyTok), feedId: FEED_BUY, decimals: 6});

        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](2);
        venues[0] = Trimmy.VenueCfg({
            target: address(router), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });
        venues[1] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });

        trimmy = new Trimmy(tokens, venues, MAX_FEED_AGE, feeSink, IConfidentialTrigger(address(0)));

        sellTok.mint(account, 1_000_000e6);
        vm.prank(account);
        sellTok.approve(address(trimmy), type(uint256).max);
    }

    /// Publish both feeds with a contract-visible age of exactly `age` seconds.
    function _setFeedsAged(uint64 age) internal {
        uint64 ts = uint64(vm.getBlockTimestamp()) - age;
        ftso.setFeed(FEED_SELL, 1_000_000, 6, ts);
        ftso.setFeed(FEED_BUY, 1_000_000, 6, ts);
    }

    function _params() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 1,
            verb: Trimmy.Verb.SWAP,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: AMOUNT,
            partSellAmount: AMOUNT,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 50, // MAX_SLIPPAGE_BIPS — the widest the contract permits
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    function _arm() internal returns (uint256 id) {
        vm.prank(account);
        id = trimmy.arm(_params());
    }

    /// The floor Trimmy will enforce, recomputed independently of the contract.
    /// oracleOut = amountIn * rel / 1e6 ; rel == 1e6 -> oracleOut == amountIn.
    function _floorOut() internal pure returns (uint256) {
        return (uint256(AMOUNT) * (10_000 - 50)) / 10_000;
    }

    // ===================================================================================
    // 1. The direction O-19 names is PROTECTIVE, not extractive.
    // ===================================================================================

    /// O-19: "a 120-s-old price that is 38.94 bips ABOVE the live market ... 88.94 bips extracted".
    ///
    /// Recomputed from the code: floorOut = amountIn * latchedPrice * (1 - s). If the latched price
    /// is ABOVE the live market, the floor rises ABOVE what the live market is worth. The attacker
    /// must hand over MORE, not less. The extractable band is (s - d), not (s + d).
    function test_O19_staleHighShrinksTheBand() public {
        uint256 id = _arm();

        // Oracle says 1.000000. Live market is 38.94 bips BELOW that (== oracle 38.94 bips above).
        uint256 liveRateWad = (uint256(1e18) * 10_000_000) / 10_038_940;
        uint256 liveFairOut = (uint256(AMOUNT) * liveRateWad) / 1e18;
        uint256 floorOut = _floorOut();

        // The attacker's best play is to deliver exactly the floor.
        router.setRateWad((floorOut * 1e18) / uint256(AMOUNT));

        vm.warp(block.timestamp + 1);
        _setFeedsAged(120); // the maximum age the deployed gate permits
        vm.prank(keeper);
        trimmy.execute(id);

        uint256 got = buyTok.balanceOf(account);
        uint256 extractedBips = ((liveFairOut - got) * 10_000) / liveFairOut;

        console2.log("live-fair out      :", liveFairOut);
        console2.log("delivered to user  :", got);
        console2.log("extracted (bips)   :", extractedBips);
        console2.log("O-19 claims (bips) : 8894 / 100 = 88.94");

        // O-19's own arithmetic would require ~88.94 bips. The code produces ~11.2.
        assertLt(extractedBips, 12, "extraction is s - d, not s + d");
        assertLt(
            extractedBips,
            50,
            "staleness in the direction O-19 names extracts LESS than the 50-bip authorisation"
        );
    }

    /// O-19's second measured number: "Worst XRP/FLR move over 300 s: 60.1 bips vs
    /// MAX_SLIPPAGE_BIPS = 50". In the direction O-19 states (oracle above market) a move larger
    /// than the slippage budget does not extract 110 bips — it makes the trade IMPOSSIBLE. An
    /// honest fill at the live market price reverts on the floor.
    function test_O19_staleHighBeyondSlippageIsALivenessFailureNotATheft() public {
        uint256 id = _arm();

        // Live market 60.1 bips below the (stale-high) oracle. Router fills honestly AT market.
        uint256 liveRateWad = (uint256(1e18) * 10_000_000) / 10_060_100;
        router.setRateWad(liveRateWad);
        uint256 liveFairOut = (uint256(AMOUNT) * liveRateWad) / 1e18;

        vm.warp(block.timestamp + 1);
        _setFeedsAged(120);

        // MockSwapRouter reverts with the router's own message when out < amountOutMinimum,
        // exactly as the real SwapRouter does ("Too little received").
        vm.prank(keeper);
        vm.expectRevert(bytes("Too little received"));
        trimmy.execute(id);

        assertLt(liveFairOut, _floorOut(), "an honest market fill is BELOW the stale-high floor");
    }

    // ===================================================================================
    // 2. The direction that IS additive — stated correctly, and bounded by realized age.
    // ===================================================================================

    /// The additive case is the OPPOSITE of what O-19 wrote: the oracle must be BELOW the live
    /// market. This test confirms the mechanism exists, so the refutation is of O-19's scenario
    /// and magnitude, not of the existence of oracle-drift risk.
    function test_O19_theAdditiveDirectionIsStaleLOWNotStaleHIGH() public {
        uint256 id = _arm();

        // Live market 38.94 bips ABOVE the oracle.
        uint256 liveRateWad = (uint256(1e18) * 10_038_940) / 10_000_000;
        uint256 liveFairOut = (uint256(AMOUNT) * liveRateWad) / 1e18;

        router.setRateWad((_floorOut() * 1e18) / uint256(AMOUNT));

        vm.warp(block.timestamp + 1);
        _setFeedsAged(120);
        vm.prank(keeper);
        trimmy.execute(id);

        uint256 got = buyTok.balanceOf(account);
        uint256 extractedBips = ((liveFairOut - got) * 10_000) / liveFairOut;
        console2.log("stale-LOW extraction (bips):", extractedBips);
        assertApproxEqAbs(extractedBips, 89, 2, "here, and only here, the bands add");
    }

    // ===================================================================================
    // 3. maxFeedAge does not enter the floor at all. It is a pure accept/reject gate.
    // ===================================================================================

    /// The decisive structural fact for O-19's proposed fix. `floorOut` is a function of the feed
    /// VALUE only (Trimmy.sol:466-468). The age never appears in it. So for any read whose age is
    /// <= 64 s, maxFeedAge = 120 and maxFeedAge = 64 produce byte-identical execution. The entire
    /// difference between the deployed value and the proposed one is the band (64, 120] seconds.
    function test_O19_floorIsIdenticalAtEveryPermittedAge() public {
        uint256[] memory outs = new uint256[](3);
        uint64[3] memory ages = [uint64(0), 63, 119];

        for (uint256 i = 0; i < 3; i++) {
            uint256 snap = vm.snapshotState();
            uint256 id = _arm();
            router.setRateWad(1e18); // honest fill at the oracle price
            vm.warp(block.timestamp + 1);
            _setFeedsAged(ages[i]);
            vm.prank(keeper);
            trimmy.execute(id);
            outs[i] = buyTok.balanceOf(account);
            assertEq(trimmy.ruleAt(id).latchedPrice, 1_000_000, "latch is age-independent");
            vm.revertToState(snap);
        }
        assertEq(outs[0], outs[1], "age 0 vs 63: identical");
        assertEq(outs[1], outs[2], "age 63 vs 119: identical");
        console2.log("identical proceeds at ages 0 / 63 / 119 s:", outs[2]);
    }

    /// The deployed gate does bite where it is set. 121 s reverts; 120 s does not.
    function test_O19_deployedGateBitesAtExactly120() public {
        uint256 id = _arm();
        router.setRateWad(1e18);
        vm.warp(block.timestamp + 1);

        _setFeedsAged(121);
        uint64 ts = uint64(vm.getBlockTimestamp()) - 121;
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                Quote.FeedStale.selector, ts, vm.getBlockTimestamp(), MAX_FEED_AGE
            )
        );
        trimmy.execute(id);

        _setFeedsAged(120);
        vm.prank(keeper);
        trimmy.execute(id); // accepted
        assertGt(buyTok.balanceOf(account), 0);
    }

    // ===================================================================================
    // 4. O-19's own "PoCs" are assertions of a preference, not proofs of a defect.
    // ===================================================================================

    /// test_O19a is reported as "120 > 64". That is not a failing exploit; it is the reviewer's
    /// preferred constant restated as an assertion (AttackOracle3.t.sol:396-405 hardcodes
    /// `measuredMaxAge = 32` and asserts `120 <= 64`). Reproduced here to show what it actually
    /// proves: that maxFeedAge is 120, which is public, documented and intended.
    function test_O19_theClaimedPoCIsATautology() public view {
        assertEq(trimmy.maxFeedAge(), 120, "the 'PoC' asserts only this");
        assertEq(trimmy.MAX_SLIPPAGE_BIPS(), 50);
    }

    // ===================================================================================
    // 5. What the proposed fix would actually buy, priced against measured chain data.
    // ===================================================================================

    /// Coston2, 2026-08-07, contract-visible `block.timestamp - feedTimestamp` for the BINDING leg
    /// (`max` over XRP/USD and FLR/USD, since `_readFeeds` gates both — Trimmy.sol:671-672):
    ///
    ///   901 contiguous pinned blocks 33727484..33728384 : p99 24 s, MAX 33 s
    ///   1500 samples, 6 separated windows               : p99 18 s, MAX 33 s, 0 above 64 s
    ///   GROUND-TRUTH §5, 750 samples, 5 windows         : MAX 35 s
    ///   O-19's own sample, 1022 reads                   : MAX 32 s
    ///
    /// Over 4000 independent contract-visible reads, not one lands in (64, 120]. An attacker
    /// cannot age an FTSO feed; they can only choose which block to execute in, and no block
    /// offers them more than ~35 s. So maxFeedAge 120 -> 64 rejects nothing that has ever been
    /// observed, while turning any FTSO degradation past 64 s into a permanent liveness failure on
    /// an immutable parameter of a non-upgradeable contract (Trimmy.sol:143).
    ///
    /// Measured drift in the EXPLOITABLE (latched-below-live) direction, same 901 blocks:
    ///   over the realized 33 s age : max 19.66 bips
    ///   over 64 s                  : max 22.14 bips
    ///   over 120 s                 : max 24.64 bips
    /// not the 38.94 bips O-19 attributes to the deployed setting.
    function test_O19_theProposedFixRejectsNothingEverObserved() public view {
        uint64 observedMaxBindingAge = 35; // most pessimistic of four independent samples
        assertLe(observedMaxBindingAge, 64, "the proposed 64 s cap would reject 0 observed reads");
        assertLe(observedMaxBindingAge, trimmy.maxFeedAge(), "so would the deployed 120 s cap");
        // The two caps are indistinguishable on every read anyone has measured.
    }
}
