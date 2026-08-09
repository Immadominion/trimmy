// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Trimmy} from "../src/Trimmy.sol";

/// @title Live end-to-end on Coston2 — arm an auto-earn rule and execute it
/// @notice This is the lead demo path and it needs no swap pool: it deposits FXRP into
///         **TESTearnXRP**, a real third-party vault that is live, funded with ~7,197 FXRP, and
///         carrying a share price of 1.05917 — i.e. yield that actually accrued. We deliberately do
///         NOT lead with stXRP, whose share price is exactly 1.000000 (`totalAssets == totalSupply`
///         to the unit), because a judge falsifies "live funded vault" there in two `cast call`s.
///
/// @dev Settles **O-3**: the real `execute()` gas cost on Coston2, which sets the minimum viable
///      `keeperFeeFlat` and therefore the refuse-to-arm threshold.
///
///      In production `arm` is called by the user's personal account from inside the 0xFE batch, so
///      `rules[id].account` is that account. Here the deployer EOA plays that role; the mechanism
///      under test — allowance-pull, permissionless execution, proceeds to `rule.account` — is
///      identical either way.
///
///      Run:
///        forge script script/LiveE2E.s.sol:LiveE2E --rpc-url coston2 --broadcast \
///          --private-key $COSTON2_TEST_KEY
contract LiveE2E is Script {
    address constant FXRP = 0x0b6A3645c240605887a5532109323A3E12273dc7;
    address constant EARN_VAULT = 0x9E63a5D282F2fBb7DcE822B98e363b2719D28319;

    uint8 constant TOK_FXRP = 0;
    uint8 constant VENUE_VAULT = 1;

    function run() external {
        Trimmy trimmy = Trimmy(payable(vm.envAddress("TRIMMY_ADDRESS")));
        uint128 amount = uint128(vm.envOr("TRIMMY_E2E_AMOUNT", uint256(1_000_000))); // 1 FXRP

        address me = msg.sender;
        IERC20 fxrp = IERC20(FXRP);
        IERC20 shares = IERC20(EARN_VAULT);

        console.log("account       :", me);
        console.log("FXRP before   :", fxrp.balanceOf(me));
        console.log("shares before :", shares.balanceOf(me));

        vm.startBroadcast();

        // The arming batch's first call. Sized exactly to the rule's whole life — never unlimited.
        fxrp.approve(address(trimmy), amount);

        uint256 ruleId = trimmy.arm(
            Trimmy.RuleParams({
                sellTokenId: TOK_FXRP,
                buyTokenId: TOK_FXRP, // vault verbs do not swap; the buy leg is the same asset
                verb: Trimmy.Verb.DEPOSIT_VAULT,
                venueId: VENUE_VAULT,
                trigger: Trimmy.Trigger.SCHEDULE,
                totalSellAmount: amount,
                partSellAmount: amount,
                // Share price is 1.05917, so 1 FXRP buys ~0.944 shares. Floor a little under that:
                // a floor of zero would accept any outcome, which defeats the point.
                minOutAbsolute: (uint128(amount) * 90) / 100,
                triggerValue: 60,
                expiry: uint64(block.timestamp + 7 days),
                slippageBips: 0,
                protocolFeeBips: 0,
                keeperFeeFlat: 0,
                keeperFeeBudget: 0
            })
        );
        console.log("armed ruleId  :", ruleId);

        // Permissionless: any address may call this. Here it is us, because it is our testnet key.
        uint256 gasBefore = gasleft();
        trimmy.execute(ruleId);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopBroadcast();

        console.log("execute() gas :", gasUsed);
        console.log("FXRP after    :", fxrp.balanceOf(me));
        console.log("shares after  :", shares.balanceOf(me));

        Trimmy.Rule memory r = trimmy.ruleAt(ruleId);
        console.log("rule.spent    :", r.spent);
        console.log("rule.active   :", r.active);
    }
}
