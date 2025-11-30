// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {FHE, euint128, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {FHEMath} from "../math/FHEMath.sol";
import {IEulerSwap} from "../interfaces/IEulerSwap.sol";

/// @title FHE Curve Library
/// @notice FHE-compatible curve verification for EulerSwap
/// @dev Translates CurveLib logic to work with encrypted values using FHE.select
library FHECurveLib {
    using FHEMath for euint128;
    using FHEMath for ebool;

    /// @notice Encrypted version of DynamicParams for curve operations
    /// @dev All values that need to be compared with encrypted reserves must be encrypted
    struct FHEDynamicParams {
        euint128 equilibriumReserve0;
        euint128 equilibriumReserve1;
        euint128 minReserve0;
        euint128 minReserve1;
        euint128 priceX;
        euint128 priceY;
        euint128 concentrationX;
        euint128 concentrationY;
        euint128 maxReserve;  // type(uint112).max as encrypted
        euint128 scaleFactor; // 1e18 as encrypted
    }

    /// @notice Convert plaintext DynamicParams to encrypted FHEDynamicParams
    function toFHEParams(IEulerSwap.DynamicParams memory p) internal pure returns (FHEDynamicParams memory fp) {
        fp.equilibriumReserve0 = FHE.asEuint128(p.equilibriumReserve0);
        fp.equilibriumReserve1 = FHE.asEuint128(p.equilibriumReserve1);
        fp.minReserve0 = FHE.asEuint128(p.minReserve0);
        fp.minReserve1 = FHE.asEuint128(p.minReserve1);
        fp.priceX = FHE.asEuint128(p.priceX);
        fp.priceY = FHE.asEuint128(p.priceY);
        fp.concentrationX = FHE.asEuint128(p.concentrationX);
        fp.concentrationY = FHE.asEuint128(p.concentrationY);
        fp.maxReserve = FHE.asEuint128(type(uint112).max);
        fp.scaleFactor = FHE.asEuint128(1e18);
    }

    /// @notice Returns encrypted bool indicating if reserve amounts satisfy the curve
    /// @dev Replaces all if/else branches with FHE.select for constant-time execution
    /// @param fp Encrypted dynamic parameters
    /// @param newReserve0 Encrypted new reserve for token 0
    /// @param newReserve1 Encrypted new reserve for token 1
    /// @return isValid Encrypted boolean - true if curve is satisfied
    function verify(
        FHEDynamicParams memory fp,
        euint128 newReserve0,
        euint128 newReserve1
    ) internal pure returns (ebool) {
        // Check 1: Overflow check (newReserve <= type(uint112).max)
        ebool reserve0InBounds = FHE.lte(newReserve0, fp.maxReserve);
        ebool reserve1InBounds = FHE.lte(newReserve1, fp.maxReserve);
        ebool boundsOk = FHEMath.and(reserve0InBounds, reserve1InBounds);

        // Check 2: Minimum reserve check
        ebool reserve0AboveMin = FHE.gte(newReserve0, fp.minReserve0);
        ebool reserve1AboveMin = FHE.gte(newReserve1, fp.minReserve1);
        ebool minsOk = FHEMath.and(reserve0AboveMin, reserve1AboveMin);

        // Check 3: Equilibrium region checks
        ebool aboveEquil0 = FHE.gte(newReserve0, fp.equilibriumReserve0);
        ebool aboveEquil1 = FHE.gte(newReserve1, fp.equilibriumReserve1);
        ebool belowEquil1 = FHE.lt(newReserve1, fp.equilibriumReserve1);

        // Compute f() for both possible branches (constant-time)
        // Branch 1: newReserve0 >= equilibrium0, check against f(reserve1, priceY, priceX, ...)
        euint128 threshold1 = f(
            newReserve1,
            fp.priceY,
            fp.priceX,
            fp.equilibriumReserve1,
            fp.equilibriumReserve0,
            fp.concentrationY,
            fp.scaleFactor
        );

        // Branch 2: newReserve0 < equilibrium0, check against f(reserve0, priceX, priceY, ...)
        euint128 threshold2 = f(
            newReserve0,
            fp.priceX,
            fp.priceY,
            fp.equilibriumReserve0,
            fp.equilibriumReserve1,
            fp.concentrationX,
            fp.scaleFactor
        );

        // Evaluate conditions for each branch
        // Case 1: aboveEquil0 && aboveEquil1 => true
        ebool case1Valid = FHEMath.and(aboveEquil0, aboveEquil1);

        // Case 2: aboveEquil0 && !aboveEquil1 => newReserve0 >= threshold1
        ebool case2Condition = FHEMath.and(aboveEquil0, belowEquil1);
        ebool case2Check = FHE.gte(newReserve0, threshold1);

        // Case 3: !aboveEquil0 && belowEquil1 => false
        ebool case3Condition = FHEMath.and(FHEMath.not(aboveEquil0), belowEquil1);
        // case3 is always invalid, so we don't compute a check

        // Case 4: !aboveEquil0 && aboveEquil1 => newReserve1 >= threshold2
        ebool case4Condition = FHEMath.and(FHEMath.not(aboveEquil0), aboveEquil1);
        ebool case4Check = FHE.gte(newReserve1, threshold2);

        // Combine all cases:
        // valid = case1Valid || (case2Condition && case2Check) || (case4Condition && case4Check)
        // Note: case3 is always false

        ebool case2Valid = FHEMath.and(case2Condition, case2Check);
        ebool case4Valid = FHEMath.and(case4Condition, case4Check);

        ebool curveValid = FHEMath.or(case1Valid, FHEMath.or(case2Valid, case4Valid));

        // Final result: bounds && mins && curveValid
        ebool allChecksPass = FHEMath.and(boundsOk, FHEMath.and(minsOk, curveValid));

        return allChecksPass;
    }

    /// @notice FHE version of the curve function f()
    /// @dev Computes output y for input x on the EulerSwap curve
    /// @param x Input reserve value
    /// @param px Price parameter X
    /// @param py Price parameter Y
    /// @param x0 Equilibrium reserve for input token
    /// @param y0 Equilibrium reserve for output token
    /// @param c Concentration parameter (0 to 1e18)
    /// @param scaleFactor 1e18 as encrypted value
    /// @return y Output reserve value
    function f(
        euint128 x,
        euint128 px,
        euint128 py,
        euint128 x0,
        euint128 y0,
        euint128 c,
        euint128 scaleFactor
    ) internal pure returns (euint128) {
        // Check if c == 1e18 (constant-sum curve)
        ebool isConstantSum = FHE.eq(c, scaleFactor);

        // Compute constant-sum result: y0 + ((x0 - x) * px) / py
        euint128 constantSumResult = computeConstantSum(x, px, py, x0, y0);

        // Compute general curve result: y0 + (a * b) / d
        // where a = px * (x0 - x), b = c * x + (1e18 - c) * x0, d = 1e18 * x * py
        euint128 generalResult = computeGeneralCurve(x, px, py, x0, y0, c, scaleFactor);

        // Select based on curve type
        return FHE.select(isConstantSum, constantSumResult, generalResult);
    }

    /// @notice Compute constant-sum curve output
    /// @dev y = y0 + ((x0 - x) * px) / py
    function computeConstantSum(
        euint128 x,
        euint128 px,
        euint128 py,
        euint128 x0,
        euint128 y0
    ) internal pure returns (euint128) {
        // (x0 - x) - using saturating sub to handle underflow
        euint128 diff = FHEMath.saturatingSub(x0, x);

        // ((x0 - x) * px) / py, rounded up
        euint128 v = FHEMath.divUp(FHE.mul(diff, px), py);

        // y0 + v
        return FHE.add(y0, v);
    }

    /// @notice Compute general curve output
    /// @dev y = y0 + (a * b) / d
    /// where a = px * (x0 - x), b = c * x + (1e18 - c) * x0, d = 1e18 * x * py
    function computeGeneralCurve(
        euint128 x,
        euint128 px,
        euint128 py,
        euint128 x0,
        euint128 y0,
        euint128 c,
        euint128 scaleFactor
    ) internal pure returns (euint128) {
        // a = px * (x0 - x)
        euint128 diff = FHEMath.saturatingSub(x0, x);
        euint128 a = FHE.mul(px, diff);

        // b = c * x + (1e18 - c) * x0
        euint128 oneMinusC = FHE.sub(scaleFactor, c);
        euint128 term1 = FHE.mul(c, x);
        euint128 term2 = FHE.mul(oneMinusC, x0);
        euint128 b = FHE.add(term1, term2);

        // d = 1e18 * x * py
        euint128 d = FHE.mul(FHE.mul(scaleFactor, x), py);

        // v = (a * b) / d, rounded up (saturating)
        euint128 v = FHEMath.saturatingMulDivUp(a, b, d);

        // y0 + v (saturating)
        return FHEMath.saturatingAdd(y0, v);
    }
}
