// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry} from "../mocks/Mocks.sol";

/// @notice Withdrawal queue transcribed from the VERIFIED source of
///         `TESTearnXRP 0x9E63a5D282F2fBb7DcE822B98e363b2719D28319`, fetched 2026-08-07 from
///         coston2-explorer `getsourcecode`. Only the three functions Trimmy touches are ported,
///         line-for-line:
///
///   _withdraw       burn, then `pendingWithdrawAssets[_receiver][period] += _assets` where
///                   `period = _getPeriodFromDate(timestampToDate(now + lagDuration))`, i.e. the
///                   UTC day index of now+lag. NO check for an existing unclaimed bucket.
///   claimWithdraw   `require(_period < dayIndex(now))`, then _completeWithdraw + _deleteReceiver.
///   _completeWithdraw `require(_assets > 0, NoPendingWithdrawAssets())` — reverts on an empty
///                   bucket, unlike the repo's lenient MockQueuedVault.
contract SourceFaithfulVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    uint256 public constant PERIOD_DURATION = 1 days;
    uint256 public lagDuration = 300; // reads 300 on chain today

    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawAssets;
    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawShares;

    error InvalidPeriod();
    error NoPendingWithdrawAssets();

    constructor(IERC20 asset_) ERC20("SourceFaithful", "sfVLT") {
        assetToken = asset_;
    }

    function decimals() public view override returns (uint8) {
        return MockERC20(address(assetToken)).decimals();
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        shares = assets; // 1:1 keeps the arithmetic in the assertions obvious
        _mint(receiver, shares);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets)
    {
        if (owner != msg.sender) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        assets = shares;
        uint256 period = (block.timestamp + lagDuration) / PERIOD_DURATION;
        pendingWithdrawAssets[receiver][period] += assets;
        pendingWithdrawShares[receiver][period] += shares;
    }

    function claimWithdraw(uint256 period) external returns (uint256 assets) {
        if (period >= block.timestamp / PERIOD_DURATION) revert InvalidPeriod();
        assets = pendingWithdrawAssets[msg.sender][period];
        if (assets == 0) revert NoPendingWithdrawAssets();
        delete pendingWithdrawAssets[msg.sender][period];
        delete pendingWithdrawShares[msg.sender][period];
        assetToken.safeTransfer(msg.sender, assets);
    }
}

