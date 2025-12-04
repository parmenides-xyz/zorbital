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

    struct SwapState {
        uint256 amountSpecifiedRemaining;
        uint256 amountCalculated;
        uint256 sumReserves;
        int24 tick;
        uint128 r;
        uint256 kBound;
        uint256 sBound;
        uint256 feeGrowthGlobalX128;
    }

    struct StepState {
        uint256 sumReservesStart;
        int24 nextTick;
        bool initialized;
        uint256 sumReservesNext;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
    }

    address public factory;
    address[] public tokens;
    int24 public tickSpacing;
    uint24 public immutable fee;

    struct Slot0 {
        uint128 sumReserves;
        int24 tick;
        bool initialized;
    }
    Slot0 public slot0;

    uint256 public sumSquaredReserves;
    uint128 public r;
    uint256 public kBound;
    uint256 public sBound;
    uint256 public feeGrowthGlobalX128;

    mapping(int24 => Tick.Info) public ticks;
    mapping(int16 => uint256) public tickBitmap;
    mapping(bytes32 => Position.Info) public positions;

    /// @notice Constructor reads parameters from deployer (Inversion of Control)
    constructor() {
        (factory, tokens, tickSpacing, fee) = IZorbitalPoolDeployer(msg.sender).parameters();
    }

    error AlreadyInitialized();

    /// @notice Initialize pool with starting state
    /// @param initialSumReserves Initial sum of reserves
    /// @param tick Initial tick
    /// @dev Assumes pool starts at equal-price point (all balances equal)
    function initialize(uint128 initialSumReserves, int24 tick) public {
        if (slot0.initialized) revert AlreadyInitialized();

        slot0 = Slot0({
            sumReserves: initialSumReserves,
            tick: tick,
            initialized: true
        });

        uint256 n = tokens.length;
        uint256 S = initialSumReserves;
        sumSquaredReserves = (S * S) / n;
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
        if (!OrbitalMath.isValidTick(params.tick, tokens.length)) revert InvalidTickRange();

        Slot0 memory slot0_ = slot0;

        bool flipped = ticks.update(
            params.tick,
            params.rDelta,
            slot0_.tick,
            feeGrowthGlobalX128
        );

        if (flipped) {
            tickBitmap.flipTick(params.tick);
        }

        uint256 feeGrowthInsideX128 = ticks.getFeeGrowthInside(
            params.tick,
            slot0_.tick,
            feeGrowthGlobalX128
        );

        position = positions.get(params.owner, params.tick);
        position.update(params.rDelta, feeGrowthInsideX128);

        amounts = new int256[](tokens.length);
        uint256 absRDelta = params.rDelta < 0 ? uint128(-params.rDelta) : uint128(params.rDelta);
        uint256 amountPerToken = OrbitalMath.calcAmountPerToken(uint128(absRDelta), tokens.length);

        bool isInterior = slot0_.tick < params.tick;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (params.rDelta < 0) {
                amounts[i] = -int256(amountPerToken);
            } else {
                amounts[i] = int256(amountPerToken);
            }
        }

        if (isInterior) {
            if (params.rDelta < 0) {
                r -= uint128(-params.rDelta);
            } else {
                r += uint128(params.rDelta);
            }
        } else {
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

        (, int256[] memory amountsInt) = _modifyPosition(
            ModifyPositionParams({
                owner: owner,
                tick: tick,
                rDelta: int128(uint128(amount))
            })
        );

        amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = uint256(amountsInt[i]);
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

        uint256 a = amounts[0];  // All amounts equal in Orbital
        uint256 n = tokens.length;
        uint256 oldS = slot0.sumReserves;
        slot0.sumReserves = uint128(oldS + n * a);
        sumSquaredReserves = sumSquaredReserves + 2 * a * oldS + n * a * a;

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

        amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = uint256(-amountsInt[i]);
        }

        if (amounts[0] > 0) {
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

        amount = amountRequested > position.tokensOwed
            ? position.tokensOwed
            : amountRequested;

        if (amount > 0) {
            position.tokensOwed -= amount;

            uint256 amountPerToken = amount / tokens.length;
            for (uint256 i = 0; i < tokens.length; i++) {
                IERC20(tokens[i]).transfer(recipient, amountPerToken);
            }

            uint256 n = tokens.length;
            uint256 oldS = slot0.sumReserves;
            slot0.sumReserves = uint128(oldS - n * amountPerToken);
            sumSquaredReserves = sumSquaredReserves + n * amountPerToken * amountPerToken - 2 * amountPerToken * oldS;
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

        uint256 balanceIn = balance(tokenInIndex);
        uint256 balanceOut = balance(tokenOutIndex);

        uint256 sumSquaredReserves_ = sumSquaredReserves;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sumReserves: slot0_.sumReserves,
            tick: slot0_.tick,
            r: r_,
            kBound: kBound,
            sBound: sBound,
            feeGrowthGlobalX128: feeGrowthGlobalX128
        });

        bool lte = balanceIn < balanceOut;

        if (sumReservesLimit != 0) {
            if (
                lte
                    ? sumReservesLimit > uint128(state.sumReserves)
                    : sumReservesLimit < uint128(state.sumReserves)
            ) revert InvalidSumReservesLimit();
        }

        while (
            state.amountSpecifiedRemaining > 0 &&
            (sumReservesLimit == 0 || uint128(state.sumReserves) != sumReservesLimit)
        ) {
            StepState memory step;

            step.sumReservesStart = state.sumReserves;

            (step.nextTick, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                lte
            );

            uint256 sumReservesTarget = OrbitalMath.calcSumReservesAtTick(
                step.nextTick,
                state.r,
                tokens.length
            );

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
                balanceIn,
                balanceOut,
                amountRemainingLessFee,
                state.kBound,
                state.sBound
            );

            bool max = step.sumReservesNext == sumReservesTarget;
            if (!max) {
                step.feeAmount = state.amountSpecifiedRemaining - step.amountIn;
            } else {
                step.feeAmount = (step.amountIn * fee) / (1e6 - fee);
            }

            if (state.r > 0) {
                state.feeGrowthGlobalX128 += (step.feeAmount << 128) / state.r;
            }

            state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount);
            state.amountCalculated += step.amountOut;

            sumSquaredReserves_ = sumSquaredReserves_
                + 2 * step.amountIn * balanceIn + step.amountIn * step.amountIn
                - 2 * step.amountOut * balanceOut + step.amountOut * step.amountOut;

            balanceIn += step.amountIn;
            balanceOut -= step.amountOut;
            state.sumReserves = step.sumReservesNext;

            if (state.sumReserves == sumReservesTarget) {
                if (step.initialized) {
                    uint128 rDelta = ticks.cross(step.nextTick, state.feeGrowthGlobalX128);

                    (uint256 kDelta, uint256 sDelta) = OrbitalMath.calcBoundaryKS(
                        step.nextTick,
                        rDelta,
                        tokens.length
                    );

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

                state.tick = lte ? step.nextTick - 1 : step.nextTick;
            }
        }

        if (r_ != state.r) r = state.r;

        kBound = state.kBound;
        sBound = state.sBound;

        sumSquaredReserves = sumSquaredReserves_;

        feeGrowthGlobalX128 = state.feeGrowthGlobalX128;

        if (state.tick != slot0_.tick) {
            (slot0.sumReserves, slot0.tick) = (uint128(state.sumReserves), state.tick);
        } else {
            slot0.sumReserves = uint128(state.sumReserves);
        }

        amountIn = int256(amountSpecified - state.amountSpecifiedRemaining);
        amountOut = -int256(state.amountCalculated);

        IERC20(tokens[tokenOutIndex]).transfer(recipient, uint256(-amountOut));

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
        uint256[] memory balancesBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balancesBefore[i] = balance(i);
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                IERC20(tokens[i]).transfer(msg.sender, amounts[i]);
            }
        }

        IZorbitalFlashCallback(msg.sender).zorbitalFlashCallback(data);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (balance(i) < balancesBefore[i]) revert FlashLoanNotRepaid();
        }

        emit Flash(msg.sender, amounts);
    }
}
