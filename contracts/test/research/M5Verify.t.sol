// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockSwapRouter} from "../mocks/Mocks.sol";

/// @title Adversarial verification of claim M-5 (_refund sweeps the whole native balance).
contract M5VerifyTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp; // 6 dp
    MockERC20 internal usd; // 6 dp — kept 6dp so the uint64 latch does not saturate here
    MockFtsoV2 internal ftso;
    MockSwapRouter internal router;

    address internal account = makeAddr("personalAccount");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("feeSink");
    address internal donor = makeAddr("donor");

    function setUp() public {
        vm.warp(10 days);

        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        usd = new MockERC20("USD", "USD", 6);

        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        uint64 nowTs = uint64(vm.getBlockTimestamp());
        ftso.setFeed(FEED_XRP, 3_000_000, 6, nowTs); // 3.0
        ftso.setFeed(FEED_FLR, 1_000_000, 6, nowTs); // 1.0

        router = new MockSwapRouter();

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(usd), feedId: FEED_FLR, decimals: 6});

        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(router), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });

        trimmy = new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1_000_000e6);
        vm.prank(account);
        fxrp.approve(address(trimmy), type(uint256).max);

        router.setRateWad(3e18); // pay the oracle price so the floor passes
    }

    function _arm() internal returns (uint256 id) {
        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 1,
            verb: Trimmy.Verb.SWAP,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6,
            partSellAmount: 10e6,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 50,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(account);
        id = trimmy.arm(p);
    }

    // ---------------------------------------------------------------------------------
    // 1. The MECHANIC. Does execute() pay out a pre-existing balance to the caller?
    // ---------------------------------------------------------------------------------
    function test_M5_mechanic_preexistingBalanceGoesToCaller() public {
        uint256 id = _arm();

        // The only way stray native gets here at all: an external transfer into receive().
        vm.deal(donor, 5 ether);
        vm.prank(donor);
        (bool sent,) = address(trimmy).call{value: 5 ether}("");
        assertTrue(sent, "receive() accepts the donation");
        assertEq(address(trimmy).balance, 5 ether);

        uint256 before = keeper.balance;
        vm.prank(keeper);
        trimmy.execute(id); // msg.value == 0, exactly what keeper.dart sends

        console2.log("keeper native gain:", keeper.balance - before);
        assertEq(keeper.balance - before, 5 ether, "caller received the donation");
        assertEq(address(trimmy).balance, 0);
    }

    // ---------------------------------------------------------------------------------
    // 2. The NORMAL path. With no donation, is the refund exactly the caller's own excess?
    // ---------------------------------------------------------------------------------
    function test_M5_normalPath_refundEqualsCallerExcess() public {
        uint256 id = _arm();
        ftso.setFeePerRead(0.01 ether); // two reads -> fee == 0.02 ether

        vm.deal(keeper, 1 ether);
        uint256 before = keeper.balance;

        vm.prank(keeper);
        trimmy.execute{value: 1 ether}(id);

        uint256 spentNative = before - keeper.balance;
        console2.log("keeper net native spend (wei):", spentNative);
        assertEq(spentNative, 0.02 ether, "keeper paid exactly the FTSO fee, no more");
        assertEq(address(trimmy).balance, 0, "contract keeps nothing");
        assertEq(address(ftso).balance, 0.02 ether, "the fee reached the oracle");
    }

    // ---------------------------------------------------------------------------------
    // 3. Can the PROTOCOL itself leave native in the contract between transactions?
    //    Every external call is checked for a native leg.
    // ---------------------------------------------------------------------------------
    function test_M5_noProtocolPathLeavesNativeBehind() public {
        uint256 id = _arm();
        ftso.setFeePerRead(0.01 ether);

        vm.deal(keeper, 10 ether);
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(vm.getBlockTimestamp() + 2 hours);
            uint64 nowTs = uint64(vm.getBlockTimestamp());
            ftso.setFeed(FEED_XRP, 3_000_000, 6, nowTs);
            ftso.setFeed(FEED_FLR, 1_000_000, 6, nowTs);
            vm.prank(keeper);
            trimmy.execute{value: 0.5 ether}(id);
            assertEq(address(trimmy).balance, 0, "no native accumulates across executions");
        }
        // The V3 router is `payable` but Trimmy never attaches value to exactInput, so there is
        // nothing for it to refund.
        assertEq(address(router).balance, 0, "router never received native, so cannot refund any");
    }

    // ---------------------------------------------------------------------------------
    // 4. Can a keeper use a donation INSTEAD of msg.value? (i.e. is there an incentive for
    //    anyone to ever leave native in the contract?)
    // ---------------------------------------------------------------------------------
    function test_M5_prefundingTheContractIsUseless() public {
        uint256 id = _arm();
        ftso.setFeePerRead(0.01 ether);

        vm.deal(donor, 10 ether);
        vm.prank(donor);
        (bool sent,) = address(trimmy).call{value: 10 ether}("");
        assertTrue(sent);

        // Even sitting on 10 ether, the contract refuses a caller who does not attach the fee.
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.InsufficientFeeValue.selector, 0, 0.02 ether));
        trimmy.execute(id);
    }
}
