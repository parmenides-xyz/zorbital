// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

library Tick {
    struct Info {
        bool initialized;
        uint128 r;
    }

    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint128 rDelta
    ) internal returns (bool flipped) {
        Tick.Info storage tickInfo = self[tick];
        uint128 rBefore = tickInfo.r;
        uint128 rAfter = rBefore + rDelta;

        flipped = (rAfter == 0) != (rBefore == 0);

        if (rBefore == 0) {
            tickInfo.initialized = true;
        }

        tickInfo.r = rAfter;
    }
}
