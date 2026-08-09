// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Trimmy} from "../src/Trimmy.sol";

/// @title Arm a CONFIDENTIAL rule
/// @notice The rule publishes no threshold. `triggerValue` is 0 and the contract REFUSES any other
///         value for a PRIVATE rule — leaving it merely unused would let a careless front end write
///         the real number into a public field while the user believed it was secret.
contract ArmPrivate is Script {
    address constant FXRP = 0x0b6A3645c240605887a5532109323A3E12273dc7;

    function run() external {
        Trimmy trimmy = Trimmy(payable(vm.envAddress("TRIMMY_ADDRESS")));
        uint128 amount = uint128(vm.envOr("TRIMMY_ARM_AMOUNT", uint256(1_000_000)));
        uint128 fee = uint128(vm.envOr("TRIMMY_KEEPER_FEE", uint256(9_400)));

        vm.startBroadcast();
        IERC20(FXRP).approve(address(trimmy), amount + fee);
        uint256 id = trimmy.arm(
            Trimmy.RuleParams({
                sellTokenId: 0,
                buyTokenId: 0,
                verb: Trimmy.Verb.DEPOSIT_VAULT,
                venueId: 1,
                trigger: Trimmy.Trigger.PRIVATE,
                totalSellAmount: amount,
                partSellAmount: amount,
                minOutAbsolute: (amount * 90) / 100,
                triggerValue: 0, // the secret lives in the enclave
                expiry: uint64(block.timestamp + 7 days),
                slippageBips: 0,
                protocolFeeBips: 0,
                keeperFeeFlat: fee,
                keeperFeeBudget: fee
            })
        );
        vm.stopBroadcast();
        console.log("armed CONFIDENTIAL rule:", id);
    }
}
