// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./OrbitalPool.sol";
import "./libraries/Path.sol";

contract OrbitalQuoter {
    using Path for bytes;

    struct QuoteSingleParams {
        address poolAddress;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint128 sumReservesLimit;
    }

    /// @notice Simulates a single-pool swap and returns the output amount
    function quoteSingle(QuoteSingleParams memory params)
        public
        returns (
            uint256 amountOut,
            uint128 sumReservesAfter,
            int24 tickAfter
        )
    {
        OrbitalPool pool = OrbitalPool(params.poolAddress);
        uint256 tokenInIndex = findTokenIndex(pool, params.tokenIn);
        uint256 tokenOutIndex = findTokenIndex(pool, params.tokenOut);

        try
            pool.swap(
                address(this),
                tokenInIndex,
                tokenOutIndex,
                params.amountIn,
                params.sumReservesLimit,
                abi.encode(params.poolAddress)
            )
        {} catch (bytes memory reason) {
            return abi.decode(reason, (uint256, uint128, int24));
        }
    }

    /// @notice Simulates a multi-pool swap following a path
    /// @param path The swap path (tokenIn + poolAddress + tokenOut + ...)
    /// @param amountIn The input amount
    /// @return amountOut The final output amount
    /// @return sumReservesAfterList Sum of reserves after each pool swap
    /// @return tickAfterList Tick after each pool swap
    function quote(bytes memory path, uint256 amountIn)
        public
        returns (
            uint256 amountOut,
            uint128[] memory sumReservesAfterList,
            int24[] memory tickAfterList
        )
    {
        uint256 numPools = path.numPools();
        sumReservesAfterList = new uint128[](numPools);
        tickAfterList = new int24[](numPools);

        uint256 i = 0;
        while (true) {
            (address tokenIn, address poolAddress, address tokenOut) = path.decodeFirstPool();

            (
                uint256 amountOut_,
                uint128 sumReservesAfter,
                int24 tickAfter
            ) = quoteSingle(
                    QuoteSingleParams({
                        poolAddress: poolAddress,
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        amountIn: amountIn,
                        sumReservesLimit: 0
                    })
                );

            sumReservesAfterList[i] = sumReservesAfter;
            tickAfterList[i] = tickAfter;
            amountIn = amountOut_;
            i++;

            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                amountOut = amountIn;
                break;
            }
        }
    }

    /// @notice Find token index in pool's token array
    function findTokenIndex(OrbitalPool pool, address token) internal view returns (uint256) {
        for (uint256 i = 0; i < 4; i++) {
            if (pool.tokens(i) == token) return i;
        }
        revert("Token not found in pool");
    }

    /// @notice Swap callback that captures results and reverts
    function orbitalSwapCallback(
        uint256 /* tokenInIndex */,
        uint256 /* tokenOutIndex */,
        int256 /* amountIn */,
        int256 amountOut,
        bytes memory data
    ) external view {
        address poolAddress = abi.decode(data, (address));

        uint256 amountOutAbs = uint256(-amountOut);

        (uint128 sumReservesAfter, int24 tickAfter,) = OrbitalPool(poolAddress).slot0();

        assembly {
            let ptr := mload(0x40)
            mstore(ptr, amountOutAbs)
            mstore(add(ptr, 0x20), sumReservesAfter)
            mstore(add(ptr, 0x40), tickAfter)
            revert(ptr, 96)
        }
    }
}
