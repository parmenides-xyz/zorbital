// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { FHE, euint256, ebool } from "@fhenixprotocol/cofhe-contracts/FHE.sol";

library ClzFHE {
    /// @dev Count leading zeros for encrypted uint256.
    /// Returns the number of zeros preceding the most significant one bit.
    /// If `x` is zero, returns 256.
    function clz(euint256 x) internal pure returns (euint256 r) {
        r = FHE.shl(FHE.select(FHE.gt(x, FHE.asEuint256(0xffffffffffffffffffffffffffffffff)), FHE.asEuint256(1), FHE.asEuint256(0)), FHE.asEuint256(7));
        r = FHE.or(r, FHE.shl(FHE.select(FHE.gt(FHE.shr(x, r), FHE.asEuint256(0xffffffffffffffff)), FHE.asEuint256(1), FHE.asEuint256(0)), FHE.asEuint256(6)));
        r = FHE.or(r, FHE.shl(FHE.select(FHE.gt(FHE.shr(x, r), FHE.asEuint256(0xffffffff)), FHE.asEuint256(1), FHE.asEuint256(0)), FHE.asEuint256(5)));
        r = FHE.or(r, FHE.shl(FHE.select(FHE.gt(FHE.shr(x, r), FHE.asEuint256(0xffff)), FHE.asEuint256(1), FHE.asEuint256(0)), FHE.asEuint256(4)));
        r = FHE.or(r, FHE.shl(FHE.select(FHE.gt(FHE.shr(x, r), FHE.asEuint256(0xff)), FHE.asEuint256(1), FHE.asEuint256(0)), FHE.asEuint256(3)));
        r = FHE.or(r, FHE.shl(FHE.select(FHE.gt(FHE.shr(x, r), FHE.asEuint256(0xf)), FHE.asEuint256(1), FHE.asEuint256(0)), FHE.asEuint256(2)));
        r = FHE.or(r, FHE.shl(FHE.select(FHE.gt(FHE.shr(x, r), FHE.asEuint256(0x3)), FHE.asEuint256(1), FHE.asEuint256(0)), FHE.asEuint256(1)));
        r = FHE.or(r, FHE.select(FHE.gt(FHE.shr(x, r), FHE.asEuint256(0x1)), FHE.asEuint256(1), FHE.asEuint256(0)));

        r = FHE.add(
            FHE.xor(r, FHE.asEuint256(255)),
            FHE.select(FHE.eq(x, FHE.asEuint256(0)), FHE.asEuint256(1), FHE.asEuint256(0))
        );
    }

    function bitLength(euint256 x) internal pure returns (euint256) {
        return FHE.sub(FHE.asEuint256(256), clz(x));
    }
}
