// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./libraries/Tick.sol";
import "./libraries/TickBitmap.sol";
import "./libraries/Position.sol";
import "./libraries/OrbitalMath.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IZorbitalMintCallback.sol";
import "./interfaces/IZorbitalSwapCallback.sol";

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
    }

    /// @notice Maintains state for one iteration of order filling
    /// @dev In Orbital, ticks are nested boundaries around equal-price point
    struct StepState {
        // Sum of reserves at iteration start
        uint256 sumReservesStart;
        // Next initialized tick (boundary to potentially cross)
        int24 nextTick;
        // Sum of reserves at next tick boundary
        uint256 sumReservesNext;
        // Amount of input tokens consumed in this step
        uint256 amountIn;
        // Amount of output tokens produced in this step
        uint256 amountOut;
    }

    // Pool tokens (n tokens)
    address[] public tokens;

    // Packing variables that are read together
    struct Slot0 {
        // Current sum of reserves (S = Σx_i)
        uint128 sumReserves;
        // Current tick
        int24 tick;
    }
    Slot0 public slot0;

    // Sum of squared reserves (Q = Σx_i²) for torus invariant
    uint256 public sumSquaredReserves;

    // Consolidated radius, r (analogue of liquidity L)
    uint128 public r;

    // Ticks info
    mapping(int24 => Tick.Info) public ticks;
    // Tick bitmap for finding initialized ticks
    mapping(int16 => uint256) public tickBitmap;
    // Positions info
    mapping(bytes32 => Position.Info) public positions;

    constructor(
        address[] memory tokens_,
        uint128 sumReserves,
        int24 tick
    ) {
        tokens = tokens_;

        slot0 = Slot0({sumReserves: sumReserves, tick: tick});
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

        // In Orbital, positions have only ONE tick (not lowerTick/upperTick)
        // since ticks are nested and all share the equal-price point as center
        bool flipped = ticks.update(tick, amount);

        if (flipped) {
            tickBitmap.flipTick(tick);
        }

        Position.Info storage position = positions.get(owner, tick);
        position.update(amount);

        Slot0 memory slot0_ = slot0;
        amounts = new uint256[](tokens.length);
        uint256 amountPerToken = OrbitalMath.calcAmountPerToken(amount, tokens.length);

        if (slot0_.tick < tick) {
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

    function swap(
        address recipient,
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        uint256 amountSpecified,
        bytes calldata data
    ) public returns (int256 amountIn, int256 amountOut) {
        require(amountSpecified > 0, "Amount must be positive");

        Slot0 memory slot0_ = slot0;

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
            tick: slot0_.tick
        });

        // Determine swap direction based on whether S will increase or decrease
        // In Orbital, swapping in token i and out token j:
        // - S' = S + amountIn - amountOut
        // - Direction: lte = true means α decreasing (toward equal-price)
        // For simplicity, assume swaps that increase S search higher ticks
        bool lte = false; // Will be determined by price movement

        // Fill the order by iterating through ticks
        while (state.amountSpecifiedRemaining > 0) {
            StepState memory step;

            step.sumReservesStart = state.sumReserves;

            // Find next initialized tick
            (step.nextTick, ) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                lte
            );

            // TODO: Calculate sumReservesTarget from step.nextTick
            // For now, use max value (no tick boundary in this milestone)
            uint256 sumReservesTarget = type(uint128).max;

            // Compute swap step using Orbital torus invariant (Newton's method)
            (step.sumReservesNext, step.amountIn, step.amountOut) = OrbitalMath.computeSwapStep(
                tokens.length,
                state.sumReserves,
                sumReservesTarget,
                r,
                sumSquaredReserves_,
                balances[tokenInIndex],
                balances[tokenOutIndex],
                state.amountSpecifiedRemaining,
                0, // k (boundary k, 0 for interior)
                0  // s (boundary s, 0 for interior)
            );

            // Update state
            state.amountSpecifiedRemaining -= step.amountIn;
            state.amountCalculated += step.amountOut;

            // Update balances for next iteration
            balances[tokenInIndex] += step.amountIn;
            balances[tokenOutIndex] -= step.amountOut;

            // Update sumReserves
            state.sumReserves = step.sumReservesNext;

            // TODO: Update tick based on new α (implement tick crossing in later milestone)
        }

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
}
