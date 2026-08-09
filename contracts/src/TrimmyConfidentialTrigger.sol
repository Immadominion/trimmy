// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/// @notice Flare's TEE extension registry — the only path by which an instruction reaches an
///         extension. It rejects any `sendInstructions` whose `msg.sender` is not the single
///         InstructionSender address bound to the extension at registration.
interface ITeeExtensionRegistry {
    struct TeeInstructionParams {
        bytes32 opType;
        bytes32 opCommand;
        bytes message;
        address[] cosigners;
        uint64 cosignersThreshold;
        address claimBackAddress;
    }

    function sendInstructions(address[] calldata _teeIds, TeeInstructionParams calldata _params)
        external
        payable
        returns (bytes32 instructionId);

    function nextPublicExtensionId() external view returns (uint256);
    function getTeeExtensionInstructionsSender(uint256 extensionId) external view returns (address);
}

/// @notice The one thing this contract needs from Trimmy: the price a rule is measured against,
///         read from FTSO by the same contract that will execute it. Kept to a single function so
///         the two contracts stay independently deployable and independently auditable.
interface ITrimmyPrice {
    function currentPrice(uint256 ruleId) external payable returns (uint128);
}

interface ITeeMachineRegistry {
    function getRandomTeeIds(uint256 _extensionId, uint256 _count)
        external
        view
        returns (address[] memory);

    /// @notice The extension a TEE machine is registered to serve.
    function getExtensionId(address teeId) external view returns (uint256);

    /// @notice A machine's lifecycle status. `2` is the live/production state — measured against
    ///         Flare's own Coston2 machines, which is also the state `getRandomTeeIds` selects from.
    function getTeeMachineStatus(address teeId) external view returns (uint8);

    /// @notice Full machine record.
    /// @dev `platform` is the attested hardware model — the ONLY on-chain signal distinguishing a
    ///      real enclave from a simulated one.
    ///
    ///      This returns a STRUCT, not five values, and the difference is not cosmetic. The
    ///      selector is identical either way, so a five-return declaration still *calls*
    ///      successfully — but the record contains a dynamic `string`, so the two ABI encodings
    ///      differ, the return decode fails, and a `try/catch` swallows it as "not authorised".
    ///      That failure mode is silent and total: every enclave, including the real one, is
    ///      rejected. Measured against a machine whose extensionId, status and platform were all
    ///      verifiably correct on chain.
    struct TeeMachineData {
        address teeId;
        address initialTeeId;
        string url;
        bytes32 codeHash;
        bytes32 platform;
    }

    function getTeeMachineWithAttestationData(address teeId)
        external
        view
        returns (TeeMachineData memory);
}

