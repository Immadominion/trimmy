// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConfidentialTrigger} from "../src/Interfaces.sol";
import {Trimmy} from "../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockQueuedVault} from "./mocks/Mocks.sol";

/// @notice Stands in for `TrimmyConfidentialTrigger` — the on-chain half of the FCC extension.
/// @dev Faithful to the real contract's `consumeVerdict`: it reverts unless a verdict for exactly
///      `(ruleId, nonce)` was accepted, and it only answers the bound Trimmy instance.
contract MockConfidentialTrigger is IConfidentialTrigger {
    address public trimmy;
    mapping(uint256 => mapping(uint64 => bool)) public accepted;

    error OnlyTrimmy(address caller);
    error NoAcceptedVerdict(uint256 ruleId, uint64 nonce);

    function setTrimmy(address t) external {
        trimmy = t;
    }

    /// Stands for the full `acceptVerdict` path: signature over the domain-separated
    /// TEE_ACTION_RESULT payload, commitment match, replay check, freshness. Those are exercised
    /// against the real contract; here we only need the gate they produce.
    function acceptFor(uint256 ruleId, uint64 nonce) external {
        accepted[ruleId][nonce] = true;
    }

    function consumeVerdict(uint256 ruleId, uint64 nonce) external view {
        if (msg.sender != trimmy) revert OnlyTrimmy(msg.sender);
        if (!accepted[ruleId][nonce]) revert NoAcceptedVerdict(ruleId, nonce);
    }
}

