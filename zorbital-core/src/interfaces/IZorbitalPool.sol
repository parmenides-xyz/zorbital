// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

interface IZorbitalPool {
    function swap(
        address recipient,
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        uint256 amountSpecified,
        bytes calldata data
    ) external returns (int256 amountIn, int256 amountOut);

    function slot0() external view returns (uint128 sumReserves, int24 tick);

    function tokens(uint256 index) external view returns (address);

    function r() external view returns (uint128);
}
