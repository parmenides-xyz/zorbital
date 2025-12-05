// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IFHERC20} from "./interfaces/IFHERC20.sol";
import {FHE, InEuint64, euint64, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title zOrbital - Private + n-dimensional AMM
/// @notice Fully private swaps using FHE coprocessor

interface IzOrbitalDeployer {
    function parameters() external view returns (
        address factory,
        address[] memory tokens,
        uint64 radius
    );
}

contract zOrbital {
    // ============ State ============

    /// @notice Factory that created this pool
    address public immutable factory;

    /// @notice Array of FHERC20 tokens in the pool
    IFHERC20[] public tokens;

    /// @notice Number of tokens in the pool
    uint256 public immutable n;

    /// @notice Encrypted liquidity reserves for each token
    mapping(uint256 => euint64) public liquidity;

    /// @notice Sphere radius parameter (encrypted)
    euint64 public radius;

    /// @notice Total LP shares
    euint64 public s_totalShares;

    /// @notice User LP shares
    mapping(address => euint64) public s_userLiquidityShares;

    // ============ Constants ============

    euint64 private immutable ZERO;
    euint64 private immutable ONE;
    euint64 private immutable TWO;

    /// @notice Number of Newton-Raphson iterations for sqrt (no decryption)
    uint256 private constant SQRT_ITERATIONS = 8;

    // ============ Events ============

    event Swap(uint256 indexed tokenInIndex, uint256 indexed tokenOutIndex);
    event LiquidityAdded(address indexed provider);
    event LiquidityRemoved(address indexed provider);

    // ============ Constructor ============

    /// @notice Creates pool - reads parameters from factory (Inversion of Control)
    constructor() {
        // Read parameters from factory
        (address _factory, address[] memory _tokens, uint64 _radius) =
            IzOrbitalDeployer(msg.sender).parameters();

        require(_tokens.length >= 2, "Need at least 2 tokens");

        factory = _factory;
        n = _tokens.length;

        for (uint256 i = 0; i < _tokens.length; i++) {
            tokens.push(IFHERC20(_tokens[i]));
        }

        // Initialize FHE constants
        ZERO = FHE.asEuint64(0);
        ONE = FHE.asEuint64(1);
        TWO = FHE.asEuint64(2);
        radius = FHE.asEuint64(_radius);
        s_totalShares = ZERO;

        // Initialize liquidity to zero for all tokens
        for (uint256 i = 0; i < n; i++) {
            liquidity[i] = ZERO;
            FHE.allowThis(liquidity[i]);
        }

        FHE.allowThis(ZERO);
        FHE.allowThis(ONE);
        FHE.allowThis(TWO);
        FHE.allowThis(radius);
        FHE.allowThis(s_totalShares);
    }

    // ============ Swap Function ============

    /// @notice Swap tokens using the sphere AMM formula
    /// @dev Sphere constraint: Σ(r - xᵢ)² = r²
    /// @param tokenInIndex Index of token being sold
    /// @param tokenOutIndex Index of token being bought
    /// @param sellAmountIn Encrypted amount to sell
    function swap(
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        InEuint64 calldata sellAmountIn
    ) external {
        require(tokenInIndex < n && tokenOutIndex < n, "Invalid token index");
        require(tokenInIndex != tokenOutIndex, "Same token");

        euint64 sellAmount = FHE.asEuint64(sellAmountIn);

        // Transfer in the sell token (transfer 0 to others to hide direction)
        for (uint256 i = 0; i < n; i++) {
            euint64 transferAmount = FHE.select(
                FHE.eq(FHE.asEuint64(uint64(i)), FHE.asEuint64(uint64(tokenInIndex))),
                sellAmount,
                ZERO
            );
            FHE.allow(transferAmount, address(tokens[i]));
            tokens[i].confidentialTransferFrom(msg.sender, address(this), transferAmount);
        }

        // Calculate output amount using sphere formula
        // After adding sellAmount to tokenIn reserve:
        // newReserveIn = liquidity[tokenInIndex] + sellAmount
        //
        // Sphere constraint: Σ(r - xᵢ)² = r²
        // (r - newReserveIn)² + (r - newReserveOut)² + Σ_{k≠in,out}(r - xₖ)² = r²
        //
        // Solving for newReserveOut:
        // (r - newReserveOut)² = r² - (r - newReserveIn)² - Σ_{k≠in,out}(r - xₖ)²
        // newReserveOut = r - sqrt(r² - (r - newReserveIn)² - Σ_{k≠in,out}(r - xₖ)²)

        euint64 newReserveIn = FHE.add(liquidity[tokenInIndex], sellAmount);

        // Calculate sum of (r - xₖ)² for all k except tokenOut
        euint64 sumSquares = ZERO;
        for (uint256 k = 0; k < n; k++) {
            if (k == tokenOutIndex) continue;

            euint64 reserve = (k == tokenInIndex) ? newReserveIn : liquidity[k];
            euint64 diff = FHE.sub(radius, reserve);
            euint64 diffSquared = FHE.mul(diff, diff);
            sumSquares = FHE.add(sumSquares, diffSquared);
        }

        // (r - newReserveOut)² = r² - sumSquares
        euint64 radiusSquared = FHE.mul(radius, radius);
        euint64 outDiffSquared = FHE.sub(radiusSquared, sumSquares);

        // newReserveOut = r - sqrt(outDiffSquared)
        euint64 outDiff = _sqrtFHE(outDiffSquared);
        euint64 newReserveOut = FHE.sub(radius, outDiff);

        // amountOut = oldReserveOut - newReserveOut
        euint64 amountOut = FHE.sub(liquidity[tokenOutIndex], newReserveOut);

        // Update liquidity
        liquidity[tokenInIndex] = newReserveIn;
        liquidity[tokenOutIndex] = newReserveOut;

        FHE.allowThis(liquidity[tokenInIndex]);
        FHE.allowThis(liquidity[tokenOutIndex]);

        // Transfer out the bought token (transfer 0 from others to hide direction)
        for (uint256 i = 0; i < n; i++) {
            euint64 transferAmount = FHE.select(
                FHE.eq(FHE.asEuint64(uint64(i)), FHE.asEuint64(uint64(tokenOutIndex))),
                amountOut,
                ZERO
            );
            FHE.allow(transferAmount, address(tokens[i]));
            tokens[i].confidentialTransfer(msg.sender, transferAmount);
        }

        emit Swap(tokenInIndex, tokenOutIndex);
    }

    // ============ Liquidity Functions ============

    /// @notice Add liquidity to the pool
    /// @param maxAmounts Maximum amounts of each token to deposit
    function addLiquidity(InEuint64[] calldata maxAmounts) external {
        require(maxAmounts.length == n, "Wrong number of amounts");

        euint64[] memory amounts = new euint64[](n);
        for (uint256 i = 0; i < n; i++) {
            amounts[i] = FHE.asEuint64(maxAmounts[i]);
        }

        // Check if this is first liquidity provision
        ebool isFirstLiquidity = FHE.eq(s_totalShares, ZERO);

        // For first liquidity, use provided amounts directly
        // For subsequent, calculate proportional amounts based on sphere constraint
        euint64[] memory optAmounts = new euint64[](n);

        for (uint256 i = 0; i < n; i++) {
            // Simple approach: accept max amounts (could be optimized)
            optAmounts[i] = amounts[i];

            FHE.allow(optAmounts[i], address(tokens[i]));
            tokens[i].confidentialTransferFrom(msg.sender, address(this), optAmounts[i]);
        }

        // Calculate LP shares: sqrt of product of first two amounts (simplified)
        euint64 shareProduct = FHE.mul(optAmounts[0], optAmounts[1]);
        euint64 poolShares = _sqrtFHE(shareProduct);

        // Update liquidity for all tokens
        for (uint256 i = 0; i < n; i++) {
            liquidity[i] = FHE.add(liquidity[i], optAmounts[i]);
            FHE.allowThis(liquidity[i]);
        }

        // Update shares
        s_totalShares = FHE.add(s_totalShares, poolShares);
        s_userLiquidityShares[msg.sender] = FHE.add(s_userLiquidityShares[msg.sender], poolShares);

        FHE.allowThis(s_totalShares);
        FHE.allowThis(s_userLiquidityShares[msg.sender]);
        FHE.allow(s_userLiquidityShares[msg.sender], msg.sender);

        emit LiquidityAdded(msg.sender);
    }

    // ============ FHE Square Root (No Decryption) ============

    /// @notice Compute square root using Newton-Raphson with fixed iterations
    /// @dev No decryption needed - purely FHE operations
    /// @param y The value to compute sqrt of
    /// @return z The approximate square root
    function _sqrtFHE(euint64 y) internal returns (euint64 z) {
        // Newton-Raphson: x_{n+1} = (x_n + y/x_n) / 2
        // Starting guess: y / 2 + 1

        // Check if y is zero or very small
        ebool isSmall = FHE.lte(y, FHE.asEuint64(3));

        // Initial guess: y/2 + 1
        euint64 x = FHE.add(FHE.div(y, TWO), ONE);

        // Fixed number of iterations (no branching on encrypted values)
        for (uint256 i = 0; i < SQRT_ITERATIONS; i++) {
            // x = (y/x + x) / 2
            euint64 yDivX = FHE.div(y, x);
            euint64 sum = FHE.add(yDivX, x);
            x = FHE.div(sum, TWO);
        }

        // For small values (0-3), result is 0 for y=0, 1 otherwise
        euint64 smallResult = FHE.select(FHE.eq(y, ZERO), ZERO, ONE);

        // Return small result for small inputs, Newton-Raphson result otherwise
        z = FHE.select(isSmall, smallResult, x);

        FHE.allowThis(z);
        return z;
    }

    // ============ View Functions ============

    /// @notice Get number of tokens in pool
    function getTokenCount() external view returns (uint256) {
        return n;
    }

    /// @notice Get token address at index
    function getToken(uint256 index) external view returns (address) {
        require(index < n, "Invalid index");
        return address(tokens[index]);
    }
}
