// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IConfidentialTrigger} from "../src/Interfaces.sol";
import {Trimmy} from "../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry, MockSwapRouter} from "./mocks/Mocks.sol";

/// @notice A vault faithful to the REAL TESTearnXRP/MyERC4626 on Coston2, including the part the
///         original M-3 report missed: a **public, unauthenticated push-claim**.
///
/// @dev Verified against the explorer's verified source for
///      `0x9E63a5D282F2fBb7DcE822B98e363b2719D28319`:
///      - `redeem` burns shares and QUEUES the payout under `dayIndex(now + lagDuration)`.
///      - `claimWithdraw(period)` credits `msg.sender` and reverts for the current/future period.
///      - `claim(year, month, day, receiver)` is **public with no access control** and pushes a
///        bucket to its receiver. Anyone may call it for anyone.
contract PushClaimVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    uint256 public lagDuration = 300;

    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawAssets;

    error InvalidPeriod();

    constructor(IERC20 a) ERC20("Push Vault", "pVLT") {
        assetToken = a;
    }

    function decimals() public view override returns (uint8) {
        return MockERC20(address(assetToken)).decimals();
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, assets);
        return assets;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 a) external pure returns (uint256) {
        return a;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        if (owner != msg.sender) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        pendingWithdrawAssets[receiver][(block.timestamp + lagDuration) / 1 days] += shares;
        return shares;
    }

    function claimWithdraw(uint256 period) external returns (uint256 assets) {
        if (period >= block.timestamp / 1 days) revert InvalidPeriod();
        assets = pendingWithdrawAssets[msg.sender][period];
        pendingWithdrawAssets[msg.sender][period] = 0;
        assetToken.safeTransfer(msg.sender, assets);
    }

    /// The real vault's public push. No access control. This is what strands assets in Trimmy.
    function pushClaim(address receiver, uint256 period) external returns (uint256 assets) {
        assets = pendingWithdrawAssets[receiver][period];
        pendingWithdrawAssets[receiver][period] = 0;
        assetToken.safeTransfer(receiver, assets);
    }
}

/// @title M-3 regression
/// @notice Two halves, both from the adversarial review of the deployed code:
///
///   (a) `_doQueueRedeem` overwrote `claimPeriod` while `pendingShares` accumulated, so a second
///       queue landing in a different day-bucket orphaned the first one permanently.
///   (b) `claim()` settled the balance DELTA around its own `claimWithdraw` call. Because the real
///       vault exposes a public push-claim, a third party could deliver the assets into Trimmy
///       first, making our call a no-op — the user was then paid zero and the assets stranded in a
///       contract with no sweep.
contract M3RegressionTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED = bytes21(uint168(0x015852502f55534400000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    PushClaimVault internal vault;
    MockFtsoV2 internal ftso;

    address internal account = makeAddr("account");
    address internal keeper = makeAddr("keeper");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        vault = new PushClaimVault(IERC20(address(fxrp)));

        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        ftso.setFeed(FEED, 1_000_000, 6, uint64(vm.getBlockTimestamp()));

        // Allowlist the SHARE token as sellable, which is what an EXIT_VAULT rule needs.
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        trimmy =
            new Trimmy(tokens, venues, 3600, makeAddr("feeSink"), IConfidentialTrigger(address(0)));

        fxrp.mint(account, 1000e6);
        vm.startPrank(account);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(500e6, account);
        vault.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();
    }

    function _exitRule(uint128 total, uint128 part) internal returns (uint256 id) {
        vm.prank(account);
        id = trimmy.arm(
            Trimmy.RuleParams({
                sellTokenId: 0,
                buyTokenId: 0,
                verb: Trimmy.Verb.EXIT_VAULT,
                venueId: 0,
                trigger: Trimmy.Trigger.SCHEDULE,
                totalSellAmount: total,
                partSellAmount: part,
                minOutAbsolute: 0,
                triggerValue: 60,
                expiry: uint64(vm.getBlockTimestamp() + 30 days),
                slippageBips: 0,
                protocolFeeBips: 0,
                keeperFeeFlat: 0,
                keeperFeeBudget: 0
            })
        );
    }

    /// (a) A second queue must not silently orphan the first bucket. It is refused instead.
    function test_secondQueueIsRefusedWhileOneIsPending() public {
        uint256 id = _exitRule(100e6, 50e6);

        vm.prank(keeper);
        trimmy.execute(id);
        Trimmy.Rule memory r = trimmy.ruleAt(id);
        assertEq(r.pendingShares, 50e6, "first part queued");
        assertEq(r.pendingAssets, 50e6, "assets recorded at queue time");

        // Move into a different day-bucket, which is exactly what used to orphan bucket one.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        ftso.setFeed(FEED, 1_000_000, 6, uint64(vm.getBlockTimestamp()));

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(Trimmy.RedemptionAlreadyPending.selector, r.claimableAt)
        );
        trimmy.execute(id);
    }

    /// (b) A stranger pushing our bucket must not strand the user's assets.
    function test_pushClaimByStrangerStillPaysTheUser() public {
        uint256 id = _exitRule(100e6, 100e6);

        vm.prank(keeper);
        trimmy.execute(id);
        Trimmy.Rule memory r = trimmy.ruleAt(id);

        vm.warp(r.claimableAt);

        // A third party pushes the bucket into Trimmy before we claim. `claimWithdraw` will now
        // move nothing, so a delta-based settlement would pay the user zero.
        vm.prank(stranger);
        vault.pushClaim(address(trimmy), r.claimPeriod);
        assertEq(fxrp.balanceOf(address(trimmy)), 100e6, "assets sitting in Trimmy");

        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.claim(id);

        assertEq(fxrp.balanceOf(account) - before, 100e6, "user paid despite the push");
        assertEq(fxrp.balanceOf(address(trimmy)), 0, "nothing stranded");
    }

    /// The ordinary path must still work unchanged.
    function test_normalClaimStillWorks() public {
        uint256 id = _exitRule(100e6, 100e6);
        vm.prank(keeper);
        trimmy.execute(id);
        Trimmy.Rule memory r = trimmy.ruleAt(id);

        vm.warp(r.claimableAt);
        uint256 before = fxrp.balanceOf(account);
        vm.prank(keeper);
        trimmy.claim(id);
        assertEq(fxrp.balanceOf(account) - before, 100e6);
        assertEq(trimmy.ruleAt(id).pendingShares, 0);
        assertEq(trimmy.ruleAt(id).pendingAssets, 0);
    }

    /// After claiming, the next part may queue — the refusal is a lock, not a permanent stop.
    function test_claimUnblocksTheNextPart() public {
        uint256 id = _exitRule(100e6, 50e6);

        vm.prank(keeper);
        trimmy.execute(id);
        Trimmy.Rule memory r = trimmy.ruleAt(id);
        vm.warp(r.claimableAt);
        vm.prank(keeper);
        trimmy.claim(id);

        ftso.setFeed(FEED, 1_000_000, 6, uint64(vm.getBlockTimestamp()));
        vm.prank(keeper);
        trimmy.execute(id); // second part now allowed
        assertEq(trimmy.ruleAt(id).pendingShares, 50e6);
        assertEq(trimmy.ruleAt(id).spent, 100e6);
    }
}
