// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

library Position {
    struct Info {
        uint128 r;
    }

    function update(Info storage self, uint128 rDelta) internal {
        uint128 rBefore = self.r;
        uint128 rAfter = rBefore + rDelta;

        self.r = rAfter;
    }

    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tick
    ) internal view returns (Position.Info storage position) {
        position = self[keccak256(abi.encodePacked(owner, tick))];
    }
}
