// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev Minimal hand-rolled Uniswap v4 surface. Vendored rather than importing
///      v4-core so this repo keeps a single dependency (forge-std). The layouts
///      below match v4-core exactly; any drift is caught by the fork tests,
///      which swap against the real PoolManager on Robinhood Chain.

type Currency is address;
type BalanceDelta is int256;

struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta);
    function sync(Currency currency) external;
    function settle() external payable returns (uint256);
    function take(Currency currency, address to, uint256 amount) external;
    function extsload(bytes32 slot) external view returns (bytes32);
}

interface IUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

library DeltaLib {
    /// @dev BalanceDelta packs amount0 in the upper 128 bits, amount1 in the lower.
    function amount0(BalanceDelta d) internal pure returns (int128) {
        return int128(BalanceDelta.unwrap(d) >> 128);
    }

    function amount1(BalanceDelta d) internal pure returns (int128) {
        return int128(int256(BalanceDelta.unwrap(d)));
    }
}
