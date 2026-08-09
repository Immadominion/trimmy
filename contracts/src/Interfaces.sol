// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Flare's contract registry. This is the ONLY address Trimmy hardcodes.
/// @dev `sdk/AGENTS.md` rule 1: everything else is resolved at runtime. Flare's own published
///      Python example hardcodes a stale FtsoV2 address; that is the failure this rule prevents.
///      The registry is at 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019 on all four networks.
interface IFlareContractRegistry {
    function getContractAddressByName(string calldata _name) external view returns (address);
    function getContractAddressByHash(bytes32 _nameHash) external view returns (address);
}

/// @notice FTSOv2 block-latency feeds.
/// @dev Two shapes matter here and both are counter-intuitive:
///
///      - `_feedId` is **bytes21**, not bytes32: one category byte plus a 20-byte name.
///      - `getFeedById` is `payable` and **non-view**. `sdk/AGENTS.md` rule 4: "payable does not
///        mean it costs money" — these read free via `eth_call` today, and `calculateFeeById`
///        returns 0. But it is governance-settable, so Trimmy queries the fee and forwards it
///        rather than assuming zero forever.
interface IFtsoV2 {
    function getFeedById(bytes21 _feedId)
        external
        payable
        returns (uint256 _value, int8 _decimals, uint64 _timestamp);

    function calculateFeeById(bytes21 _feedId) external view returns (uint256 _fee);
}

/// @notice Uniswap V3 SwapRouter, as actually deployed on Coston2.
/// @dev Verified against the explorer ABI for 0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc on
///      2026-08-07: this is the ORIGINAL `SwapRouter`, whose `ExactInputParams` carries a
///      `deadline`. SwapRouter02 drops that field. Writing against the wrong one reverts on every
///      call, and an earlier design targeted `swapExactTokensForTokens`, which no Coston2 router
///      implements at all.
interface ISwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

/// @notice The Upshift-style queued-withdrawal vault used by TESTearnXRP and MyERC4626.
/// @dev Read from verified source at 0x9E63a5D282F2fBb7DcE822B98e363b2719D28319 on 2026-08-07.
///      Three traps are encoded in how Trimmy calls this, all recorded in GROUND-TRUTH §4a-bis:
///
///      1. `requestRedeem` is `this.redeem(...)` — an external SELF-call — so `_caller` becomes the
///         vault and `_spendAllowance(owner, vault, shares)` runs. Calling it without approving the
///         vault against yourself reverts. Trimmy calls `redeem` directly with
///         `owner == address(this)` so `_caller == _owner` and no allowance is spent.
///      2. `requestRedeem` returns `_claimableEpoch`, a timestamp. `claimWithdraw` wants a
///         **day-index period**. They are different numbers.
///      3. `claimWithdraw` credits `msg.sender`, so Trimmy must be the receiver at request time and
///         must call the claim itself.
interface IQueuedVault {
    function asset() external view returns (address);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @dev Does NOT transfer assets. The overridden `_withdraw` burns shares and queues the
    ///      payout under `period = dayIndex(block.timestamp + lagDuration)`.
    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets);

    /// @dev Reverts `InvalidPeriod()` unless `_period < dayIndex(now)` — the current period is
    ///      never claimable, so the true wait is the next UTC midnight, not `lagDuration`.
    function claimWithdraw(uint256 _period) external returns (uint256 assets);

    function lagDuration() external view returns (uint256);
    function pendingWithdrawAssets(address receiver, uint256 period) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
}

/// @notice The on-chain half of a confidential trigger: a rule whose threshold price is held in a
///         TEE and never published.
/// @dev Deployed separately (see `fcc/extension/contracts/TrimmyConfidentialTrigger.sol`) so that
///      Trimmy's own allowlists stay immutable and a change to the confidential path never requires
///      redeploying the rule engine.
interface IConfidentialTrigger {
    /// @notice Reverts unless an enclave verdict for `(ruleId, nonce)` was accepted and says fire.
    /// @dev Callable only by the Trimmy instance bound at construction.
    function consumeVerdict(uint256 ruleId, uint64 nonce) external view;
}
