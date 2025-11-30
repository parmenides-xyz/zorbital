// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {FHE, euint128, ebool, InEuint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {FHEMath} from "../math/FHEMath.sol";
import {FHECurveLib} from "./FHECurveLib.sol";
import {CtxLib} from "./CtxLib.sol";
import {IEulerSwap} from "../interfaces/IEulerSwap.sol";

/// @title FHE Swap Library
/// @notice Handles encrypted swap logic for FHEulerSwap
/// @dev All swap amounts and reserves are encrypted, curve verification is done in FHE
library FHESwapLib {
    using FHEMath for euint128;
    using FHEMath for ebool;

    /// @notice Emitted after a confidential swap (amounts are encrypted handles, not values)
    event ConfidentialSwap(
        address indexed sender,
        uint256 eAmount0In,   // Handle to encrypted amount
        uint256 eAmount1In,   // Handle to encrypted amount
        uint256 eAmount0Out,  // Handle to encrypted amount
        uint256 eAmount1Out,  // Handle to encrypted amount
        address indexed to
    );

    error FHEStateNotInitialized();
    error SwapFailed();

    /// @notice Context for an encrypted swap operation
    struct FHESwapContext {
        IEulerSwap.DynamicParams dParams;
        FHECurveLib.FHEDynamicParams fheParams;
        address sender;
        address to;
        euint128 eAmount0In;
        euint128 eAmount1In;
        euint128 eAmount0Out;
        euint128 eAmount1Out;
    }

    /// @notice Initialize a swap context
    function init(
        address sender,
        address to
    ) internal view returns (FHESwapContext memory ctx) {
        ctx.dParams = CtxLib.getDynamicParams();
        ctx.fheParams = FHECurveLib.toFHEParams(ctx.dParams);
        ctx.sender = sender;
        ctx.to = to;

        // Initialize amounts to zero
        ctx.eAmount0In = FHE.asEuint128(0);
        ctx.eAmount1In = FHE.asEuint128(0);
        ctx.eAmount0Out = FHE.asEuint128(0);
        ctx.eAmount1Out = FHE.asEuint128(0);
    }

    /// @notice Set encrypted output amounts
    function setAmountsOut(
        FHESwapContext memory ctx,
        euint128 eAmount0Out,
        euint128 eAmount1Out
    ) internal pure {
        ctx.eAmount0Out = eAmount0Out;
        ctx.eAmount1Out = eAmount1Out;
    }

    /// @notice Set encrypted input amounts
    function setAmountsIn(
        FHESwapContext memory ctx,
        euint128 eAmount0In,
        euint128 eAmount1In
    ) internal pure {
        ctx.eAmount0In = eAmount0In;
        ctx.eAmount1In = eAmount1In;
    }

    /// @notice Execute the swap with encrypted values
    /// @dev Verifies curve in FHE and updates reserves atomically
    /// @return success Encrypted boolean indicating if swap was valid
    function finish(FHESwapContext memory ctx) internal returns (ebool success) {
        CtxLib.FHEState storage fs = CtxLib.getFHEState();
        require(fs.initialized, FHEStateNotInitialized());

        // Compute new reserves: newReserve = oldReserve + amountIn - amountOut
        euint128 newReserve0 = FHE.add(
            FHE.sub(fs.eReserve0, ctx.eAmount0Out),
            ctx.eAmount0In
        );
        euint128 newReserve1 = FHE.add(
            FHE.sub(fs.eReserve1, ctx.eAmount1Out),
            ctx.eAmount1In
        );

        // Verify curve in FHE (returns encrypted bool)
        ebool isValid = FHECurveLib.verify(
            ctx.fheParams,
            newReserve0,
            newReserve1
        );

        // Atomically update reserves using FHE.select
        // If valid: use new reserves. If invalid: keep old reserves (no-op)
        euint128 finalReserve0 = FHE.select(isValid, newReserve0, fs.eReserve0);
        euint128 finalReserve1 = FHE.select(isValid, newReserve1, fs.eReserve1);

        // Update storage
        CtxLib.updateFHEReserves(finalReserve0, finalReserve1);

        // Emit event with encrypted handles (not actual values)
        emit ConfidentialSwap(
            ctx.sender,
            euint128.unwrap(ctx.eAmount0In),
            euint128.unwrap(ctx.eAmount1In),
            euint128.unwrap(ctx.eAmount0Out),
            euint128.unwrap(ctx.eAmount1Out),
            ctx.to
        );

        return isValid;
    }

    /// @notice Compute encrypted fee amount
    /// @param amount The input amount
    /// @param feeRate The fee rate (scaled by 1e18)
    /// @return feeAmount The fee amount
    function computeFee(
        euint128 amount,
        euint128 feeRate
    ) internal pure returns (euint128) {
        euint128 scaleFactor = FHE.asEuint128(1e18);
        return FHEMath.mulDiv(amount, feeRate, scaleFactor);
    }

    /// @notice Apply fee to input amount
    /// @param amount The gross input amount
    /// @param feeRate The fee rate
    /// @return netAmount Amount after fee deduction
    /// @return feeAmount The fee amount
    function applyFee(
        euint128 amount,
        euint128 feeRate
    ) internal pure returns (euint128 netAmount, euint128 feeAmount) {
        feeAmount = computeFee(amount, feeRate);
        netAmount = FHE.sub(amount, feeAmount);
    }
}
