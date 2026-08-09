// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {
    ITeeExtensionRegistry,
    ITeeMachineRegistry,
    TrimmyConfidentialTrigger
} from "../src/TrimmyConfidentialTrigger.sol";

/// @title Deploy the confidential-trigger InstructionSender
/// @notice This contract is the ONLY address permitted to submit instructions for our FCC
///         extension — `TeeExtensionRegistry` rejects any `sendInstructions` whose `msg.sender` is
///         not the address bound at registration. So it must exist before the extension can be
///         registered, and its address is what registration binds.
///
/// @dev **The TEE registries are not in Flare's `ContractRegistry`.** All three of
///      `TeeExtensionRegistry`, `TeeMachineRegistry` and `FlareTeeManager` resolve to `address(0)`
///      there, verified on Coston2. So unlike every other address in this project they cannot be
///      resolved at runtime, and the rule "only `ContractRegistry.address` is ever hardcoded"
///      cannot be honoured by resolution.
///
///      It is honoured a different way: the address is a **deploy-time argument**, never a literal
///      in the contract, and the script asserts it has code and answers both interfaces before
///      anything is deployed against it. A wrong address fails here rather than at the first
///      instruction.
///
///      `FlareTeeManager` on Coston2 is a diamond that serves BOTH registry interfaces from one
///      address — measured: `getRandomTeeIds` and `getTeeExtensionInstructionsSender` both answer
///      on `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE`. The two constructor parameters are kept
///      separate anyway, because they are logically distinct interfaces that may not always share
///      a deployment.
///
///      Run:
///        TEE_MANAGER=0x1a9C... \
///        forge script script/DeployConfidential.s.sol:DeployConfidential \
///          --rpc-url coston2 --broadcast --private-key $COSTON2_TEST_KEY
contract DeployConfidential is Script {
    function run() external returns (TrimmyConfidentialTrigger trigger) {
        address manager = vm.envAddress("TEE_MANAGER");

        // The enclave's signing address. `acceptVerdict` requires `ecrecover` to return exactly

        require(manager.code.length > 0, "TEE_MANAGER has no code");

        // Probe both interfaces before trusting the address. A diamond that cannot answer these is
        // not the manager, whatever it is.
        uint256 next = ITeeExtensionRegistry(manager).nextPublicExtensionId();
        require(next > 0x10000, "manager does not answer nextPublicExtensionId");
        console.log("  TEE manager      :", manager);
        console.log("  public extensions:", next - 0x10000);

        vm.startBroadcast();
        trigger = new TrimmyConfidentialTrigger(
            ITeeExtensionRegistry(manager), ITeeMachineRegistry(manager)
        );
        vm.stopBroadcast();

        console.log("TrimmyConfidentialTrigger:", address(trigger));
        console.log("");
        console.log("");
        console.log("No teeAddress is bound: verdict signers are validated against the registry,");
        console.log("so a machine can be registered, replaced or rotated with no redeploy.");
        console.log("");
        console.log("Next, in order:");
        console.log("  1. register the extension, binding this address as the InstructionSender");
        console.log("  2. trigger.setExtensionId(<id>)   -- verified against the registry, O(1)");
        console.log("  3. deploy Trimmy with TRIMMY_CONFIDENTIAL_TRIGGER set to this address");
        console.log("  4. trigger.setTrimmy(<trimmy>)    -- set-once");
    }
}
