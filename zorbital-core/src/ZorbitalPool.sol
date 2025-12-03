// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./libraries/Tick.sol";
import "./libraries/Position.sol";

contract ZorbitalPool {
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    int24 internal constant MIN_TICK = 0;
    int24 internal constant MAX_TICK = 4055;

    // Pool tokens (n tokens)
    address[] public tokens;

    // Packing variables that are read together
    struct Slot0 {
        // Current sum of reserves
        uint128 sumReserves;
        // Current tick
        int24 tick;
    }
    Slot0 public slot0;

    // Consolidated radius, r (analogue of liquidity L)
    uint128 public r;

    // Ticks info
    mapping(int24 => Tick.Info) public ticks;
    // Positions info
    mapping(bytes32 => Position.Info) public positions;
}
