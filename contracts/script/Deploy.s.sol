// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Trimmy} from "../src/Trimmy.sol";
import {
    IFlareContractRegistry,
    IFtsoV2,
    IQueuedVault,
    IConfidentialTrigger
} from "../src/Interfaces.sol";

/// @title Trimmy deployment
/// @notice **The constructor arguments ARE the security model.** Trimmy has no owner, no admin, no
///         proxy and no setter — the token and venue allowlists written here are fixed for the
///         contract's entire life. A wrong address in this file cannot be corrected later; it can
///         only be abandoned and redeployed. Treat this file as production code, not as glue.
///
/// @dev Everything except the registry is resolved or asserted at deploy time:
///
///      - `WNat` and `FtsoV2` come from the registry, never from a literal. Flare's own published
///        Python example hardcodes a stale FtsoV2 address; that is the failure this avoids.
///      - Every token's `decimals()` is read from the token and checked against what we declare
///        (Trimmy's constructor enforces this too — belt and braces, because a wrong scale here
///        mis-prices every quote for that token forever).
///      - Every feed is read live and must return a non-zero, fresh value, so a typo in a 21-byte
///        feed id fails at deploy rather than at the first execution.
///      - Every vault's `asset()` is checked against the token we intend to pair it with.
///
///      Run:
///        forge script script/Deploy.s.sol:Deploy --rpc-url coston2 --broadcast \
///          --private-key $COSTON2_TEST_KEY
contract Deploy is Script {
    IFlareContractRegistry constant REGISTRY =
        IFlareContractRegistry(0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019);

    // Coston2. FXRP is the FAssets token; the vault and router were read from the explorer and
    // their interfaces verified against source (see docs/GROUND-TRUTH.md §4a-bis and §4d).
    address constant FXRP = 0x0b6A3645c240605887a5532109323A3E12273dc7;
    address constant SWAP_ROUTER = 0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc;
    address constant EARN_VAULT = 0x9E63a5D282F2fBb7DcE822B98e363b2719D28319; // TESTearnXRP

    bytes21 constant FEED_XRP_USD = bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 constant FEED_FLR_USD = bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    uint24 constant FEE_TIER = 3000; // 0.3%

    /// @dev O-2 is settled: 5 separated windows, 750 samples, max-of-per-window-p99 = **34 s**,
    ///      global max 35 s (docs/GROUND-TRUTH.md).
    ///
    ///      This was 120 s, chosen before that measurement on the reasoning that too-tight is a
    ///      permanent liveness failure on a non-upgradeable contract. Adversarial review (O-19)
    ///      showed the other side of that trade is worse than assumed: **a five-minute realised
    ///      XRP move already exceeds the entire 50-bip slippage band**, so every extra second of
    ///      permitted staleness is extractable value, and 120 s was 3.75x the measured worst case
    ///      with nothing measured to justify it.
    ///
    ///      64 s is 2x the measured max-of-p99 — still comfortably clear of a stall, and it halves
    ///      the window in which a stale price can be used against the floor.
    uint64 constant DEFAULT_MAX_FEED_AGE = 64;

    function run() external returns (Trimmy trimmy) {
        address wnat = REGISTRY.getContractAddressByName("WNat");
        address ftso = REGISTRY.getContractAddressByName("FtsoV2");
        require(wnat != address(0), "WNat unresolved");
        require(ftso != address(0), "FtsoV2 unresolved");

        uint64 maxFeedAge = uint64(vm.envOr("TRIMMY_MAX_FEED_AGE", uint256(DEFAULT_MAX_FEED_AGE)));
        address feeRecipient = vm.envOr("TRIMMY_FEE_RECIPIENT", msg.sender);

        // Optional. Left at address(0), PRIVATE rules are disabled entirely — which is the right
        // configuration for a deployment that does not want a censorship-capable trigger at all.
        // Set it only when the confidential-trigger contract is deployed and its extension is
        // registered, and say plainly in the submission which deployment has it enabled.
        address confidential = vm.envOr("TRIMMY_CONFIDENTIAL_TRIGGER", address(0));

        // ---- tokens -----------------------------------------------------------------------
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({
            token: FXRP,
            feedId: FEED_XRP_USD,
            decimals: IERC20Metadata(FXRP).decimals()
        });
        tokens[1] = Trimmy.TokenCfg({
            token: wnat,
            feedId: FEED_FLR_USD,
            decimals: IERC20Metadata(wnat).decimals()
        });

        // ---- venues -----------------------------------------------------------------------
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](2);
        venues[0] = Trimmy.VenueCfg({
            target: SWAP_ROUTER,
            kind: Trimmy.VenueKind.SWAP_ROUTER_V3,
            feeTier: FEE_TIER
        });
        venues[1] = Trimmy.VenueCfg({
            target: EARN_VAULT,
            kind: Trimmy.VenueKind.QUEUED_VAULT,
            feeTier: 0
        });

        _preflight(tokens, venues, ftso, maxFeedAge);

        vm.startBroadcast();
        trimmy = new Trimmy(
            tokens, venues, maxFeedAge, feeRecipient, IConfidentialTrigger(confidential)
        );
        vm.stopBroadcast();

        console.log("Trimmy deployed:", address(trimmy));
        console.log("  maxFeedAge   :", maxFeedAge);
        console.log("  feeRecipient :", feeRecipient);
        console.log("  confidential :", confidential == address(0) ? "disabled" : "enabled");
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log("  token", i, tokens[i].token);
        }
        for (uint256 i = 0; i < venues.length; i++) {
            console.log("  venue", i, venues[i].target);
        }
    }

    /// @dev Fail here, loudly, rather than on someone's first execution. Every assertion below
    ///      corresponds to a way an immutable allowlist can be permanently wrong.
    ///
    ///      Not `view`: `getFeedById` is declared `payable` and non-view even though it reads free
    ///      (`sdk/AGENTS.md` rule 4 — "payable does not mean it costs money"). This runs outside
    ///      `startBroadcast`, so it simulates locally and sends nothing.
    function _preflight(
        Trimmy.TokenCfg[] memory tokens,
        Trimmy.VenueCfg[] memory venues,
        address ftso,
        uint64 maxFeedAge
    ) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i].token != address(0), "token zero");
            require(tokens[i].token.code.length > 0, "token has no code");

            uint8 onChain = IERC20Metadata(tokens[i].token).decimals();
            require(onChain == tokens[i].decimals, "declared decimals disagree with token");

            // A feed id typo yields a zero value; catching it here is the difference between a
            // failed deploy and a contract that can never quote that token.
            (uint256 value, int8 dec, uint64 ts) =
                IFtsoV2(ftso).getFeedById(tokens[i].feedId);
            require(value != 0, "feed returned zero");
            require(block.timestamp <= ts || block.timestamp - ts <= maxFeedAge, "feed already stale");
            // Log the scale as a SIGNED value. FTSO decimals are int8 and may be negative; casting
            // through uint256 would render -2 as 1.157e77 and quietly hide a misconfigured feed.
            console.log(
                string.concat(
                    "  feed ok  value=", vm.toString(value), "  decimals=", vm.toString(int256(dec))
                )
            );
        }

        for (uint256 i = 0; i < venues.length; i++) {
            require(venues[i].target != address(0), "venue zero");
            require(venues[i].target.code.length > 0, "venue has no code");

            if (venues[i].kind == Trimmy.VenueKind.QUEUED_VAULT) {
                // The vault must custody a token we actually allowlisted, or a deposit rule sends
                // funds somewhere no rule can ever redeem them from.
                address underlying = IQueuedVault(venues[i].target).asset();
                bool found;
                for (uint256 j = 0; j < tokens.length; j++) {
                    if (tokens[j].token == underlying) found = true;
                }
                require(found, "vault asset is not an allowlisted token");
            } else {
                require(venues[i].feeTier != 0, "swap venue needs a fee tier");
            }
        }
    }
}
