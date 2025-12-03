// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "solmate/utils/FixedPointMathLib.sol";

/// @title OrbitalMath
/// @notice Math library for Orbital AMM calculations
library OrbitalMath {
    using FixedPointMathLib for uint256;

    uint256 internal constant WAD = 1e18;

    /// @notice Calculates the amount of each token needed when minting at equal-price point
    /// @dev amount_i = rDelta * (1 - 1/√n) for each token
    /// @param rDelta The radius being added
    /// @param n The number of tokens in the pool
    /// @return amount The amount of each token needed
    function calcAmountPerToken(
        uint128 rDelta,
        uint256 n
    ) internal pure returns (uint256 amount) {
        // sqrtN = √n (in WAD)
        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);

        // invSqrtN = 1/√n = WAD/sqrtN (in WAD)
        uint256 invSqrtN = WAD.mulDivDown(WAD, sqrtN);

        // factor = (1 - 1/√n) in WAD
        uint256 factor = WAD - invSqrtN;

        // amount = rDelta * factor / WAD
        amount = uint256(rDelta).mulWadDown(factor);
    }

    /// @notice Calculates the reserve at equal-price point for a given radius
    /// @dev x_base = r * (1 - 1/√n)
    /// @param radius The total radius
    /// @param n The number of tokens in the pool
    /// @return reserve The reserve of each token at equal-price point
    function calcEqualPriceReserve(
        uint128 radius,
        uint256 n
    ) internal pure returns (uint256 reserve) {
        reserve = calcAmountPerToken(radius, n);
    }

    /// @notice Calculates the projection α = (1/√n) * Σxᵢ
    /// @dev α is the component of reserves parallel to v⃗ = (1/√n)(1,1,...,1)
    /// @param sumReserves The sum of all reserves (Σxᵢ)
    /// @param n The number of tokens
    /// @return alpha The projection value
    function calcAlpha(
        uint256 sumReserves,
        uint256 n
    ) internal pure returns (uint256 alpha) {
        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);
        alpha = sumReserves.mulDivDown(WAD, sqrtN);
    }

    /// @notice The swap calculation didn't converge
    error SwapDidNotConverge();

    /// @notice Computes swap amounts within one tick range using Newton-Raphson iteration
    /// @dev Adapted from Uniswap V3's SwapMath.computeSwapStep for Orbital's torus invariant.
    ///      Uses Newton's method like Balancer's StableMath.computeBalance.
    ///      Invariant: r² = (S/√n - k - r√n)² + (√(Q - S²/n) - s)²
    /// @param n Number of tokens
    /// @param sumReservesCurrent Current sum of reserves (S)
    /// @param sumReservesTarget Target sum of reserves at tick boundary
    /// @param radius Current radius (r)
    /// @param sumSquaredReserves Current sum of squared reserves (Q)
    /// @param balanceIn Current balance of input token
    /// @param balanceOut Current balance of output token
    /// @param amountRemaining Remaining input amount to swap
    /// @param k Boundary k value (0 for interior)
    /// @param s Boundary s value (0 for interior)
    /// @return sumReservesNext New sum of reserves after swap step
    /// @return amountIn Amount of input tokens consumed
    /// @return amountOut Amount of output tokens produced
    function computeSwapStep(
        uint256 n,
        uint256 sumReservesCurrent,
        uint256 sumReservesTarget,
        uint256 radius,
        uint256 sumSquaredReserves,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountRemaining,
        uint256 k,
        uint256 s
    )
        internal
        pure
        returns (
            uint256 sumReservesNext,
            uint256 amountIn,
            uint256 amountOut
        )
    {
        // After adding input: S' = S + d, Q' = Q + 2*d*balanceIn + d²
        uint256 sumAfterIn = sumReservesCurrent + amountRemaining;
        uint256 sumSqAfterIn = sumSquaredReserves + 2 * amountRemaining * balanceIn + amountRemaining * amountRemaining;

        // Constants for Newton iteration (excluding the output token)
        // A = S' - balanceOut, B = Q' - balanceOut²
        uint256 A = sumAfterIn - balanceOut;
        uint256 B = sumSqAfterIn - balanceOut * balanceOut;

        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);
        uint256 rSqrtN = radius * sqrtN / WAD;
        uint256 rSquared = radius * radius;

        // Newton iteration to find new output balance (y)
        uint256 y = balanceOut; // Initial guess
        uint256 prevY;

        for (uint256 i = 0; i < 255; ++i) {
            prevY = y;

            // S' = A + y, Q' = B + y²
            uint256 S = A + y;
            uint256 Q = B + y * y;

            // u = S/√n - k - r√n
            uint256 alpha = S * WAD / sqrtN;
            int256 u = int256(alpha) - int256(k) - int256(rSqrtN);

            // ||w||² = Q - S²/n = (nQ - S²) / n
            // During iteration, nQ - S² might be negative; use signed math
            int256 nQ = int256(n * Q);
            int256 S2 = int256(S) * int256(S);
            int256 wSquaredSigned = (nQ - S2) / int256(n);

            // w = sqrt(max(0, wSquared)) - if negative, we're outside valid region
            uint256 w = wSquaredSigned > 0 ? FixedPointMathLib.sqrt(uint256(wSquaredSigned)) : 0;

            // f(y) = u² + (w - s)² - r²
            int256 wMinusS = int256(w) - int256(s);
            int256 fVal = u * u + wMinusS * wMinusS - int256(rSquared);

            // f'(y) = 2u/√n + 2(w-s) * ((n-1)y - A) / (nw)
            int256 dudy = int256(WAD * WAD / sqrtN);
            int256 dwdy_numer = int256(n - 1) * int256(y) - int256(A);

            if (w == 0) w = 1;

            int256 term1 = 2 * u * dudy / int256(WAD);
            int256 term2 = 2 * wMinusS * dwdy_numer / int256(n * w);
            int256 fPrime = term1 + term2;

            if (fPrime == 0) break;

            // Newton step: y_new = y - f(y) / f'(y)
            int256 step = fVal * int256(WAD) / fPrime;

            if (step >= 0) {
                y = uint256(step) > y ? 0 : y - uint256(step);
            } else {
                y = y + uint256(-step);
            }

            // Bound y to prevent underflow in amountOut calculation
            // y must be <= balanceOut (we're removing tokens, not adding)
            if (y > balanceOut) {
                y = balanceOut;
            }

            // Convergence check
            unchecked {
                if (y > prevY) {
                    if (y - prevY <= 1) break;
                } else if (prevY - y <= 1) {
                    break;
                }
            }
        }

        // Compute output and new sum of reserves
        amountOut = balanceOut - y;
        sumReservesNext = sumReservesCurrent + amountRemaining - amountOut;
        amountIn = amountRemaining;

        // Check if we crossed the tick boundary
        bool increasing = sumReservesCurrent <= sumReservesTarget;
        bool crossesBoundary = increasing
            ? sumReservesNext > sumReservesTarget
            : sumReservesNext < sumReservesTarget;

        if (crossesBoundary) {
            // Cap at target boundary
            sumReservesNext = sumReservesTarget;
        }
    }
}
