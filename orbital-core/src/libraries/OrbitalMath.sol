// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "solmate/utils/FixedPointMathLib.sol";

/// @title OrbitalMath
/// @notice Math library for Orbital AMM calculations
library OrbitalMath {
    using FixedPointMathLib for uint256;

    uint256 internal constant WAD = 1e18;

    /// @notice Base for tick calculations: 1.0001 in WAD
    uint256 internal constant TICK_BASE = 1000100000000000000;

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

    /// @notice Calculates radius from a single token amount (inverse of calcAmountPerToken)
    /// @dev r = amount / (1 - 1/√n)
    /// @param amount The token amount
    /// @param n The number of tokens in the pool
    /// @return radius The radius that corresponds to this amount
    function calcRadiusForAmount(
        uint256 amount,
        uint256 n
    ) internal pure returns (uint128 radius) {
        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);
        uint256 invSqrtN = WAD.mulDivDown(WAD, sqrtN);
        uint256 factor = WAD - invSqrtN;
        radius = uint128(amount.mulDivDown(WAD, factor));
    }

    /// @notice Calculates radius from multiple token amounts (picks minimum)
    /// @dev Like Uniswap V3's getLiquidityForAmounts, picks the limiting factor
    /// @param amounts Array of token amounts
    /// @return radius The maximum radius that can be provided with these amounts
    function calcRadiusForAmounts(
        uint256[] memory amounts
    ) internal pure returns (uint128 radius) {
        require(amounts.length > 0, "Empty amounts");
        uint256 minAmount = amounts[0];
        for (uint256 i = 1; i < amounts.length; i++) {
            if (amounts[i] < minAmount) {
                minAmount = amounts[i];
            }
        }
        radius = calcRadiusForAmount(minAmount, amounts.length);
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

    /// @notice Calculates the normalized boundary k^norm = 1.0001^tick
    /// @param tick The tick index (>= 0)
    /// @return kNorm The normalized boundary value (in WAD)
    function tickToKNorm(int24 tick) internal pure returns (uint256 kNorm) {
        kNorm = WAD;
        uint256 base = TICK_BASE;
        uint24 t = uint24(tick);
        while (t > 0) {
            if (t & 1 != 0) {
                kNorm = kNorm.mulWadDown(base);
            }
            base = base.mulWadDown(base);
            t >>= 1;
        }
    }

    /// @notice Calculates k^norm_min = √n - 1 (minimum valid normalized boundary)
    /// @dev From spec: the minimal tick boundary is the equal price point
    /// @param n The number of tokens
    /// @return kNormMin The minimum valid k^norm value (in WAD)
    function kNormMin(uint256 n) internal pure returns (uint256) {
        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);
        return sqrtN - WAD;  // √n - 1
    }

    /// @notice Calculates k^norm_max = (n-1)/√n (maximum valid normalized boundary)
    /// @dev From spec: the maximal tick is where one reserve hits 0, others at r
    /// @param n The number of tokens
    /// @return kNormMax The maximum valid k^norm value (in WAD)
    function kNormMax(uint256 n) internal pure returns (uint256) {
        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);
        return ((n - 1) * WAD).mulDivDown(WAD, sqrtN);  // (n-1)/√n
    }

    /// @notice Validates that a tick's k^norm is within valid bounds for n tokens
    /// @param tick The tick index
    /// @param n The number of tokens
    /// @return valid True if the tick is within valid bounds
    function isValidTick(int24 tick, uint256 n) internal pure returns (bool valid) {
        if (tick < 0) return false;
        uint256 kNorm = tickToKNorm(tick);
        return kNorm >= kNormMin(n) && kNorm <= kNormMax(n);
    }

    /// @notice Calculates the sum of reserves S at which α^norm = k^norm
    function calcSumReservesAtTick(
        int24 tick,
        uint256 radius,
        uint256 n
    ) internal pure returns (uint256 sumReserves) {
        uint256 kNorm = tickToKNorm(tick);
        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);
        sumReserves = kNorm.mulWadDown(radius).mulWadDown(sqrtN);
    }

    /// @notice Calculates the boundary k and s values for a tick
    /// @dev Per spec: k = k^norm * r (unnormalized), s = √(r² - (k - r√n)²)
    /// Used when a tick transitions to boundary state
    /// @param tick The tick index
    /// @param radius The radius contribution at this tick (rNet)
    /// @param n The number of tokens
    /// @return k The tick's unnormalized k value (k = k^norm * r)
    /// @return s The boundary s value
    function calcBoundaryKS(
        int24 tick,
        uint256 radius,
        uint256 n
    ) internal pure returns (uint256 k, uint256 s) {
        uint256 kNorm = tickToKNorm(tick);
        k = kNorm.mulWadDown(radius);  // k = k^norm * r (unnormalized)

        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);
        uint256 rSqrtN = radius.mulWadDown(sqrtN);  // r√n
        uint256 diff = k > rSqrtN ? k - rSqrtN : rSqrtN - k;
        uint256 diffSquared = diff.mulWadDown(diff);
        uint256 rSquared = radius.mulWadDown(radius);

        if (rSquared > diffSquared) {
            uint256 sSquared = rSquared - diffSquared;
            s = FixedPointMathLib.sqrt(sSquared * WAD);
        } else {
            s = 0;
        }
    }

    /// @notice Calculates input/output amounts to reach a target sumReserves
    /// @dev Analogous to Uniswap V3's calcAmount0Delta - uses Newton's method
    function calcAmountToTarget(
        uint256 n,
        uint256 sumReservesCurrent,
        uint256 sumReservesTarget,
        uint256 radius,
        uint256 sumSquaredReserves,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 k,
        uint256 s
    ) internal pure returns (uint256 amountIn, uint256 amountOut) {
        int256 delta = int256(sumReservesTarget) - int256(sumReservesCurrent);

        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);
        uint256 rSqrtN = radius * sqrtN / WAD;
        uint256 rSquared = radius * radius;

        // Newton iteration to find y (output amount)
        // With d = delta + y, we solve for y such that invariant holds
        uint256 y = balanceOut / 2;
        uint256 prevY;

        for (uint256 i = 0; i < 255; ++i) {
            prevY = y;
            int256 dSigned = delta + int256(y);
            if (dSigned < 0) {
                y = y / 2;
                continue;
            }
            uint256 d = uint256(dSigned);
            uint256 S = sumReservesTarget;
            uint256 Q = sumSquaredReserves + 2 * d * balanceIn + d * d;
            if (2 * y * balanceOut > Q + y * y) {
                y = y / 2;
                continue;
            }
            Q = Q - 2 * y * balanceOut + y * y;

            uint256 alpha = S * WAD / sqrtN;
            int256 u = int256(alpha) - int256(k) - int256(rSqrtN);

            int256 nQ = int256(n * Q);
            int256 S2 = int256(S) * int256(S);
            int256 wSquaredSigned = (nQ - S2) / int256(n);
            uint256 w = wSquaredSigned > 0 ? FixedPointMathLib.sqrt(uint256(wSquaredSigned)) : 0;

            int256 wMinusS = int256(w) - int256(s);
            int256 fVal = u * u + wMinusS * wMinusS - int256(rSquared);

            if (w == 0) w = WAD; // Use 1e18 to maintain scaling
            int256 dQdy = 2 * (int256(balanceIn) + int256(d) - int256(balanceOut) + int256(y));
            int256 fPrime = 2 * wMinusS * dQdy / int256(2 * w);

            if (fPrime == 0) break;

            int256 step = fVal / fPrime;

            if (step >= 0) {
                y = uint256(step) > y ? 0 : y - uint256(step);
            } else {
                y = y + uint256(-step);
            }

            if (y > balanceOut) y = balanceOut;

            unchecked {
                if (y > prevY) {
                    if (y - prevY <= 1) break;
                } else if (prevY - y <= 1) {
                    break;
                }
            }
        }

        amountOut = y;
        // d = delta + y, but ensure non-negative
        amountIn = delta >= 0 ? uint256(delta) + y : (y > uint256(-delta) ? y - uint256(-delta) : 0);
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
        uint256 sumAfterIn = sumReservesCurrent + amountRemaining;
        uint256 sumSqAfterIn = sumSquaredReserves + 2 * amountRemaining * balanceIn + amountRemaining * amountRemaining;

        uint256 A = sumAfterIn - balanceOut;
        uint256 B = sumSqAfterIn - balanceOut * balanceOut;

        uint256 sqrtN = FixedPointMathLib.sqrt(n * WAD * WAD);
        uint256 rSqrtN = radius * sqrtN / WAD;
        uint256 rSquared = radius * radius;

        uint256 y = balanceOut > amountRemaining ? balanceOut - amountRemaining : balanceOut / 2;
        uint256 prevY;

        for (uint256 i = 0; i < 255; ++i) {
            prevY = y;

            // S' = A + y, Q' = B + y²
            uint256 S = A + y;
            uint256 Q = B + y * y;

            uint256 alpha = S * WAD / sqrtN;
            int256 u = int256(alpha) - int256(k) - int256(rSqrtN);

            int256 nQ = int256(n * Q);
            int256 S2 = int256(S) * int256(S);
            int256 wSquaredSigned = (nQ - S2) / int256(n);

            uint256 w = wSquaredSigned > 0 ? FixedPointMathLib.sqrt(uint256(wSquaredSigned)) : 0;

            int256 wMinusS = int256(w) - int256(s);
            int256 fVal = u * u + wMinusS * wMinusS - int256(rSquared);

            int256 dudy = int256(WAD * WAD / sqrtN);
            int256 dwdy_numer = int256(n - 1) * int256(y) - int256(A);

            if (w == 0) w = WAD; // Use 1e18 to maintain scaling

            int256 term1 = 2 * u * dudy / int256(WAD);
            int256 term2 = 2 * wMinusS * dwdy_numer / int256(n * w);
            int256 fPrime = term1 + term2;

            if (fPrime == 0) break;

            int256 step = fVal / fPrime;

            uint256 maxStep = y / 2;
            if (step >= 0) {
                uint256 absStep = uint256(step);
                if (absStep > maxStep) absStep = maxStep;
                y = absStep > y ? 0 : y - absStep;
            } else {
                uint256 absStep = uint256(-step);
                if (absStep > maxStep) absStep = maxStep;
                y = y + absStep;
            }

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

        amountOut = balanceOut - y;
        sumReservesNext = sumReservesCurrent + amountRemaining - amountOut;
        amountIn = amountRemaining;

        bool increasing = sumReservesCurrent <= sumReservesTarget;
        bool crossesBoundary = increasing
            ? sumReservesNext > sumReservesTarget
            : sumReservesNext < sumReservesTarget;

        if (crossesBoundary) {
            (amountIn, amountOut) = calcAmountToTarget(
                n,
                sumReservesCurrent,
                sumReservesTarget,
                radius,
                sumSquaredReserves,
                balanceIn,
                balanceOut,
                k,
                s
            );
            sumReservesNext = sumReservesTarget;
        }
    }
}
