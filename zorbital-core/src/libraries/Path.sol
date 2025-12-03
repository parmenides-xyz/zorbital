// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @title Path
/// @notice Library for encoding/decoding multi-pool swap paths for Orbital
/// @dev Path format: tokenIn (20 bytes) + poolAddress (20 bytes) + tokenOut (20 bytes) + [poolAddress + tokenOut]...
/// Unlike Uniswap V3 which uses tokenIn + tickSpacing + tokenOut, Orbital pools have n tokens
/// so we use pool addresses directly instead of deriving them.
library Path {

    /// @dev The length of a bytes encoded address
    uint256 private constant ADDR_SIZE = 20;

    /// @dev The offset of a single token address + pool address
    uint256 private constant NEXT_OFFSET = ADDR_SIZE + ADDR_SIZE; // 40 bytes

    /// @dev The offset of an encoded pool hop (tokenIn + poolAddress + tokenOut)
    uint256 private constant POP_OFFSET = ADDR_SIZE + ADDR_SIZE + ADDR_SIZE; // 60 bytes

    /// @dev The minimum length of a path that contains 2 or more pools
    uint256 private constant MULTIPLE_POOLS_MIN_LENGTH = POP_OFFSET + NEXT_OFFSET; // 100 bytes

    /// @notice Returns the number of pools in the path
    /// @param path The encoded swap path
    /// @return The number of pools in the path
    function numPools(bytes memory path) internal pure returns (uint256) {
        // Path structure: tokenIn + (poolAddress + tokenOut) * numPools
        // So: path.length = ADDR_SIZE + (NEXT_OFFSET * numPools)
        // numPools = (path.length - ADDR_SIZE) / NEXT_OFFSET
        return (path.length - ADDR_SIZE) / NEXT_OFFSET;
    }

    /// @notice Returns true if the path contains two or more pools
    /// @param path The encoded swap path
    /// @return True if path contains two or more pools
    function hasMultiplePools(bytes memory path) internal pure returns (bool) {
        return path.length >= MULTIPLE_POOLS_MIN_LENGTH;
    }

    /// @notice Returns the first pool in the path
    /// @param path The encoded swap path
    /// @return The first pool's encoded data (tokenIn + poolAddress + tokenOut)
    function getFirstPool(bytes memory path) internal pure returns (bytes memory) {
        return slice(path, 0, POP_OFFSET);
    }

    /// @notice Skips a token + pool in the path and returns the remainder
    /// @param path The encoded swap path
    /// @return The remaining path after skipping the first token + pool
    function skipToken(bytes memory path) internal pure returns (bytes memory) {
        return slice(path, NEXT_OFFSET, path.length - NEXT_OFFSET);
    }

    /// @notice Decodes the first pool in the path
    /// @param path The encoded swap path
    /// @return tokenIn The input token address
    /// @return pool The pool address
    /// @return tokenOut The output token address
    function decodeFirstPool(bytes memory path)
        internal
        pure
        returns (
            address tokenIn,
            address pool,
            address tokenOut
        )
    {
        tokenIn = toAddress(path, 0);
        pool = toAddress(path, ADDR_SIZE);
        tokenOut = toAddress(path, NEXT_OFFSET);
    }

    // ============ Bytes Utilities ============

    /// @notice Extracts an address from bytes at a given offset
    function toAddress(bytes memory _bytes, uint256 _start)
        internal
        pure
        returns (address)
    {
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := mload(add(add(_bytes, 0x14), _start))
        }

        return tempAddress;
    }

    /// @notice Extracts a slice from bytes
    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory) {
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                // Update free-memory pointer
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            default {
                tempBytes := mload(0x40)
                mstore(tempBytes, 0)
                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }
}
