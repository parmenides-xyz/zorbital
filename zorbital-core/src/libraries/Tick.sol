// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @title Tick library for Orbital AMM
/// @notice In Orbital, ticks are nested boundaries around the equal-price point.
/// Unlike Uniswap V3 where ticks have lower/upper pairs, Orbital ticks have a single
/// boundary at distance k from the equal-price point.
///
/// Key concepts from Orbital.md:
/// - Interior tick: α^norm < k^norm (reserves inside boundary, contributes to r_int)
/// - Boundary tick: α^norm = k^norm (reserves pinned at plane, contributes to s_bound)
/// - When α increases past k^norm: interior → boundary, subtract r from r_int
/// - When α decreases below k^norm: boundary → interior, add r to r_int
library Tick {
    struct Info {
        bool initialized;
        // Total radius at this tick (for flip detection, like liquidityGross)
        uint128 rGross;
        // Radius to add/subtract when crossing (always positive in Orbital)
        // Direction of crossing determines whether to add or subtract
        uint128 rNet;
        // Fee growth per unit radius outside this tick (when α was beyond boundary)
        // For Orbital, we track a single fee accumulator (stablecoins are ~equal value)
        uint256 feeGrowthOutsideX128;
    }

    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint128 rDelta,
        int24 currentTick,
        uint256 feeGrowthGlobalX128
    ) internal returns (bool flipped) {
        Tick.Info storage tickInfo = self[tick];
        uint128 rGrossBefore = tickInfo.rGross;
        uint128 rGrossAfter = rGrossBefore + rDelta;

        flipped = (rGrossAfter == 0) != (rGrossBefore == 0);

        if (rGrossBefore == 0) {
            tickInfo.initialized = true;
            // Initialize feeGrowthOutside: by convention, assume all fees were
            // accumulated "outside" (when α was below this tick) if currentTick < tick
            if (currentTick < tick) {
                tickInfo.feeGrowthOutsideX128 = feeGrowthGlobalX128;
            }
        }

        tickInfo.rGross = rGrossAfter;
        // In Orbital with nested ticks, rNet simply accumulates the radius
        // (always positive - direction determines add/subtract when crossing)
        tickInfo.rNet = tickInfo.rNet + rDelta;
    }

    /// @notice Cross a tick and update fee tracking
    /// @dev Called when a swap crosses this tick boundary
    /// @param self The mapping of tick info
    /// @param tick The tick being crossed
    /// @param feeGrowthGlobalX128 Current global fee growth
    /// @return rNet The radius to add/subtract
    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobalX128
    ) internal returns (uint128 rNet) {
        Tick.Info storage info = self[tick];

        // Update fee growth outside: flip the perspective
        info.feeGrowthOutsideX128 = feeGrowthGlobalX128 - info.feeGrowthOutsideX128;

        rNet = info.rNet;
    }
}