/// @title PRIVATE trigger — the confidential rule path
/// @notice A PRIVATE rule's threshold is never on chain. What is on chain is a commitment, and the
///         only thing that lets the rule fire is a signed verdict from the enclave.
///
///         These tests exist to pin the property the Bounty 2 submission claims: **you cannot read
///         a confidential rule's trigger price off the chain, and you cannot fire one without a
///         verdict.**
contract PrivateTriggerTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED = bytes21(uint168(0x015852502f55534400000000000000000000000000));

    Trimmy internal trimmy;
    Trimmy internal trimmyNoTrigger;
    MockConfidentialTrigger internal ct;
    MockERC20 internal fxrp;
    MockQueuedVault internal vault;
    MockFtsoV2 internal ftso;

    address internal account = makeAddr("account");
    address internal keeper = makeAddr("keeper");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        vault = new MockQueuedVault(IERC20(address(fxrp)));

        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        ftso.setFeed(FEED, 1_000_000, 6, uint64(vm.getBlockTimestamp()));

        ct = new MockConfidentialTrigger();

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });

        trimmy = new Trimmy(tokens, venues, 3600, makeAddr("feeSink"), ct);
        ct.setTrimmy(address(trimmy));

        // A second instance with confidential triggers DISABLED, which is the correct configuration
        // for a deployment that does not want a censorship-capable trigger at all.
        trimmyNoTrigger =
            new Trimmy(tokens, venues, 3600, makeAddr("feeSink"), IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1000e6);
        vm.startPrank(account);
        fxrp.approve(address(trimmy), type(uint256).max);
        fxrp.approve(address(trimmyNoTrigger), type(uint256).max);
        vm.stopPrank();
    }

    function _privateRule(Trimmy t) internal returns (uint256 id) {
        vm.prank(account);
        id = t.arm(
            Trimmy.RuleParams({
                sellTokenId: 0,
                buyTokenId: 0,
                verb: Trimmy.Verb.DEPOSIT_VAULT,
                venueId: 0,
                trigger: Trimmy.Trigger.PRIVATE,
                totalSellAmount: 100e6,
                partSellAmount: 50e6,
                minOutAbsolute: 0,
                // Meaningless for a PRIVATE rule and deliberately so — the real threshold is in the
                // enclave. Any value here reveals nothing.
                triggerValue: 0,
                expiry: uint64(vm.getBlockTimestamp() + 30 days),
                slippageBips: 0,
                protocolFeeBips: 0,
                keeperFeeFlat: 0,
                keeperFeeBudget: 0
            })
        );
    }

    /// The headline property: nothing on chain reveals when this rule fires.
    function test_theThresholdIsNotOnChain() public {
        uint256 id = _privateRule(trimmy);
        Trimmy.Rule memory r = trimmy.ruleAt(id);
        assertEq(uint8(r.trigger), uint8(Trimmy.Trigger.PRIVATE));
        assertEq(r.triggerValue, 0, "a PRIVATE rule publishes no threshold");
    }

    /// A PRIVATE rule that tries to publish a threshold is refused. Leaving it merely "unused"
    /// would let a careless or hostile front end write the real number into a public field while
    /// the user believed it was confidential.
    function test_privateRuleMayNotPublishAThreshold() public {
        vm.prank(account);
        vm.expectRevert(Trimmy.PrivateRuleMustNotPublishThreshold.selector);
        trimmy.arm(
            Trimmy.RuleParams({
                sellTokenId: 0,
                buyTokenId: 0,
                verb: Trimmy.Verb.DEPOSIT_VAULT,
                venueId: 0,
                trigger: Trimmy.Trigger.PRIVATE,
                totalSellAmount: 100e6,
                partSellAmount: 50e6,
                minOutAbsolute: 0,
                triggerValue: 1_234_567, // the leak
                expiry: uint64(vm.getBlockTimestamp() + 30 days),
                slippageBips: 0,
                protocolFeeBips: 0,
                keeperFeeFlat: 0,
                keeperFeeBudget: 0
            })
        );
    }

    /// Without a verdict, the rule does not fire. This is what makes the enclave load-bearing
    /// rather than decorative.
    function test_withoutAVerdictItDoesNotFire() public {
        uint256 id = _privateRule(trimmy);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockConfidentialTrigger.NoAcceptedVerdict.selector, id, uint64(0)
            )
        );
        trimmy.execute(id);
    }

    /// With one, it does.
    function test_withAVerdictItFires() public {
        uint256 id = _privateRule(trimmy);
        ct.acceptFor(id, 0); // nonce == spent == 0 for the first part

        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).spent, 50e6);
    }

    /// A verdict is good for exactly one part. The nonce advances with `spent`, so a `fire` verdict
    /// cannot be replayed onto a later part once the price has moved back.
    function test_aVerdictCannotBeReplayedOntoTheNextPart() public {
        uint256 id = _privateRule(trimmy);
        ct.acceptFor(id, 0);

        vm.prank(keeper);
        trimmy.execute(id);

        vm.warp(vm.getBlockTimestamp() + 120);
        ftso.setFeed(FEED, 1_000_000, 6, uint64(vm.getBlockTimestamp()));

        // The second part needs its own verdict at nonce == 50e6.
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockConfidentialTrigger.NoAcceptedVerdict.selector, id, uint64(50e6)
            )
        );
        trimmy.execute(id);

        ct.acceptFor(id, uint64(50e6));
        vm.prank(keeper);
        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).spent, 100e6);
    }

    /// Only Trimmy may consume a verdict — otherwise anyone could burn one and grief the rule.
    function test_onlyTrimmyMayConsumeAVerdict() public {
        uint256 id = _privateRule(trimmy);
        ct.acceptFor(id, 0);
        vm.expectRevert(
            abi.encodeWithSelector(MockConfidentialTrigger.OnlyTrimmy.selector, address(this))
        );
        ct.consumeVerdict(id, 0);
    }

    /// A deployment that sets no trigger contract refuses PRIVATE rules outright rather than
    /// silently treating them as unconditional.
    function test_disabledDeploymentRefusesPrivateRules() public {
        uint256 id = _privateRule(trimmyNoTrigger);
        vm.prank(keeper);
        vm.expectRevert(Trimmy.PrivateTriggersDisabled.selector);
        trimmyNoTrigger.execute(id);
    }
}
