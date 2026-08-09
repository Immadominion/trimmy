// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function initialize(uint160 sqrtPriceX96) external;
    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1);
    function burn(int24 tickLower, int24 tickUpper, uint128 amount)
        external
        returns (uint256 amount0, uint256 amount1);
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
    function liquidity() external view returns (uint128);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IWNat {
    function deposit() external payable;
}

/// @title Liquidity seeder for the FXRP/WC2FLR pool we deploy ourselves
///
/// @notice **This is a harness, not product code.** Trimmy never provides liquidity and never holds
///         an LP position; it only swaps against venues that already exist. This contract exists
///         because on Coston2 no FXRP pool existed at all — measured, all 80 combinations of
///         5 factories x 4 counter-tokens x 4 fee tiers returned `address(0)` (GROUND-TRUTH §3) —
///         so a swap-verb rule had nothing to execute against.
///
/// @dev The pool's `mint` takes **liquidity**, not token amounts, and pays via a callback. The
///      liquidity figure is computed off chain from the FTSO price and the chosen range, and the
///      callback pays whatever the pool asks up to a ceiling the caller sets. Paying "whatever is
///      asked" without that ceiling would let a mis-computed range drain the whole balance.
contract PoolSeeder {
    address public immutable owner;
    IUniswapV3Pool public immutable pool;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 private _max0;
    uint256 private _max1;

    error NotOwner();
    error NotPool();
    error Exceeds(uint256 owed, uint256 ceiling);

    constructor(IUniswapV3Pool pool_) {
        owner = msg.sender;
        pool = pool_;
        token0 = IERC20(pool_.token0());
        token1 = IERC20(pool_.token1());
    }

    function seed(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 max0, uint256 max1)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        if (msg.sender != owner) revert NotOwner();
        _max0 = max0;
        _max1 = max1;
        (amount0, amount1) = pool.mint(address(this), tickLower, tickUpper, liquidity, "");
        _max0 = 0;
        _max1 = 0;
    }

    /// @dev **Not `uniswapV3MintCallback`.** The Coston2 deployment is a Flare-branded V3 fork and
    ///      renames the callback to `flareSwapMintCallback` (selector `0x8930e8c5`) — measured, the
    ///      pool reverted with "unrecognized function selector" against the Uniswap name. This does
    ///      not affect Trimmy itself, which only ever calls the SwapRouter and never receives a
    ///      pool callback, but it is exactly the kind of fork divergence that a copied integration
    ///      would hit at runtime rather than at compile time.
    function flareSwapMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata)
        external
    {
        if (msg.sender != address(pool)) revert NotPool();
        if (amount0Owed > _max0) revert Exceeds(amount0Owed, _max0);
        if (amount1Owed > _max1) revert Exceeds(amount1Owed, _max1);
        if (amount0Owed > 0) token0.transfer(address(pool), amount0Owed);
        if (amount1Owed > 0) token1.transfer(address(pool), amount1Owed);
    }

    /// @notice Pull the position back out. Present so the liquidity is recoverable rather than
    ///         stranded in a contract with no exit — the same reasoning that made `M-3`'s orphaned
    ///         vault bucket a bug.
    function unseed(int24 tickLower, int24 tickUpper, uint128 liquidity) external {
        if (msg.sender != owner) revert NotOwner();
        pool.burn(tickLower, tickUpper, liquidity);
        pool.collect(owner, tickLower, tickUpper, type(uint128).max, type(uint128).max);
    }

    function sweep() external {
        if (msg.sender != owner) revert NotOwner();
        token0.transfer(owner, token0.balanceOf(address(this)));
        token1.transfer(owner, token1.balanceOf(address(this)));
    }
}

/// @notice Deploys the seeder, initialises the pool at the FTSO-derived price, and mints one
///         concentrated position.
///
/// @dev Run:
///   POOL=0xafcA... SQRT_PRICE_X96=... TICK_LOWER=... TICK_UPPER=... LIQUIDITY=... \
///   MAX0=... MAX1=... WRAP_WEI=... \
///   forge script script/SeedPool.s.sol:SeedPool --rpc-url coston2 --broadcast --private-key $KEY
contract SeedPool is Script {
    function run() external {
        IUniswapV3Pool pool = IUniswapV3Pool(vm.envAddress("POOL"));
        uint160 sqrtPriceX96 = uint160(vm.envUint("SQRT_PRICE_X96"));
        int24 tickLower = int24(vm.envInt("TICK_LOWER"));
        int24 tickUpper = int24(vm.envInt("TICK_UPPER"));
        uint128 liquidity = uint128(vm.envUint("LIQUIDITY"));
        uint256 max0 = vm.envUint("MAX0");
        uint256 max1 = vm.envUint("MAX1");
        uint256 wrapWei = vm.envOr("WRAP_WEI", uint256(0));

        vm.startBroadcast();

        (uint160 existing,,,,,,) = pool.slot0();
        if (existing == 0) {
            pool.initialize(sqrtPriceX96);
            console.log("initialised pool at sqrtPriceX96");
        } else {
            console.log("pool already initialised");
        }

        if (wrapWei > 0) IWNat(pool.token1()).deposit{value: wrapWei}();

        PoolSeeder seeder = new PoolSeeder(pool);
        IERC20(pool.token0()).transfer(address(seeder), max0);
        IERC20(pool.token1()).transfer(address(seeder), max1);

        (uint256 a0, uint256 a1) = seeder.seed(tickLower, tickUpper, liquidity, max0, max1);
        seeder.sweep();

        vm.stopBroadcast();

        console.log("seeder    :", address(seeder));
        console.log("amount0   :", a0);
        console.log("amount1   :", a1);
        console.log("liquidity :", pool.liquidity());
    }
}
