// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Trimmy} from "../src/Trimmy.sol";

/// @title Arm a rule and leave it for the keeper
/// @notice Deliberately does NOT execute. The whole product claim is that a rule fires without the
///         user present, so the demo has to show something other than us pressing the button.
contract Arm is Script {
    address constant FXRP = 0x0b6A3645c240605887a5532109323A3E12273dc7;
    uint8 constant TOK_FXRP = 0;
    uint8 constant VENUE_VAULT = 1;

    function run() external {
        Trimmy trimmy = Trimmy(payable(vm.envAddress("TRIMMY_ADDRESS")));
        uint128 amount = uint128(vm.envOr("TRIMMY_ARM_AMOUNT", uint256(1_000_000)));
        // O-3 measured execute() at 383,451 gas = 4,698 UBA of value. 9,400 gives ~2x margin, so a
        // rational keeper is actually paid to run this rather than subsidising it.
        uint128 fee = uint128(vm.envOr("TRIMMY_KEEPER_FEE", uint256(9_400)));

        vm.startBroadcast();
        IERC20(FXRP).approve(address(trimmy), amount);
        uint256 id = trimmy.arm(
            Trimmy.RuleParams({
                sellTokenId: TOK_FXRP,
                buyTokenId: TOK_FXRP,
                verb: Trimmy.Verb.DEPOSIT_VAULT,
                venueId: VENUE_VAULT,
                trigger: Trimmy.Trigger.SCHEDULE,
                totalSellAmount: amount,
                partSellAmount: amount,
                minOutAbsolute: (uint128(amount) * 90) / 100,
                triggerValue: 60,
                expiry: uint64(block.timestamp + 7 days),
                slippageBips: 0,
                protocolFeeBips: 0,
                keeperFeeFlat: fee,
                keeperFeeBudget: fee
            })
        );
        vm.stopBroadcast();
        console.log("armed ruleId:", id, "-- left for the keeper");
    }
}
