// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./ZorbitalPool.sol";

interface IZorbitalPoolDeployer {
    function parameters() external view returns (
        address factory,
        address[] memory tokens,
        int24 tickSpacing
    );
}

contract ZorbitalFactory is IZorbitalPoolDeployer {
    // Supported tick spacings (10 for stablecoins, 60 for others)
    mapping(int24 => bool) public tickSpacings;

    // Pool parameters - set temporarily during createPool (Inversion of Control)
    address internal _factory;
    address[] internal _tokens;
    int24 internal _tickSpacing;

    // Registry: salt => pool address
    mapping(bytes32 => address) public pools;

    event PoolCreated(address[] tokens, int24 tickSpacing, address pool);

    error TokensMustBeDifferent();
    error InvalidTokenCount();
    error TokenCannotBeZero();
    error PoolAlreadyExists();
    error UnsupportedTickSpacing();

    constructor() {
        tickSpacings[10] = true;  // High precision for stablecoins
        tickSpacings[60] = true;  // Lower precision for volatile pairs
    }

    function parameters() external view returns (
        address factory,
        address[] memory tokens,
        int24 tickSpacing
    ) {
        return (_factory, _tokens, _tickSpacing);
    }

    /// @notice Creates a new Orbital pool for the given tokens
    /// @param tokens Array of token addresses (will be sorted)
    /// @param tickSpacing The tick spacing for this pool
    /// @return pool Address of the created pool
    function createPool(
        address[] memory tokens,
        int24 tickSpacing
    ) public returns (address pool) {
        // Validate tick spacing
        if (!tickSpacings[tickSpacing]) revert UnsupportedTickSpacing();

        // Validate token count (need at least 2 tokens)
        if (tokens.length < 2) revert InvalidTokenCount();

        // Sort tokens for consistent salt computation
        tokens = sortTokens(tokens);

        // Validate: no zero addresses and no duplicates
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert TokenCannotBeZero();
            if (i > 0 && tokens[i] == tokens[i - 1]) revert TokensMustBeDifferent();
        }

        // Check if pool already exists
        bytes32 salt = keccak256(abi.encodePacked(tokens, tickSpacing));
        if (pools[salt] != address(0)) revert PoolAlreadyExists();

        // Set parameters for pool constructor to read (Inversion of Control)
        _factory = address(this);
        _tokens = tokens;
        _tickSpacing = tickSpacing;

        // Deploy pool with CREATE2
        pool = address(
            new ZorbitalPool{salt: salt}()
        );

        // Clean up parameters
        delete _factory;
        delete _tokens;
        delete _tickSpacing;

        // Register pool
        pools[salt] = pool;

        emit PoolCreated(tokens, tickSpacing, pool);
    }

    /// @notice Get pool address for given tokens and tick spacing
    /// @param tokens Array of token addresses (will be sorted)
    /// @param tickSpacing The tick spacing
    /// @return pool Address of the pool (or zero if not exists)
    function getPool(
        address[] memory tokens,
        int24 tickSpacing
    ) public view returns (address pool) {
        tokens = sortTokens(tokens);
        bytes32 salt = keccak256(abi.encodePacked(tokens, tickSpacing));
        return pools[salt];
    }

    /// @notice Sort tokens in ascending order
    function sortTokens(address[] memory tokens) internal pure returns (address[] memory) {
        // Simple bubble sort (fine for small arrays like 2-8 tokens)
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
