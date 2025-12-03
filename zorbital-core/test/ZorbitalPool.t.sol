// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "./ERC20Mintable.sol";
import "../src/ZorbitalPool.sol";
import "../src/ZorbitalFactory.sol";

contract ZorbitalPoolTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    ERC20Mintable token2;
    ERC20Mintable token3;
    ZorbitalPool pool;
    ZorbitalFactory factory;

    bool shouldTransferInCallback;

    struct TestCaseParams {
        uint256 token0Balance;
        uint256 token1Balance;
        uint256 token2Balance;
        uint256 token3Balance;
        int24 currentTick;
        int24 tick;
        uint128 radius;
        uint128 currentSumReserves;
        bool shouldTransferInCallback;
        bool mintLiquidity;
    }

    function setUp() public {
        token0 = new ERC20Mintable("USDC", "USDC", 18);
        token1 = new ERC20Mintable("USDT", "USDT", 18);
        token2 = new ERC20Mintable("DAI", "DAI", 18);
        token3 = new ERC20Mintable("FRAX", "FRAX", 18);

        factory = new ZorbitalFactory();
    }

    /// @notice Find the index of a token in the pool's sorted token array
    function findTokenIndex(address token) internal view returns (uint256) {
        for (uint256 i = 0; i < 4; i++) {
            if (pool.tokens(i) == token) return i;
        }
        revert("Token not found in pool");
    }

    function setupTestCase(TestCaseParams memory params)
        internal
        returns (uint256[] memory poolBalances)
    {
        token0.mint(address(this), params.token0Balance);
        token1.mint(address(this), params.token1Balance);
        token2.mint(address(this), params.token2Balance);
        token3.mint(address(this), params.token3Balance);

        address[] memory tokens = new address[](4);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);

        // Create pool via factory
        pool = ZorbitalPool(factory.createPool(tokens, 500)); // fee=500 (0.05%) for stablecoins

        // Initialize pool with starting state
        pool.initialize(params.currentSumReserves, params.currentTick);

        shouldTransferInCallback = params.shouldTransferInCallback;

        if (params.mintLiquidity) {
            poolBalances = pool.mint(
                address(this),
                params.tick,
                params.radius,
                ""
            );
        }
    }

    function zorbitalMintCallback(
        uint256[] memory amounts,
        bytes calldata /* data */
    ) public {
        if (shouldTransferInCallback) {
            token0.transfer(msg.sender, amounts[0]);
            token1.transfer(msg.sender, amounts[1]);
            token2.transfer(msg.sender, amounts[2]);
            token3.transfer(msg.sender, amounts[3]);
        }
    }

    function testMintSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            token0Balance: 1000e18,
            token1Balance: 1000e18,
            token2Balance: 1000e18,
            token3Balance: 1000e18,
            currentTick: 0,
            tick: 2000,
            radius: 1000e18,
            currentSumReserves: 4000e18,
            shouldTransferInCallback: true,
            mintLiquidity: true
        });

        uint256[] memory poolBalances = setupTestCase(params);

        // Check amounts: r * (1 - 1/√n) = 1000e18 * (1 - 1/√4) = 1000e18 * 0.5 = 500e18
        uint256 expectedAmount = 500e18;
        assertEq(poolBalances[0], expectedAmount, "incorrect token0 deposited amount");
        assertEq(poolBalances[1], expectedAmount, "incorrect token1 deposited amount");
        assertEq(poolBalances[2], expectedAmount, "incorrect token2 deposited amount");
        assertEq(poolBalances[3], expectedAmount, "incorrect token3 deposited amount");

        // Check balances were transferred to pool
        assertEq(token0.balanceOf(address(pool)), expectedAmount);
        assertEq(token1.balanceOf(address(pool)), expectedAmount);
        assertEq(token2.balanceOf(address(pool)), expectedAmount);
        assertEq(token3.balanceOf(address(pool)), expectedAmount);

        // Check position (keyed by owner, tick)
        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), params.tick)
        );
        (uint128 posRadius) = pool.positions(positionKey);
        assertEq(posRadius, params.radius, "incorrect position radius");

        // Check tick was initialized (Tick.Info has: initialized, rGross, rNet, feeGrowthOutsideX128)
        (bool tickInitialized, uint128 tickRGross, uint128 tickRNet,) = pool.ticks(params.tick);
        assertTrue(tickInitialized, "tick not initialized");
        assertEq(tickRGross, params.radius, "incorrect tick rGross");
        assertEq(tickRNet, params.radius, "incorrect tick rNet");

        // Check slot0 and r
        (uint128 sumReserves, int24 tick, bool initialized) = pool.slot0();
        assertEq(sumReserves, params.currentSumReserves, "invalid sumReserves");
        assertEq(tick, params.currentTick, "invalid current tick");
        assertTrue(initialized, "pool not initialized");
        assertEq(pool.r(), params.radius, "invalid current radius");
    }

    function testSwapUSDCForUSDT() public {
        TestCaseParams memory params = TestCaseParams({
            token0Balance: 1000e18,
            token1Balance: 1000e18,
            token2Balance: 1000e18,
            token3Balance: 1000e18,
            currentTick: 0,
            tick: 2000,
            radius: 1000e18,
            currentSumReserves: 4000e18,
            shouldTransferInCallback: true,
            mintLiquidity: true
        });
        uint256[] memory poolBalances = setupTestCase(params);

        // Mint extra USDC for the swap
        uint256 swapAmount = 10e18;
        token0.mint(address(this), swapAmount);

        // Find correct indices after token sorting
        uint256 tokenInIndex = findTokenIndex(address(token0));
        uint256 tokenOutIndex = findTokenIndex(address(token1));

        uint256 userBalance0Before = token0.balanceOf(address(this));
        uint256 userBalance1Before = token1.balanceOf(address(this));

        // Swap USDC (token0) for USDT (token1) with specified amount
        (int256 amountIn, int256 amountOut) = pool.swap(
            address(this),
            tokenInIndex,
            tokenOutIndex,
            swapAmount,
            0, // sumReservesLimit (0 = no slippage limit)
            ""
        );

        // Check that input amount matches what we specified
        assertEq(amountIn, int256(swapAmount), "invalid USDC in");
        // Output should be negative (tokens leaving pool to user)
        assertTrue(amountOut < 0, "amountOut should be negative");

        // Check user balances
        assertEq(
            token0.balanceOf(address(this)),
            userBalance0Before - uint256(amountIn),
            "invalid user USDC balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            userBalance1Before + uint256(-amountOut),
            "invalid user USDT balance"
        );

        // Check pool balances (use correct indices after sorting)
        assertEq(
            token0.balanceOf(address(pool)),
            poolBalances[tokenInIndex] + uint256(amountIn),
            "invalid pool USDC balance"
        );
        assertEq(
            token1.balanceOf(address(pool)),
            poolBalances[tokenOutIndex] - uint256(-amountOut),
            "invalid pool USDT balance"
        );

        // Check pool state
        (uint128 sumReserves, int24 tick,) = pool.slot0();
        // sumReserves should update: original + (amountIn - fee) - |amountOut|
        // Fee is 0.05% (500 hundredths of bps), so fee = amountIn * 500 / 1e6
        uint256 originalSum = 4 * poolBalances[tokenInIndex]; // 4 tokens * 500e18 each = 2000e18
        uint256 feeAmount = (uint256(amountIn) * 500) / 1e6; // 0.05% fee
        uint256 expectedSum = originalSum + uint256(amountIn) - feeAmount - uint256(-amountOut);
        assertEq(sumReserves, uint128(expectedSum), "invalid sumReserves");
        assertEq(tick, 0, "invalid current tick");
        assertEq(pool.r(), params.radius, "invalid current radius");
    }

    function zorbitalSwapCallback(
        uint256 tokenInIndex,
        uint256 /* tokenOutIndex */,
        int256 amountIn,
        int256 /* amountOut */,
        bytes calldata /* data */
    ) public {
        if (amountIn > 0) {
            // Transfer the token at the correct index (tokens are sorted in pool)
            ERC20Mintable(pool.tokens(tokenInIndex)).transfer(msg.sender, uint256(amountIn));
        }
    }

    // ============ Cross-Tick Swap Tests ============
    // Adapted from Uniswap V3 tutorial for Orbital's nested tick model

    /// @notice Test: Two identical ticks (same boundary k)
    /// In Orbital, multiple LPs can provide liquidity at the same tick.
    /// Their radii add up, providing deeper liquidity (like overlapping ranges in Uniswap V3).
    function testSwapTwoIdenticalTicks() public {
        // Setup: mint tokens for two positions at the same tick
        token0.mint(address(this), 2000e18);
        token1.mint(address(this), 2000e18);
        token2.mint(address(this), 2000e18);
        token3.mint(address(this), 2000e18);

        address[] memory tokens = new address[](4);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);

        pool = ZorbitalPool(factory.createPool(tokens, 500)); // fee=500 (0.05%)
        pool.initialize(4000e18, 0);
        shouldTransferInCallback = true;

        // First LP: mint at tick 2000
        pool.mint(address(this), 2000, 500e18, "");

        // Second LP: mint at same tick 2000
        pool.mint(address(this), 2000, 500e18, "");

        // Check combined liquidity
        assertEq(pool.r(), 1000e18, "combined radius should be 1000e18");

        // Check tick has combined rGross and rNet
        (bool initialized, uint128 rGross, uint128 rNet,) = pool.ticks(2000);
        assertTrue(initialized, "tick should be initialized");
        assertEq(rGross, 1000e18, "rGross should be combined");
        assertEq(rNet, 1000e18, "rNet should be combined");

        // Swap: with deeper liquidity, price should move slower
        uint256 swapAmount = 10e18;
        token0.mint(address(this), swapAmount);

        // Find correct indices after token sorting
        uint256 tokenInIndex = findTokenIndex(address(token0));
        uint256 tokenOutIndex = findTokenIndex(address(token1));

        (int256 amountIn, int256 amountOut) = pool.swap(
            address(this),
            tokenInIndex,
            tokenOutIndex,
            swapAmount,
            0, // sumReservesLimit (0 = no slippage limit)
            ""
        );

        assertEq(amountIn, int256(swapAmount), "should consume full input");
        assertTrue(amountOut < 0, "should output tokens");

        // Liquidity unchanged (swap within single tick)
        assertEq(pool.r(), 1000e18, "radius should be unchanged");
    }

    /// @notice Test: Nested ticks at different boundaries
    /// In Orbital, ticks are nested around equal-price point.
    /// Tick 1000 has boundary closer to equal-price than tick 2000.
    /// A large swap moving away from equal-price crosses tick boundaries.
    function testSwapNestedTicks() public {
        // Setup: mint tokens
        token0.mint(address(this), 2000e18);
        token1.mint(address(this), 2000e18);
        token2.mint(address(this), 2000e18);
        token3.mint(address(this), 2000e18);

        address[] memory tokens = new address[](4);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);

        pool = ZorbitalPool(factory.createPool(tokens, 500)); // fee=500 (0.05%)
        pool.initialize(4000e18, 0);
        shouldTransferInCallback = true;

        // Tick 1000: closer boundary (smaller k)
        pool.mint(address(this), 1000, 400e18, "");

        // Tick 2000: farther boundary (larger k)
        pool.mint(address(this), 2000, 600e18, "");

        // Both ticks are interior since currentTick=0 < 1000 < 2000
        // Combined interior radius: 400 + 600 = 1000e18
        assertEq(pool.r(), 1000e18, "combined radius should be 1000e18");

        // Check both ticks initialized
        (bool init1, uint128 rGross1,,) = pool.ticks(1000);
        (bool init2, uint128 rGross2,,) = pool.ticks(2000);
        assertTrue(init1, "tick 1000 should be initialized");
        assertTrue(init2, "tick 2000 should be initialized");
        assertEq(rGross1, 400e18, "tick 1000 rGross");
        assertEq(rGross2, 600e18, "tick 2000 rGross");
    }
}
