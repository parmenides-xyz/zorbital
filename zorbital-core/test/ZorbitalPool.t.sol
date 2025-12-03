// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "./ERC20Mintable.sol";
import "../src/ZorbitalPool.sol";

contract ZorbitalPoolTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    ERC20Mintable token2;
    ERC20Mintable token3;
    ZorbitalPool pool;

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

        pool = new ZorbitalPool(
            tokens,
            params.currentSumReserves,
            params.currentTick
        );

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

        // Check tick was initialized
        (bool tickInitialized, uint128 tickRadius) = pool.ticks(params.tick);
        assertTrue(tickInitialized, "tick not initialized");
        assertEq(tickRadius, params.radius, "incorrect tick radius");

        // Check slot0 and r
        (uint128 sumReserves, int24 tick) = pool.slot0();
        assertEq(sumReserves, params.currentSumReserves, "invalid sumReserves");
        assertEq(tick, params.currentTick, "invalid current tick");
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

        uint256 userBalance0Before = token0.balanceOf(address(this));
        uint256 userBalance1Before = token1.balanceOf(address(this));

        // Swap USDC (token0) for USDT (token1) with specified amount
        (int256 amountIn, int256 amountOut) = pool.swap(
            address(this),
            0,
            1,
            swapAmount,
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

        // Check pool balances
        assertEq(
            token0.balanceOf(address(pool)),
            poolBalances[0] + uint256(amountIn),
            "invalid pool USDC balance"
        );
        assertEq(
            token1.balanceOf(address(pool)),
            poolBalances[1] - uint256(-amountOut),
            "invalid pool USDT balance"
        );

        // Check pool state
        (uint128 sumReserves, int24 tick) = pool.slot0();
        // sumReserves should update: original + amountIn - |amountOut|
        uint256 originalSum = 4 * poolBalances[0]; // 4 tokens * 500e18 each = 2000e18
        uint256 expectedSum = originalSum + uint256(amountIn) - uint256(-amountOut);
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
            if (tokenInIndex == 0) token0.transfer(msg.sender, uint256(amountIn));
            if (tokenInIndex == 1) token1.transfer(msg.sender, uint256(amountIn));
            if (tokenInIndex == 2) token2.transfer(msg.sender, uint256(amountIn));
            if (tokenInIndex == 3) token3.transfer(msg.sender, uint256(amountIn));
        }
    }
}
