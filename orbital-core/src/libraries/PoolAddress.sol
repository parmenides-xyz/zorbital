// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../OrbitalPool.sol";

/// @title PoolAddress
/// @notice Computes pool addresses without making external calls
library PoolAddress {
    /// @notice Computes the CREATE2 address for a pool
    /// @param factory The factory contract address
    /// @param tokens Array of token addresses (must be sorted)
    /// @param tickSpacing The tick spacing
    /// @return pool The computed pool address
    function computeAddress(
        address factory,
        address[] memory tokens,
        int24 tickSpacing
    ) internal pure returns (address pool) {
        // Verify tokens are sorted
        for (uint256 i = 1; i < tokens.length; i++) {
            require(tokens[i - 1] < tokens[i], "tokens not sorted");
        }

        // Compute the CREATE2 address:
        // address = keccak256(0xff ++ factory ++ salt ++ keccak256(creationCode))
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(tokens, tickSpacing)),
                            keccak256(type(OrbitalPool).creationCode)
                        )
                    )
                )
            )
        );
    }

    /// @notice Sort tokens in ascending order (helper for external use)
    function sortTokens(address[] memory tokens) internal pure returns (address[] memory) {
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                if (tokens[i] > tokens[j]) {
                    (tokens[i], tokens[j]) = (tokens[j], tokens[i]);
                }
            }
        }
        return tokens;
    }
}
