// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./ZorbitalPool.sol";
import "./interfaces/IERC20.sol";

contract ZorbitalManager {
    struct CallbackData {
        address pool;
        address payer;
    }

    function mint(
        address poolAddress,
        int24 tick,
        uint128 amount
    ) public returns (uint256[] memory amounts) {
        amounts = ZorbitalPool(poolAddress).mint(
            msg.sender,
            tick,
            amount,
            abi.encode(CallbackData({pool: poolAddress, payer: msg.sender}))
        );
    }

    function swap(
        address poolAddress,
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        uint256 amountSpecified
    ) public returns (int256 amountIn, int256 amountOut) {
        (amountIn, amountOut) = ZorbitalPool(poolAddress).swap(
            msg.sender,
            tokenInIndex,
            tokenOutIndex,
            amountSpecified,
            abi.encode(CallbackData({pool: poolAddress, payer: msg.sender}))
        );
    }

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
        CallbackData memory extra = abi.decode(data, (CallbackData));
        ZorbitalPool pool = ZorbitalPool(extra.pool);

        if (amountIn > 0) {
            IERC20(pool.tokens(tokenInIndex)).transferFrom(
                extra.payer,
                msg.sender,
                uint256(amountIn)
            );
        }
    }
}
