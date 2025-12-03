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

    /// @notice Maintains the current swap's state
    struct SwapState {
        // Remaining amount of input tokens to be swapped
        uint256 amountSpecifiedRemaining;
        // Accumulated output amount calculated
        uint256 amountCalculated;
        // Current sum of reserves (S = Σx_i), analogous to sqrtPriceX96
        uint256 sumReserves;
        // Current tick
        int24 tick;
        // Current consolidated interior radius
        uint128 r;
        // Boundary tick state for torus invariant
        uint256 kBound;
        uint256 sBound;
        // Fee growth accumulated during this swap
        uint256 feeGrowthGlobalX128;
    }

    /// @notice Maintains state for one iteration of order filling
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

    // Consolidated interior radius, r_int (analogue of liquidity L)
    uint128 public r;

    // Boundary tick state (for torus invariant)
    // kBound = sum of k values for all boundary ticks
    // sBound = sum of s values for all boundary ticks
    uint256 public kBound;
    uint256 public sBound;

    // Global fee growth per unit of radius
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

    /// @notice Initialize pool with starting state
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
    error InsufficientPosition();

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tick,
        uint128 amount,
        uint256[] amounts
    );

    event Burn(
        address indexed owner,
        int24 indexed tick,
        uint128 amount,
        uint256[] amounts
    );

    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tick,
        uint128 amount
    );

    struct ModifyPositionParams {
        address owner;
        int24 tick;
        int128 rDelta;
    }

    /// @notice Internal function to modify a position (add or remove liquidity)
    /// @dev Used by both mint() and burn()
    function _modifyPosition(
        ModifyPositionParams memory params
    ) internal returns (Position.Info storage position, int256[] memory amounts) {
        // Validate tick is within valid k^norm bounds for this pool's n
        // k^norm_min = √n - 1, k^norm_max = (n-1)/√n
        if (!OrbitalMath.isValidTick(params.tick, tokens.length)) revert InvalidTickRange();

        Slot0 memory slot0_ = slot0;

        // Update tick state
        bool flipped = ticks.update(
            params.tick,
            params.rDelta,
            slot0_.tick,
            feeGrowthGlobalX128
        );

        if (flipped) {
            tickBitmap.flipTick(params.tick);
        }

        // Get fee growth inside this position's boundary
        uint256 feeGrowthInsideX128 = ticks.getFeeGrowthInside(
            params.tick,
            slot0_.tick,
            feeGrowthGlobalX128
        );

        // Update position with fee tracking
        position = positions.get(params.owner, params.tick);
        position.update(params.rDelta, feeGrowthInsideX128);

        // Calculate token amounts
        amounts = new int256[](tokens.length);
        uint256 absRDelta = params.rDelta < 0 ? uint128(-params.rDelta) : uint128(params.rDelta);
        uint256 amountPerToken = OrbitalMath.calcAmountPerToken(uint128(absRDelta), tokens.length);

        // Determine if this tick is interior (current α inside boundary)
        bool isInterior = slot0_.tick < params.tick;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (params.rDelta < 0) {
                amounts[i] = -int256(amountPerToken);
            } else {
                amounts[i] = int256(amountPerToken);
            }
        }

        // Update global state based on whether position is interior or boundary
        if (isInterior) {
            // Interior tick: update consolidated radius r
            if (params.rDelta < 0) {
                r -= uint128(-params.rDelta);
            } else {
                r += uint128(params.rDelta);
            }
        } else {
            // Boundary tick: update kBound and sBound
            (uint256 kDelta, uint256 sDelta) = OrbitalMath.calcBoundaryKS(
                params.tick,
                absRDelta,
                tokens.length
            );
            if (params.rDelta < 0) {
                kBound = kBound > kDelta ? kBound - kDelta : 0;
                sBound = sBound > sDelta ? sBound - sDelta : 0;
            } else {
                kBound += kDelta;
                sBound += sDelta;
            }
        }
    }

    function mint(
        address owner,
        int24 tick,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256[] memory amounts) {
        if (amount == 0) revert ZeroRadius();

        (Position.Info storage position, int256[] memory amountsInt) = _modifyPosition(
            ModifyPositionParams({
                owner: owner,
                tick: tick,
                rDelta: int128(uint128(amount))
            })
        );

        // Convert to uint256 amounts for callback
        amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = uint256(amountsInt[i]);
        }

        // Callback for token transfer
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

    /// @notice Remove liquidity from a position
    /// @param tick The position's boundary tick
    /// @param amount The amount of radius to remove
    /// @return amounts The token amounts removed (added to tokensOwed)
    function burn(
        int24 tick,
        uint128 amount
    ) external returns (uint256[] memory amounts) {
        (Position.Info storage position, int256[] memory amountsInt) = _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                tick: tick,
                rDelta: -int128(uint128(amount))
            })
        );

        // Convert to uint256 amounts (they come back negative from _modifyPosition)
        amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = uint256(-amountsInt[i]);
        }

        // Add burned amounts to tokensOwed
        // Note: In Orbital with single accumulator, we track total tokens owed
        // The burned amounts represent the LP's share that can be collected
        if (amounts[0] > 0) {
            // All token amounts are equal for Orbital stablecoin pools
            position.tokensOwed += uint128(amounts[0] * tokens.length);
        }

        emit Burn(msg.sender, tick, amount, amounts);
    }

    /// @notice Collect tokens owed to a position (burned liquidity + fees)
    /// @param recipient Address to receive the tokens
    /// @param tick The position's boundary tick
    /// @param amountRequested Maximum amount to collect
    /// @return amount The actual amount collected
    function collect(
        address recipient,
        int24 tick,
        uint128 amountRequested
    ) external returns (uint128 amount) {
        Position.Info storage position = positions.get(msg.sender, tick);

        // Collect up to the requested amount
        amount = amountRequested > position.tokensOwed
            ? position.tokensOwed
            : amountRequested;

        if (amount > 0) {
            position.tokensOwed -= amount;

            // Distribute equally across all tokens (Orbital stablecoin pool)
            uint256 amountPerToken = amount / tokens.length;
            for (uint256 i = 0; i < tokens.length; i++) {
                IERC20(tokens[i]).transfer(recipient, amountPerToken);
            }
        }

        emit Collect(msg.sender, recipient, tick, amount);
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

        // Initialize swap state (including boundary tick state)
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sumReserves: sumReserves_,
            tick: slot0_.tick,
            r: r_,
            kBound: kBound,
            sBound: sBound,
            feeGrowthGlobalX128: feeGrowthGlobalX128
        });

        // Determine swap direction based on whether we're moving toward or away from equal-price
        // In Orbital, the equal-price point is where all reserves are equal.
        // - lte = true: moving toward equal-price (α decreasing, reserves becoming more equal)
        // - lte = false: moving away from equal-price (α increasing, reserves becoming more unequal)
        //
        // When swapping in token i and out token j:
        // - If balanceIn < balanceOut: adding to low side, removing from high → toward equal (lte = true)
        // - If balanceIn > balanceOut: adding to high side, removing from low → away (lte = false)
        bool lte = balances[tokenInIndex] < balances[tokenOutIndex];

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
        // Stop if: amount filled OR sumReserves hits limit
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
                state.kBound, // Boundary k (sum of all boundary tick k values)
                state.sBound  // Boundary s (sum of all boundary tick s values)
            );

            // Calculate fee amount
            bool max = step.sumReservesNext == sumReservesTarget;
            if (!max) {
                // Didn't reach target
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

            // Check if we reached a tick boundary
            if (state.sumReserves == sumReservesTarget) {
                // We reached the tick boundary
                if (step.initialized) {
                    // Cross the tick: get radius and update fee tracking
                    uint128 rDelta = ticks.cross(step.nextTick, state.feeGrowthGlobalX128);

                    // Compute k and s for boundary tick state (like Uniswap computes liquidityNet)
                    (uint256 kDelta, uint256 sDelta) = OrbitalMath.calcBoundaryKS(
                        step.nextTick,
                        rDelta,
                        tokens.length
                    );

                    // In Orbital with nested ticks (from Orbital.md "Crossing Ticks"):
                    // - lte (toward equal-price, α decreasing): tick becomes interior
                    //   → add rDelta to r, subtract k/s from boundary
                    // - !lte (away from equal-price, α increasing): tick becomes boundary
                    //   → subtract rDelta from r, add k/s to boundary
                    if (lte) {
                        state.r = state.r + rDelta;
                        state.kBound = state.kBound > kDelta ? state.kBound - kDelta : 0;
                        state.sBound = state.sBound > sDelta ? state.sBound - sDelta : 0;
                    } else {
                        state.r = state.r - rDelta;
                        state.kBound = state.kBound + kDelta;
                        state.sBound = state.sBound + sDelta;
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

        // Update global boundary tick state
        kBound = state.kBound;
        sBound = state.sBound;

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
