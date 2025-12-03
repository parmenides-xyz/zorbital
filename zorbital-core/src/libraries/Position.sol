// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @title Position library for Orbital AMM
/// @notice Manages liquidity positions and fee accumulation
/// @dev Unlike Uniswap V3, Orbital has a single fee accumulator (stablecoins ~equal value)
library Position {
    // Q128.128 fixed point constant
    uint256 internal constant Q128 = 1 << 128;

    struct Info {
        // Radius provided by this position
        uint128 r;
        // Fee growth inside the position's boundary, last time fees were collected
        uint256 feeGrowthInsideLastX128;
        // Tokens owed to the position owner (accumulated fees)
        uint128 tokensOwed;
    }

    /// @notice Update a position with new radius and calculate owed tokens
    /// @param self The position to update
    /// @param rDelta The change in radius (positive for add, negative for remove)
    /// @param feeGrowthInsideX128 Current fee growth inside the position's boundary
    function update(
        Info storage self,
        int128 rDelta,
        uint256 feeGrowthInsideX128
    ) internal {
        // Calculate tokens owed from fee growth since last update
        // tokensOwed = (feeGrowthInside - feeGrowthInsideLast) * r / Q128
        uint128 tokensOwed = uint128(
            ((feeGrowthInsideX128 - self.feeGrowthInsideLastX128) * self.r) / Q128
        );

        // Update radius (handle both add and remove)
        if (rDelta < 0) {
            self.r = self.r - uint128(-rDelta);
        } else {
            self.r = self.r + uint128(rDelta);
        }

        // Update fee growth tracker
        self.feeGrowthInsideLastX128 = feeGrowthInsideX128;

        // Accumulate tokens owed
        if (tokensOwed > 0) {
            self.tokensOwed += tokensOwed;
        }
    }

    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tick
    ) internal view returns (Position.Info storage position) {
        position = self[keccak256(abi.encodePacked(owner, tick))];
    }
}