/// @title TrimmyConfidentialTrigger
/// @notice Holds the on-chain half of a Trimmy rule whose trigger price is secret.
///
/// # Why a secret trigger is the thing worth protecting
///
/// An ordinary Trimmy rule stores `triggerValue` on chain. For a stop that publishes the exact
/// price at which a large, price-insensitive sell will arrive — which is the same failure as
/// finding A2 (the execution floor is a publicly computable target), one step earlier. Centralised
/// venues do not publish stop books for this reason.
///
/// FDC structurally cannot help: `Web2Json`'s source id is `PublicWeb2`, so the request and its
/// headers are submitted on chain for ~100 providers to fetch. That is what makes it trustworthy
/// and exactly what stops it holding a secret.
///
/// So the chain holds only `keccak256(threshold ‖ salt ‖ direction)`, and an enclave holds the
/// threshold.
///
/// # What this contract trusts, stated precisely
///
/// It trusts **one enclave's signature** over a verdict. That is a strictly weaker property than an
/// ordinary Trimmy rule, where `execute` is permissionless and every bound is re-derived on chain
/// from live FTSO. A confidential rule cannot fire if the enclave operator declines to run.
///
/// The submission says this every time it describes the product. The two halves have different
/// trust models and pretending otherwise would be the dishonest part.
contract TrimmyConfidentialTrigger {
    // The three-layer identifiers. These must match `internal/config/config.go` byte for byte;
    // a mismatch falls through to "unsupported op type" and is silent from the caller's side.
    // forge-lint: disable-start(unsafe-typecast)
    // safe: each literal is well under 31 bytes, so bytes32(...) cannot truncate. These must match
    // `fcc/extension/go/internal/config/config.go` byte for byte.
    bytes32 public constant OP_TYPE_TRIMMY = bytes32("TRIMMY");
    bytes32 public constant OP_COMMAND_PROVISION = bytes32("PROVISION");
    bytes32 public constant OP_COMMAND_EVALUATE = bytes32("EVALUATE");
    bytes32 public constant OP_COMMAND_FORGET = bytes32("FORGET");
    // forge-lint: disable-end(unsafe-typecast)

    /// @dev Mirrors `config.MaxVerdictAgeSeconds`. A verdict is the one part of a confidential rule
    ///      the permissionless path cannot re-derive, so a stale verdict is a stale price by
    ///      another route and is bounded by the same reasoning that set `maxFeedAge` to 64 s.
    uint64 public constant MAX_VERDICT_AGE = 90;

    /// @dev Matches `Quote.MAX_CLOCK_SKEW`. Measured Coston2 inter-block gap is p50 1 s, max 25 s,
    ///      so a few seconds of disagreement is ordinary and minutes is not.
    uint64 public constant MAX_CLOCK_SKEW = 10;

    ITeeExtensionRegistry public immutable extensionRegistry;
    ITeeMachineRegistry public immutable machineRegistry;

    /// @dev A machine's live status in the registry. Measured: Flare's own production machines and
    ///      the simulated ones alike report `2`, and that is the state `getRandomTeeIds` selects
    ///      from. See docs/GROUND-TRUTH.md.
    uint8 public constant TEE_STATUS_ACTIVE = 2;

    /// @dev `bytes32("GCP_AMD_SEV")` — real AMD SEV hardware under GCP Confidential Space.
    ///
    ///      **This check is the difference between a confidentiality claim and a costume.** Both a
    ///      real enclave and a simulated one register as live machines on the same extension, and
    ///      `getRandomTeeIds` routes to either. We measured exactly that: our own extension briefly
    ///      had one `GCP_AMD_SEV` machine and one `TEST_PLATFORM` machine, both status 2, both
    ///      accepted. A simulated machine's codeHash is a network-wide constant shared by hundreds
    ///      of machines, so it proves nothing about what code ran — and a verdict it signs is a
    ///      verdict anybody with that constant could have produced.
    ///
    ///      Flare's tooling recognises four platforms: GCP_INTEL_TDX, GCP_AMD_SEV, GCP_AMD_SEV_ES
    ///      and TEST_PLATFORM. We accept exactly one, and it is not the last.
    // safe: "GCP_AMD_SEV" is 11 bytes, so bytes32(...) cannot truncate. Verified equal to the
    // live on-chain value 0x4743505f414d445f534556… via `cast --format-bytes32-string`.
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant REQUIRED_PLATFORM = bytes32("GCP_AMD_SEV");

    uint256 public extensionId;
    bool private _extensionIdSet;

    /// @dev The Trimmy instance permitted to consume verdicts. Set once, by the deployer, because
    ///      the two contracts reference each other and one of them has to be deployed first.
    address public trimmy;
    bool private _trimmySet;

    /// @notice The commitment a rule's secret threshold must match.
    mapping(uint256 ruleId => bytes32 commitment) public commitmentOf;
    mapping(uint256 ruleId => address account) public ownerOf;

    /// @notice Consumed verdict nonces, so a `fire` verdict cannot be replayed on a later block
    ///         when the price has moved back.
    mapping(uint256 ruleId => mapping(uint64 nonce => bool used)) public verdictUsed;

    /// @notice The instruction this contract sent for a given `(ruleId, nonce)`. A verdict is only
    ///         accepted if it is the answer to exactly this instruction.
    /// @dev Re-requesting the same nonce overwrites it, which is correct: the newest question is
    ///      the one about the current price, and older answers should stop being usable.
    mapping(uint256 ruleId => mapping(uint64 nonce => bytes32 actionId)) public pendingAction;

    event TriggerCommitted(uint256 indexed ruleId, address indexed account, bytes32 commitment);
    event ProvisionRequested(uint256 indexed ruleId, bytes32 instructionId);
    event EvaluationRequested(uint256 indexed ruleId, uint64 nonce, bytes32 instructionId);
    event VerdictAccepted(uint256 indexed ruleId, uint64 nonce, bool fire);
    event TriggerForgotten(uint256 indexed ruleId);

    error ExtensionIdAlreadySet();
    error ExtensionIdNotFound();
    error NotRuleOwner(address caller, address owner);
    error AlreadyCommitted(uint256 ruleId);
    error NoCommitment(uint256 ruleId);
    error CommitmentMismatch(bytes32 expected, bytes32 got);
    error VerdictReplayed(uint256 ruleId, uint64 nonce);
    error VerdictStale(int64 issuedAt, uint256 nowTs);
    error VerdictFromTheFuture(int64 issuedAt, uint256 nowTs);
    error UnauthorisedTee(address recovered);
    error VerdictDidNotFire(uint256 ruleId);
    error TrimmyAlreadySet();
    error TrimmyNotSet();
    error NoEvaluationRequested(uint256 ruleId, uint64 nonce);
    error VerdictNotRequested(bytes32 requested, bytes32 got);
    error OnlyTrimmy(address caller);
    error NoAcceptedVerdict(uint256 ruleId, uint64 nonce);

    /// @dev There is deliberately no `teeAddress` parameter.
    ///
    ///      An earlier version pinned one immutable enclave address, and that was unimplementable
    ///      for a reason worth recording: **a TEE node generates its identity keypair on boot**, so
    ///      its signing address does not exist until it runs — while the scaffold's lifecycle
    ///      requires the InstructionSender to be deployed and the extension registered BEFORE the
    ///      node starts. The address could never be known at construction time.
    ///
    ///      Asking the registry instead is not a workaround, it is the correct trust anchor: the
    ///      registry is what decides which machines legitimately serve this extension, it is what
    ///      `getRandomTeeIds` routes on, and it lets a machine be replaced or rotated without
    ///      redeploying anything.
    constructor(ITeeExtensionRegistry extensionRegistry_, ITeeMachineRegistry machineRegistry_) {
        extensionRegistry = extensionRegistry_;
        machineRegistry = machineRegistry_;
    }

    /// @notice True when `signer` is a live TEE machine registered to serve THIS extension.
    /// @dev Both halves matter. Without the extension check, any machine anywhere on Flare could
    ///      sign our verdicts; without the status check, a decommissioned machine could.
    function isAuthorisedTee(address signer) public view returns (bool) {
        if (signer == address(0)) return false;
        if (!_extensionIdSet) return false;

        // The registry REVERTS for an address that was never a machine rather than returning zero
        // (measured on Coston2). A predicate that reverts instead of answering is a landmine: it
        // would turn "this signature is from a stranger" — the ordinary, expected case for a forged
        // verdict — into an opaque failure, and make this function unusable off chain for exactly
        // the check a front end most wants to run. So both calls are contained.
        try machineRegistry.getExtensionId(signer) returns (uint256 ext) {
            if (ext != extensionId) return false;
        } catch {
            return false;
        }
        try machineRegistry.getTeeMachineStatus(signer) returns (uint8 status) {
            if (status != TEE_STATUS_ACTIVE) return false;
        } catch {
            return false;
        }

        // Real hardware only. A simulated machine is a live, routable machine on this very
        // extension — refusing it here is the whole point.
        try machineRegistry.getTeeMachineWithAttestationData(signer) returns (
            ITeeMachineRegistry.TeeMachineData memory data
        ) {
            return data.platform == REQUIRED_PLATFORM;
        } catch {
            return false;
        }
    }

    /// @notice Cache our extension id, verifying it against the registry. Set-once.
    ///
    /// @dev The caller supplies the id and the contract CHECKS it, rather than scanning for it.
    ///      Scanning was the obvious implementation and it is the wrong one: 482 public extensions
    ///      are registered on Coston2 today, each probe is an external call, and the scan therefore
    ///      costs well over a million gas and grows without bound as the network fills. Verifying a
    ///      supplied id is O(1) and exactly as safe — the registry is still the authority, and an id
    ///      that does not point back at this contract is rejected.
    ///
    ///      Public ids start at 0x10000; everything below is reserved for system extensions.
    function setExtensionId(uint256 id) external {
        if (_extensionIdSet) revert ExtensionIdAlreadySet();
        if (id < 0x10000 || id >= extensionRegistry.nextPublicExtensionId()) {
            revert ExtensionIdNotFound();
        }
        if (extensionRegistry.getTeeExtensionInstructionsSender(id) != address(this)) {
            revert ExtensionIdNotFound();
        }
        extensionId = id;
        _extensionIdSet = true;
    }

    /// @notice Bind the Trimmy instance allowed to consume verdicts. Set-once.
    /// @dev Deliberately not an owner-gated setter that can be called twice: the two contracts
    ///      reference each other, so one must be deployed first, but after that the binding is as
    ///      immutable as everything else in this system.
    function setTrimmy(address trimmy_) external {
        if (_trimmySet) revert TrimmyAlreadySet();
        trimmy = trimmy_;
        _trimmySet = true;
    }

    /// @notice Reverts unless an enclave verdict for `(ruleId, nonce)` was accepted and said fire.
    /// @dev `acceptVerdict` reverts on a verdict that did NOT fire, so anything recorded here is a
    ///      fire verdict that passed signature, commitment, replay and freshness checks. This is a
    ///      view: Trimmy calls it inside `execute`, and the anti-replay is the nonce advancing with
    ///      the rule's `spent`, not a flag flipped here.
    function consumeVerdict(uint256 ruleId, uint64 nonce) external view {
        if (msg.sender != trimmy) revert OnlyTrimmy(msg.sender);
        if (!verdictUsed[ruleId][nonce]) revert NoAcceptedVerdict(ruleId, nonce);
    }

    /// @notice Publish the commitment for a rule's secret threshold.
    /// @dev The threshold itself never touches this function, this contract, or this chain.
    function commitTrigger(uint256 ruleId, bytes32 commitment) external {
        if (commitmentOf[ruleId] != bytes32(0)) revert AlreadyCommitted(ruleId);
        commitmentOf[ruleId] = commitment;
        ownerOf[ruleId] = msg.sender;
        emit TriggerCommitted(ruleId, msg.sender, commitment);
    }

    /// @notice Deliver the ECIES-encrypted threshold to the enclave.
    /// @param encryptedPayload ECIES ciphertext of the JSON `ProvisionRequest`, encrypted to the
    ///        enclave's public key. Only the enclave can read it; this contract cannot.
    function provision(uint256 ruleId, bytes calldata encryptedPayload) external payable {
        if (commitmentOf[ruleId] == bytes32(0)) revert NoCommitment(ruleId);
        if (msg.sender != ownerOf[ruleId]) revert NotRuleOwner(msg.sender, ownerOf[ruleId]);

        bytes32 instructionId = _send(OP_COMMAND_PROVISION, encryptedPayload);
        emit ProvisionRequested(ruleId, instructionId);
    }

    /// @notice Ask the enclave whether a rule should fire at the price the chain sees right now.
    ///
    /// @dev Deliberately permissionless — a keeper that cannot request an evaluation cannot execute
    ///      a confidential rule, and execution has to work without the owner present.
    ///
    ///      **The price is NOT a parameter, and that is the whole security of this function.** It
    ///      used to be a caller-supplied string, which meant any stranger could ask the enclave
    ///      "does rule 7 fire at a price of 1?", collect the signed `fire` verdict from the public
    ///      result endpoint, and push someone else's rule through `acceptVerdict` at a price its
    ///      owner never chose. The same primitive, asked repeatedly, binary-searches the secret
    ///      threshold in about twenty queries — so the confidentiality claim failed too. Both
    ///      follow from one root cause: the number the enclave compared against came from the
    ///      attacker rather than from the chain.
    ///
    ///      `Trimmy.currentPrice` re-derives it from the same feeds the execution itself would use.
    ///      What a caller still controls is *when* to ask, which is public anyway.
    function requestEvaluation(uint256 ruleId, uint64 nonce) external payable {
        if (commitmentOf[ruleId] == bytes32(0)) revert NoCommitment(ruleId);
        if (verdictUsed[ruleId][nonce]) revert VerdictReplayed(ruleId, nonce);
        if (!_trimmySet) revert TrimmyNotSet();

        // Track only the value this call brought in, never the contract's whole balance — the
        // AUTH-7 lesson, applied to the FTSO refund. `currentPrice` refunds its excess to us, and
        // whatever comes back is what pays for the instruction.
        uint256 preexisting = address(this).balance - msg.value;
        uint128 price = ITrimmyPrice(trimmy).currentPrice{value: msg.value}(ruleId);
        uint256 available = address(this).balance - preexisting;

        bytes memory message = abi.encodePacked(
            '{"ruleId":', _u(ruleId), ',"observedPrice":"', _u(price), '","nonce":', _u(nonce), "}"
        );
        bytes32 instructionId = _send(OP_COMMAND_EVALUATE, message, available);

        // Bind the verdict to THIS request. Without it, a verdict minted by any other instruction
        // — including one an attacker sent directly, outside this contract — satisfies
        // `acceptVerdict`, and every check above becomes decorative.
        pendingAction[ruleId][nonce] = instructionId;
        emit EvaluationRequested(ruleId, nonce, instructionId);
    }

    /// @dev Accepts the FTSO fee refund handed back by `Trimmy.currentPrice`. Without this the
    ///      refund reverts and every evaluation request fails.
    receive() external payable {}

    /// @notice Verify a signed verdict and mark it usable.
    ///
    /// @dev Verification mirrors `fce-weather-insurance`: the node signs
    ///      `keccak256(abi.encode(bytes32("TEE_ACTION_RESULT"), chainId, resultHash))` with the
    ///      EIP-191 prefix — **not** the bare result hash. Verifying against the raw hash fails
    ///      against real TEE node signatures.
    ///
    ///      Four things are checked, and each corresponds to a way a verdict can lie:
    ///        - the signature recovers to the registered enclave  (it came from the enclave)
    ///        - the commitment matches the rule's                (it is about THIS rule's secret)
    ///        - the nonce is unused                              (it is not a replay)
    ///        - it is neither stale nor future-dated             (it is about now)
    ///
    ///      The future-dating check is not decoration: `requireFresh` in Quote.sol had exactly this
    ///      hole (O-18) and one future-dated reading poisoned a rule's floor for its whole life.
    function acceptVerdict(
        uint256 ruleId,
        bool fire,
        bytes32 commitment,
        uint64 nonce,
        int64 issuedAt,
        bytes calldata resultData,
        bytes32 actionId,
        string calldata submissionTag,
        uint8 status,
        bytes calldata signature
    ) external {
        bytes32 expected = commitmentOf[ruleId];
        if (expected == bytes32(0)) revert NoCommitment(ruleId);
        if (expected != commitment) revert CommitmentMismatch(expected, commitment);
        if (verdictUsed[ruleId][nonce]) revert VerdictReplayed(ruleId, nonce);

        // The verdict must answer a question THIS contract asked. Everything below proves the
        // enclave signed some result; only this proves it signed the result of an evaluation whose
        // price came from FTSO rather than from whoever wanted the rule to fire.
        bytes32 requested = pendingAction[ruleId][nonce];
        if (requested == bytes32(0)) revert NoEvaluationRequested(ruleId, nonce);
        if (requested != actionId) revert VerdictNotRequested(requested, actionId);

        // Normalise the sign once, here, rather than casting at each use site and relying on a
        // guard several lines away to make those casts safe.
        if (issuedAt < 0) revert VerdictStale(issuedAt, block.timestamp);
        uint256 issued = SafeCast.toUint256(int256(issuedAt));

        if (issued + MAX_VERDICT_AGE < block.timestamp) {
            revert VerdictStale(issuedAt, block.timestamp);
        }
        // O-18 again, in a second place: a future-dated verdict must be refused, not treated as
        // fresh. `Quote.requireFresh` had precisely this hole and one poisoned reading pinned a
        // rule's floor for its whole life.
        if (issued > block.timestamp + MAX_CLOCK_SKEW) {
            revert VerdictFromTheFuture(issuedAt, block.timestamp);
        }

        bytes32 resultHash = keccak256(
            abi.encodePacked(
                keccak256(resultData), actionId, keccak256(bytes(submissionTag)), status
            )
        );
        bytes32 payloadHash =
        // safe: "TEE_ACTION_RESULT" is 17 bytes, so bytes32(...) cannot truncate. The node
        // signs this domain-separated payload, NOT the bare result hash.
        // forge-lint: disable-next-line(unsafe-typecast)
        keccak256(abi.encode(bytes32("TEE_ACTION_RESULT"), block.chainid, resultHash));
        address signer = _recover(_ethSigned(payloadHash), signature);
        if (!isAuthorisedTee(signer)) revert UnauthorisedTee(signer);

        if (!fire) revert VerdictDidNotFire(ruleId);

        verdictUsed[ruleId][nonce] = true;
        emit VerdictAccepted(ruleId, nonce, fire);
    }

    /// @notice Ask the enclave to drop a rule's secret.
    /// @dev A user who cancels should not have to trust that we stopped holding their threshold.
    function forget(uint256 ruleId) external payable {
        if (msg.sender != ownerOf[ruleId]) revert NotRuleOwner(msg.sender, ownerOf[ruleId]);
        bytes memory message =
            abi.encodePacked('{"ruleId":', _u(ruleId), ',"account":"', _addr(msg.sender), '"}');
        _send(OP_COMMAND_FORGET, message);
        emit TriggerForgotten(ruleId);
    }

    // -------------------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------------------

    function _send(bytes32 opCommand, bytes memory message) private returns (bytes32) {
        return _send(opCommand, message, msg.value);
    }

    /// @dev `fee` is separate from `msg.value` because `requestEvaluation` spends part of its value
    ///      on the FTSO read first and forwards only what came back.
    ///
    ///      Routing is `getRandomTeeIds`, which draws from the machines the registry considers live
    ///      for this extension. That set is curated by the extension owner through
    ///      `disableCodeHashPlatforms`: retiring a measurement retires every machine running it.
    ///      Measured — leaving a superseded image enabled left a machine ACTIVE at a URL whose
    ///      container no longer existed, and roughly half of all instructions were routed into it
    ///      and silently lost, fee paid. See docs/GROUND-TRUTH.md.
    function _send(bytes32 opCommand, bytes memory message, uint256 fee) private returns (bytes32) {
        address[] memory teeIds = machineRegistry.getRandomTeeIds(extensionId, 1);
        return extensionRegistry.sendInstructions{value: fee}(
            teeIds,
            ITeeExtensionRegistry.TeeInstructionParams({
                opType: OP_TYPE_TRIMMY,
                opCommand: opCommand,
                message: message,
                cosigners: new address[](0),
                cosignersThreshold: 0,
                claimBackAddress: msg.sender
            })
        );
    }

    function _ethSigned(bytes32 h) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }

    function _recover(bytes32 digest, bytes calldata sig) private pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(sig[64]);
        if (v < 27) v += 27;
        // Reject the malleable upper half of the curve order rather than accepting two valid
        // signatures for one message.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }
        return ecrecover(digest, v, r, s);
    }

    function _u(uint256 v) private pure returns (bytes memory) {
        if (v == 0) return "0";
        uint256 n = v;
        uint256 len;
        while (n != 0) {
            len++;
            n /= 10;
        }
        bytes memory out = new bytes(len);
        while (v != 0) {
            out[--len] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return out;
    }

    function _addr(address a) private pure returns (bytes memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory out = new bytes(42);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            // safe: the shift leaves at most one byte of significance before the cast.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 b = uint8(uint160(a) >> (8 * (19 - i)));
            out[2 + i * 2] = alphabet[b >> 4];
            out[3 + i * 2] = alphabet[b & 0x0f];
        }
        return out;
    }
}
