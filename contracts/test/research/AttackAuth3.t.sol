// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {IConfidentialTrigger} from "../../src/Interfaces.sol";
import {Trimmy} from "../../src/Trimmy.sol";
import {
    MockERC20,
    MockFtsoV2,
    MockRegistry,
    MockQueuedVault,
    MockSwapRouter
} from "../mocks/Mocks.sol";

interface IHookReceiver {
    function tokensReceived(address from, uint256 value) external;
}

/// @notice ERC-777-style token: calls back into the RECIPIENT on every inbound transfer.
/// @dev Neither FXRP nor WC2FLR does this today. The point of this mock is to answer the question
///      "is `nonReentrant` sufficient?" on its own terms rather than by appealing to the current
///      allowlist — the allowlist is immutable, but the argument should not depend on that alone.
contract HookERC20 is ERC20 {
    uint8 private immutable _decimals;
    address public hookOn;

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setHookOn(address a) external {
        hookOn = a;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (to != address(0) && to == hookOn && from != address(0)) {
            IHookReceiver(to).tokensReceived(from, value);
        }
    }
}

/// @notice A hostile CONTRACT acting as `rule.account`. Question 2 of the brief.
contract HostileAccount is IHookReceiver {
    Trimmy public immutable trimmy;
    bool public armed;
    bool public hookFired;

    // Recorded outcomes, one per re-entry attempt.
    bytes4 public reExecuteSameErr;
    bytes4 public reExecuteOtherErr;
    bytes4 public reClaimErr;
    bool public reArmOk;
    bool public reCancelAllOk;
    uint256 public reArmedId;

    uint256 public targetSame;
    uint256 public targetOther;
    uint256 public targetClaim;
    bool public tryArm;
    bool public tryCancelAll;
    Trimmy.RuleParams internal _armPayload;

    constructor(Trimmy t) {
        trimmy = t;
    }

    function approveAll(address token) external {
        IERC20(token).approve(address(trimmy), type(uint256).max);
    }

    function arm(Trimmy.RuleParams calldata p) external returns (uint256) {
        return trimmy.arm(p);
    }

    function configure(
        uint256 same,
        uint256 other,
        uint256 claimId,
        bool arm_,
        bool cancelAll_,
        Trimmy.RuleParams calldata payload
    ) external {
        targetSame = same;
        targetOther = other;
        targetClaim = claimId;
        tryArm = arm_;
        tryCancelAll = cancelAll_;
        _armPayload = payload;
    }

    function _sel(bytes memory reason) private pure returns (bytes4 s) {
        if (reason.length < 4) return bytes4(0);
        assembly {
            s := mload(add(reason, 0x20))
        }
    }

    function tokensReceived(address, uint256) external override {
        hookFired = true;

        try trimmy.execute(targetSame) {
            reExecuteSameErr = bytes4(0xdeadbeef); // sentinel: it SUCCEEDED
        } catch (bytes memory r) {
            reExecuteSameErr = _sel(r);
        }

        try trimmy.execute(targetOther) {
            reExecuteOtherErr = bytes4(0xdeadbeef);
        } catch (bytes memory r) {
            reExecuteOtherErr = _sel(r);
        }

        try trimmy.claim(targetClaim) {
            reClaimErr = bytes4(0xdeadbeef);
        } catch (bytes memory r) {
            reClaimErr = _sel(r);
        }

        if (tryArm) {
            try trimmy.arm(_armPayload) returns (uint256 id) {
                reArmOk = true;
                reArmedId = id;
            } catch {
                reArmOk = false;
            }
        }

        if (tryCancelAll) {
            try trimmy.cancelAll(address(this)) {
                reCancelAllOk = true;
            } catch {
                reCancelAllOk = false;
            }
        }
    }

    receive() external payable {}
}

/// @notice A hostile KEEPER. `_refund()` hands it control with the guard still engaged.
contract HostileKeeper {
    Trimmy public immutable trimmy;
    uint256 public target;
    bytes4 public reErr;
    bool public entered;

    constructor(Trimmy t) {
        trimmy = t;
    }

    function go(uint256 id, uint256 reenterId) external payable {
        target = reenterId;
        trimmy.execute{value: msg.value}(id);
    }

    receive() external payable {
        if (entered) return;
        entered = true;
        try trimmy.execute(target) {
            reErr = bytes4(0xdeadbeef);
        } catch (bytes memory r) {
            bytes4 s;
            if (r.length >= 4) {
                assembly {
                    s := mload(add(r, 0x20))
                }
            }
            reErr = s;
        }
    }
}

