// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// @author Modified from Solady by Vectorized https://github.com/Vectorized/solady/blob/701406e8126cfed931645727b274df303fbcd94d/src/utils/LibBit.sol#L30-L45 under the MIT license
library ClzFHE {
    /// @dev Count leading zeros for encrypted uint256.
    /// Returns the number of zeros preceding the most significant one bit.
    /// If `x` is zero, returns 256.
    function clz(euint256 x) internal pure returns (euint256 r) {
        assembly ("memory-safe") {
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, ))
        }
    }
}


