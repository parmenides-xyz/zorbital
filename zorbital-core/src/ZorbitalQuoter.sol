// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./interfaces/IZorbitalPool.sol";

contract ZorbitalQuoter {
    struct QuoteParams {
        address pool;
        uint256 tokenInIndex;
        uint256 tokenOutIndex;
        uint256 amountIn;
    }

    /// @notice Simulates a swap and returns the output amount without executing
    /// @dev Initiates a real swap but reverts in the callback to capture calculated amounts
    /// @param params The quote parameters
    /// @return amountOut The calculated output amount
    /// @return sumReservesAfter The sum of reserves after the simulated swap
    /// @return tickAfter The tick after the simulated swap
    function quote(QuoteParams memory params)
        public
        returns (
            uint256 amountOut,
            uint128 sumReservesAfter,
            int24 tickAfter
        )
    {
        try
            IZorbitalPool(params.pool).swap(
                address(this),
                params.tokenInIndex,
                params.tokenOutIndex,
                params.amountIn,
                abi.encode(params.pool)
            )
        {} catch (bytes memory reason) {
            return abi.decode(reason, (uint256, uint128, int24));
        }
    }

    /// @notice Swap callback that captures results and reverts
    /// @dev This is called by the pool during swap simulation
    function zorbitalSwapCallback(
        uint256 /* tokenInIndex */,
        uint256 /* tokenOutIndex */,
        int256 /* amountIn */,
        int256 amountOut,
        bytes memory data
    ) external view {
        address pool = abi.decode(data, (address));

        // amountOut is negative (tokens leaving the pool)
        uint256 amountOutAbs = uint256(-amountOut);

        (uint128 sumReservesAfter, int24 tickAfter) = IZorbitalPool(pool).slot0();

        // Revert with the calculated values (gas optimized using assembly)
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, amountOutAbs)
            mstore(add(ptr, 0x20), sumReservesAfter)
            mstore(add(ptr, 0x40), tickAfter)
            revert(ptr, 96)
        }
    }
}
