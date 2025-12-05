// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./zOrbital.sol";

/// @title zOrbitalFactory - Factory for creating private Sphere AMM pools
/// @notice Creates zOrbital pools with CREATE2 for deterministic addresses
contract zOrbitalFactory is IzOrbitalDeployer {
    // Pool parameters - set temporarily during createPool (Inversion of Control)
    address internal _factory;
    address[] internal _tokens;
    uint64 internal _radius;

    // Registry: salt => pool address
    mapping(bytes32 => address) public pools;

    // All created pools
    address[] public allPools;

    event PoolCreated(address[] tokens, uint64 radius, address pool);

    error TokensMustBeDifferent();
    error InvalidTokenCount();
    error TokenCannotBeZero();
    error PoolAlreadyExists();
    error InvalidRadius();

    function parameters() external view returns (
        address factory,
        address[] memory tokens,
        uint64 radius
    ) {
        return (_factory, _tokens, _radius);
    }

    /// @notice Creates a new zOrbital pool for the given tokens
    /// @param tokens Array of FHERC20 token addresses (will be sorted)
    /// @param radius The sphere radius parameter
    /// @return pool Address of the created pool
    function createPool(
        address[] memory tokens,
        uint64 radius
    ) public returns (address pool) {
        // Validate radius
        if (radius == 0) revert InvalidRadius();

        // Validate token count (need at least 2 tokens)
        if (tokens.length < 2) revert InvalidTokenCount();

        // Sort tokens for consistent salt computation
        tokens = sortTokens(tokens);

        // Validate: no zero addresses and no duplicates
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert TokenCannotBeZero();
            if (i > 0 && tokens[i] == tokens[i - 1]) revert TokensMustBeDifferent();
        }

        // Check if pool already exists (identified by tokens + radius)
        bytes32 salt = keccak256(abi.encodePacked(tokens, radius));
        if (pools[salt] != address(0)) revert PoolAlreadyExists();

        // Set parameters for pool constructor to read (Inversion of Control)
        _factory = address(this);
        _tokens = tokens;
        _radius = radius;

        // Deploy pool with CREATE2
        pool = address(
            new zOrbital{salt: salt}()
        );

        // Clean up parameters
        delete _factory;
        delete _tokens;
        delete _radius;

        // Register pool
        pools[salt] = pool;
        allPools.push(pool);

        emit PoolCreated(tokens, radius, pool);
    }

    /// @notice Get pool address for given tokens and radius
    /// @param tokens Array of token addresses (will be sorted)
    /// @param radius The sphere radius
    /// @return pool Address of the pool (or zero if not exists)
    function getPool(
        address[] memory tokens,
        uint64 radius
    ) public view returns (address pool) {
        tokens = sortTokens(tokens);
        bytes32 salt = keccak256(abi.encodePacked(tokens, radius));
        return pools[salt];
    }

    /// @notice Get total number of pools created
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
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