// =========================================================================================
// Suite 1 — the allowlists really are write-once.
// =========================================================================================
contract AuthImmutabilityTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));
    /// @dev keccak("ReentrancyGuardReentrantCall()")[0:4]
    bytes4 internal constant REENTRANT = 0x3ee5aeb5;

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockERC20 internal wflr;
    MockSwapRouter internal router;
    MockQueuedVault internal vault;
    MockFtsoV2 internal ftso;

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wflr = new MockERC20("WC2FLR", "WC2FLR", 18);
        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        router = new MockSwapRouter();
        vault = new MockQueuedVault(IERC20(address(fxrp)));

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

        trimmy =
            new Trimmy(tokens, venues, 60, makeAddr("feeSink"), IConfidentialTrigger(address(0)));
    }

    function _snapshot() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                trimmy.tokenCount(),
                trimmy.venueCount(),
                trimmy.tokenAt(0),
                trimmy.tokenAt(1),
                trimmy.venueAt(0),
                trimmy.venueAt(1)
            )
        );
    }

    /// AUTH-1. Arbitrary calldata from an arbitrary caller cannot move the allowlist.
    /// 10,000 fuzz runs of a raw `call` against the deployed dispatcher.
    function testFuzz_AUTH1_arbitraryCalldataNeverMutatesTheAllowlist(
        address caller,
        bytes4 sel,
        bytes calldata payload,
        uint96 value
    ) public {
        vm.assume(caller != address(0) && caller != address(vm));
        bytes32 before = _snapshot();
        vm.deal(caller, value);
        vm.prank(caller);
        // forge-lint: disable-next-line(unchecked-call)
        (bool ok,) = address(trimmy).call{value: value}(abi.encodePacked(sel, payload));
        ok; // success or revert is irrelevant; the invariant is the allowlist
        assertEq(_snapshot(), before, "AUTH-1: allowlist moved");
    }

    /// AUTH-1b. Same, but for the storage slots directly: `_tokens` is slot 2, `_venues` slot 3
    /// (slot 0/1 are consumed by nothing — ReentrancyGuardTransient uses transient storage).
    /// Reading the raw length words proves no path grew or shrank either array.
    function test_AUTH1b_allowlistArrayLengthsAreConstantAcrossEveryEntryPoint() public {
        uint256 tLen = uint256(vm.load(address(trimmy), bytes32(uint256(0))));
        uint256 vLen = uint256(vm.load(address(trimmy), bytes32(uint256(1))));
        assertEq(tLen, 2, "token array at slot 0");
        assertEq(vLen, 2, "venue array at slot 1");

        address a = makeAddr("anyone");
        vm.startPrank(a);
        trimmy.setGuardian(a);
        trimmy.cancelAll(a);
        vm.stopPrank();

        assertEq(uint256(vm.load(address(trimmy), bytes32(uint256(0)))), tLen);
        assertEq(uint256(vm.load(address(trimmy), bytes32(uint256(1)))), vLen);
    }
}

