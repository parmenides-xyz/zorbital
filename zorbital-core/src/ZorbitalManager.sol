// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./ZorbitalPool.sol";
import "./libraries/OrbitalMath.sol";
import "./libraries/Path.sol";
import "./interfaces/IERC20.sol";

contract ZorbitalManager {
    using Path for bytes;

    // ============ Structs ============

    struct CallbackData {
        address pool;
        address payer;
    }

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    struct MintParams {
        address poolAddress;
        int24 tick;
        uint256[] amountsDesired;
        uint256[] amountsMin;
    }

    struct SwapSingleParams {
        address poolAddress;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint128 sumReservesLimit;
    }

    struct SwapParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 minAmountOut;
    }

    // ============ Errors ============

    error SlippageCheckFailed(uint256[] amounts);
    error TooLittleReceived(uint256 amountOut);

    // ============ Mint Functions ============

    function mint(MintParams calldata params)
        public
        returns (uint256[] memory amounts)
    {
        uint128 radius = OrbitalMath.calcRadiusForAmounts(params.amountsDesired);

        amounts = ZorbitalPool(params.poolAddress).mint(
            msg.sender,
            params.tick,
            radius,
            abi.encode(CallbackData({pool: params.poolAddress, payer: msg.sender}))
        );

        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] < params.amountsMin[i])
                revert SlippageCheckFailed(amounts);
        }
    }

    // ============ Swap Functions ============

    /// @notice Swap tokens within a single pool
    function swapSingle(SwapSingleParams calldata params)
        public
        returns (uint256 amountOut)
    {
        amountOut = _swap(
            params.amountIn,
            msg.sender,
            params.sumReservesLimit,
            SwapCallbackData({
                path: bytes.concat(
                    bytes20(params.tokenIn),
                    bytes20(params.poolAddress),
                    bytes20(params.tokenOut)
                ),
                payer: msg.sender
            })
        );
    }

    /// @notice Multi-pool swap following a path
    function swap(SwapParams memory params) public returns (uint256 amountOut) {
        address payer = msg.sender;
        bool hasMultiplePools;

        while (true) {
            hasMultiplePools = params.path.hasMultiplePools();

            // For intermediate swaps, output goes to this contract
            // For final swap, output goes to recipient
            params.amountIn = _swap(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient,
                0, // No sumReservesLimit for multi-pool (use minAmountOut instead)
                SwapCallbackData({
                    path: params.path.getFirstPool(),
                    payer: payer
                })
            );

            if (hasMultiplePools) {
                // After first swap, this contract pays for subsequent swaps
                payer = address(this);
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        // Slippage protection for multi-pool swaps
        if (amountOut < params.minAmountOut)
            revert TooLittleReceived(amountOut);
    }

    /// @notice Internal swap function used by both single and multi-pool swaps
    function _swap(
        uint256 amountIn,
        address recipient,
        uint128 sumReservesLimit,
        SwapCallbackData memory data
    ) internal returns (uint256 amountOut) {
        // Decode path to get pool and tokens
        (address tokenIn, address pool, address tokenOut) = data.path.decodeFirstPool();

        // Find token indices in the pool
        ZorbitalPool orbitalPool = ZorbitalPool(pool);
        uint256 tokenInIndex = findTokenIndex(orbitalPool, tokenIn);
        uint256 tokenOutIndex = findTokenIndex(orbitalPool, tokenOut);

        // Execute swap
        (int256 amountInResult, int256 amountOutResult) = orbitalPool.swap(
            recipient,
            tokenInIndex,
            tokenOutIndex,
            amountIn,
            sumReservesLimit,
            abi.encode(data)
        );

        // amountOut is negative (tokens leaving pool)
        amountOut = uint256(-amountOutResult);
    }

    /// @notice Find token index in pool's token array
    function findTokenIndex(ZorbitalPool pool, address token) internal view returns (uint256) {
        uint256 numTokens = 4; // Assuming 4 tokens, could be made dynamic
        for (uint256 i = 0; i < numTokens; i++) {
            if (pool.tokens(i) == token) return i;
        }
        revert("Token not found in pool");
    }

    // ============ Callbacks ============

    function zorbitalMintCallback(
        uint256[] memory amounts,
        bytes calldata data
    ) public {
        CallbackData memory extra = abi.decode(data, (CallbackData));
        ZorbitalPool pool = ZorbitalPool(extra.pool);

        for (uint256 i = 0; i < amounts.length; i++) {
            IERC20(pool.tokens(i)).transferFrom(
                extra.payer,
                msg.sender,
                amounts[i]
            );
        }
    }

    function zorbitalSwapCallback(
        uint256 tokenInIndex,
        uint256 /* tokenOutIndex */,
        int256 amountIn,
        int256 /* amountOut */,
        bytes calldata data
    ) public {
        SwapCallbackData memory swapData = abi.decode(data, (SwapCallbackData));
        (address tokenIn, , ) = swapData.path.decodeFirstPool();

        if (amountIn > 0) {
            if (swapData.payer == address(this)) {
                // Intermediate swap: transfer from this contract's balance
                IERC20(tokenIn).transfer(msg.sender, uint256(amountIn));
            } else {
                // First swap: transfer from user's balance
                IERC20(tokenIn).transferFrom(
                    swapData.payer,
                    msg.sender,
                    uint256(amountIn)
                );
            }
        }
    }
}
