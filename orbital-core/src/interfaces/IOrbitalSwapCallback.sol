// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

interface IOrbitalSwapCallback {
    function orbitalSwapCallback(
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        int256 amountIn,
        int256 amountOut,
        bytes calldata data
    ) external;
}
