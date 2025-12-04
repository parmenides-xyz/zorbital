// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./BitMath.sol";

/// @title Tick Bitmap for Orbital
/// @notice Stores a packed mapping of tick index to its initialized state
/// @dev In Orbital, ticks are nested and centered at the equal-price point.
/// Each tick index maps to a normalized boundary k^norm = 1.0001^tick.
/// When α^norm (normalized projection of reserves) crosses k^norm,
/// a tick transitions between "interior" and "boundary" states.
library TickBitmap {
    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(uint24(tick % 256));
    }

    /// @notice Flips the initialized state for a given tick from false to true, or vice versa
    /// @dev In Orbital, each position has only ONE tick (not lowerTick/upperTick like Uniswap V3),
    /// since ticks are nested and all share the equal-price point as their center.
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick
    ) internal {
        (int16 wordPos, uint8 bitPos) = position(tick);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    /// @notice Returns the next initialized tick within one word
    /// @dev In Orbital, direction refers to α^norm movement:
    ///      - lte = true: α decreasing (toward equal-price), search lower ticks
    ///      - lte = false: α increasing (away from equal-price), search higher ticks
    /// @param self The mapping in which to search
    /// @param tick The starting tick
    /// @param lte Whether to search for the next initialized tick to the left (lower)
    /// @return next The next initialized tick (or boundary of the word)
    /// @return initialized Whether the next tick is initialized
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick;

        if (lte) {
            // α decreasing: search left (lower ticks, toward equal-price point)
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // Mask: all bits to the right of current position, including it
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;
            next = initialized
                ? (compressed - int24(uint24(bitPos - BitMath.mostSignificantBit(masked))))
                : (compressed - int24(uint24(bitPos)));
        } else {
            // α increasing: search right (higher ticks, away from equal-price point)
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // Mask: all bits to the left of current position
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;
            next = initialized
                ? (compressed + 1 + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos)))
                : (compressed + 1 + int24(uint24(type(uint8).max - bitPos)));
        }
    }
}
