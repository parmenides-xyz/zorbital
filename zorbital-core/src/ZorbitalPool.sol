// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./libraries/Tick.sol";
import "./libraries/TickBitmap.sol";
import "./libraries/Position.sol";
import "./libraries/OrbitalMath.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IZorbitalMintCallback.sol";
import "./interfaces/IZorbitalSwapCallback.sol";
import "./interfaces/IZorbitalFlashCallback.sol";
import "./ZorbitalFactory.sol";

contract ZorbitalPool {
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    int24 internal constant MIN_TICK = 0;
    int24 internal constant MAX_TICK = 4055;

    /// @notice Maintains the current swap's state
    /// @dev Adapted from Uniswap V3 for Orbital's multi-token torus invariant
    struct SwapState {
        // Remaining amount of input tokens to be swapped
        uint256 amountSpecifiedRemaining;
        // Accumulated output amount calculated
        uint256 amountCalculated;
        // Current sum of reserves (S = Σx_i), analogous to sqrtPriceX96
        uint256 sumReserves;
        // Current tick
        int24 tick;
        // Current consolidated radius (analogous to liquidity L)
        uint128 r;
        // Fee growth accumulated during this swap
        uint256 feeGrowthGlobalX128;
    }

    /// @notice Maintains state for one iteration of order filling
    /// @dev In Orbital, ticks are nested boundaries around equal-price point
    struct StepState {
        // Sum of reserves at iteration start
        uint256 sumReservesStart;
        // Next initialized tick (boundary to potentially cross)
        int24 nextTick;
        // Whether the next tick is initialized
        bool initialized;
        // Sum of reserves at next tick boundary
        uint256 sumReservesNext;
        // Amount of input tokens consumed in this step
        uint256 amountIn;
        // Amount of output tokens produced in this step
        uint256 amountOut;
        // Fee amount collected in this step
        uint256 feeAmount;
    }

    // Factory that deployed this pool
    address public factory;
    // Pool tokens (n tokens, sorted)
    address[] public tokens;
    // Tick spacing for this pool
    int24 public tickSpacing;
    // Fee amount (in hundredths of basis point, e.g. 500 = 0.05%)
    uint24 public immutable fee;

    // Packing variables that are read together
    struct Slot0 {
        // Current sum of reserves (S = Σx_i)
        uint128 sumReserves;
        // Current tick
        int24 tick;
        // Whether pool has been initialized
        bool initialized;
    }
    Slot0 public slot0;

    // Sum of squared reserves (Q = Σx_i²) for torus invariant
    uint256 public sumSquaredReserves;

    // Consolidated radius, r (analogue of liquidity L)
    uint128 public r;

    // Global fee growth per unit of radius (in Q128.128)
    // For Orbital stablecoin pools, we track a single fee accumulator since all tokens are ~equal value
    uint256 public feeGrowthGlobalX128;

    // Ticks info
    mapping(int24 => Tick.Info) public ticks;
    // Tick bitmap for finding initialized ticks
    mapping(int16 => uint256) public tickBitmap;
    // Positions info
    mapping(bytes32 => Position.Info) public positions;

    /// @notice Constructor reads parameters from deployer (Inversion of Control)
    constructor() {
        (factory, tokens, tickSpacing, fee) = IZorbitalPoolDeployer(msg.sender).parameters();
    }

    error AlreadyInitialized();

    /// @notice Initialize pool with starting state (called after deployment)
    /// @param sumReserves Initial sum of reserves
    /// @param tick Initial tick
    function initialize(uint128 sumReserves, int24 tick) public {
        if (slot0.initialized) revert AlreadyInitialized();

        slot0 = Slot0({
            sumReserves: sumReserves,
            tick: tick,
            initialized: true
        });
    }

    error InvalidTickRange();
    error ZeroRadius();
    error InsufficientInputAmount();

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tick,
        uint128 amount,
        uint256[] amounts
    );

    function mint(
        address owner,
        int24 tick,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256[] memory amounts) {
        if (tick < MIN_TICK || tick > MAX_TICK) revert InvalidTickRange();
        if (amount == 0) revert ZeroRadius();

        Slot0 memory slot0_ = slot0;

        // Determine if this tick is interior (current α inside boundary)
        bool isInterior = slot0_.tick < tick;

        // In Orbital, positions have only ONE tick (not lowerTick/upperTick)
        // since ticks are nested and all share the equal-price point as center
        bool flipped = ticks.update(
            tick,
            amount,
            slot0_.tick,
            feeGrowthGlobalX128
        );

        if (flipped) {
            tickBitmap.flipTick(tick);
        }

        Position.Info storage position = positions.get(owner, tick);
        position.update(amount);

        amounts = new uint256[](tokens.length);
        uint256 amountPerToken = OrbitalMath.calcAmountPerToken(amount, tokens.length);

        if (isInterior) {
            // Position is active (current α inside boundary)
            for (uint256 i = 0; i < tokens.length; i++) {
                amounts[i] = amountPerToken;
            }

            r += amount;
        } else {
            // Position is inactive (current α at/beyond boundary)
            for (uint256 i = 0; i < tokens.length; i++) {
                amounts[i] = amountPerToken;
            }
        }

        uint256[] memory balancesBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balancesBefore[i] = balance(i);
        }

        IZorbitalMintCallback(msg.sender).zorbitalMintCallback(amounts, data);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0 && balancesBefore[i] + amounts[i] > balance(i))
                revert InsufficientInputAmount();
        }

        emit Mint(msg.sender, owner, tick, amount, amounts);
    }

    function balance(uint256 tokenIndex) internal view returns (uint256) {
        return IERC20(tokens[tokenIndex]).balanceOf(address(this));
    }

    event Swap(
        address indexed sender,
        address indexed recipient,
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        int256 amountIn,
        int256 amountOut,
        uint128 sumReserves,
        uint128 r,
        int24 tick
    );

    error NotEnoughLiquidity();
    error InvalidSumReservesLimit();

    function swap(
        address recipient,
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        uint256 amountSpecified,
        uint128 sumReservesLimit,
        bytes calldata data
    ) public returns (int256 amountIn, int256 amountOut) {
        require(amountSpecified > 0, "Amount must be positive");

        Slot0 memory slot0_ = slot0;
        uint128 r_ = r;

        // Compute current reserves from actual balances
        uint256[] memory balances = new uint256[](tokens.length);
        uint256 sumReserves_ = 0;
        uint256 sumSquaredReserves_ = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = balance(i);
            sumReserves_ += balances[i];
            sumSquaredReserves_ += balances[i] * balances[i];
        }

        // Initialize swap state
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sumReserves: sumReserves_,
            tick: slot0_.tick,
            r: r_,
            feeGrowthGlobalX128: feeGrowthGlobalX128
        });

        // Determine swap direction based on whether S will increase or decrease
        // In Orbital, swapping in token i and out token j:
        // - S' = S + amountIn - amountOut
        // - Direction: lte = true means α decreasing (toward equal-price)
        // For simplicity, assume swaps that increase S search higher ticks
        bool lte = false; // Will be determined by price movement

        // Validate sumReservesLimit (slippage protection)
        // If sumReservesLimit is 0, no limit is applied
        // Otherwise, it must be a valid limit based on swap direction
        if (sumReservesLimit != 0) {
            if (
                lte
                    ? sumReservesLimit > uint128(state.sumReserves) // moving toward equal-price, S decreases
                    : sumReservesLimit < uint128(state.sumReserves) // moving away, S increases
            ) revert InvalidSumReservesLimit();
        }

        // Fill the order by iterating through ticks
        // Stop if: amount filled OR sumReserves hits limit (slippage protection)
        while (
            state.amountSpecifiedRemaining > 0 &&
            (sumReservesLimit == 0 || uint128(state.sumReserves) != sumReservesLimit)
        ) {
            StepState memory step;

            step.sumReservesStart = state.sumReserves;

            // Find next initialized tick (save initialized flag for gas optimization)
            (step.nextTick, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                lte
            );

            // Calculate sumReservesTarget from step.nextTick
            uint256 sumReservesTarget = OrbitalMath.calcSumReservesAtTick(
                step.nextTick,
                state.r,
                tokens.length
            );

            // Cap target at sumReservesLimit if more restrictive than tick boundary
            // (mirrors Uniswap V3's sqrtPriceLimitX96 capping in computeSwapStep)

            // Deduct fee from remaining amount before computing swap
            uint256 amountRemainingLessFee = (state.amountSpecifiedRemaining * (1e6 - fee)) / 1e6;

            (step.sumReservesNext, step.amountIn, step.amountOut) = OrbitalMath.computeSwapStep(
                tokens.length,
                state.sumReserves,
                (
                    lte
                        ? sumReservesTarget < sumReservesLimit
                        : sumReservesTarget > sumReservesLimit
                )
                    ? sumReservesLimit
                    : sumReservesTarget,
                state.r,
                sumSquaredReserves_,
                balances[tokenInIndex],
                balances[tokenOutIndex],
                amountRemainingLessFee,
                0, // k (boundary k, 0 for interior)
                0  // s (boundary s, 0 for interior)
            );

            // Calculate fee amount
            bool max = step.sumReservesNext == sumReservesTarget;
            if (!max) {
                // Didn't reach target: fee is difference between what we had and what was used
                step.feeAmount = state.amountSpecifiedRemaining - step.amountIn;
            } else {
                // Reached target: calculate fee from amountIn
                step.feeAmount = (step.amountIn * fee) / (1e6 - fee);
            }

            // Update fee growth (per unit of radius)
            if (state.r > 0) {
                state.feeGrowthGlobalX128 += (step.feeAmount << 128) / state.r;
            }

            // Update state (amountIn includes fee)
            state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount);
            state.amountCalculated += step.amountOut;

            // Update balances for next iteration
            balances[tokenInIndex] += step.amountIn;
            balances[tokenOutIndex] -= step.amountOut;

            // Update sumReserves and sumSquaredReserves for next iteration
            sumSquaredReserves_ = sumSquaredReserves_
                + 2 * step.amountIn * (balances[tokenInIndex] - step.amountIn) + step.amountIn * step.amountIn
                - 2 * step.amountOut * (balances[tokenOutIndex] + step.amountOut) + step.amountOut * step.amountOut;
            state.sumReserves = step.sumReservesNext;

            // Check if we reached a tick boundary (like Uniswap V3's sqrtPriceX96 == sqrtPriceNextX96)
            if (state.sumReserves == sumReservesTarget) {
                // We reached the tick boundary
                if (step.initialized) {
                    // Cross the tick: get radius and update fee tracking
                    uint128 rDelta = ticks.cross(step.nextTick, state.feeGrowthGlobalX128);

                    // In Orbital with nested ticks (from Orbital.md "Crossing Ticks"):
                    // - lte (toward equal-price, α decreasing): add rDelta (tick becomes interior)
                    // - !lte (away from equal-price, α increasing): subtract rDelta (tick becomes boundary)
                    if (lte) {
                        state.r = state.r + rDelta;
                    } else {
                        state.r = state.r - rDelta;
                    }

                    if (state.r == 0) revert NotEnoughLiquidity();
                }

                // Update tick: step past the boundary
                state.tick = lte ? step.nextTick - 1 : step.nextTick;
            } else {
                // Stayed within range, no tick update needed
            }
        }

        // Update global r if it changed (gas optimization: only write if different)
        if (r_ != state.r) r = state.r;

        // Update global fee growth
        feeGrowthGlobalX128 = state.feeGrowthGlobalX128;

        // Update slot0 only if state changed (gas optimization)
        if (state.tick != slot0_.tick) {
            (slot0.sumReserves, slot0.tick) = (uint128(state.sumReserves), state.tick);
        } else {
            slot0.sumReserves = uint128(state.sumReserves);
        }

        // Calculate final amounts
        amountIn = int256(amountSpecified - state.amountSpecifiedRemaining);
        amountOut = -int256(state.amountCalculated);

        // Transfer output tokens to recipient
        IERC20(tokens[tokenOutIndex]).transfer(recipient, uint256(-amountOut));

        // Callback for input token transfer
        uint256 balanceBefore = balance(tokenInIndex);
        IZorbitalSwapCallback(msg.sender).zorbitalSwapCallback(
            tokenInIndex,
            tokenOutIndex,
            amountIn,
            amountOut,
            data
        );
        if (balanceBefore + uint256(amountIn) > balance(tokenInIndex))
            revert InsufficientInputAmount();

        emit Swap(
            msg.sender,
            recipient,
            tokenInIndex,
            tokenOutIndex,
            amountIn,
            amountOut,
            slot0.sumReserves,
            r,
            slot0.tick
        );
    }

    event Flash(address indexed sender, uint256[] amounts);

    error FlashLoanNotRepaid();

    /// @notice Flash loan: borrow tokens and repay in same transaction
    /// @param amounts Array of amounts to borrow for each token
    /// @param data Arbitrary data passed to callback
    function flash(
        uint256[] calldata amounts,
        bytes calldata data
    ) public {
        // Record balances before
        uint256[] memory balancesBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balancesBefore[i] = balance(i);
        }

        // Transfer requested amounts to caller
        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                IERC20(tokens[i]).transfer(msg.sender, amounts[i]);
            }
        }

        // Call the callback - caller must repay here
        IZorbitalFlashCallback(msg.sender).zorbitalFlashCallback(data);

        // Verify balances haven't decreased
        for (uint256 i = 0; i < tokens.length; i++) {
            if (balance(i) < balancesBefore[i]) revert FlashLoanNotRepaid();
        }

        emit Flash(msg.sender, amounts);
    }
}
