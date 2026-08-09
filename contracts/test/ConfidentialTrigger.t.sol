// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {
    ITeeExtensionRegistry,
    ITeeMachineRegistry,
    TrimmyConfidentialTrigger
} from "../src/TrimmyConfidentialTrigger.sol";

/// @notice Faithful to the REAL Coston2 registry in the one respect that bit us: it **reverts**
///         for an address that was never a TEE machine, rather than returning zero.
contract RevertingRegistry is ITeeExtensionRegistry, ITeeMachineRegistry {
    mapping(address => uint256) public ext;
    mapping(address => uint8) public stat;
    mapping(address => bool) public known;
    mapping(address => bytes32) public plat;
    mapping(uint256 => address) public senders;
    uint256 public next = 0x10000;

    error NotAMachine();

    function register(address tee, uint256 extensionId, uint8 status) external {
        // safe: 11-byte literal, cannot truncate into bytes32.
        // forge-lint: disable-next-line(unsafe-typecast)
        registerWithPlatform(tee, extensionId, status, bytes32("GCP_AMD_SEV"));
    }

    function registerWithPlatform(address tee, uint256 extensionId, uint8 status, bytes32 platform)
        public
    {
        ext[tee] = extensionId;
        stat[tee] = status;
        plat[tee] = platform;
        known[tee] = true;
    }

    /// @dev Returns a STRUCT, matching the real registry. Declaring five separate returns instead
    ///      compiles and calls fine — the selector is identical — but the record holds a dynamic
    ///      `string`, so the encodings differ, the decode fails, and the caller's try/catch reports
    ///      "not authorised" for EVERY machine. This mock exists in the struct shape precisely so
    ///      that mistake cannot pass the suite.
    function getTeeMachineWithAttestationData(address t)
        external
        view
        returns (TeeMachineData memory)
    {
        if (!known[t]) revert NotAMachine();
        return TeeMachineData({
            teeId: t,
            initialTeeId: address(0),
            url: "http://example",
            codeHash: bytes32(0),
            platform: plat[t]
        });
    }

    function setSender(uint256 id, address s) external {
        senders[id] = s;
        if (id >= next) next = id + 1;
    }

    function getExtensionId(address t) external view returns (uint256) {
        if (!known[t]) revert NotAMachine();
        return ext[t];
    }

    function getTeeMachineStatus(address t) external view returns (uint8) {
        if (!known[t]) revert NotAMachine();
        return stat[t];
    }

    function getRandomTeeIds(uint256, uint256) external pure returns (address[] memory a) {
        a = new address[](1);
        a[0] = address(0xBEEF);
    }

    function nextPublicExtensionId() external view returns (uint256) {
        return next;
    }

    function getTeeExtensionInstructionsSender(uint256 id) external view returns (address) {
        return senders[id];
    }

    function sendInstructions(address[] calldata, TeeInstructionParams calldata)
        external
        payable
        returns (bytes32)
    {
        return bytes32(uint256(1));
    }
}

/// @title Confidential trigger — registry-anchored TEE authorisation
contract ConfidentialTriggerTest is Test {
    RevertingRegistry internal reg;
    TrimmyConfidentialTrigger internal ct;

    uint256 internal constant EXT = 0x10005;
    address internal ourTee = makeAddr("ourTee");
    address internal otherTee = makeAddr("otherExtensionTee");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        reg = new RevertingRegistry();
        ct = new TrimmyConfidentialTrigger(reg, reg);
        reg.setSender(EXT, address(ct));
        ct.setExtensionId(EXT);

        reg.register(ourTee, EXT, 2); // live, ours
        reg.register(otherTee, 0x10009, 2); // live, someone else's
    }

    /// The bug this file exists for: a stranger is not a machine, the registry REVERTS, and the
    /// predicate must answer `false` rather than propagate that revert.
    function test_strangerIsNotAuthorisedAndDoesNotRevert() public view {
        assertFalse(ct.isAuthorisedTee(stranger));
    }

    function test_zeroIsNotAuthorised() public view {
        assertFalse(ct.isAuthorisedTee(address(0)));
    }

    /// A live machine serving THIS extension is authorised.
    function test_ourLiveTeeIsAuthorised() public view {
        assertTrue(ct.isAuthorisedTee(ourTee));
    }

    /// Without the extension check, any machine on Flare could sign our verdicts.
    function test_anotherExtensionsTeeIsNotAuthorised() public view {
        assertFalse(ct.isAuthorisedTee(otherTee));
    }

    /// Without the status check, a decommissioned machine could.
    function test_inactiveTeeIsNotAuthorised() public {
        reg.register(ourTee, EXT, 1); // any non-live status
        assertFalse(ct.isAuthorisedTee(ourTee));
    }

    /// Before the extension id is known, nothing is authorised — refusing is the safe default.
    function test_nothingIsAuthorisedBeforeTheExtensionIdIsSet() public {
        TrimmyConfidentialTrigger fresh = new TrimmyConfidentialTrigger(reg, reg);
        assertFalse(fresh.isAuthorisedTee(ourTee));
    }

    function test_setExtensionIdRejectsAnIdThatIsNotOurs() public {
        TrimmyConfidentialTrigger fresh = new TrimmyConfidentialTrigger(reg, reg);
        reg.setSender(0x10077, address(0xDEAD));
        vm.expectRevert(TrimmyConfidentialTrigger.ExtensionIdNotFound.selector);
        fresh.setExtensionId(0x10077);
    }

    function test_setExtensionIdRejectsSystemRange() public {
        TrimmyConfidentialTrigger fresh = new TrimmyConfidentialTrigger(reg, reg);
        vm.expectRevert(TrimmyConfidentialTrigger.ExtensionIdNotFound.selector);
        fresh.setExtensionId(0xFFFF); // below the public range
    }

    /// The finding this check exists for, reproduced: a SIMULATED machine registers as live on the
    /// very same extension and `getRandomTeeIds` will route to it. Its codeHash is a network-wide
    /// constant, so a verdict it signs is one anybody could produce. It must not be authorised.
    function test_simulatedPlatformIsRejected() public {
        address simTee = makeAddr("simulatedTee");
        // safe: 13-byte literal, cannot truncate into bytes32.
        // forge-lint: disable-next-line(unsafe-typecast)
        reg.registerWithPlatform(simTee, EXT, 2, bytes32("TEST_PLATFORM"));
        assertFalse(ct.isAuthorisedTee(simTee), "a TEST_PLATFORM machine must never sign verdicts");
        assertTrue(ct.isAuthorisedTee(ourTee), "and real hardware still is authorised");
    }

    function test_setTrimmyIsSetOnce() public {
        ct.setTrimmy(address(0xAAA));
        vm.expectRevert(TrimmyConfidentialTrigger.TrimmyAlreadySet.selector);
        ct.setTrimmy(address(0xBBB));
    }

    function test_onlyTrimmyMayConsume() public {
        ct.setTrimmy(address(0xAAA));
        vm.expectRevert(
            abi.encodeWithSelector(TrimmyConfidentialTrigger.OnlyTrimmy.selector, address(this))
        );
        ct.consumeVerdict(1, 0);
    }
}