/// Independent verification of M-3 (`claimPeriod` is a scalar and is overwritten by a second
/// `_doQueueRedeem`). Three questions, answered separately:
///   Q1 does the loss need a narrow pre-midnight straddle, as the finding claims?
///   Q2 is the loss bounded at one bucket, or does it scale with the number of parts?
///   Q3 is EXIT_VAULT reachable on the LIVE allowlist (FXRP + WC2FLR, share token absent)?
contract VerifyM3IndependentTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    MockERC20 internal fxrp;
    MockERC20 internal wflr;
    MockFtsoV2 internal ftso;
    SourceFaithfulVault internal vault;

    address internal victim = makeAddr("victim");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        vm.warp(10 days + 12 hours); // mid-day: nowhere near a period boundary
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wflr = new MockERC20("WC2FLR", "WC2FLR", 18);
        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        vault = new SourceFaithfulVault(IERC20(address(fxrp)));
        _feeds();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
        ftso.setFeed(FEED_FLR, 20_000, 6, uint64(vm.getBlockTimestamp()));
    }

    /// The only configuration in which EXIT_VAULT can work at all: the share token is the sell
    /// token, so `execute`'s transferFrom gives Trimmy the shares that `redeem` then burns.
    function _deployExitCapable() internal returns (Trimmy) {
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        return new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));
    }

    /// The EXACT live allowlist read from chain on 2026-08-07.
    function _deployLive() internal returns (Trimmy) {
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(wflr), feedId: FEED_FLR, decimals: 18});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](2);
        venues[0] = Trimmy.VenueCfg({
            target: address(this), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });
        venues[1] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        return new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));
    }

    function _armExit(Trimmy t, uint8 sellTokenId, uint8 venueId, uint128 total, uint128 part)
        internal
        returns (uint256)
    {
        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: sellTokenId,
            buyTokenId: sellTokenId,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: venueId,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: total,
            partSellAmount: part,
            minOutAbsolute: 0,
            triggerValue: 1 days,
            expiry: uint64(block.timestamp + 300 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(victim);
        return t.arm(p);
    }

    function _fundShares(Trimmy t, uint256 assets) internal {
        fxrp.mint(victim, assets);
        vm.startPrank(victim);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(assets, victim);
        vault.approve(address(t), type(uint256).max);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------------------
    // Q1 + Q2: a plain DAILY exit drip. No griefer, no midnight straddle, no adversary.
    // -----------------------------------------------------------------------------------

    /// A 4-part daily EXIT_VAULT drip. Every part after the first lands in a strictly later day
    /// index than the unclaimed one, because `_advance` sets nextEligibleAt = now + 1 days for a
    /// SCHEDULE rule. Each such part overwrites `r.claimPeriod` (Trimmy.sol:533) and the previous
    /// bucket becomes unreachable: nothing in Trimmy takes a period argument, the only
    /// `claimWithdraw` call site is Trimmy.sol:557 with `r.claimPeriod`, and `claim()` zeroes
    /// `pendingShares` wholesale (Trimmy.sol:560).
    ///
    /// Loss is therefore (N-1)/N of the position, not one bucket, and needs no 23:53 window.
    function test_dailyDrip_strandsEveryBucketButTheLast() public {
        Trimmy t = _deployExitCapable();
        _fundShares(t, 400e6);
        uint256 id = _armExit(t, 0, 0, 400e6, 100e6);

        uint64[] memory periods = new uint64[](4);
        for (uint256 i = 0; i < 4; i++) {
            _feeds();
            vm.prank(keeper);
            t.execute(id);
            periods[i] = t.ruleAt(id).claimPeriod;
            if (i > 0) {
                assertGt(periods[i], periods[i - 1], "each part files under a LATER day index");
            }
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }

        // Rule is exhausted; the honest keeper now claims. It can only ever claim the last pointer.
        vm.warp(uint256(t.ruleAt(id).claimableAt) + 1);
        _feeds();
        uint256 before = fxrp.balanceOf(victim);
        vm.prank(keeper);
        t.claim(id);
        uint256 paid = fxrp.balanceOf(victim) - before;

        // Everything else is orphaned in the vault, still credited to Trimmy, forever unreachable.
        uint256 orphaned;
        for (uint256 i = 0; i < 3; i++) {
            orphaned += vault.pendingWithdrawAssets(address(t), periods[i]);
        }
        emit log_named_uint("shares burned", 400e6);
        emit log_named_uint("assets paid to victim", paid);
        emit log_named_uint("assets orphaned in the vault", orphaned);

        vm.prank(keeper);
        vm.expectRevert(Trimmy.NothingPending.selector);
        t.claim(id); // pendingShares was zeroed wholesale: no second chance

        assertEq(orphaned, 0, "no bucket may be left behind");
        assertEq(paid, 400e6, "victim burned 400e6 of shares and must receive 400e6 of assets");
    }

    /// Control: two parts inside ONE day index accumulate correctly and are fully paid. This is
    /// what proves the defect is the period CROSSING and not the second queue itself — so any
    /// fix must key the claim by period, not merely forbid a second redeem.
    function test_control_sameDayPartsAreFullyPaid() public {
        Trimmy t = _deployExitCapable();
        _fundShares(t, 200e6);

        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 200e6,
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 60,
            expiry: uint64(block.timestamp + 300 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(victim);
        uint256 id = t.arm(p);

        vm.prank(keeper);
        t.execute(id);
        uint64 P = t.ruleAt(id).claimPeriod;
        vm.warp(vm.getBlockTimestamp() + 120);
        _feeds();
        vm.prank(keeper);
        t.execute(id);
        assertEq(t.ruleAt(id).claimPeriod, P, "same bucket");

        vm.warp(uint256(P + 1) * 1 days + 1);
        _feeds();
        uint256 before = fxrp.balanceOf(victim);
        vm.prank(keeper);
        t.claim(id);
        assertEq(fxrp.balanceOf(victim) - before, 200e6, "no loss inside one period");
    }

    /// The repo's OWN honest keeper strands a bucket, with no adversary and no race.
    /// `keeper.dart:242` claims first — but on a failed claim simulation it only logs and FALLS
    /// THROUGH to `execute` (there is no `continue` on that branch, unlike the success branch at
    /// :256). So in the window where the previous bucket is queued-but-not-yet-claimable and the
    /// schedule is due, the keeper itself performs execute-before-claim.
    ///
    /// This models that algorithm exactly: try claim(), and if it reverts, execute().
    function test_honestKeeperAlgorithm_strandsBucketInThePreMidnightWindow() public {
        Trimmy t = _deployExitCapable();
        _fundShares(t, 100e6);

        // 23:53 UTC. A 300 s schedule: part two is due at 23:58, i.e. inside `lagDuration` of
        // midnight, so it files under the NEXT day index while bucket one is still unclaimable.
        vm.warp(11 days - 7 minutes);
        _feeds();
        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 100e6,
            partSellAmount: 50e6,
            minOutAbsolute: 0,
            triggerValue: 300,
            expiry: uint64(block.timestamp + 300 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(victim);
        uint256 id = t.arm(p);

        uint64 P;
        // 20 keeper passes, one per minute, running keeper.dart's exact ordering.
        for (uint256 pass = 0; pass < 20; pass++) {
            _feeds();
            Trimmy.Rule memory r = t.ruleAt(id);
            if (r.verb == Trimmy.Verb.EXIT_VAULT && r.pendingShares > 0) {
                vm.prank(keeper);
                try t.claim(id) {
                    continue; // keeper.dart:256 — claim landed, pass ends here
                } catch {
                    // keeper.dart:255 — logs `skip: claim: <why>` and falls through
                }
            }
            if (r.active && r.spent < r.totalSellAmount) {
                vm.prank(keeper);
                try t.execute(id) {
                    if (P == 0) P = t.ruleAt(id).claimPeriod;
                } catch {}
            }
            vm.warp(vm.getBlockTimestamp() + 60);
        }

        emit log_named_uint("first bucket period", P);
        emit log_named_uint("orphaned in first bucket", vault.pendingWithdrawAssets(address(t), P));
        assertEq(
            vault.pendingWithdrawAssets(address(t), P),
            0,
            "the honest keeper's own ordering orphaned the first bucket"
        );
    }

    // -----------------------------------------------------------------------------------
    // Q3: reachability on the deployed instance
    // -----------------------------------------------------------------------------------

    /// On the live allowlist the sell token can only be FXRP or WC2FLR; the vault SHARE token
    /// 0x9E63... is not allowlisted (`tokenCount()==2`, verified on chain). `_validate` only
    /// checks `asset() == sellToken` for DEPOSIT_VAULT (Trimmy.sol:347), so the rule ARMS — but
    /// `_doQueueRedeem` burns shares Trimmy does not hold, and Trimmy's share balance is 0 on
    /// chain. Every EXIT_VAULT execution on the live instance therefore reverts, which is what
    /// keeps M-3 off the deployed contract.
    function test_liveAllowlist_exitVaultArmsButAlwaysReverts() public {
        Trimmy t = _deployLive();
        fxrp.mint(victim, 1000e6);
        vm.prank(victim);
        fxrp.approve(address(t), type(uint256).max);

        uint256 id = _armExit(t, 0, 1, 100e6, 50e6);
        assertEq(uint8(t.ruleAt(id).verb), uint8(Trimmy.Verb.EXIT_VAULT), "arm() accepted it");
        assertEq(vault.balanceOf(address(t)), 0, "Trimmy holds no shares, as on chain");

        vm.prank(keeper);
        vm.expectRevert(); // ERC20InsufficientBalance inside _burn(Trimmy, shares)
        t.execute(id);
    }
}