// =========================================================================================
// Suite 2 — reentrancy. A hostile contract arms a rule and gets a hook on `_settle`.
// =========================================================================================
contract AuthReentrancyTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));
    bytes21 internal constant FEED_FLR =
        bytes21(uint168(0x01464c522f55534400000000000000000000000000));
    bytes4 internal constant REENTRANT = 0x3ee5aeb5;

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    HookERC20 internal wflr;
    MockSwapRouter internal router;
    MockQueuedVault internal vault;
    MockFtsoV2 internal ftso;
    HostileAccount internal hostile;

    address internal feeSink = makeAddr("feeSink");
    address internal keeper = makeAddr("keeper");
    address internal victim = makeAddr("victim");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        wflr = new HookERC20("WC2FLR", "WC2FLR", 18);
        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));

        router = new MockSwapRouter();
        router.setRateWad(150e18); // 1 FXRP -> 150 WC2FLR, exactly oracle fair value
        vault = new MockQueuedVault(IERC20(address(fxrp)));

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

        trimmy = new Trimmy(tokens, venues, 60, feeSink, IConfidentialTrigger(address(0)));

        hostile = new HostileAccount(trimmy);
        wflr.setHookOn(address(hostile));

        fxrp.mint(address(hostile), 1_000_000e6);
        fxrp.mint(victim, 1_000_000e6);
        hostile.approveAll(address(fxrp));
        vm.prank(victim);
        fxrp.approve(address(trimmy), type(uint256).max);

        _feeds();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp())); // $3.00
        ftso.setFeed(FEED_FLR, 2_000_000, 8, uint64(vm.getBlockTimestamp())); // $0.02
    }

    function _swapParams() internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 1,
            verb: Trimmy.Verb.SWAP,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: 400e6,
            partSellAmount: 100e6,
            minOutAbsolute: 0,
            triggerValue: 60,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 50,
            protocolFeeBips: 10,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    /// AUTH-2. The hostile account gets control inside `_settle` and tries every reentrant path.
    function test_AUTH2_hostileAccountCannotReenterExecuteOrClaim() public {
        uint256 hostileRule = hostile.arm(_swapParams());
        vm.prank(victim);
        uint256 victimRule = trimmy.arm(_swapParams());

        hostile.configure(hostileRule, victimRule, victimRule, false, false, _swapParams());

        vm.prank(keeper);
        trimmy.execute(hostileRule);

        assertTrue(hostile.hookFired(), "AUTH-2: the hook never ran - test is vacuous");
        assertEq(hostile.reExecuteSameErr(), REENTRANT, "re-entered execute() on its own rule");
        assertEq(
            hostile.reExecuteOtherErr(), REENTRANT, "re-entered execute() on a stranger's rule"
        );
        assertEq(hostile.reClaimErr(), REENTRANT, "re-entered claim()");

        // And the outer execution completed coherently.
        Trimmy.Rule memory r = trimmy.ruleAt(hostileRule);
        assertEq(r.spent, 100e6, "one part spent, exactly once");
        assertTrue(r.active, "still live");
    }

    /// AUTH-2b. `arm()` and `cancelAll()` are NOT nonReentrant. Reaching them from inside `_settle`
    /// pushes onto `_rules` while the caller frame holds a `Rule storage` pointer into that array.
    /// This proves the pointer survives (storage arrays do not relocate) and that the damage is
    /// confined to the attacker's own epoch.
    function test_AUTH2b_reentrantArmAndCancelAllCannotCorruptTheLiveRule() public {
        uint256 hostileRule = hostile.arm(_swapParams());
        vm.prank(victim);
        uint256 victimRule = trimmy.arm(_swapParams());

        hostile.configure(hostileRule, victimRule, victimRule, true, true, _swapParams());

        uint256 countBefore = trimmy.ruleCount();
        vm.prank(keeper);
        trimmy.execute(hostileRule);

        assertTrue(hostile.reArmOk(), "arm() is reachable from inside _settle");
        assertTrue(hostile.reCancelAllOk(), "cancelAll() is reachable from inside _settle");
        assertEq(trimmy.ruleCount(), countBefore + 1, "a rule really was pushed mid-settle");

        // The live rule's own bookkeeping is intact: spent advanced once, not twice, and
        // `_advance` wrote nextEligibleAt to the rule the caller frame was holding.
        Trimmy.Rule memory r = trimmy.ruleAt(hostileRule);
        assertEq(r.spent, 100e6, "AUTH-2b: spent corrupted");
        assertEq(r.account, address(hostile), "AUTH-2b: account slot corrupted");
        assertGt(r.nextEligibleAt, block.timestamp, "AUTH-2b: _advance wrote the wrong slot");

        // The reentrant cancelAll bumped the attacker's OWN epoch, killing both of its rules.
        assertEq(trimmy.epochOf(address(hostile)), 1);
        assertEq(trimmy.epochOf(victim), 0, "the stranger's epoch is untouched");
        vm.warp(block.timestamp + 3600);
        _feeds();
        vm.expectRevert(abi.encodeWithSelector(Trimmy.StaleEpoch.selector, uint32(0), uint32(1)));
        trimmy.execute(hostileRule);

        // The stranger's rule is unharmed.
        vm.prank(keeper);
        trimmy.execute(victimRule);
        assertEq(trimmy.ruleAt(victimRule).spent, 100e6);
    }

    /// AUTH-2c. `_refund()` hands the KEEPER control (raw call, all gas) with the guard engaged.
    function test_AUTH2c_keeperCannotReenterFromTheRefundCallback() public {
        vm.prank(victim);
        uint256 a = trimmy.arm(_swapParams());
        vm.prank(victim);
        uint256 b = trimmy.arm(_swapParams());

        HostileKeeper hk = new HostileKeeper(trimmy);
        vm.deal(address(hk), 1 ether);
        hk.go{value: 1 ether}(a, b);

        assertTrue(hk.entered(), "AUTH-2c: _refund never called back - test is vacuous");
        assertEq(hk.reErr(), REENTRANT, "AUTH-2c: keeper re-entered execute from _refund");
    }
}

