// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @title Tick library for Orbital AMM
library Tick {
    struct Info {
        bool initialized;
        uint128 rGross;
        uint128 rNet;
        uint256 feeGrowthOutsideX128;
    }

    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int128 rDelta,
        int24 currentTick,
        uint256 feeGrowthGlobalX128
    ) internal returns (bool flipped) {
        Tick.Info storage tickInfo = self[tick];
        uint128 rGrossBefore = tickInfo.rGross;
        uint128 rGrossAfter;

        if (rDelta < 0) {
            rGrossAfter = rGrossBefore - uint128(-rDelta);
        } else {
            rGrossAfter = rGrossBefore + uint128(rDelta);
        }

        flipped = (rGrossAfter == 0) != (rGrossBefore == 0);

        if (rGrossBefore == 0) {
            tickInfo.initialized = true;
            if (currentTick < tick) {
                tickInfo.feeGrowthOutsideX128 = feeGrowthGlobalX128;
            }
        }

        tickInfo.rGross = rGrossAfter;
        if (rDelta < 0) {
            tickInfo.rNet = tickInfo.rNet - uint128(-rDelta);
        } else {
            tickInfo.rNet = tickInfo.rNet + uint128(rDelta);
        }
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

        info.feeGrowthOutsideX128 = feeGrowthGlobalX128 - info.feeGrowthOutsideX128;

        rNet = info.rNet;
    }

    /// @notice Get fee growth inside a position's boundary
    /// @param self The mapping of tick info
    /// @param tick The position's boundary tick
    /// @param currentTick The current tick
    /// @param feeGrowthGlobalX128 Current global fee growth
    /// @return feeGrowthInsideX128 Fee growth inside the position's boundary
    function getFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 currentTick,
        uint256 feeGrowthGlobalX128
    ) internal view returns (uint256 feeGrowthInsideX128) {
        Tick.Info storage tickInfo = self[tick];

        if (currentTick < tick) {
            feeGrowthInsideX128 = feeGrowthGlobalX128 - tickInfo.feeGrowthOutsideX128;
        } else {
            feeGrowthInsideX128 = tickInfo.feeGrowthOutsideX128;
        }
    }
}
