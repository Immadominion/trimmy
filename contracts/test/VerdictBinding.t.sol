// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {
    ITeeExtensionRegistry,
    ITeeMachineRegistry,
    TrimmyConfidentialTrigger
} from "../src/TrimmyConfidentialTrigger.sol";

/// @notice A registry that hands back a DISTINCT instruction id per send and records the message.
/// @dev Both matter. The constant-id mock used elsewhere cannot tell "the verdict for the request
///      we made" apart from "a verdict for some other instruction", which is exactly the
///      distinction this file exists to test; and without the recorded message there is no way to
///      assert what price the enclave was actually asked about.
contract RecordingRegistry is ITeeExtensionRegistry, ITeeMachineRegistry {
    mapping(address => uint256) public ext;
    mapping(address => uint8) public stat;
    mapping(address => bool) public known;
    mapping(uint256 => address) public senders;
    uint256 public next = 0x10000;

    uint256 public sends;
    bytes public lastMessage;
    uint256 public lastValue;

    error NotAMachine();

    function register(address tee, uint256 extensionId) external {
        ext[tee] = extensionId;
        stat[tee] = 2;
        known[tee] = true;
    }

    function setSender(uint256 id, address s) external {
        senders[id] = s;
        if (id >= next) next = id + 1;
    }

    function getTeeMachineWithAttestationData(address t)
        external
        view
        returns (TeeMachineData memory)
    {
        if (!known[t]) revert NotAMachine();
        // safe: 11-byte literal, cannot truncate into bytes32.
        // forge-lint: disable-next-line(unsafe-typecast)
        return TeeMachineData(t, address(0), "http://example", bytes32(0), bytes32("GCP_AMD_SEV"));
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

    function sendInstructions(address[] calldata, TeeInstructionParams calldata p)
        external
        payable
        returns (bytes32)
    {
        sends++;
        lastMessage = p.message;
        lastValue = msg.value;
        return keccak256(abi.encodePacked("instruction", sends));
    }
}

/// @notice Stands in for Trimmy's `currentPrice`: charges an FTSO fee and refunds the rest, so the
///         trigger's value accounting is exercised rather than assumed.
contract PriceSource {
    uint128 public price;
    uint256 public ftsoFee;

    constructor(uint128 p, uint256 fee) {
        price = p;
        ftsoFee = fee;
    }

    function set(uint128 p) external {
        price = p;
    }

    function currentPrice(uint256) external payable returns (uint128) {
        require(msg.value >= ftsoFee, "fee");
        uint256 refund = msg.value - ftsoFee;
        if (refund > 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            require(ok, "refund");
        }
        return price;
    }
}

/// @title The evaluation price must come from the chain, and a verdict must answer OUR question
///
/// @notice This file is the regression for the worst defect this project has had.
///
///         `requestEvaluation` used to take the observed price as a caller-supplied string, and
///         `acceptVerdict` never checked that a verdict answered an instruction this contract
///         sent. Together those gave any stranger a complete bypass of the confidential trigger:
///
///           1. call `requestEvaluation(victimRule, "1", nonce)` — a price they invent
///           2. the enclave compares 1 against the secret threshold, sees it satisfied, signs
///              `fire = true`, and publishes the signed result on the proxy's public endpoint
///           3. `acceptVerdict` accepts it — the commitment is public, the nonce is unused, the
///              signature really is the enclave's
///           4. `Trimmy.execute` fires the victim's rule at a price they never chose
///
///         The same primitive, asked repeatedly, recovers the secret itself: each verdict is one
///         bit of "is the threshold above or below the number I picked", so about twenty queries
///         binary-search it. The threshold was secret in name only.
///
///         Both failures have one root cause — the number the enclave compared against came from
///         the attacker instead of from FTSO — and the tests below pin both halves of the fix.
contract VerdictBindingTest is Test {
    RecordingRegistry internal reg;
    TrimmyConfidentialTrigger internal ct;
    PriceSource internal trimmy;

    uint256 internal constant EXT = 0x10005;
    uint256 internal constant FTSO_FEE = 0.0003 ether;
    uint128 internal constant CHAIN_PRICE = 1_234_567;

    uint256 internal teeKey;
    address internal tee;

    address internal owner = makeAddr("owner");
    address internal attacker = makeAddr("attacker");
    address internal keeper = makeAddr("keeper");

    bytes32 internal constant COMMITMENT = keccak256("commitment");

    function setUp() public {
        (tee, teeKey) = makeAddrAndKey("tee");

        reg = new RecordingRegistry();
        ct = new TrimmyConfidentialTrigger(reg, reg);
        reg.setSender(EXT, address(ct));
        ct.setExtensionId(EXT);
        reg.register(tee, EXT);

        trimmy = new PriceSource(CHAIN_PRICE, FTSO_FEE);
        ct.setTrimmy(address(trimmy));

        vm.prank(owner);
        ct.commitTrigger(1, COMMITMENT);

        vm.deal(owner, 10 ether);
        vm.deal(attacker, 10 ether);
        vm.deal(keeper, 10 ether);
    }

    // ---------------------------------------------------------------------------------------
    // The price is the chain's, not the caller's
    // ---------------------------------------------------------------------------------------

    /// The enclave is asked about the price this contract read from FTSO. Nothing in the call
    /// lets a caller name a different one — the parameter is gone.
    function test_theEnclaveIsAskedAboutTheChainsPrice() public {
        vm.prank(keeper);
        ct.requestEvaluation{value: 0.01 ether}(1, 0);

        assertEq(
            string(reg.lastMessage()),
            '{"ruleId":1,"observedPrice":"1234567","nonce":0}',
            "the instruction must carry the price Trimmy derived from FTSO"
        );
    }

    /// A different chain price produces a different question — proving the number is read at call
    /// time rather than baked in at deployment.
    function test_theQuestionTracksTheChainPrice() public {
        trimmy.set(999);
        vm.prank(attacker);
        ct.requestEvaluation{value: 0.01 ether}(1, 0);
        assertEq(string(reg.lastMessage()), '{"ruleId":1,"observedPrice":"999","nonce":0}');
    }

    /// The FTSO fee is paid out of the caller's value and the remainder funds the instruction —
    /// the trigger must not be left holding either party's money.
    function test_valueAccounting() public {
        vm.prank(keeper);
        ct.requestEvaluation{value: 0.01 ether}(1, 0);
        assertEq(reg.lastValue(), 0.01 ether - FTSO_FEE, "instruction is funded by what came back");
        assertEq(address(ct).balance, 0, "the trigger keeps nothing");
    }

    // ---------------------------------------------------------------------------------------
    // A verdict must answer OUR question
    // ---------------------------------------------------------------------------------------

    /// The core bypass. A genuinely enclave-signed `fire` verdict, for a rule whose commitment is
    /// public, is refused outright when this contract never asked the question.
    function test_anUnrequestedVerdictIsRefused() public {
        bytes32 forged = keccak256("an instruction the attacker sent themselves");
        (bytes memory data, bytes memory sig) = _verdict(forged, int64(uint64(block.timestamp)));

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                TrimmyConfidentialTrigger.NoEvaluationRequested.selector, uint256(1), uint64(0)
            )
        );
        ct.acceptVerdict(
            1, true, COMMITMENT, 0, int64(uint64(block.timestamp)), data, forged, "end", 1, sig
        );
    }

    /// And when we DID ask, a verdict answering some other instruction is still refused. Otherwise
    /// an attacker only has to ask their own question in parallel with an honest one.
    function test_aVerdictForAnotherInstructionIsRefused() public {
        vm.prank(keeper);
        ct.requestEvaluation{value: 0.01 ether}(1, 0);
        bytes32 ours = ct.pendingAction(1, 0);

        bytes32 other = keccak256("some other instruction");
        (bytes memory data, bytes memory sig) = _verdict(other, int64(uint64(block.timestamp)));

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                TrimmyConfidentialTrigger.VerdictNotRequested.selector, ours, other
            )
        );
        ct.acceptVerdict(
            1, true, COMMITMENT, 0, int64(uint64(block.timestamp)), data, other, "end", 1, sig
        );
    }

    /// The happy path still works: ask, and the answer to that exact instruction is accepted.
    function test_theAnswerToOurOwnQuestionIsAccepted() public {
        vm.prank(keeper);
        ct.requestEvaluation{value: 0.01 ether}(1, 0);
        bytes32 ours = ct.pendingAction(1, 0);

        (bytes memory data, bytes memory sig) = _verdict(ours, int64(uint64(block.timestamp)));

        vm.prank(keeper);
        ct.acceptVerdict(
            1, true, COMMITMENT, 0, int64(uint64(block.timestamp)), data, ours, "end", 1, sig
        );

        // Consuming it is what Trimmy does during execute(); it must now succeed exactly once.
        vm.prank(address(trimmy));
        ct.consumeVerdict(1, 0);
    }

    /// Re-asking supersedes the previous question. The stale answer stops being usable, which is
    /// what keeps a verdict tied to a recent price rather than to whenever it was convenient.
    function test_reAskingInvalidatesTheEarlierAnswer() public {
        vm.prank(keeper);
        ct.requestEvaluation{value: 0.01 ether}(1, 0);
        bytes32 first = ct.pendingAction(1, 0);

        vm.prank(keeper);
        ct.requestEvaluation{value: 0.01 ether}(1, 0);
        bytes32 second = ct.pendingAction(1, 0);
        assertTrue(first != second, "each request is a distinct instruction");

        (bytes memory data, bytes memory sig) = _verdict(first, int64(uint64(block.timestamp)));
        vm.expectRevert(
            abi.encodeWithSelector(
                TrimmyConfidentialTrigger.VerdictNotRequested.selector, second, first
            )
        );
        ct.acceptVerdict(
            1, true, COMMITMENT, 0, int64(uint64(block.timestamp)), data, first, "end", 1, sig
        );
    }

    /// An evaluation cannot be requested before the Trimmy binding exists — otherwise the price
    /// would be read from address(0) and the call would fail somewhere less legible.
    function test_requestBeforeBindingIsRefused() public {
        TrimmyConfidentialTrigger fresh = new TrimmyConfidentialTrigger(reg, reg);
        reg.setSender(EXT + 1, address(fresh));
        fresh.setExtensionId(EXT + 1);
        vm.prank(owner);
        fresh.commitTrigger(1, COMMITMENT);

        vm.prank(keeper);
        vm.expectRevert(TrimmyConfidentialTrigger.TrimmyNotSet.selector);
        fresh.requestEvaluation{value: 0.01 ether}(1, 0);
    }

    // ---------------------------------------------------------------------------------------

    /// Builds a verdict signed by the registered enclave key, exactly as the TEE node signs it:
    /// over the domain-separated `TEE_ACTION_RESULT` payload, not the bare result hash.
    function _verdict(bytes32 actionId, int64 issuedAt)
        internal
        view
        returns (bytes memory data, bytes memory sig)
    {
        data = abi.encodePacked('{"ruleId":1,"fire":true,"issuedAt":', vm.toString(issuedAt), "}");
        bytes32 resultHash = keccak256(
            abi.encodePacked(keccak256(data), actionId, keccak256(bytes("end")), uint8(1))
        );
        // safe: 17-byte literal, cannot truncate into bytes32. The directive has to sit on the
        // line immediately above the cast itself, not above the statement — `forge fmt` wraps this
        // assignment and the cast lands one line lower than it was written.
        bytes32 payload = keccak256(
            // forge-lint: disable-next-line(unsafe-typecast)
            abi.encode(bytes32("TEE_ACTION_RESULT"), block.chainid, resultHash)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", payload));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(teeKey, digest);
        sig = abi.encodePacked(r, s, v);
    }
}
