// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./ZorbitalPool.sol";

interface IZorbitalPoolDeployer {
    function parameters() external view returns (
        address factory,
        address[] memory tokens,
        int24 tickSpacing,
        uint24 fee
    );
}

contract ZorbitalFactory is IZorbitalPoolDeployer {
    // Fee amounts map to tick spacings
    // Fee is in hundredths of a basis point (1 = 0.0001%, 500 = 0.05%, 3000 = 0.3%)
    mapping(uint24 => int24) public fees;

    // Pool parameters - set temporarily during createPool (Inversion of Control)
    address internal _factory;
    address[] internal _tokens;
    int24 internal _tickSpacing;
    uint24 internal _fee;

    // Registry: salt => pool address
    mapping(bytes32 => address) public pools;

    event PoolCreated(address[] tokens, uint24 fee, address pool);

    error TokensMustBeDifferent();
    error InvalidTokenCount();
    error TokenCannotBeZero();
    error PoolAlreadyExists();
    error UnsupportedFee();

    constructor() {
        fees[500] = 10;   // 0.05% fee -> tick spacing 10 (stablecoins)
        fees[3000] = 60;  // 0.3% fee -> tick spacing 60 (volatile pairs)
    }

    function parameters() external view returns (
        address factory,
        address[] memory tokens,
        int24 tickSpacing,
        uint24 fee
    ) {
        return (_factory, _tokens, _tickSpacing, _fee);
    }

    /// @notice Creates a new Orbital pool for the given tokens
    /// @param tokens Array of token addresses (will be sorted)
    /// @param fee The fee amount (500 = 0.05%, 3000 = 0.3%)
    /// @return pool Address of the created pool
    function createPool(
        address[] memory tokens,
        uint24 fee
    ) public returns (address pool) {
        // Validate fee and get tick spacing
        int24 tickSpacing = fees[fee];
        if (tickSpacing == 0) revert UnsupportedFee();

        // Validate token count (need at least 2 tokens)
        if (tokens.length < 2) revert InvalidTokenCount();

        // Sort tokens for consistent salt computation
        tokens = sortTokens(tokens);

        // Validate: no zero addresses and no duplicates
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert TokenCannotBeZero();
            if (i > 0 && tokens[i] == tokens[i - 1]) revert TokensMustBeDifferent();
        }

        // Check if pool already exists (identified by tokens + fee)
        bytes32 salt = keccak256(abi.encodePacked(tokens, fee));
        if (pools[salt] != address(0)) revert PoolAlreadyExists();

        // Set parameters for pool constructor to read (Inversion of Control)
        _factory = address(this);
        _tokens = tokens;
        _tickSpacing = tickSpacing;
        _fee = fee;

        // Deploy pool with CREATE2
        pool = address(
            new ZorbitalPool{salt: salt}()
        );

        // Clean up parameters
        delete _factory;
        delete _tokens;
        delete _tickSpacing;
        delete _fee;

        // Register pool
        pools[salt] = pool;

        emit PoolCreated(tokens, fee, pool);
    }

    /// @notice Get pool address for given tokens and fee
    /// @param tokens Array of token addresses (will be sorted)
    /// @param fee The fee amount
    /// @return pool Address of the pool (or zero if not exists)
    function getPool(
        address[] memory tokens,
        uint24 fee
    ) public view returns (address pool) {
        tokens = sortTokens(tokens);
        bytes32 salt = keccak256(abi.encodePacked(tokens, fee));
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
