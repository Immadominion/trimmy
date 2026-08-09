// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";

interface IV3Factory {
    function getPool(address a, address b, uint24 fee) external view returns (address);
}

/// Adversarial verification of claim L-0: is venue 0 (SwapRouter, feeTier 3000) usable at all
/// against the live Coston2 state?
contract ForkSwapVenueTest is Test {
    address constant TRIMMY = 0xf73a2aF06B315adAA1afe2C1A6C1A6933d8A6554;
    address constant ROUTER = 0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc;
    address constant FXRP = 0x0b6A3645c240605887a5532109323A3E12273dc7;
    address constant WC2FLR = 0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273;

    function setUp() public {
        vm.createSelectFork("coston2");
    }

    /// The exact path bytes Trimmy._doSwap builds (Trimmy.sol:476) for venue 0, FXRP -> WC2FLR.
    function _path() internal view returns (bytes memory) {
        Trimmy.VenueCfg memory v = Trimmy(payable(TRIMMY)).venueAt(0);
        return abi.encodePacked(FXRP, v.feeTier, WC2FLR);
    }

    function test_liveVenue0_feeTier_is_3000_and_kind_is_swap() public view {
        Trimmy.VenueCfg memory v = Trimmy(payable(TRIMMY)).venueAt(0);
        assertEq(v.target, ROUTER);
        assertEq(uint256(v.feeTier), 3000);
        assertEq(uint256(uint8(v.kind)), 0); // SWAP_ROUTER_V3
    }

    function test_factory_has_no_pool_at_any_tier() public view {
        address factory = ISwapRouterFactory(ROUTER).factory();
        uint24[4] memory tiers = [uint24(100), 500, 3000, 10000];
        for (uint256 i = 0; i < tiers.length; i++) {
            assertEq(IV3Factory(factory).getPool(FXRP, WC2FLR, tiers[i]), address(0));
        }
    }

    /// THE PROOF: drive the live router with the exact path Trimmy would build.
    function test_exactInput_on_live_router_reverts() public {
        uint256 amountIn = 1e6; // 1 FXRP (6dp)
        deal(FXRP, address(this), amountIn);
        IERC20(FXRP).approve(ROUTER, amountIn);
        bytes memory path = _path();

        vm.expectRevert();
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
    }

    /// And the reverse direction, in case only one ordering was intended.
    function test_exactInput_reverse_direction_also_reverts() public {
        uint256 amountIn = 1e18;
        deal(WC2FLR, address(this), amountIn);
        IERC20(WC2FLR).approve(ROUTER, amountIn);

        Trimmy.VenueCfg memory v = Trimmy(payable(TRIMMY)).venueAt(0);
        bytes memory path = abi.encodePacked(WC2FLR, v.feeTier, FXRP);
        vm.expectRevert();
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
    }
}

interface ISwapRouterFactory {
    function factory() external view returns (address);
}
