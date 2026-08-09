// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";

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
}

interface IWNat {
    function deposit() external payable;
}

interface IRouterFactory {
    function factory() external view returns (address);
}

/// Does the "permanently dead, must redeploy Trimmy" half of claim L-0 hold?
contract ForkSwapVenueFixableTest is Test {
    address constant TRIMMY = 0xf73a2aF06B315adAA1afe2C1A6C1A6933d8A6554;
    address constant ROUTER = 0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc;
    address constant FXRP = 0x0b6A3645c240605887a5532109323A3E12273dc7;
    address constant WC2FLR = 0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273;
    /// The address the live router's CREATE2 path computation resolves to (measured: the revert
    /// message of exactInput on the unmodified fork is "call to non-contract address 0xafcA…").
    address constant EXPECTED_POOL = 0xafcA1C5DfF08b3B8Bacb7721fb8189d2D8E7C3DB;

    address constant FXRP_HOLDER = 0x9E63a5D282F2fBb7DcE822B98e363b2719D28319; // TESTearnXRP, 7844 FXRP

    address factory;

    function setUp() public {
        vm.createSelectFork("coston2");
        factory = IRouterFactory(ROUTER).factory();
    }

    function flareSwapMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata)
        external
    {
        if (amount0Owed > 0) IERC20(FXRP).transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) IERC20(WC2FLR).transfer(msg.sender, amount1Owed);
    }

    /// createPool on a Uniswap V3 factory is permissionless for any enabled fee tier.
    /// If this passes, no Trimmy redeploy is required: the immutable venue already points at
    /// the right address, the pool just has to exist.
    function test_pool_can_still_be_created_at_the_address_the_router_uses() public {
        // Not the factory owner. Anyone.
        vm.prank(address(0xBEEF));
        address pool = IV3Factory(factory).createPool(FXRP, WC2FLR, 3000);

        assertEq(pool, EXPECTED_POOL, "created pool is exactly the address the router computes");
        assertEq(IV3Factory(factory).getPool(FXRP, WC2FLR, 3000), pool);
    }

    /// End to end: create + seed the pool, then run the exact path Trimmy._doSwap builds.
    function test_after_seeding_the_immutable_venue_works() public {
        address pool = IV3Factory(factory).createPool(FXRP, WC2FLR, 3000);
        assertEq(IV3Pool(pool).token0(), FXRP);
        assertEq(IV3Pool(pool).token1(), WC2FLR);

        // 1 whole FXRP (1e6) == 100 whole WC2FLR (100e18) -> raw ratio 1e14 -> sqrt = 1e7.
        IV3Pool(pool).initialize(uint160(1e7) << 96);

        // `deal` corrupts FXRP: it is a proxy with its own accounting, and a dealt slot
        // underflows on transfer. Source real tokens instead.
        address fxrpWhale = address(0);
        vm.prank(FXRP_HOLDER);
        IERC20(FXRP).transfer(address(this), 1_000e6);
        vm.deal(address(this), 1_000_000e18);
        IWNat(WC2FLR).deposit{value: 500_000e18}();
        fxrpWhale;
        IV3Pool(pool).mint(address(this), int24(316320), int24(328320), 1e15, "");

        uint256 amountIn = 1e6;
        IERC20(FXRP).approve(ROUTER, amountIn);

        Trimmy.VenueCfg memory v = Trimmy(payable(TRIMMY)).venueAt(0);
        bytes memory path = abi.encodePacked(FXRP, v.feeTier, WC2FLR);

        uint256 before = IERC20(WC2FLR).balanceOf(address(this));
        ISwapRouter(ROUTER)
            .exactInput(
                ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            })
            );
        assertGt(IERC20(WC2FLR).balanceOf(address(this)) - before, 0, "swap produced output");
    }
}