// =========================================================================================
// Suite 3 — guardians, epochs, and the panic button. Vault world, so `claim()` is reachable.
// =========================================================================================
contract AuthGuardianEpochTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    MockQueuedVault internal vault;
    MockFtsoV2 internal ftso;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal guardian = makeAddr("guardian");
    address internal attacker = makeAddr("attacker");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        vault = new MockQueuedVault(IERC20(address(fxrp)));

        // The share token is the sell token: the ONLY shape in which EXIT_VAULT is coherent
        // (M-6 — the live allowlist cannot express it at all).
        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        trimmy = new Trimmy(tokens, venues, 60, feeSink, IConfidentialTrigger(address(0)));

        _fund(alice);
        _fund(bob);
        _feeds();
    }

    function _fund(address who) internal {
        fxrp.mint(who, 1_000_000e6);
        vm.startPrank(who);
        fxrp.approve(address(vault), type(uint256).max);
        vault.deposit(10_000e6, who);
        vault.approve(address(trimmy), type(uint256).max);
        vm.stopPrank();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
    }

    function _p(uint128 total, uint128 part, uint128 fee, uint128 budget, uint16 protoBips)
        internal
        view
        returns (Trimmy.RuleParams memory p)
    {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: total,
            partSellAmount: part,
            minOutAbsolute: 0,
            triggerValue: 60,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: protoBips,
            keeperFeeFlat: fee,
            keeperFeeBudget: budget
        });
    }

    // -------- Question 3: guardians --------

    /// AUTH-3. `setGuardian` writes only `guardianOf[msg.sender]`. Nobody can install a guardian
    /// on somebody else's account. REFUTED as an attack.
    function testFuzz_AUTH3_nobodyCanSetAnotherAccountsGuardian(address who, address g) public {
        vm.assume(who != address(0) && who != alice && who != address(vm));
        vm.prank(who);
        trimmy.setGuardian(g);
        assertEq(trimmy.guardianOf(who), g, "writes its own slot");
        assertEq(trimmy.guardianOf(alice), address(0), "and only its own slot");
    }

    /// AUTH-3b. `guardianOf` is read at exactly one site (`cancel`). A guardian therefore gets
    /// cancellation and nothing else: it cannot arm, cannot redirect proceeds, and cannot stop a
    /// claim that is already queued.
    function test_AUTH3b_guardianGetsCancellationAndNothingElse() public {
        vm.prank(alice);
        trimmy.setGuardian(guardian);
        vm.prank(alice);
        uint256 id = trimmy.arm(_p(200e6, 100e6, 1e6, 2e6, 50));

        // 1. It can cancel. That is the whole grant.
        vm.prank(guardian);
        trimmy.cancel(id);
        assertFalse(trimmy.ruleAt(id).active);

        // 2. It cannot un-cancel. There is no such function; `cancel` is one-way and there is no
        //    path back to `active = true` for an existing rule.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.RuleInactive.selector, id));
        trimmy.execute(id);

        // 3. Arming "for" Alice binds the rule to the guardian, not to Alice.
        vm.prank(guardian);
        uint256 gid = trimmy.arm(_p(100e6, 100e6, 0, 0, 0));
        assertEq(trimmy.ruleAt(gid).account, guardian, "arm() always binds msg.sender");
        // …and the guardian has no vault shares, so it can never be executed.
        vm.expectRevert();
        trimmy.execute(gid);

        // 4. It cannot cancel a rule belonging to an account that never named it.
        vm.prank(bob);
        uint256 bid = trimmy.arm(_p(100e6, 100e6, 0, 0, 0));
        vm.prank(guardian);
        vm.expectRevert(Trimmy.NotAuthorised.selector);
        trimmy.cancel(bid);
    }

    /// AUTH-3c REGRESSION. `cancelAll` took no argument and bumped `epochOf[msg.sender]`, so a
    /// guardian pressing the panic button bumped its OWN (empty) epoch and the rule it meant to
    /// kill ran anyway. It now takes the account, and a guardian may name the account that
    /// appointed it.
    function test_AUTH3c_guardianPanicButtonKillsTheProtectedAccountsRules() public {
        vm.prank(alice);
        trimmy.setGuardian(guardian);
        vm.prank(alice);
        uint256 id = trimmy.arm(_p(200e6, 100e6, 0, 0, 0));

        vm.prank(guardian);
        trimmy.cancelAll(alice);

        assertEq(trimmy.epochOf(alice), 1, "the protected account's epoch moved");
        assertEq(trimmy.epochOf(guardian), 0, "and the guardian's own did not");

        vm.expectRevert(abi.encodeWithSelector(Trimmy.StaleEpoch.selector, uint32(0), uint32(1)));
        trimmy.execute(id);
    }

    /// And a stranger still cannot press it for somebody else.
    function test_AUTH3d_strangerCannotCancelAllForAnotherAccount() public {
        vm.prank(alice);
        uint256 id = trimmy.arm(_p(200e6, 100e6, 0, 0, 0));

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(Trimmy.NotAuthorised.selector);
        trimmy.cancelAll(alice);

        trimmy.execute(id); // untouched
        assertEq(trimmy.ruleAt(id).spent, 100e6);
    }

    // -------- Question 4: epochs --------

    /// AUTH-4. Nobody but the account or its guardian can bump an account's epoch.
    function testFuzz_AUTH4_nobodyCanBumpAnotherAccountsEpoch(address who) public {
        vm.assume(who != alice && who != address(0) && who != address(vm));
        vm.prank(who);
        vm.expectRevert(Trimmy.NotAuthorised.selector);
        trimmy.cancelAll(alice);
        assertEq(trimmy.epochOf(alice), 0, "alice's epoch is untouched");

        // ...and they may still cancel their own, which affects nobody else.
        vm.prank(who);
        trimmy.cancelAll(who);
        assertEq(trimmy.epochOf(who), 1);
        assertEq(trimmy.epochOf(alice), 0);
    }

    /// AUTH-4b. A rule cannot survive `cancelAll` on the `execute` path, and a stale-epoch rule
    /// cannot be revived: `epochOf` is monotonically increasing and `arm` stamps the value at
    /// arm time.
    function test_AUTH4b_cancelAllIsIrreversibleOnTheExecutePath() public {
        vm.prank(alice);
        uint256 id = trimmy.arm(_p(200e6, 100e6, 0, 0, 0));
        vm.prank(alice);
        trimmy.cancelAll(alice);

        vm.expectRevert(abi.encodeWithSelector(Trimmy.StaleEpoch.selector, uint32(0), uint32(1)));
        trimmy.execute(id);

        // Arming again lands on the new epoch — the old rule stays dead.
        vm.prank(alice);
        uint256 id2 = trimmy.arm(_p(200e6, 100e6, 0, 0, 0));
        assertEq(trimmy.ruleAt(id2).epoch, 1);
        vm.expectRevert(abi.encodeWithSelector(Trimmy.StaleEpoch.selector, uint32(0), uint32(1)));
        trimmy.execute(id);
    }

    /// AUTH-4c. **A rule DOES survive `cancelAll` on the `claim` path.** `claim()` never calls
    /// `_load`: it checks neither `active`, nor `expiry`, nor `epoch`. After the panic button, an
    /// arbitrary caller can still move value out of Alice's rule and take a keeper fee for doing
    /// it, and the protocol fee is charged too.
    function test_AUTH4c_panicButtonDoesNotStopAClaimAndStillPaysAStrangerAFee() public {
        vm.prank(alice);
        uint256 id = trimmy.arm(_p(200e6, 100e6, 1e6, 2e6, 50));
        trimmy.execute(id); // queues 100 shares
        assertGt(trimmy.ruleAt(id).pendingShares, 0);

        // Alice panics, and also targets the rule directly. Both.
        vm.prank(alice);
        trimmy.cancel(id);
        vm.prank(alice);
        trimmy.cancelAll(alice);
        assertFalse(trimmy.ruleAt(id).active);
        assertEq(trimmy.epochOf(alice), 1);
        assertTrue(trimmy.ruleAt(id).epoch != trimmy.epochOf(alice));

        vm.warp(((block.timestamp / 1 days) + 2) * 1 days);
        _feeds();

        uint256 attackerBefore = fxrp.balanceOf(attacker);
        uint256 sinkBefore = fxrp.balanceOf(feeSink);

        vm.prank(attacker);
        trimmy.claim(id); // succeeds: cancelled AND stale-epoch AND explicitly cancelled

        assertGt(
            fxrp.balanceOf(attacker) - attackerBefore,
            0,
            "AUTH-4c: a stranger was paid out of a rule the owner cancelled twice"
        );
        assertGt(
            fxrp.balanceOf(feeSink) - sinkBefore,
            0,
            "AUTH-4c: the protocol fee was charged after cancellation"
        );
    }

    // -------- Question 5: what a keeper key confers --------

    /// AUTH-5. Everything `execute`/`claim` gives `msg.sender` is available to the public, and
    /// `arm` binds the rule to the caller, so a leaked keeper key adds nothing.
    function test_AUTH5_leakedKeeperKeyGrantsNothingThePublicLacks() public {
        address leaked = makeAddr("leakedKeeperKey");
        vm.prank(alice);
        uint256 id = trimmy.arm(_p(200e6, 100e6, 1e6, 2e6, 0));

        // 1. It can execute — but so can anybody, and the proceeds go to Alice regardless.
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(leaked);
        trimmy.execute(id);
        assertEq(vault.balanceOf(alice), aliceShares - 100e6, "debited Alice, as designed");
        assertEq(trimmy.ruleAt(id).account, alice, "destination is immutable");

        // 2. Arming with the leaked key binds the rule to the leaked key, whose allowance is zero.
        vm.prank(leaked);
        uint256 bad = trimmy.arm(_p(100e6, 100e6, 0, 0, 0));
        assertEq(trimmy.ruleAt(bad).account, leaked);
        vm.warp(block.timestamp + 120);
        _feeds();
        vm.expectRevert(); // ERC20InsufficientBalance on the leaked key
        trimmy.execute(bad);

        // 3. It cannot cancel Alice's rule, set her guardian, or bump her epoch.
        vm.prank(leaked);
        vm.expectRevert(Trimmy.NotAuthorised.selector);
        trimmy.cancel(id);
        vm.prank(leaked);
        trimmy.setGuardian(leaked);
        assertEq(trimmy.guardianOf(alice), address(0));
        vm.prank(leaked);
        vm.expectRevert(Trimmy.NotAuthorised.selector);
        trimmy.cancelAll(alice);
        assertEq(trimmy.epochOf(alice), 0);
    }

    // -------- Question 6: value stuck in the contract --------

    /// AUTH-6. `receive()` is open and `_refund()` sends `address(this).balance`, not
    /// `msg.value - fee`. FLR one party sends is taken by an unrelated party. (This is M-5,
    /// re-verified against the FIXED deployment's source.)
    function test_AUTH6_oneCallerTakesTheFlrAnotherCallerSent() public {
        vm.prank(alice);
        uint256 id = trimmy.arm(_p(200e6, 100e6, 0, 0, 0));

        address donor = makeAddr("donor");
        vm.deal(donor, 5 ether);
        vm.prank(donor);
        // forge-lint: disable-next-line(unchecked-call)
        (bool ok,) = address(trimmy).call{value: 5 ether}("");
        assertTrue(ok, "receive() accepted it");
        assertEq(address(trimmy).balance, 5 ether);

        address thief = makeAddr("thief");
        vm.deal(thief, 0);
        vm.prank(thief);
        trimmy.execute(id); // msg.value == 0; the FTSO fee is 0

        assertEq(thief.balance, 5 ether, "AUTH-6: swept a stranger's native balance for free");
        assertEq(address(trimmy).balance, 0);
    }

    /// AUTH-6b. The pooled-bucket path (M-2) is FIXED in the working tree: `pendingAssets` is
    /// recorded at queue time and `claim` pays `min(owed, held)`, so the first claimer no longer
    /// takes the whole `(Trimmy, period)` bucket. **This fix is not on chain** — the deployed
    /// `ruleAt` returns 24 words, i.e. the 8-slot struct without `pendingAssets`.
    function test_AUTH6b_pooledBucketNoLongerLetsOneRuleTakeAnothers() public {
        vm.prank(alice);
        uint256 aliceId = trimmy.arm(_p(1_000e6, 1_000e6, 0, 0, 0));
        vm.prank(bob);
        uint256 bobId = trimmy.arm(_p(1e6, 1e6, 0, 0, 0));

        trimmy.execute(aliceId); // 1000 shares queued under period P
        trimmy.execute(bobId); //      1 share  queued under the SAME period P
        assertEq(
            trimmy.ruleAt(aliceId).claimPeriod,
            trimmy.ruleAt(bobId).claimPeriod,
            "the vault still pools both rules into one bucket"
        );

        vm.warp(((block.timestamp / 1 days) + 2) * 1 days);
        _feeds();

        uint256 aliceBefore = fxrp.balanceOf(alice);
        uint256 bobBefore = fxrp.balanceOf(bob);

        trimmy.claim(bobId); // Bob's rule drains the whole bucket into Trimmy…
        assertEq(fxrp.balanceOf(bob) - bobBefore, 1e6, "but is credited only its own 1 FXRP");
        assertEq(fxrp.balanceOf(address(trimmy)), 1_000e6, "Alice's 1000 sits in Trimmy");

        trimmy.claim(aliceId); // …and Alice is paid out of that ambient balance.
        assertEq(fxrp.balanceOf(alice) - aliceBefore, 1_000e6, "Alice made whole");
        assertEq(fxrp.balanceOf(address(trimmy)), 0);
    }

    /// AUTH-6c. The orphaned-period path (M-3) is FIXED in the working tree by refusing to queue a
    /// second redemption while one is outstanding. Also not on chain. The cost is a liveness
    /// coupling that did not exist before: a multi-part EXIT_VAULT rule cannot advance until
    /// somebody clears the previous claim, which is at minimum the next UTC midnight.
    function test_AUTH6c_secondQueueIsNowRefusedRatherThanOrphaned() public {
        vm.prank(alice);
        uint256 id = trimmy.arm(_p(200e6, 100e6, 0, 0, 0));

        trimmy.execute(id);
        uint64 claimableAt = trimmy.ruleAt(id).claimableAt;

        vm.warp(((block.timestamp / 1 days) + 1) * 1 days + 1 hours);
        _feeds();
        vm.expectRevert(
            abi.encodeWithSelector(Trimmy.RedemptionAlreadyPending.selector, claimableAt)
        );
        trimmy.execute(id);

        // The rule is stalled — for up to a day — on a third party calling claim().
        vm.warp(((block.timestamp / 1 days) + 2) * 1 days);
        _feeds();
        trimmy.claim(id);
        trimmy.execute(id); // only now can part 2 run
        assertEq(trimmy.ruleAt(id).spent, 200e6);
    }

    /// AUTH-6d. The keeper-fee budget is sized by `_validate` for EXECUTIONS only
    /// (`required = keeperFeeFlat * ceilDiv(total, part)`), but `claim()` draws `keeperFeeFlat`
    /// from the same budget. An EXIT_VAULT rule therefore has HALF the funded runway `_validate`
    /// certified, and L2's "refuse to arm a rule that cannot fund its own executions" is wrong by
    /// exactly 2x for this verb.
    function test_AUTH6d_claimDrainsTheBudgetValidateSizedForExecutionsAlone() public {
        // 2 parts * 1 FXRP fee = 2 FXRP budget, exactly what _validate demands and no more.
        vm.prank(alice);
        uint256 id = trimmy.arm(_p(200e6, 100e6, 1e6, 2e6, 0));

        trimmy.execute(id);
        assertEq(trimmy.ruleAt(id).keeperFeePaid, 0, "execute() on EXIT_VAULT settles nothing");

        vm.warp(((block.timestamp / 1 days) + 2) * 1 days);
        _feeds();
        trimmy.claim(id);
        assertEq(trimmy.ruleAt(id).keeperFeePaid, 1e6, "claim() drew a whole execution's fee");

        trimmy.execute(id); // part 2
        vm.warp(uint256(trimmy.ruleAt(id).claimableAt) + 1);
        _feeds();
        trimmy.claim(id);
        assertEq(
            trimmy.ruleAt(id).keeperFeePaid,
            2e6,
            "AUTH-6d: 2 executions + 2 claims exhausted a budget certified for 2 executions"
        );
    }
}

