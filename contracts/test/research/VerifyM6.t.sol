// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

import {Trimmy} from "../../src/Trimmy.sol";
import {TrimmyTest} from "../Trimmy.t.sol";

/// @notice Adversarial verification of M-6: _validate gates the vault-asset assertion on
///         DEPOSIT_VAULT (Trimmy.sol:347), so EXIT_VAULT arms with any allowlisted sell token.
/// @dev Inherits the default fixture, whose allowlist has the SAME SHAPE as the live deployment:
///      token0 = the vault's underlying asset, token1 = an unrelated token, venue1 = the vault.
///      Neither allowlisted token is the vault share token — exactly as on 0xf73a2af0…6554.
contract VerifyM6Test is TrimmyTest {
    function _exitParams() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: TOK_FXRP, // the vault's ASSET, not its SHARE token
            buyTokenId: TOK_FXRP,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: VENUE_VAULT,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6,
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    /// Half one: the guard is genuinely absent. DEPOSIT_VAULT with the same wrong token is
    /// rejected; EXIT_VAULT with it is accepted.
    function test_M6_armAcceptsExitVaultWhoseSellTokenIsNotTheShareToken() public {
        assertTrue(address(vault) != address(fxrp), "fxrp is not the share token");
        assertTrue(address(vault) != address(usdt), "usdt is not the share token");

        // DEPOSIT_VAULT with a non-asset sell token is refused …
        Trimmy.RuleParams memory bad = _exitParams();
        bad.verb = Trimmy.Verb.DEPOSIT_VAULT;
        bad.sellTokenId = TOK_USDT;
        bad.buyTokenId = TOK_USDT;
        vm.prank(account);
        vm.expectRevert(
            abi.encodeWithSelector(
                Trimmy.VaultAssetMismatch.selector, address(vault), address(fxrp), address(usdt)
            )
        );
        trimmy.arm(bad);

        // … but EXIT_VAULT is armed against a token the vault does not even issue.
        uint256 id = _arm(_exitParams());
        assertEq(uint8(trimmy.ruleAt(id).verb), uint8(Trimmy.Verb.EXIT_VAULT));

        // And it is permanently unexecutable: Trimmy holds 0 shares, so the redeem reverts.
        // (Live equivalent measured on chain: vault.redeem(1e8, Trimmy, Trimmy) from Trimmy
        //  reverts ERC4626ExceededMaxRedeem(0xf73a…6554, 100000000, 0).)
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(trimmy), 0, 100e6
            )
        );
        trimmy.execute(id);
    }

    /// Half two: with share tokens sitting in Trimmy from ANY source, the redeem stops reverting
    /// and the sell token the rule pulled from the user is stranded with no way out.
    function test_M6_donatedSharesMakeItExecuteAndStrandTheUsersFunds() public {
        // Anyone can put shares here. Here a third party does it; no permission is needed.
        fxrp.mint(attacker, 500e6);
        vm.startPrank(attacker);
        fxrp.approve(address(vault), 500e6);
        vault.deposit(500e6, attacker);
        vault.transfer(address(trimmy), 100e6);
        vm.stopPrank();

        uint256 id = _arm(_exitParams());

        uint256 userFxrpBefore = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.execute(id); // no revert now

        uint256 debited = userFxrpBefore - fxrp.balanceOf(account);
        assertEq(debited, 100e6, "user's FXRP was pulled");
        assertEq(fxrp.balanceOf(address(trimmy)), 100e6, "and it is sitting in Trimmy");
        assertEq(trimmy.ruleAt(id).pendingShares, 100e6, "donated shares were burned instead");

        // Phase two pays the user out of the DONATED shares; the pulled FXRP never moves again.
        Trimmy.Rule memory r = trimmy.ruleAt(id);
        vm.warp(r.claimableAt);
        vm.prank(keeper);
        trimmy.claim(id);

        assertEq(
            fxrp.balanceOf(address(trimmy)),
            100e6,
            "M-6: the pulled sell token is stranded forever - no rescue path exists"
        );

        // BUT: the claim paid the user out of the donated shares, so the USER is whole. The value
        // that is actually destroyed belonged to whoever donated the shares. The original claim's
        // "the user's pulled FXRP is stranded" is true of those exact units and false of the
        // user's net position.
        assertEq(fxrp.balanceOf(account), userFxrpBefore, "user net position is FLAT, not -100e6");
        emit log_named_uint("user FXRP debited            ", debited);
        emit log_named_uint(
            "user FXRP net change         ", fxrp.balanceOf(account) - userFxrpBefore
        );
        emit log_named_uint("FXRP permanently in Trimmy   ", fxrp.balanceOf(address(trimmy)));
    }
}
