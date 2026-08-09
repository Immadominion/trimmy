// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "../../src/Interfaces.sol";

/// @notice ERC20 with configurable decimals and an optional transfer fee.
/// @dev The fee exists to test A9. FXRP has no transfer fee today — the AssetManager reverts
///      `FunctionNotFound` for `transferFeeMillionths()` — but FAssets transfer fees are a
///      governance switch and Trimmy is not upgradeable, so the contract must charge the measured
///      balance delta rather than the requested amount. This mock is how that gets proven.
contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;
    uint16 public transferFeeBips;

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTransferFeeBips(uint16 bips) external {
        transferFeeBips = bips;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && transferFeeBips > 0) {
            uint256 fee = (value * transferFeeBips) / 10_000;
            if (fee > 0) {
                super._update(from, address(0xFEE), fee);
                value -= fee;
            }
        }
        super._update(from, to, value);
    }
}

/// @notice FTSOv2 stand-in. Feed IDs are bytes21, and `getFeedById` is payable and non-view.
contract MockFtsoV2 {
    struct FeedData {
        uint256 value;
        int8 decimals;
        uint64 timestamp;
        bool set;
    }

    mapping(bytes21 => FeedData) public feeds;
    uint256 public feePerRead;

    function setFeed(bytes21 id, uint256 value, int8 dec, uint64 ts) external {
        feeds[id] = FeedData(value, dec, ts, true);
    }

    function setFeePerRead(uint256 fee) external {
        feePerRead = fee;
    }

    function calculateFeeById(bytes21) external view returns (uint256) {
        return feePerRead;
    }

    function getFeedById(bytes21 id) external payable returns (uint256 value, int8 dec, uint64 ts) {
        FeedData memory f = feeds[id];
        require(f.set, "feed unset");
        return (f.value, f.decimals, f.timestamp);
    }
}

/// @notice Flare contract registry stand-in, etched at the real registry address in tests.
contract MockRegistry {
    address public ftso;

    function setFtso(address a) external {
        ftso = a;
    }

    function getContractAddressByHash(bytes32) external view returns (address) {
        return ftso;
    }

    function getContractAddressByName(string calldata) external view returns (address) {
        return ftso;
    }
}

/// @notice Uniswap V3 SwapRouter stand-in with the ORIGINAL `ExactInputParams` (deadline present).
/// @dev Decodes the packed path exactly as the real router does: 20-byte tokenIn, 3-byte fee,
///      20-byte tokenOut. Output is minted at a configurable rate so tests can drive the price
///      away from the oracle and prove the floor bites.
contract MockSwapRouter {
    using SafeERC20 for IERC20;

    /// @dev Output per input, scaled by 1e18, before token-decimal adjustment.
    uint256 public rateWad = 1e18;
    bool public underdeliver;

    function setRateWad(uint256 r) external {
        rateWad = r;
    }

    function setUnderdeliver(bool v) external {
        underdeliver = v;
    }

    function _decodePath(bytes calldata path)
        internal
        pure
        returns (address tokenIn, address tokenOut)
    {
        require(path.length == 43, "bad path");
        tokenIn = address(bytes20(path[0:20]));
        tokenOut = address(bytes20(path[23:43]));
    }

    function exactInput(ISwapRouter.ExactInputParams calldata p)
        external
        payable
        returns (uint256 amountOut)
    {
        (address tokenIn, address tokenOut) = _decodePath(p.path);
        require(block.timestamp <= p.deadline, "expired");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), p.amountIn);

        uint8 dIn = MockERC20(tokenIn).decimals();
        uint8 dOut = MockERC20(tokenOut).decimals();

        amountOut = (p.amountIn * rateWad) / 1e18;
        if (dOut >= dIn) amountOut = amountOut * (10 ** (dOut - dIn));
        else amountOut = amountOut / (10 ** (dIn - dOut));

        // A router that lies: returns the requested minimum but transfers less. Trimmy must catch
        // this by measuring its own balance delta rather than trusting the return value.
        uint256 delivered = underdeliver ? amountOut / 2 : amountOut;
        require(amountOut >= p.amountOutMinimum, "Too little received");

        MockERC20(tokenOut).mint(p.recipient, delivered);
        return amountOut;
    }
}

/// @notice Upshift-style queued-withdrawal vault stand-in.
/// @dev Reproduces the three mechanics measured on TESTearnXRP:
///      - `redeem` burns shares and QUEUES the payout; it transfers nothing.
///      - the queue bucket is `dayIndex(block.timestamp + lagDuration)`.
///      - `claimWithdraw(period)` requires `period < dayIndex(now)` and credits `msg.sender`.
contract MockQueuedVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable assetToken;
    uint256 public lagDuration = 300;
    uint256 public sharePriceWad = 1e18;

    mapping(address => mapping(uint256 => uint256)) public pendingWithdrawAssets;

    error InvalidPeriod();

    constructor(IERC20 asset_) ERC20("Mock Vault", "mVLT") {
        assetToken = asset_;
    }

    function decimals() public view override returns (uint8) {
        return MockERC20(address(assetToken)).decimals();
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function setLagDuration(uint256 v) external {
        lagDuration = v;
    }

    function setSharePriceWad(uint256 v) external {
        sharePriceWad = v;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        shares = (assets * 1e18) / sharePriceWad;
        _mint(receiver, shares);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return (assets * 1e18) / sharePriceWad;
    }

    /// @dev Transfers nothing. Matches the real vault's overridden `_withdraw`.
    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets)
    {
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        assets = (shares * sharePriceWad) / 1e18;

        uint256 period = (block.timestamp + lagDuration) / 1 days;
        pendingWithdrawAssets[receiver][period] += assets;
    }

    function claimWithdraw(uint256 period) external returns (uint256 assets) {
        if (period >= block.timestamp / 1 days) revert InvalidPeriod();
        assets = pendingWithdrawAssets[msg.sender][period];
        pendingWithdrawAssets[msg.sender][period] = 0;
        assetToken.safeTransfer(msg.sender, assets);
    }
}
