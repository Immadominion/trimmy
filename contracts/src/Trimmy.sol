// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {
    ReentrancyGuardTransient
} from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";

import {Quote} from "./Quote.sol";
import {
    IFlareContractRegistry,
    IFtsoV2,
    ISwapRouter,
    IQueuedVault,
    IConfidentialTrigger
} from "./Interfaces.sol";

/// @title Trimmy — conditional execution for XRP
/// @notice One XRPL payment arms a rule. The rule then executes itself, with no further action from
///         the user, no EVM wallet and no gas token.
///
/// @dev **There is no owner, no admin, no proxy, no pause and no rescue function.** The token and
///      venue allowlists are written once in the constructor and there is no code path that can
///      change them. That is deliberate: a mutable venue registry is a rug vector, and the whole
///      security argument here rests on the set of reachable external calls being fixed at deploy
///      time and publicly auditable.
///
///      Design record: `research/01-ARCHITECTURE.md`. Adversarial review that shaped it:
///      `research/02-ARCHITECTURE-ATTACK.md`. Measured chain facts: `docs/GROUND-TRUTH.md`.
contract Trimmy is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // -------------------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------------------

    enum Verb {
        SWAP,
        DEPOSIT_VAULT,
        EXIT_VAULT
    }

    enum Trigger {
        PRICE_BELOW,
        PRICE_ABOVE,
        SCHEDULE,
        /// @dev The threshold is held in a TEE and never appears on chain — only a commitment does.
        ///
        ///      This exists because a published stop price is a target. `PRICE_BELOW` stores
        ///      `triggerValue` in the clear, so anyone reading `ruleAt(id)` knows exactly when a
        ///      large, price-insensitive sell will arrive. That is finding A2 one step earlier, and
        ///      it is why centralised venues do not publish stop books.
        ///
        ///      **The trust model is strictly weaker than the other three.** A PRIVATE rule needs a
        ///      fresh signed verdict from one enclave, so the enclave operator can censor it by
        ///      declining to run. The other triggers are permissionless: anyone can execute them and
        ///      every bound is re-derived on chain. Never describe the two as equally trustless.
        PRIVATE
    }

    enum VenueKind {
        SWAP_ROUTER_V3,
        QUEUED_VAULT
    }

    /// @notice An allowlisted token, with the feed that prices it.
    /// @dev Both legs of every quote are pinned here at construction. A rule cannot name a token
    ///      that has no feed, which is what makes the "one oracle read is not a price" rule
    ///      enforceable rather than aspirational.
    struct TokenCfg {
        address token;
        bytes21 feedId;
        uint8 decimals;
    }

    struct VenueCfg {
        address target;
        VenueKind kind;
        uint24 feeTier; // V3 fee tier; unused for vaults
    }

    /// @dev Packed into 8 slots. Field order is load-bearing for that packing — reordering
    ///      silently costs gas on every execution.
    ///
    ///      **`triggerValue` and `latchedPrice` are `uint128`, and that width is a correctness
    ///      requirement, not headroom.** Both hold a *relative* price: buy-token base units per one
    ///      whole sell token. For the allowlisted FXRP → WC2FLR pair the exponent in `Quote.convert`
    ///      is `(18 + 8) - (6 + 6) = +14`, so the value is ~1.7e20 — **9.3x past `uint64`**.
    ///
    ///      When these were `uint64` the latch saturated at `type(uint64).max`, the execution floor
    ///      was computed from the saturated value, and a rule armed at 50 bips of slippage settled
    ///      at roughly **10.7% of oracle fair value** while reporting that it had honoured its
    ///      floor. A price threshold in that range could not be expressed either, so `PRICE_ABOVE`
    ///      fired after a 5x adverse move and `PRICE_BELOW` could not fire after a 9x crash.
    ///      Found by adversarial review of the deployed code; proof of concept in `M1Verify.t.sol`.
    struct Rule {
        // slot 0
        address account; // the personal account; == msg.sender at arm()
        uint32 epoch; // must equal epochOf[account] or the rule is dead
        uint8 sellTokenId;
        uint8 buyTokenId;
        Verb verb;
        uint8 venueId;
        Trigger trigger;
        bool active;
        // slot 1
        uint128 totalSellAmount;
        uint128 partSellAmount;
        // slot 2
        uint128 spent;
        uint128 minOutAbsolute;
        // slot 3
        uint128 triggerValue; // relative price (buy units per whole sell token), or interval seconds
        uint128 latchedPrice; // 0 until first fire; then every part floors against it
        // slot 4
        uint64 nextEligibleAt;
        uint64 expiry;
        uint64 claimableAt; // EXIT_VAULT: earliest claim time
        uint64 claimPeriod; // EXIT_VAULT: day-index bucket the vault filed it under
        // slot 5
        uint128 keeperFeeFlat; // buyToken units, per execution
        uint128 keeperFeeBudget; // lifetime cap
        // slot 6
        uint128 keeperFeePaid;
        uint128 pendingShares; // EXIT_VAULT: shares queued, awaiting claim
        // slot 7
        uint16 slippageBips;
        uint16 protocolFeeBips;
        uint128 pendingAssets; // EXIT_VAULT: assets the vault owes for pendingShares
        uint64 latchedAt; // when latchedPrice was set; the latch decays from here
    }

    /// @notice Arming parameters. Deliberately NOT the storage struct: a caller supplies intent,
    ///         never bookkeeping. `spent`, `latchedPrice`, `keeperFeePaid`, `pendingShares`,
    ///         `claimableAt`, `claimPeriod` and `epoch` are all derived, never supplied.
    struct RuleParams {
        uint8 sellTokenId;
        uint8 buyTokenId;
        Verb verb;
        uint8 venueId;
        Trigger trigger;
        uint128 totalSellAmount;
        uint128 partSellAmount;
        uint128 minOutAbsolute;
        uint128 triggerValue; // same units as Rule.triggerValue — see the note on Rule
        uint64 expiry;
        uint16 slippageBips;
        uint16 protocolFeeBips;
        uint128 keeperFeeFlat;
        uint128 keeperFeeBudget;
    }

    // -------------------------------------------------------------------------------------
    // Immutable configuration
    // -------------------------------------------------------------------------------------

    /// @dev The only hardcoded address in the system. Identical on all four Flare networks.
    IFlareContractRegistry public constant REGISTRY =
        IFlareContractRegistry(0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019);

    bytes32 private constant FTSO_V2_NAME_HASH = keccak256(abi.encode("FtsoV2"));

    /// @dev A2 is unfixable in principle — any floor is a public target — so it is bounded.
    ///      The extractable band is linear in slippage, so 50 rather than the 100–200 previously
    ///      proposed is a direct 2–4x reduction in what an observer can take per execution.
    uint16 public constant MAX_SLIPPAGE_BIPS = 50;
    uint16 public constant MAX_PROTOCOL_FEE_BIPS = 50;
    uint64 public constant MIN_SCHEDULE_INTERVAL = 60;

    /// @dev **O-16.** The A12 latch stops a partial exit chasing the market down, but a permanent
    ///      latch is too strong in the other direction: a rule that happened to latch at a local
    ///      maximum could never clear its own floor again and was bricked for its whole life, with
    ///      a live allowance and no way to recover.
    ///
    ///      The latch therefore decays linearly back toward the live oracle price over this window.
    ///      Inside it, later parts are still protected against a falling market; past it, the rule
    ///      executes at fair value. One hour comfortably covers a multi-part exit — parts are
    ///      spaced by at least MIN_SCHEDULE_INTERVAL plus jitter, so ten parts take about twelve
    ///      minutes — while bounding the unfillable window to something a user can wait out.
    uint64 public constant LATCH_DECAY_WINDOW = 1 hours;
    uint64 public constant MAX_RULE_LIFETIME = 365 days;

    /// @dev Derived from the in-contract p99 of `block.timestamp - feedTimestamp`, never from a
    ///      wall-clock measurement taken off chain. See GROUND-TRUTH §5.
    uint64 public immutable maxFeedAge;
    address public immutable protocolFeeRecipient;

    /// @dev Optional. `address(0)` disables PRIVATE rules entirely, which is the correct
    ///      configuration for a deployment that does not want a censorship-capable trigger at all.
    IConfidentialTrigger public immutable confidentialTrigger;

    // Written once, in the constructor. No setter exists anywhere in this contract.
    TokenCfg[] private _tokens;
    VenueCfg[] private _venues;

    // -------------------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------------------

    Rule[] private _rules;
    mapping(address account => uint32 epoch) public epochOf;
    mapping(address account => address guardian) public guardianOf;

    // -------------------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------------------

    event Armed(uint256 indexed ruleId, address indexed account, Verb verb, Trigger trigger);
    event Executed(
        uint256 indexed ruleId,
        address indexed keeper,
        uint256 sold,
        uint256 received,
        uint256 keeperFee,
        uint256 protocolFee
    );
    event RedeemQueued(uint256 indexed ruleId, uint256 shares, uint64 claimableAt, uint64 period);
    event Claimed(uint256 indexed ruleId, address indexed keeper, uint256 assets);
    event Cancelled(uint256 indexed ruleId, address indexed by);
    event AllCancelled(address indexed account, uint32 newEpoch, address indexed by);
    event GuardianSet(address indexed account, address indexed guardian);

    // -------------------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------------------

    error EmptyAllowlist();
    error ZeroAddress();
    error TokenDecimalsMismatch(address token, uint8 declared, uint8 actual);
    error UnknownToken(uint8 id);
    error UnknownVenue(uint8 id);
    error VenueKindMismatch(uint8 venueId, Verb verb);
    error VaultAssetMismatch(address vault, address asset, address sellToken);
    error SameToken();
    error ZeroAmount();
    error PartExceedsTotal();
    error SlippageTooHigh(uint16 given, uint16 max);
    error ProtocolFeeTooHigh(uint16 given, uint16 max);
    error BadExpiry();
    error ScheduleTooFast(uint64 given, uint64 min);
    error FeeBudgetCannotFundExecutions(uint128 budget, uint256 required);
    error NoRule(uint256 ruleId);
    error RuleInactive(uint256 ruleId);
    error RuleExpired(uint256 ruleId);
    error StaleEpoch(uint32 ruleEpoch, uint32 currentEpoch);
    error NotYetEligible(uint64 nextEligibleAt);
    error TriggerNotMet(uint256 price, uint128 triggerValue);
    error Exhausted();
    error FloorBreached(uint256 got, uint256 floor);
    error NotAuthorised();
    error WrongVerb();
    error NothingPending();
    error PrivateTriggersDisabled();
    error PrivateRuleMustNotPublishThreshold();
    error RedemptionAlreadyPending(uint64 claimableAt);
    error NotYetClaimable(uint64 claimableAt);
    error InsufficientFeeValue(uint256 supplied, uint256 required);

    // -------------------------------------------------------------------------------------
    // Construction
    // -------------------------------------------------------------------------------------

    constructor(
        TokenCfg[] memory tokens_,
        VenueCfg[] memory venues_,
        uint64 maxFeedAge_,
        address protocolFeeRecipient_,
        IConfidentialTrigger confidentialTrigger_
    ) {
        if (tokens_.length == 0 || venues_.length == 0) {
            revert EmptyAllowlist();
        }
        // AUTH-9: there is no setter and no rescue, so a mistake here is permanent. Every field
        // that can be wrong is checked at deploy time rather than discovered at first execution.
        if (protocolFeeRecipient_ == address(0)) revert ZeroAddress();

        for (uint256 i = 0; i < tokens_.length; i++) {
            if (tokens_[i].token == address(0)) revert ZeroAddress();
            if (tokens_[i].feedId == bytes21(0)) revert ZeroAddress();
            // Verify the declared decimals against the token itself. Caching a wrong value here
            // would silently mis-scale every quote for that token's whole life — and decimals are
            // exactly the thing this codebase has a rule about never assuming.
            uint8 actual = IERC20Metadata(tokens_[i].token).decimals();
            if (actual != tokens_[i].decimals) {
                revert TokenDecimalsMismatch(tokens_[i].token, tokens_[i].decimals, actual);
            }
            _tokens.push(tokens_[i]);
        }
        for (uint256 i = 0; i < venues_.length; i++) {
            if (venues_[i].target == address(0)) revert ZeroAddress();
            if (venues_[i].kind == VenueKind.QUEUED_VAULT) {
                // Probe it. A vault that cannot name its asset is not a vault, and finding that
                // out now is the difference between a failed deploy and a permanently wrong venue.
                if (IQueuedVault(venues_[i].target).asset() == address(0)) revert ZeroAddress();
            } else if (venues_[i].feeTier == 0) {
                revert ZeroAmount();
            }
            _venues.push(venues_[i]);
        }

        maxFeedAge = maxFeedAge_;
        protocolFeeRecipient = protocolFeeRecipient_;
        confidentialTrigger = confidentialTrigger_;
    }

    // -------------------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------------------

    function tokenCount() external view returns (uint256) {
        return _tokens.length;
    }

    function venueCount() external view returns (uint256) {
        return _venues.length;
    }

    function ruleCount() external view returns (uint256) {
        return _rules.length;
    }

    function tokenAt(uint8 id) external view returns (TokenCfg memory) {
        if (id >= _tokens.length) revert UnknownToken(id);
        return _tokens[id];
    }

    function venueAt(uint8 id) external view returns (VenueCfg memory) {
        if (id >= _venues.length) revert UnknownVenue(id);
        return _venues[id];
    }

    function ruleAt(uint256 ruleId) external view returns (Rule memory) {
        if (ruleId >= _rules.length) revert NoRule(ruleId);
        return _rules[ruleId];
    }

    function ftsoV2() public view returns (IFtsoV2) {
        return IFtsoV2(REGISTRY.getContractAddressByHash(FTSO_V2_NAME_HASH));
    }

    // -------------------------------------------------------------------------------------
    // Arming
    // -------------------------------------------------------------------------------------

    /// @notice Arm a rule. Called by the user's personal account, inside the 0xFE arming batch.
    /// @dev `msg.sender` is the personal account, and it is bound into the rule here. That binding
    ///      is why a leaked keeper key is worthless: a keeper calling `arm` can only ever arm a
    ///      rule against its own address, whose allowance to this contract is zero.
    function arm(RuleParams calldata p) external returns (uint256 ruleId) {
        _validate(p);

        ruleId = _rules.length;
        _rules.push(
            Rule({
                account: msg.sender,
                epoch: epochOf[msg.sender],
                sellTokenId: p.sellTokenId,
                buyTokenId: p.buyTokenId,
                verb: p.verb,
                venueId: p.venueId,
                trigger: p.trigger,
                active: true,
                totalSellAmount: p.totalSellAmount,
                partSellAmount: p.partSellAmount,
                spent: 0,
                minOutAbsolute: p.minOutAbsolute,
                triggerValue: p.triggerValue,
                nextEligibleAt: block.timestamp.toUint64(),
                expiry: p.expiry,
                latchedPrice: 0,
                keeperFeeFlat: p.keeperFeeFlat,
                keeperFeeBudget: p.keeperFeeBudget,
                keeperFeePaid: 0,
                pendingShares: 0,
                slippageBips: p.slippageBips,
                protocolFeeBips: p.protocolFeeBips,
                pendingAssets: 0,
                latchedAt: 0,
                claimableAt: 0,
                claimPeriod: 0
            })
        );

        emit Armed(ruleId, msg.sender, p.verb, p.trigger);
    }

    function _validate(RuleParams calldata p) private view {
        if (p.sellTokenId >= _tokens.length) revert UnknownToken(p.sellTokenId);
        if (p.buyTokenId >= _tokens.length) revert UnknownToken(p.buyTokenId);
        if (p.venueId >= _venues.length) revert UnknownVenue(p.venueId);
        if (p.totalSellAmount == 0 || p.partSellAmount == 0) revert ZeroAmount();
        if (p.partSellAmount > p.totalSellAmount) revert PartExceedsTotal();
        if (p.slippageBips > MAX_SLIPPAGE_BIPS) {
            revert SlippageTooHigh(p.slippageBips, MAX_SLIPPAGE_BIPS);
        }
        if (p.protocolFeeBips > MAX_PROTOCOL_FEE_BIPS) {
            revert ProtocolFeeTooHigh(p.protocolFeeBips, MAX_PROTOCOL_FEE_BIPS);
        }
        if (p.expiry <= block.timestamp || p.expiry > block.timestamp + MAX_RULE_LIFETIME) {
            revert BadExpiry();
        }
        if (p.trigger == Trigger.SCHEDULE) {
            if (p.triggerValue < MIN_SCHEDULE_INTERVAL) {
                revert ScheduleTooFast(uint64(p.triggerValue), MIN_SCHEDULE_INTERVAL);
            }
        } else if (p.trigger == Trigger.PRIVATE) {
            // A PRIVATE rule must publish NOTHING here. Its threshold lives in the enclave, and the
            // entire point is that the chain cannot reveal when the rule fires — so a non-zero
            // value is not merely unused, it is a leak, and it is refused rather than ignored.
            if (p.triggerValue != 0) revert PrivateRuleMustNotPublishThreshold();
        } else if (p.triggerValue == 0) {
            // A zero threshold is not a price. PRICE_BELOW would never fire and PRICE_ABOVE would
            // always fire, and neither is what anyone meant.
            revert ZeroAmount();
        }

        VenueCfg memory v = _venues[p.venueId];
        if (p.verb == Verb.SWAP) {
            if (v.kind != VenueKind.SWAP_ROUTER_V3) revert VenueKindMismatch(p.venueId, p.verb);
            if (p.sellTokenId == p.buyTokenId) revert SameToken();
        } else {
            if (v.kind != VenueKind.QUEUED_VAULT) revert VenueKindMismatch(p.venueId, p.verb);
            // For vault verbs the "sell" side is what the vault custodies. Assert it rather than
            // trusting the caller: a mismatch here queues a redemption against the wrong asset.
            address underlying = IQueuedVault(v.target).asset();
            address sellToken = _tokens[p.sellTokenId].token;
            if (p.verb == Verb.DEPOSIT_VAULT) {
                if (underlying != sellToken) {
                    revert VaultAssetMismatch(v.target, underlying, sellToken);
                }
            } else {
                // M-2d: an EXIT_VAULT rule burns the venue's SHARE token, so the sell token must
                // be that share token — not the vault's underlying. Without this, a rule could be
                // armed to "exit" while selling FXRP, which pulls FXRP in and then reverts inside
                // the vault's `_burn`, stranding the pulled balance. The DEPOSIT_VAULT side has
                // always asserted its counterpart; this one was simply missing.
                if (sellToken != v.target) {
                    revert VaultAssetMismatch(v.target, v.target, sellToken);
                }
            }
        }

        // L2: a rule whose fee budget cannot fund its own executions stops silently partway
        // through, with months left to run and a live allowance. Refuse to arm it.
        uint256 maxExecutions = _ceilDiv(p.totalSellAmount, p.partSellAmount);
        // AUTH-6: an EXIT_VAULT rule pays the keeper twice per part — once for the `execute` that
        // queues the redemption and once for the `claim` that settles it. Sizing the budget for
        // executions alone leaves the tail unfunded, which is L2's silent-stop failure by a
        // different route.
        uint256 chargesPerPart = p.verb == Verb.EXIT_VAULT ? 2 : 1;
        uint256 required = uint256(p.keeperFeeFlat) * maxExecutions * chargesPerPart;
        if (required > p.keeperFeeBudget) {
            revert FeeBudgetCannotFundExecutions(p.keeperFeeBudget, required);
        }
    }

    // -------------------------------------------------------------------------------------
    // Execution — permissionless
    // -------------------------------------------------------------------------------------

    /// @notice Execute a rule whose conditions are met. Callable by anyone.
    /// @dev `msg.sender` appears exactly once in this function, as the keeper-fee recipient. That
    ///      is the entirety of what a keeper is trusted with. Every bound is re-derived here from
    ///      the stored rule and a fresh FTSO read; nothing the caller supplies can loosen one.
    /// @param ruleId The rule to execute.
    /// @dev Payable so the caller can cover an FTSO feed fee if governance ever sets one. Any
    ///      excess is refunded.
    function execute(uint256 ruleId) external payable nonReentrant {
        Rule storage r = _load(ruleId);

        if (block.timestamp < r.nextEligibleAt) revert NotYetEligible(r.nextEligibleAt);
        if (r.spent >= r.totalSellAmount) revert Exhausted();

        TokenCfg memory sellCfg = _tokens[r.sellTokenId];
        TokenCfg memory buyCfg = _tokens[r.buyTokenId];

        // Both legs, fresh, staleness-checked against block.timestamp.
        (Quote.Feed memory sellFeed, Quote.Feed memory buyFeed, uint256 feeSpent) =
            _readFeeds(sellCfg.feedId, buyCfg.feedId);

        uint128 price = _evaluateTrigger(r, ruleId, sellFeed, buyFeed);

        // A12: latch on the first fire and floor every subsequent part against the latched price,
        // so a partial exit does not chase the market down.
        if (r.latchedPrice == 0) {
            r.latchedPrice = price;
            r.latchedAt = block.timestamp.toUint64();
        }

        // A8: the final part takes the remainder rather than reverting on a dust tail.
        uint256 amount = r.partSellAmount;
        uint256 remaining = r.totalSellAmount - r.spent;
        if (amount > remaining) amount = remaining;

        // A9: charge the measured delta, not the requested amount. FAssets transfer fees are a
        // governance switch, and this contract is not upgradeable.
        IERC20 sellToken = IERC20(sellCfg.token);
        uint256 balBefore = sellToken.balanceOf(address(this));
        sellToken.safeTransferFrom(r.account, address(this), amount);
        uint256 received = sellToken.balanceOf(address(this)) - balBefore;
        if (received == 0) revert ZeroAmount();

        r.spent += received.toUint128();

        if (r.verb == Verb.SWAP) {
            _doSwap(r, ruleId, sellCfg, buyCfg, received, price);
        } else if (r.verb == Verb.DEPOSIT_VAULT) {
            _doDeposit(r, ruleId, sellCfg, received);
        } else {
            _doQueueRedeem(r, ruleId, received);
        }

        _advance(r);
        // AUTH-7: refund exactly this caller's unspent value, never the contract's whole balance.
        _refund(msg.value - feeSpent);
    }

    function _evaluateTrigger(
        Rule storage r,
        uint256 ruleId,
        Quote.Feed memory sellFeed,
        Quote.Feed memory buyFeed
    ) private view returns (uint128 price) {
        price = _relativePrice(r, sellFeed, buyFeed);

        if (r.trigger == Trigger.PRICE_BELOW) {
            if (price > r.triggerValue) revert TriggerNotMet(price, r.triggerValue);
        } else if (r.trigger == Trigger.PRICE_ABOVE) {
            if (price < r.triggerValue) revert TriggerNotMet(price, r.triggerValue);
        } else if (r.trigger == Trigger.PRIVATE) {
            // The threshold is not here. It is in an enclave, and the chain holds only a
            // commitment to it — which is the entire point, because a published stop price tells
            // every observer when a large sell will arrive.
            //
            // The nonce is `spent`, so it advances with each executed part and is derivable by any
            // keeper without extra state. One verdict per part; a verdict cannot be replayed onto a
            // later part when the price has moved back.
            if (address(confidentialTrigger) == address(0)) revert PrivateTriggersDisabled();
            confidentialTrigger.consumeVerdict(ruleId, uint64(r.spent));
        }
        // Trigger.SCHEDULE: eligibility was already checked against nextEligibleAt in execute().
    }

    /// @dev The price a rule is measured against, in buy-token base units per ONE WHOLE sell token.
    ///
    ///      Computed for EVERY trigger type, not just price ones, because it is also what the
    ///      execution floor latches onto. Returning a raw USD mantissa for SCHEDULE rules would put
    ///      two different units in the same field and mis-scale every scheduled swap's floor by
    ///      orders of magnitude.
    ///
    ///      Comparing the sell leg against the buy leg rather than against USD means a threshold
    ///      keeps its meaning whatever the buy token is worth — a single-leg comparison would
    ///      silently assume a $1 peg.
    function _relativePrice(Rule storage r, Quote.Feed memory sellFeed, Quote.Feed memory buyFeed)
        private
        view
        returns (uint128)
    {
        uint256 relative = Quote.convert(
            10 ** uint256(_tokens[r.sellTokenId].decimals),
            sellFeed,
            _tokens[r.sellTokenId].decimals,
            buyFeed,
            _tokens[r.buyTokenId].decimals
        );
        // No clamp. Saturating here was the M-1 defect: the floor is derived from this value, so
        // a clamped price silently becomes a floor far below oracle fair value. Overflowing
        // uint128 would mean a token/feed pairing this contract cannot price, and reverting is the
        // correct outcome — refuse rather than execute against a wrong number (rule 7).
        return relative.toUint128();
    }

    /// @notice The price rule `ruleId` is currently measured against, read from FTSO now.
    ///
    /// @dev **This exists so that a confidential rule's evaluation price cannot be chosen by the
    ///      party asking for the evaluation.** `TrimmyConfidentialTrigger.requestEvaluation` used to
    ///      take the price as a caller-supplied string, and the enclave compared the secret
    ///      threshold against whatever number arrived. That let anyone mint a `fire` verdict for
    ///      anyone else's rule by asking about a price that trivially satisfies it — and, by
    ///      probing, binary-search the secret in about twenty queries. The threshold stayed secret
    ///      in name only, and the rule fired at a price its owner never chose.
    ///
    ///      Reading the price here closes both: the number the enclave compares against is the same
    ///      number this contract would use to execute, derived from the same feeds in the same
    ///      block. A caller can pick *when* to ask, which is public information anyway, but not
    ///      *what* is asked.
    ///
    ///      Not a view: `getFeedById` is payable. Any excess is refunded to the caller, and the
    ///      rule's own liveness checks apply, so an expired or cancelled rule cannot be evaluated.
    function currentPrice(uint256 ruleId) external payable returns (uint128 price) {
        Rule storage r = _load(ruleId);
        (Quote.Feed memory sellFeed, Quote.Feed memory buyFeed, uint256 feeSpent) =
            _readFeeds(_tokens[r.sellTokenId].feedId, _tokens[r.buyTokenId].feedId);
        price = _relativePrice(r, sellFeed, buyFeed);
        _refund(msg.value - feeSpent);
    }

    /// @dev The latch, decayed. Returns `live` once the window has elapsed, `latchedPrice` at the
    ///      moment of latching, and a linear interpolation between them in between. Never returns
    ///      less than `live`.
    function _effectiveLatch(Rule storage r, uint256 live) private view returns (uint256) {
        uint256 latched = r.latchedPrice;
        if (latched <= live) return live;

        uint256 elapsed = block.timestamp - r.latchedAt;
        if (elapsed >= LATCH_DECAY_WINDOW) return live;

        uint256 excess = latched - live;
        return live + (excess * (LATCH_DECAY_WINDOW - elapsed)) / LATCH_DECAY_WINDOW;
    }

    function _doSwap(
        Rule storage r,
        uint256 ruleId,
        TokenCfg memory sellCfg,
        TokenCfg memory buyCfg,
        uint256 amountIn,
        uint256 livePrice
    ) private {
        VenueCfg memory v = _venues[r.venueId];

        // The floor comes from FTSO, never from the venue. Rule 4: an AMM quote is a number an
        // attacker can move, and a venue-spot deviation check is itself an AMM read.
        //
        // A12 + O-16. Floor against the latched price rather than the live one, so a partial exit
        // does not chase the market down — but let the latch DECAY back to live over
        // LATCH_DECAY_WINDOW, so a rule that latched at a local maximum is not bricked forever.
        //
        // The effective price is never below live: if the market rose, the stale lower latch would
        // under-protect the user, so live wins. Only the excess above live decays.
        uint256 effective = _effectiveLatch(r, livePrice);
        uint256 oracleOut = (amountIn * effective) / (10 ** uint256(sellCfg.decimals));
        uint256 floorOut = (oracleOut * (10_000 - r.slippageBips)) / 10_000;
        if (r.minOutAbsolute > floorOut) floorOut = r.minOutAbsolute;

        IERC20(sellCfg.token).forceApprove(v.target, amountIn);

        // A5 is deleted rather than fixed: no route is supplied by anyone. The path is derived
        // from the allowlisted (sellToken, feeTier, buyToken) triple, so there is nothing to
        // mismatch and nothing a caller can substitute.
        bytes memory path = abi.encodePacked(sellCfg.token, v.feeTier, buyCfg.token);

        IERC20 buyToken = IERC20(buyCfg.token);
        uint256 buyBefore = buyToken.balanceOf(address(this));

        ISwapRouter(v.target)
            .exactInput(
                ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: floorOut
            })
            );

        // A15: measure what actually arrived. The router's claimed return value is not evidence.
        uint256 actualOut = buyToken.balanceOf(address(this)) - buyBefore;

        // O-17, resolved as a DISCLOSURE defect rather than a mechanism one.
        //
        // The floor exists to bound what an ADVERSARY can extract through the venue (A2), and that
        // is a property of the gross fill — so `actualOut` is the right quantity to check. Fees are
        // a different thing: they go to the keeper and the protocol, they are bounded by
        // `keeperFeeBudget` and `MAX_PROTOCOL_FEE_BIPS`, and they are committed at arm time.
        //
        // Binding the floor to NET was tried and is wrong: a flat keeper fee is routinely a larger
        // fraction of a small part than the whole 50-bip band, so no venue on earth could satisfy
        // it and every such rule would simply never execute.
        //
        // What was genuinely broken is that the user was told "slippage 50 bips max" and not told
        // that fees come out afterwards. That is fixed in `arming/bin/decode.dart`, which now
        // states the floor and the fees as separate lines and shows the net.
        if (actualOut < floorOut) revert FloorBreached(actualOut, floorOut);

        _settle(r, ruleId, buyToken, actualOut, amountIn);
    }

    function _doDeposit(Rule storage r, uint256 ruleId, TokenCfg memory sellCfg, uint256 amountIn)
        private
    {
        VenueCfg memory v = _venues[r.venueId];
        IERC20(sellCfg.token).forceApprove(v.target, amountIn);

        IERC20 shareToken = IERC20(v.target);
        uint256 before = shareToken.balanceOf(address(this));
        IQueuedVault(v.target).deposit(amountIn, address(this));
        uint256 shares = shareToken.balanceOf(address(this)) - before;

        if (shares < r.minOutAbsolute) revert FloorBreached(shares, r.minOutAbsolute);

        _settle(r, ruleId, shareToken, shares, amountIn);
    }

    /// @dev L5 phase one. `maxWithdraw` is 0 on every FXRP vault on Coston2, so a vault exit cannot
    ///      settle in one transaction. This queues it; `claim()` completes it.
    function _doQueueRedeem(Rule storage r, uint256 ruleId, uint256 shares) private {
        // M-3: at most ONE outstanding redemption per rule. `pendingShares` used to accumulate
        // while `claimPeriod` was overwritten, so a second queue landing in a different day-bucket
        // orphaned the first bucket permanently — `claim()` can only ever name one period.
        // Refusing is safe because `claim()` is permissionless: anyone can clear the block.
        if (r.pendingShares != 0) revert RedemptionAlreadyPending(r.claimableAt);

        VenueCfg memory v = _venues[r.venueId];

        // GROUND-TRUTH §4a-bis(2): call `redeem` directly with owner == self, so `_caller ==
        // _owner` and no allowance is spent. `requestRedeem` would self-call and demand that we
        // approve the vault against ourselves.
        uint256 assets = IQueuedVault(v.target).redeem(shares, address(this), address(this));

        uint256 lag = IQueuedVault(v.target).lagDuration();

        // §4a-bis(1): the claim gate is the day-index period, not `lagDuration`. The vault files
        // the request under dayIndex(now + lag), and `claimWithdraw` requires the current day index
        // to be strictly greater — so the earliest claim is the following UTC midnight.
        uint64 period = ((block.timestamp + lag) / 1 days).toUint64();
        uint64 claimableAt = ((uint256(period) + 1) * 1 days).toUint64();

        r.pendingShares = shares.toUint128();
        r.pendingAssets = assets.toUint128();
        r.claimPeriod = period;
        r.claimableAt = claimableAt;

        emit RedeemQueued(ruleId, shares, claimableAt, period);
    }

    /// @notice Complete a queued vault redemption. Callable by anyone.
    /// @dev L5 phase two. Permissionless for the same reason `execute` is: liveness must not depend
    ///      on our keeper being alive, and the destination is fixed to `rule.account` regardless of
    ///      who calls.
    function claim(uint256 ruleId) external nonReentrant {
        if (ruleId >= _rules.length) revert NoRule(ruleId);
        Rule storage r = _rules[ruleId];

        if (r.verb != Verb.EXIT_VAULT) revert WrongVerb();
        if (r.pendingShares == 0) revert NothingPending();
        if (block.timestamp < r.claimableAt) revert NotYetClaimable(r.claimableAt);

        VenueCfg memory v = _venues[r.venueId];
        IERC20 asset = IERC20(IQueuedVault(v.target).asset());

        // §4a-bis(3): `claimWithdraw` credits msg.sender, which is why Trimmy is the receiver at
        // request time and makes this call itself.
        //
        // M-3: the vault ALSO exposes a public, unauthenticated `claim(y,m,d,receiver)` that
        // pushes a bucket to its receiver. A third party can therefore deliver our assets into
        // Trimmy before we get here, in which case `claimWithdraw` has nothing to move.
        //
        // AUTH-5: an earlier version wrapped that call in `try … catch {}`, which swallowed EVERY
        // failure — including a gas-starved sub-call — and then paid out of the shared balance
        // anyway. That turns any vault malfunction into a payout from ambient funds. Instead, ask
        // the vault whether the bucket still holds anything and only call when it does, so a
        // genuine failure propagates and an already-drained bucket is handled without a blanket
        // catch.
        if (IQueuedVault(v.target).pendingWithdrawAssets(address(this), r.claimPeriod) > 0) {
            IQueuedVault(v.target).claimWithdraw(r.claimPeriod);
        }

        // Capped by what this rule queued, so no rule can ever be paid more than it is owed and
        // total payouts can never exceed total obligations.
        uint256 owed = r.pendingAssets;
        uint256 held = asset.balanceOf(address(this));
        uint256 assets = owed < held ? owed : held;

        r.pendingShares = 0;
        r.pendingAssets = 0;
        r.claimableAt = 0;
        r.claimPeriod = 0;

        if (assets == 0) revert NothingPending();

        // AUTH-4: claim() deliberately does NOT go through _load. The shares are already burned
        // and the user is owed the assets, so a cancelled or stale-epoch rule must still be able
        // to collect — refusing here would strand the money, which is the opposite of what cancel
        // is for. But a dead rule must not keep paying fees, so they are zeroed for that case.
        bool dead = !r.active || r.epoch != epochOf[r.account];
        if (dead) {
            asset.safeTransfer(r.account, assets);
            emit Executed(ruleId, msg.sender, 0, assets, 0, 0);
        } else {
            _settle(r, ruleId, asset, assets, 0);
        }
        emit Claimed(ruleId, msg.sender, assets);
    }

    /// @dev The single place value leaves this contract. Fees are taken from the proceeds and the
    ///      entire remainder goes to `rule.account`. There is no `receiver` field to abuse — A1's
    ///      third leg is closed by there being no code path that sends anywhere else.
    function _settle(
        Rule storage r,
        uint256 ruleId,
        IERC20 proceedsToken,
        uint256 proceeds,
        uint256 sold
    ) private {
        uint256 keeperFee = r.keeperFeeFlat;
        uint256 budgetLeft = r.keeperFeeBudget - r.keeperFeePaid;
        if (keeperFee > budgetLeft) keeperFee = budgetLeft;
        if (keeperFee > proceeds) keeperFee = proceeds;

        uint256 protocolFee = ((proceeds - keeperFee) * r.protocolFeeBips) / 10_000;

        r.keeperFeePaid += keeperFee.toUint128();

        if (keeperFee > 0) proceedsToken.safeTransfer(msg.sender, keeperFee);
        if (protocolFee > 0) proceedsToken.safeTransfer(protocolFeeRecipient, protocolFee);

        uint256 toUser = proceeds - keeperFee - protocolFee;
        if (toUser > 0) proceedsToken.safeTransfer(r.account, toUser);

        emit Executed(ruleId, msg.sender, sold, proceeds, keeperFee, protocolFee);
    }

    function _advance(Rule storage r) private {
        if (r.spent >= r.totalSellAmount) {
            r.active = false;
            return;
        }
        if (r.trigger == Trigger.SCHEDULE) {
            // triggerValue is an interval in seconds on this branch. _validate bounds it below
            // by MIN_SCHEDULE_INTERVAL; toUint64 bounds it above rather than wrapping.
            r.nextEligibleAt = block.timestamp.toUint64() + uint256(r.triggerValue).toUint64();
        } else {
            // A2 mitigation three: jitter, so execution timing is not predictable for an observer
            // positioning around the floor. Derived from state an observer cannot cheaply steer
            // within the same block.
            // forge-lint: disable-next-line(unsafe-typecast)
            // casting to 'uint64' is safe because the value is `x % 30`, so it is at most 29.
            uint64 jitter = uint64(
                uint256(keccak256(abi.encode(blockhash(block.number - 1), r.spent, r.account))) % 30
            );
            r.nextEligibleAt = block.timestamp.toUint64() + MIN_SCHEDULE_INTERVAL + jitter;
        }
    }

    // -------------------------------------------------------------------------------------
    // Cancellation
    // -------------------------------------------------------------------------------------

    function setGuardian(address guardian) external {
        guardianOf[msg.sender] = guardian;
        emit GuardianSet(msg.sender, guardian);
    }

    function cancel(uint256 ruleId) external {
        if (ruleId >= _rules.length) revert NoRule(ruleId);
        Rule storage r = _rules[ruleId];
        if (msg.sender != r.account && msg.sender != guardianOf[r.account]) revert NotAuthorised();
        r.active = false;
        emit Cancelled(ruleId, msg.sender);
    }

    /// @notice Kill every rule for the caller at once.
    /// @dev C-auth: the earlier design documented this as an epoch bump but the rule struct had no
    ///      epoch field and `execute` read none, so the panic button was a counter nothing
    ///      consulted. `epoch` is now a real field, checked in `_load`.
    /// @param account The account whose rules to kill. Callers may pass their own address, and a
    ///        guardian may pass the account that appointed them.
    /// @dev AUTH-3: this previously took no argument and bumped `epochOf[msg.sender]`, so a
    ///      guardian could cancel rules one at a time but could never use the panic button at all —
    ///      it silently bumped the guardian's own (empty) epoch instead. The panic button is the
    ///      thing that makes a 131-second XRPL cancel round trip tolerable, so a guardian who
    ///      cannot press it is a guardian in name only.
    function cancelAll(address account) external {
        if (msg.sender != account && msg.sender != guardianOf[account]) revert NotAuthorised();
        uint32 next = epochOf[account] + 1;
        epochOf[account] = next;
        emit AllCancelled(account, next, msg.sender);
    }

    // -------------------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------------------

    function _load(uint256 ruleId) private view returns (Rule storage r) {
        if (ruleId >= _rules.length) revert NoRule(ruleId);
        r = _rules[ruleId];
        if (!r.active) revert RuleInactive(ruleId);
        if (block.timestamp > r.expiry) revert RuleExpired(ruleId);
        uint32 current = epochOf[r.account];
        if (r.epoch != current) revert StaleEpoch(r.epoch, current);
    }

    function _readFeeds(bytes21 sellFeedId, bytes21 buyFeedId)
        private
        returns (Quote.Feed memory sellFeed, Quote.Feed memory buyFeed, uint256 feeSpent)
    {
        IFtsoV2 ftso = ftsoV2();

        uint256 fee = ftso.calculateFeeById(sellFeedId) + ftso.calculateFeeById(buyFeedId);
        if (msg.value < fee) revert InsufficientFeeValue(msg.value, fee);

        uint256 half = fee == 0 ? 0 : ftso.calculateFeeById(sellFeedId);
        (sellFeed.value, sellFeed.decimals, sellFeed.timestamp) =
            ftso.getFeedById{value: half}(sellFeedId);
        (buyFeed.value, buyFeed.decimals, buyFeed.timestamp) =
            ftso.getFeedById{value: fee - half}(buyFeedId);

        Quote.requireFresh(sellFeed, maxFeedAge);
        Quote.requireFresh(buyFeed, maxFeedAge);
        feeSpent = fee;
    }

    /// @dev AUTH-7: this used to send `address(this).balance`, so whoever executed next collected
    ///      any native token another caller had left here. It now refunds exactly this caller's
    ///      unspent value and nothing else.
    function _refund(uint256 unspent) private {
        if (unspent > 0) {
            (bool ok,) = msg.sender.call{value: unspent}("");
            ok; // A failed refund must not strand the execution; the keeper chose to overpay.
        }
    }

    function _ceilDiv(uint256 a, uint256 b) private pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    receive() external payable {}
}