// =========================================================================================
// Suite 4 — the NEW `claim()` in the working tree pays out of Trimmy's ambient asset balance.
// =========================================================================================

/// @notice Vault stand-in that reproduces the two properties the M-3 fix comment relies on:
///         a `claimWithdraw` that can fail or under-deliver, and a public push path that lets a
///         third party deliver a bucket into Trimmy ahead of `claim()`.
contract ShortfallVault is ERC20 {
    IERC20 public immutable assetToken;
    uint256 public lagDuration = 300;
    uint256 public shortfallBips;
    bool public revertOnClaim;

    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawAssets;

    constructor(IERC20 a) ERC20("Shortfall Vault", "sVLT") {
        assetToken = a;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function setShortfallBips(uint256 v) external {
        shortfallBips = v;
    }

    function setRevertOnClaim(bool v) external {
        revertOnClaim = v;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function deposit(uint256, address) external pure returns (uint256) {
        revert("unused");
    }

    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets)
    {
        if (owner != msg.sender) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        assets = shares; // 1:1 at queue time — this is what Trimmy records as pendingAssets
        pendingWithdrawAssets[receiver][(block.timestamp + lagDuration) / 1 days] += assets;
    }

    /// @dev Delivers `shortfallBips` less than was recorded, or reverts outright.
    function claimWithdraw(uint256 period) external returns (uint256) {
        if (revertOnClaim) revert("vault: claim failed");
        if (period >= block.timestamp / 1 days) revert("InvalidPeriod");
        uint256 owed = pendingWithdrawAssets[msg.sender][period];
        pendingWithdrawAssets[msg.sender][period] = 0;
        uint256 paid = owed - (owed * shortfallBips) / 10_000;
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        assetToken.transfer(msg.sender, paid);
        return paid;
    }
}

contract AuthAmbientBalanceTest is Test {
    address internal constant REGISTRY_ADDR = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;
    bytes21 internal constant FEED_XRP =
        bytes21(uint168(0x015852502f55534400000000000000000000000000));

    Trimmy internal trimmy;
    MockERC20 internal fxrp;
    ShortfallVault internal vault;
    MockFtsoV2 internal ftso;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal feeSink = makeAddr("feeSink");

    function setUp() public {
        vm.warp(10 days);
        fxrp = new MockERC20("FTestXRP", "FXRP", 6);
        ftso = new MockFtsoV2();
        MockRegistry reg = new MockRegistry();
        vm.etch(REGISTRY_ADDR, address(reg).code);
        MockRegistry(REGISTRY_ADDR).setFtso(address(ftso));
        vault = new ShortfallVault(IERC20(address(fxrp)));

        Trimmy.TokenCfg[] memory tokens = new Trimmy.TokenCfg[](1);
        tokens[0] = Trimmy.TokenCfg({token: address(vault), feedId: FEED_XRP, decimals: 6});
        Trimmy.VenueCfg[] memory venues = new Trimmy.VenueCfg[](1);
        venues[0] = Trimmy.VenueCfg({
            target: address(vault), kind: Trimmy.VenueKind.QUEUED_VAULT, feeTier: 0
        });
        trimmy = new Trimmy(tokens, venues, 60, feeSink, IConfidentialTrigger(address(0)));

        fxrp.mint(address(vault), 1_000_000e6);
        vault.mint(alice, 10_000e6);
        vault.mint(bob, 10_000e6);
        vm.prank(alice);
        vault.approve(address(trimmy), type(uint256).max);
        vm.prank(bob);
        vault.approve(address(trimmy), type(uint256).max);
        _feeds();
    }

    function _feeds() internal {
        ftso.setFeed(FEED_XRP, 3_000_000, 6, uint64(vm.getBlockTimestamp()));
    }

    function _p(uint128 total) internal view returns (Trimmy.RuleParams memory p) {
        p = Trimmy.RuleParams({
            sellTokenId: 0,
            buyTokenId: 0,
            verb: Trimmy.Verb.EXIT_VAULT,
            venueId: 0,
            trigger: Trimmy.Trigger.SCHEDULE,
            totalSellAmount: total,
            partSellAmount: total,
            minOutAbsolute: 0,
            triggerValue: 60,
            expiry: uint64(block.timestamp + 30 days),
            slippageBips: 0,
            protocolFeeBips: 0,
            keeperFeeFlat: 0,
            keeperFeeBudget: 0
        });
    }

    /// AUTH-7. `claim()` now pays `min(pendingAssets, asset.balanceOf(this))` and swallows every
    /// revert from `claimWithdraw`. Both terms are wrong for the purpose: `balanceOf(this)` is the
    /// contract's WHOLE balance, which is other rules' money, and the swallowed revert means the
    /// vault does not have to have paid anything at all for a claim to settle.
    ///
    /// Alice's rule is short 100 FXRP; the shortfall is made up out of Bob's already-delivered
    /// assets, and Bob is the one who ends up short.
    function test_AUTH7_claimTopsUpOneRuleOutOfAnothersDeliveredAssets() public {
        vm.prank(alice);
        uint256 aliceId = trimmy.arm(_p(1_000e6));
        vm.prank(bob);
        uint256 bobId = trimmy.arm(_p(1_000e6));

        trimmy.execute(aliceId);
        trimmy.execute(bobId);
        assertEq(trimmy.ruleAt(aliceId).pendingAssets, 1_000e6);
        assertEq(trimmy.ruleAt(bobId).pendingAssets, 1_000e6);

        vm.warp(((block.timestamp / 1 days) + 2) * 1 days);
        _feeds();

        // The vault delivers 10% less than it recorded at queue time — a withdrawal fee, a share
        // price move, anything. `withdrawalFee` is a live parameter on TESTearnXRP; it reads 0
        // today (GROUND-TRUTH 4a-bis) but nothing in Trimmy depends on it staying 0.
        vault.setShortfallBips(1_000);

        // Alice claims first. Her `claimWithdraw` drains the POOLED bucket (both rules queued in
        // the same day), delivering 1800 into Trimmy. `held` is 1800, `owed` is 1000, so she is
        // paid in full and the entire shortfall is displaced onto whoever claims next.
        uint256 aliceBefore = fxrp.balanceOf(alice);
        trimmy.claim(aliceId);
        assertEq(
            fxrp.balanceOf(alice) - aliceBefore,
            1_000e6,
            "AUTH-7: Alice paid in full though the vault delivered 90 percent"
        );

        uint256 bobBefore = fxrp.balanceOf(bob);
        trimmy.claim(bobId); // his bucket is already empty; he gets whatever is left
        assertEq(
            fxrp.balanceOf(bob) - bobBefore,
            800e6,
            "AUTH-7: Bob absorbed 200 of a 200 total shortfall - 100 of it was Alice's"
        );
        assertEq(trimmy.ruleAt(bobId).pendingAssets, 0, "and his claim is unrepeatable");
    }

    /// AUTH-7b. The swallowed revert on its own: a claim settles in full while the vault call
    /// fails outright, purely out of ambient balance.
    function test_AUTH7b_claimSettlesEvenWhenTheVaultCallReverts() public {
        vm.prank(alice);
        uint256 aliceId = trimmy.arm(_p(1_000e6));
        trimmy.execute(aliceId);

        vm.warp(((block.timestamp / 1 days) + 2) * 1 days);
        _feeds();

        fxrp.mint(address(trimmy), 1_000e6); // ambient balance from anywhere at all
        vault.setRevertOnClaim(true);

        uint256 before = fxrp.balanceOf(alice);
        trimmy.claim(aliceId);
        assertEq(
            fxrp.balanceOf(alice) - before,
            1_000e6,
            "AUTH-7b: settled in full on a reverting vault call"
        );
        assertEq(
            vault.pendingWithdrawAssets(address(trimmy), 0) == 0,
            true,
            "the vault bucket was never touched"
        );
    }
}
